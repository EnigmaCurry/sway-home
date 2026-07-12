#!/usr/bin/env bb

;;; ============================================================
;;; setup-disk.bb
;;; ============================================================
;;;
;;; Interactive wizard that partitions, formats, and mounts a target
;;; disk for a fresh NixOS install -- run it from the booted live ISO.
;;;
;;; One of the `setup-*` installer tools (git-extension style): run it
;;; directly as `setup-disk`, or via the dispatcher as `setup disk`.
;;;
;;; Scope:
;;;   - pick a target layout: single disk OR multi-disk btrfs raid (raid1,
;;;     raid1c3, raid10, raid1c4 -- the count-appropriate levels are
;;;     offered based on the number of disks selected)
;;;   - GPT layout: ESP (UEFI) or bios_grub (legacy BIOS) + btrfs root
;;;     - single disk: ESP + optional swap + btrfs (optionally in LUKS)
;;;     - raid: ESP on the FIRST disk only (losing that disk requires
;;;       reinstalling the bootloader on another member); every disk gets
;;;       its own optional swap; every disk's root partition is either a
;;;       LUKS container (encrypted) or a labeled bare partition
;;;       (unencrypted); the btrfs pool is declared on the LAST disk with
;;;       `extraArgs` referencing the other members
;;;   - btrfs subvolumes: @ (/), @home (/home), @nix (/nix)
;;;   - optional swap partitions (per disk; total = N * size for raid)
;;;   - optional full-disk LUKS encryption of the btrfs root (per-disk
;;;     LUKS in the raid case) and, when swap is present, random-key
;;;     encryption of swap
;;;   - apply declaratively with `disko` and mount everything under /mnt
;;;
;;; Encryption note: we never touch the passphrase ourselves. With no
;;; key/password file in the generated config, disko's `askPassword`
;;; defaults on -- it prompts for (and confirms) the passphrase via
;;; cryptsetup at format time. `initrdUnlock` likewise defaults on, so
;;; the disko NixOS module (imported by the host flake) generates the
;;; boot.initrd.luks unlock entry and the system prompts at boot. For
;;; multi-disk raid this means one prompt per LUKS container: disko will
;;; ask N times during formatting -- type the same passphrase each time.
;;;
;;; Future features (ext4/xfs, ZFS raid, ESP mirroring) slot into the
;;; same generate-a-Nix-file-then-apply structure.
;;;
;;; This runs on the installer ISO, which already ships babashka and
;;; the script-wizard pod binary, so the pod loads from PATH (no
;;; pod-registry download needed). Network is still required to fetch
;;; `disko` via `nix run`.
;;; ============================================================

(require '[babashka.pods :as pods])

;; Load the script-wizard pod directly from the installed binary, which
;; is on $PATH in the ISO. This avoids the babashka pod-registry network
;; lookup. The pod namespace is required in the ns form below (it exists
;; once the pod is loaded).
(pods/load-pod ["script-wizard" "pod"])

(ns setup-disk
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [cheshire.core :as json]
            [clojure.string :as str]
            [pod.enigmacurry.script-wizard :as sw]))

;;; ============================================================
;;; Output helpers
;;; ============================================================

(defn stderr [& args]
  (binding [*out* *err*] (apply println args)))

(defn die [& msg]
  (when (seq msg) (binding [*out* *err*] (apply println "ERROR:" msg)))
  (System/exit 1))

(defn root? []
  (let [r (proc/shell {:out :string :continue true} "id" "-u")]
    (= "0" (str/trim (:out r)))))

(defn sh
  "Run a command, sudo-prefixed when not already root. `opts` is passed to
  babashka.process/shell (e.g. {:continue true} or {:out :string ...}).
  Returns the process result map."
  [opts & args]
  (let [cmd (if (root?) (vec args) (into ["sudo"] args))]
    (apply proc/shell opts cmd)))

;;; ============================================================
;;; Disk discovery
;;; ============================================================

(defn human-size
  "Render a byte count as a short human string (e.g. 953.9G)."
  [bytes]
  (loop [n (double (or bytes 0)) us ["B" "K" "M" "G" "T" "P"]]
    (if (or (< n 1024.0) (= (count us) 1))
      (format "%.1f%s" n (first us))
      (recur (/ n 1024.0) (rest us)))))

(defn node-mounted?
  "True if this lsblk node, or any of its partitions/children, currently
  has an active mountpoint. Such a disk is in use by the running system
  (most importantly the live boot medium) and cannot be repartitioned."
  [node]
  (or (some #(and % (not (str/blank? %))) (:mountpoints node))
      (boolean (some node-mounted? (:children node)))))

(defn list-disks
  "Return a vector of {:name :size :model :tran :rota :in-use?} for real
  disks. :in-use? flags disks with active mounts (e.g. the boot medium)."
  []
  (let [r (proc/shell {:out :string :err :string :continue true}
                      "lsblk" "-J" "-b" "-p"
                      "-o" "NAME,SIZE,MODEL,SERIAL,TYPE,TRAN,ROTA,MOUNTPOINTS")]
    (when-not (zero? (:exit r))
      (die "lsblk failed:" (str/trim (:err r))))
    (->> (get (json/parse-string (:out r) true) :blockdevices)
         (filter #(and (= "disk" (:type %))
                       (not (str/starts-with? (:name %) "/dev/zram"))))
         (map (fn [d]
                (assoc (select-keys d [:name :size :model :serial :tran :rota])
                       :in-use? (node-mounted? d))))
         vec)))

(defn disk-fields
  "Break a disk into the display columns used by `disk-labels`."
  [{:keys [name size model tran rota]}]
  [name
   (human-size size)
   (if (and model (not (str/blank? model))) (str/trim model) "")
   (str "(" (or (some-> tran str/upper-case) "?")
        (if (= 1 rota) ", HDD" ", SSD") ")")])

(defn disk-labels
  "Render all disks as menu labels with the columns aligned on the ' — '
  separator, so name/size/model line up regardless of length. Columns
  that are empty for every disk (e.g. no model) are dropped entirely."
  [disks]
  (let [rows   (mapv disk-fields disks)
        ncol   (count (first rows))
        widths (mapv (fn [c] (apply max 0 (map #(count (nth % c)) rows)))
                     (range ncol))]
    (mapv (fn [row]
            (->> (keep-indexed
                  (fn [i field]
                    (cond
                      ;; drop columns empty for every disk
                      (and (< i (dec ncol)) (zero? (nth widths i))) nil
                      ;; pad every column except the trailing tag
                      (< i (dec ncol)) (format (str "%-" (nth widths i) "s") field)
                      :else field))
                  row)
                 (str/join "  —  ")))
          rows)))

(defn swap-partitions
  "Full device paths under `device` that carry a swap signature (set by
  disko's mkswap). Used to confirm/activate swap after applying."
  [device]
  (let [r (proc/shell {:out :string :err :string :continue true}
                      "lsblk" "-J" "-p" "-o" "NAME,FSTYPE" device)]
    (if-not (zero? (:exit r))
      []
      (letfn [(walk [nodes]
                (mapcat #(cons % (walk (:children %))) nodes))]
        (->> (get (json/parse-string (:out r) true) :blockdevices)
             walk
             (filter #(= "swap" (:fstype %)))
             (mapv :name))))))

;;; ============================================================
;;; Existing-layout detection (reinstall path)
;;; ============================================================

(defn list-partitions
  "Partition nodes ({:name :fstype}) under `device`, recursively."
  [device]
  (let [r (proc/shell {:out :string :err :string :continue true}
                      "lsblk" "-J" "-p" "-o" "NAME,FSTYPE,TYPE" device)]
    (if-not (zero? (:exit r))
      []
      (letfn [(walk [nodes] (mapcat #(cons % (walk (:children %))) nodes))]
        (->> (get (json/parse-string (:out r) true) :blockdevices)
             walk
             (filter #(= "part" (:type %)))
             vec)))))

(defn partition-of-fstype
  "First partition device under `device` whose filesystem is `fstype`
  (e.g. \"btrfs\", \"vfat\", \"swap\"), or nil."
  [device fstype]
  (->> (list-partitions device)
       (filter #(= fstype (:fstype %)))
       (map :name)
       first))

(defn btrfs-subvol-paths
  "Subvolume paths on the btrfs at `part` (e.g. #{\"@\" \"@home\" \"@nix\"}).
  Mounts the top-level (subvolid=5) read-only at a temp dir to list them,
  then unmounts. Empty set on any failure."
  [part]
  (let [tmp (str (fs/create-temp-dir {:prefix "btrfs-probe-"}))]
    (try
      (if-not (zero? (:exit (sh {:err :string :continue true}
                                "mount" "-o" "ro,subvolid=5" part tmp)))
        #{}
        (try
          (let [r (sh {:out :string :err :string :continue true}
                      "btrfs" "subvolume" "list" tmp)]
            (->> (str/split-lines (str (:out r)))
                 (keep #(second (re-find #"\bpath\s+(.+)$" %)))
                 set))
          (finally (sh {:continue true} "umount" tmp))))
      (finally (fs/delete-tree tmp)))))

(defn btrfs-pool-members
  "Every partition device that's a member of the btrfs pool at `part`.
  Mount the top-level (subvolid=5) and read `btrfs filesystem show`
  against it -- disko's raid layout puts N members in one pool, and
  mounting any single member exposes the whole thing. For a single-disk
  btrfs this is just #{part}. Empty set on any failure."
  [part]
  (let [tmp (str (fs/create-temp-dir {:prefix "btrfs-members-"}))]
    (try
      (if-not (zero? (:exit (sh {:err :string :continue true}
                                "mount" "-o" "ro,subvolid=5" part tmp)))
        #{}
        (try
          (let [r (sh {:out :string :err :string :continue true}
                      "btrfs" "filesystem" "show" tmp)]
            (->> (str/split-lines (str (:out r)))
                 (keep #(second (re-find #"\bpath\s+(/dev\S+)" %)))
                 set))
          (finally (sh {:continue true} "umount" tmp))))
      (finally (fs/delete-tree tmp)))))

(defn partition-parent-disk
  "The parent disk device (/dev/...) for a partition path (/dev/sda1
  -> /dev/sda; /dev/nvme0n1p3 -> /dev/nvme0n1). Uses `lsblk -no PKNAME`
  because sysfs walks and name-munging both misbehave on nvme."
  [part]
  (let [r (proc/shell {:out :string :err :string :continue true}
                      "lsblk" "-no" "PKNAME" part)
        parent (some-> (:out r) str/split-lines first str/trim)]
    (when-not (str/blank? parent)
      (str "/dev/" parent))))

(defn detect-reinstall
  "If the given `devices` (vector of {:device ...} maps) already hold a
  btrfs with @/@home/@nix and -- for raid -- all pool members are in
  the selected set, return
      {:devices :btrfs-part :esp-part :swap-parts}
  otherwise nil. For a single-disk layout this is unchanged behavior;
  for raid, mounting any member exposes the pool so we probe each disk
  until we find one, then verify member coverage.

  Encrypted layouts show crypto_LUKS rather than btrfs at the partition
  level, so this returns nil for them (matching the existing behavior
  -- reinstall requires unlocking, which would need the passphrase we
  deliberately don't handle)."
  [devices]
  (let [dev-paths (set (map :device devices))
        ;; find the first disk that carries a btrfs partition
        probe (some (fn [d]
                      (when-let [p (partition-of-fstype (:device d) "btrfs")]
                        {:disk d :btrfs-part p}))
                    devices)]
    (when probe
      (let [{:keys [btrfs-part]} probe
            subvols (btrfs-subvol-paths btrfs-part)]
        (when (every? subvols ["@" "@home" "@nix"])
          (let [members         (btrfs-pool-members btrfs-part)
                member-parents  (into #{} (keep partition-parent-disk members))
                coverage-ok?    (and (seq member-parents)
                                     (every? dev-paths member-parents)
                                     (= (count member-parents) (count devices)))]
            (when coverage-ok?
              {:devices    devices
               :btrfs-part btrfs-part
               :esp-part   (some #(partition-of-fstype (:device %) "vfat") devices)
               :swap-parts (vec (keep #(partition-of-fstype (:device %) "swap") devices))})))))))

;;; ============================================================
;;; disko.nix generation
;;; ============================================================

(defn btrfs-subvolumes
  "The btrfs subvolume map (@ -> /, @home -> /home, @nix -> /nix). `pad`
  is the indentation of the `subvolumes = {` line, so the block sits at
  the right depth whether btrfs is the direct root content or nested
  inside a luks container."
  [pad]
  (let [item (str pad "  ")]
    (str
     pad "subvolumes = {\n"
     item "\"@\"     = { mountpoint = \"/\";     mountOptions = [ \"compress=zstd\" \"noatime\" ]; };\n"
     item "\"@home\" = { mountpoint = \"/home\"; mountOptions = [ \"compress=zstd\" \"noatime\" ]; };\n"
     item "\"@nix\"  = { mountpoint = \"/nix\";  mountOptions = [ \"compress=zstd\" \"noatime\" ]; };\n"
     pad "};\n")))

(defn btrfs-content
  "The `type = \"btrfs\"` content block (with subvolumes), indented by
  `pad`. Used directly as the root content, or nested inside the luks
  block when the disk is encrypted.

  `extra-args` is a vector of additional extraArgs elements appended
  after \"-f\". For a multi-disk raid, callers pass the raid level flags
  and the paths of the OTHER pool members (disko implicitly uses the
  owning member's own device as the primary), e.g.
    [\"-d raid1\" \"-m raid1\" \"/dev/mapper/root1\" \"/dev/mapper/root2\"]"
  ([pad] (btrfs-content pad []))
  ([pad extra-args]
   (let [args    (into ["-f"] extra-args)
         arg-str (str/join " " (map #(str "\"" % "\"") args))]
     (str
      pad "type = \"btrfs\";\n"
      pad "extraArgs = [ " arg-str " ];\n"
      (btrfs-subvolumes pad)))))

(defn esp-partition []
  (str
   "            ESP = {\n"
   "              priority = 1;\n"
   "              size = \"512M\";\n"
   "              type = \"EF00\";\n"
   "              content = {\n"
   "                type = \"filesystem\";\n"
   "                format = \"vfat\";\n"
   "                mountpoint = \"/boot\";\n"
   "                mountOptions = [ \"umask=0077\" ];\n"
   "              };\n"
   "            };\n"))

(defn bios-boot-partition []
  (str
   "            boot = {\n"
   "              priority = 1;\n"
   "              size = \"1M\";\n"
   "              type = \"EF02\"; # BIOS boot partition for GRUB\n"
   "            };\n"))

(defn swap-partition
  "A fixed-size swap partition. priority 2 keeps it after the
  boot/ESP partition and before the 100% root, so root still grabs
  the remaining space. When `encrypt?`, swap is re-keyed with a random
  passphrase on every boot (randomEncryption) so it never leaks RAM
  contents in plaintext on an otherwise-encrypted disk -- this rules
  out hibernation (suspend-to-disk)."
  [size encrypt?]
  (str
   "            swap = {\n"
   "              priority = 2;\n"
   "              size = \"" size "\";\n"
   "              content = {\n"
   "                type = \"swap\";\n"
   (when encrypt? "                randomEncryption = true;\n")
   "              };\n"
   "            };\n"))

(defn root-partition
  "The 100% root partition.

  Options:
    :encrypt?    wrap the partition in a LUKS container (the disko
                 NixOS module adds the boot.initrd.luks unlock entry;
                 allowDiscards passes TRIM through to the SSD).
    :luks-name   LUKS mapper name (default \"cryptroot\"). For a raid
                 layout each member gets its own name (\"root1\",
                 \"root2\", ...) so /dev/mapper/rootN is stable.
    :label       GPT partlabel to set on the raw partition. Used by
                 the non-encrypted raid layout so members can be
                 referenced as /dev/disk/by-partlabel/rootN.
    :empty?      true for raid non-last members: emit the LUKS
                 container (or bare labeled partition) with NO inner
                 content -- the btrfs pool declared on the LAST member
                 formats them via extraArgs.
    :raid-extra  extra extraArgs elements (raid level flags + other
                 members' paths) for the pool-owning last member;
                 empty vector for a single-disk btrfs.

  We never touch the passphrase ourselves: with no key/password file,
  disko's askPassword defaults on and prompts via cryptsetup at format
  time. In the raid case that means one prompt per LUKS container
  (N times) -- type the same passphrase each time."
  [{:keys [encrypt? luks-name label empty? raid-extra]
    :or   {luks-name "cryptroot" raid-extra []}}]
  (let [pad-encrypted   "                  "  ;; content nested in LUKS
        pad-unencrypted "                "]   ;; content at partition level
    (str
     "            root = {\n"
     "              size = \"100%\";\n"
     (when label (str "              label = \"" label "\";\n"))
     (cond
       encrypt?
       (str
        "              content = {\n"
        "                type = \"luks\";\n"
        "                name = \"" luks-name "\";\n"
        "                settings = { allowDiscards = true; };\n"
        (when-not empty?
          (str
           "                content = {\n"
           (btrfs-content pad-encrypted raid-extra)
           "                };\n"))
        "              };\n")
       (not empty?)
       (str
        "              content = {\n"
        (btrfs-content pad-unencrypted raid-extra)
        "              };\n")
       ;; empty AND unencrypted -> bare labeled partition, no content.
       :else "")
     "            };\n")))

(defn disk-block
  "Emit one `diskN = { ... }` entry inside `disko.devices.disk`. `esp?`
  places the ESP (UEFI) or bios_grub (legacy BIOS) partition on this
  disk; for a raid layout, only the first disk carries it. Swap and the
  root partition are per-disk. `root-str` is the pre-rendered root
  block from `root-partition`."
  [{:keys [name device uefi? swap-size encrypt? esp? root-str]}]
  (str
   "      " name " = {\n"
   "        type = \"disk\";\n"
   "        device = \"" device "\";\n"
   "        content = {\n"
   "          type = \"gpt\";\n"
   "          partitions = {\n"
   (when esp? (if uefi? (esp-partition) (bios-boot-partition)))
   (when swap-size (swap-partition swap-size encrypt?))
   root-str
   "          };\n"
   "        };\n"
   "      };\n"))

(defn disko-nix
  "Generate the disko config. `:devices` is a vector of {:device ...}
  maps -- 1 entry for the single-disk layout, 2+ for a btrfs raid.
  `:raid-level` is nil for single-disk, or one of \"raid1\" /
  \"raid1c3\" / \"raid10\" / \"raid1c4\" for multi-disk.

  Raid layout details:
   - ESP (or bios_grub) lives on the FIRST disk only. Losing that disk
     requires manually reinstalling the bootloader on another member.
   - Each disk gets its own root partition. When encrypted, each is a
     LUKS container named rootN, referenced as /dev/mapper/rootN.
     When not encrypted, each is a bare partition with GPT partlabel
     rootN, referenced as /dev/disk/by-partlabel/rootN.
   - The btrfs pool is declared on the LAST disk's root partition with
     `extraArgs = [ \"-f\" \"-d LEVEL\" \"-m LEVEL\" <other members> ]`
     (disko implicitly passes the last member as the primary device to
     mkfs.btrfs)."
  [{:keys [devices uefi? swap-size encrypt? raid-level]}]
  (let [n         (count devices)
        single?   (= 1 n)
        ;; per-disk metadata: name, mapper/label, and how the pool
        ;; references this member from the last disk's extraArgs.
        entries   (map-indexed
                   (fn [i {:keys [device]}]
                     (let [idx (inc i)
                           luks-name (if single? "cryptroot" (str "root" idx))
                           label     (when-not single? (str "root" idx))
                           ref       (if encrypt?
                                       (str "/dev/mapper/" luks-name)
                                       (str "/dev/disk/by-partlabel/" label))]
                       {:name      (if single? "main" (str "disk" idx))
                        :device    device
                        :first?    (zero? i)
                        :last?     (= i (dec n))
                        :luks-name luks-name
                        :label     label
                        :ref       ref}))
                   devices)
        ;; The last member owns the btrfs pool declaration; its
        ;; extraArgs list carries the raid flags plus paths to the OTHER
        ;; members (disko passes the owning member's own device
        ;; implicitly). For a single disk this is empty.
        raid-extra (if single?
                     []
                     (into [(str "-d " raid-level) (str "-m " raid-level)]
                           (->> entries butlast (mapv :ref))))
        blocks
        (mapv (fn [{:keys [name device first? last? luks-name label]}]
                (let [root-str (root-partition
                                {:encrypt?   encrypt?
                                 :luks-name  luks-name
                                 :label      label
                                 :empty?     (not last?)
                                 :raid-extra (when last? raid-extra)})]
                  (disk-block
                   {:name      name
                    :device    device
                    :uefi?     uefi?
                    :swap-size swap-size
                    :encrypt?  encrypt?
                    :esp?      first?
                    :root-str  root-str})))
              entries)]
    (str
     "# Generated by setup-disk -- declarative disk layout (disko).\n"
     "# Apply:  disko --mode destroy,format,mount ./disko.nix\n"
     "{\n"
     "  disko.devices = {\n"
     "    disk = {\n"
     (str/join blocks)
     "    };\n"
     "  };\n"
     "}\n")))

;;; ============================================================
;;; Review + apply
;;; ============================================================

(defn confirm-review [{:keys [devices uefi? swap-size encrypt? raid-level config-path]}]
  (let [n       (count devices)
        single? (= 1 n)
        first-dev (:device (first devices))
        target-line (if single?
                      first-dev
                      (str "raid (" n " disks): "
                           (str/join ", " (map :device devices))))]
    (println)
    (println "================ Review =================")
    (println "Target disks:" target-line)
    (println "Firmware:    " (if uefi? "UEFI (ESP /boot)" "Legacy BIOS (bios_grub)"))
    (println "Filesystem:   btrfs"
             (if single? "" (str "(" raid-level " across " n " disks)")))
    (when-not single?
      (println (str "ESP:          on " first-dev " only"
                    " (losing this disk requires reinstalling the bootloader on another member)")))
    (println "Encryption:  " (if encrypt?
                               (if single?
                                 "LUKS2 (passphrase set during format, prompted at boot)"
                                 (str "LUKS2 per disk (" n " containers rootN, one prompt each -- type the same passphrase)"))
                               "none"))
    (println "Subvolumes:   @ -> /, @home -> /home, @nix -> /nix")
    (println "Swap:        " (cond
                               (and swap-size (not single?) encrypt?)
                               (str swap-size " per disk, " n " disks (random-key encrypted)")
                               (and swap-size (not single?))
                               (str swap-size " per disk, " n " disks")
                               (and swap-size encrypt?)
                               (str swap-size " (random-key encrypted)")
                               swap-size swap-size
                               :else "none"))
    (println "Config:      " config-path)
    (println "=========================================")
    (println)
    (println (if single?
               (str "⚠️  This ERASES ALL DATA on " first-dev " and mounts the new")
               (str "⚠️  This ERASES ALL DATA on ALL " n " disks and mounts the new")))
    (println "    filesystems under /mnt.")
    (when encrypt?
      (println)
      (println (str "    disko will prompt " (if single? "" (str n " times ")) "for the LUKS passphrase during")))
    (when encrypt?
      (if single?
        (println "    formatting -- keep it safe, it cannot be recovered.")
        (println "    formatting -- enter the SAME passphrase each time. Keep it safe, it cannot be recovered.")))
    (println)
    (sw/confirm "Proceed?" :default :no)))

(defn apply-disko! [config-path]
  ;; disko is fetched on demand via `nix run` -- it's not bundled into
  ;; the ISO because running a disko `--mode` builds a derivation that
  ;; pulls a toolchain from the binary cache, so it needs the network
  ;; regardless (and nixos-install needs it right after anyway).
  ;; --yes-wipe-all-disks skips disko's own wipe prompt: we already did a
  ;; strong confirmation (re-typing the device path + the review screen).
  (let [base ["nix" "--extra-experimental-features" "nix-command flakes"
              "run" "github:nix-community/disko" "--"
              "--yes-wipe-all-disks"
              "--mode" "destroy,format,mount" config-path]
        cmd  (if (root?) base (into ["sudo"] base))]
    (println)
    (println "== Applying disk layout with disko (via nix run) ==")
    (let [r (apply proc/shell {:continue true} cmd)]
      (when-not (zero? (:exit r))
        (die "disko failed -- the disk may be in a partial state.")))))

(defn ensure-swap-active!
  "Make sure swap partition(s) across the given `devices` are active for
  the rest of the install (nixos-install can spill there instead of the
  live ISO's RAM-backed store). disko's mount phase already runs `swapon`
  with a no-double-activation guard, so this is a confirmation + fallback."
  [devices]
  (doseq [d     devices
          p     (swap-partitions (:device d))]
    (let [base ["swapon" p]
          cmd  (if (root?) base (into ["sudo"] base))
          r    (apply proc/shell {:out :string :err :string :continue true} cmd)
          err  (str/trim (str (:err r)))]
      (cond
        (zero? (:exit r))             (println (str "Swap activated: " p))
        (str/includes? err "already") (println (str "Swap active: " p))
        :else (stderr (str "Warning: could not activate swap on " p ": " err))))))

;;; ============================================================
;;; Reinstall (keep /home + /nix, wipe root)
;;; ============================================================

(defn recreate-root-subvol!
  "On the existing btrfs at `btrfs-part`, delete the @ subvolume (and any
  nested subvolumes under it) and recreate an empty @. @home and @nix are
  left untouched, so the user's /home and /nix survive. Mounts the
  top-level (subvolid=5) at a temp dir for the operation."
  [btrfs-part]
  (println)
  (println "== Recreating the root subvolume (@) -- keeping @home and @nix ==")
  (let [tmp (str (fs/create-temp-dir {:prefix "btrfs-top-"}))]
    (try
      (when-not (zero? (:exit (sh {:continue true} "mount" "-o" "subvolid=5" btrfs-part tmp)))
        (die "could not mount btrfs top-level on" btrfs-part))
      (try
        ;; Delete @ and anything nested under it, deepest paths first so a
        ;; parent is never deleted before its children.
        (let [out    (:out (sh {:out :string :err :string :continue true}
                               "btrfs" "subvolume" "list" tmp))
              paths  (->> (str/split-lines (str out))
                          (keep #(second (re-find #"\bpath\s+(.+)$" %))))
              to-del (->> paths
                          (filter #(or (= % "@") (str/starts-with? % "@/")))
                          (sort-by #(count (re-seq #"/" %)) >))]
          (doseq [p to-del]
            (let [target (str (fs/path tmp p))]
              (println (str "  delete subvolume " p))
              (when-not (zero? (:exit (sh {:continue true} "btrfs" "subvolume" "delete" target)))
                (die "failed to delete subvolume" p))))
          (println "  create subvolume @")
          (when-not (zero? (:exit (sh {:continue true} "btrfs" "subvolume" "create"
                                      (str (fs/path tmp "@")))))
            (die "failed to create new @ subvolume")))
        (finally (sh {:continue true} "umount" tmp)))
      (finally (fs/delete-tree tmp)))))

(defn mount-reinstall!
  "Mount the preserved layout under /mnt for nixos-install: @ at /, @home
  at /home, @nix at /nix, plus a freshly-formatted ESP at /boot (UEFI) and
  any swap. Mount options mirror what `setup disk` writes into disko.nix.
  For a raid layout, mounting any single member exposes the whole pool."
  [{:keys [btrfs-part esp-part swap-parts uefi?]}]
  (let [opts "compress=zstd,noatime"
        mnt! (fn [subvol dst]
               (fs/create-dirs dst)
               (when-not (zero? (:exit (sh {:continue true} "mount"
                                           "-o" (str "subvol=" subvol "," opts)
                                           btrfs-part dst)))
                 (die "failed to mount" subvol "at" dst)))]
    (println)
    (println "== Mounting target under /mnt ==")
    (mnt! "@" "/mnt")
    (mnt! "@home" "/mnt/home")
    (mnt! "@nix" "/mnt/nix")
    (when (and uefi? esp-part)
      (println)
      (println (str "== Reformatting ESP (" esp-part ") for a fresh bootloader =="))
      (when-not (zero? (:exit (sh {:continue true} "mkfs.vfat" "-F" "32" esp-part)))
        (die "failed to reformat ESP" esp-part))
      (fs/create-dirs "/mnt/boot")
      (when-not (zero? (:exit (sh {:continue true} "mount" "-o" "umask=0077" esp-part "/mnt/boot")))
        (die "failed to mount ESP at /mnt/boot")))
    (doseq [sp swap-parts]
      (let [r   (sh {:out :string :err :string :continue true} "swapon" sp)
            err (str/trim (str (:err r)))]
        (cond
          (zero? (:exit r))             (println (str "Swap activated: " sp))
          (str/includes? err "already") (println (str "Swap active: " sp))
          :else (stderr (str "Warning: could not activate swap on " sp ": " err)))))))

(defn reinstall-flow!
  "The keep-data reinstall path: review, confirm, wipe @, remount. Returns
  after /mnt is ready for `setup install` (which reuses the preserved
  config repo on /home -- no `setup host` needed)."
  [{:keys [devices uefi?] :as layout}]
  (let [n         (count devices)
        target    (if (= 1 n)
                    (:device (first devices))
                    (str "raid (" n " disks): "
                         (str/join ", " (map :device devices))))]
    (println)
    (println "================ Reinstall ================")
    (println "Target:       " target)
    (println "Keep:          @home -> /home, @nix -> /nix   (data preserved)")
    (println "Recreate:      @ -> /                         (root WIPED)")
    (println "Bootloader:   " (if uefi?
                                (str "reformat ESP " (:esp-part layout))
                                "GRUB to existing bios_grub partition"))
    (println "Swap:         " (let [sps (:swap-parts layout)]
                                (if (seq sps) (str/join ", " sps) "none")))
    (println "===========================================")
    (println)
    (println (str "⚠️  This ERASES the root filesystem (@) on " target ", but keeps"))
    (println "    /home and /nix. Your config repo under /home survives.")
    (println)
    (when-not (sw/confirm "Proceed with reinstall?" :default :no)
      (println "Aborted.")
      (System/exit 0))
    ;; Drop any stale mounts from a previous run before touching @.
    (sh {:err :string :continue true} "umount" "-R" "/mnt")
    (recreate-root-subvol! (:btrfs-part layout))
    (mount-reinstall! layout)
    (println)
    (println "✅ Root wiped and target mounted under /mnt (/home and /nix preserved).")
    (println)
    (println "Next step:")
    (println "  setup install   # rebuild your EXISTING config and reinstall the bootloader")
    (println "  (skip `setup host` -- the config repo in /home/<user>/nixos is preserved.)")))

;;; ============================================================
;;; /mnt guard
;;; ============================================================
;;;
;;; /mnt is the installer's reserved target mountpoint. A leftover mount
;;; there -- typically from a previous `setup disk` run -- marks the
;;; target disk as in-use (see `node-mounted?`), so it'd be hidden and
;;; we'd bail with "No installable disks found". Detect it up front and
;;; offer to clear it before partitioning.

(defn mnt-mounted?
  "True if anything is currently mounted at /mnt or under it. Uses
  `findmnt` (util-linux, same package as lsblk) to list every mount
  target -- this sees the recursive subvolume/ESP mounts disko leaves
  behind, not just /mnt itself. (We avoid slurping /proc/mounts: reading
  procfs through babashka's slurp throws 'Invalid argument'.)"
  []
  (let [r (proc/shell {:out :string :err :string :continue true}
                      "findmnt" "-rno" "TARGET")]
    (and (zero? (:exit r))
         (->> (str/split-lines (str (:out r)))
              (some (fn [mp] (or (= mp "/mnt") (str/starts-with? mp "/mnt/"))))
              boolean))))

(defn unmount-mnt!
  "Recursively unmount everything under /mnt so the target disk is free
  to repartition. Dies if the unmount fails (something is still using it)."
  []
  (println)
  (println "== Unmounting /mnt ==")
  (let [r (sh {:err :string :continue true} "umount" "-R" "/mnt")]
    (if (zero? (:exit r))
      (println "/mnt unmounted.")
      (die (str "could not unmount /mnt: " (str/trim (str (:err r)))
                "\n  Something may still be using it -- close it and retry.")))))

(defn ensure-mnt-free!
  "If /mnt is mounted, refuse to partition until it's cleared. Offers
  'Unmount /mnt' as the first option; any other choice (or ESC) aborts."
  []
  (when (mnt-mounted?)
    (println)
    (println "⚠️  /mnt is currently mounted -- it's reserved for the installer target.")
    (println "    A previous `setup disk` run likely left it mounted, which marks the")
    (println "    target disk as in-use and hides it. Clear it before repartitioning.")
    (println)
    (let [unmount "Unmount /mnt"
          cancel  "Cancel"]
      (if (= unmount (sw/choose "/mnt is mounted -- what do you want to do?" [unmount cancel]))
        (unmount-mnt!)
        (do (println "Aborted.") (System/exit 0))))))

;;; ============================================================
;;; Swap guard
;;; ============================================================
;;;
;;; Active swap on a real disk partition shows up in lsblk as a [SWAP]
;;; mountpoint, so `node-mounted?` flags the whole disk as in-use and
;;; hides it -- yet it never appears in `mount`. A previous `setup disk`
;;; run leaves swap active (disko's mount phase + ensure-swap-active!),
;;; and the /mnt unmount above does NOT swapoff, so it lingers. Clear it
;;; before listing disks, just like the /mnt guard.

(defn active-disk-swaps
  "Active swap devices backed by a real disk partition (not zram).
  Read via `swapon` (not /proc/swaps -- slurping procfs throws in bb)."
  []
  (let [r (proc/shell {:out :string :err :string :continue true}
                      "swapon" "--show=NAME" "--noheadings")]
    (if-not (zero? (:exit r))
      []
      (->> (str/split-lines (str (:out r)))
           (map str/trim)
           (remove str/blank?)
           (remove #(str/starts-with? % "/dev/zram"))
           vec))))

(defn swapoff!
  "Disable the given swap devices so their parent disks are free to
  repartition. Dies if a swapoff fails."
  [devs]
  (println)
  (println "== Disabling active swap ==")
  (doseq [d devs]
    (let [r (sh {:err :string :continue true} "swapoff" d)]
      (if (zero? (:exit r))
        (println (str "swapoff " d))
        (die (str "could not swapoff " d ": " (str/trim (str (:err r)))))))))

(defn ensure-swap-off!
  "If swap is active on a real disk, refuse to partition until it's
  cleared. Offers 'Disable swap' first; any other choice (or ESC) aborts."
  []
  (when-let [devs (seq (active-disk-swaps))]
    (println)
    (println "⚠️  Active swap detected on a disk -- this marks it in-use and hides it:")
    (doseq [d devs] (println (str "    - " d)))
    (println "    A previous `setup disk` run likely left it active. Clear it before")
    (println "    repartitioning. (Swap never appears in `mount`.)")
    (println)
    (let [off    "Disable swap (swapoff)"
          cancel "Cancel"]
      (if (= off (sw/choose "Active swap found -- what do you want to do?" [off cancel]))
        (swapoff! devs)
        (do (println "Aborted.") (System/exit 0))))))

;;; ============================================================
;;; CLI
;;; ============================================================

(defn usage []
  (println "Usage: setup-disk [options]   (or: setup disk [options])")
  (println)
  (println "Partition, format, and mount disk(s) for NixOS install (btrfs).")
  (println "Supports either a single disk or a multi-disk btrfs raid.")
  (println)
  (println "Options:")
  (println "  --output FILE       Write disko.nix to FILE and exit (no changes made).")
  (println "  --no-apply          Generate the config but do not run disko.")
  (println "  --encrypt           Encrypt the disk(s) (LUKS) without prompting.")
  (println "  --no-encrypt        Skip encryption without prompting.")
  (println "                      (Default: ask interactively.)")
  (println "  --raid-level LEVEL  Btrfs raid level for multi-disk layouts:")
  (println "                      raid1 (2+), raid1c3 (3+), raid10 (4+), raid1c4 (4+).")
  (println "                      (Default: ask interactively when 2+ disks picked.)")
  (println "  --include-mounted   Also list disks with active mounts (e.g. the")
  (println "                      live boot medium). Off by default for safety.")
  (println "  -h, --help          Show help."))

(defn parse-args [args]
  (loop [args args opts {:apply true :output nil :include-mounted false
                         :encrypt nil :raid-level nil}]
    (if-let [a (first args)]
      (case a
        "--output"     (recur (drop 2 args) (assoc opts :output (second args) :apply false))
        "--no-apply"   (recur (rest args) (assoc opts :apply false))
        "--encrypt"    (recur (rest args) (assoc opts :encrypt true))
        "--no-encrypt" (recur (rest args) (assoc opts :encrypt false))
        "--raid-level" (recur (drop 2 args) (assoc opts :raid-level (second args)))
        "--include-mounted" (recur (rest args) (assoc opts :include-mounted true))
        ("-h" "--help") (do (usage) (System/exit 0))
        (do (stderr "Unknown option:" a) (usage) (System/exit 2)))
      opts)))

(defn total-ram-bytes
  "Total physical RAM in bytes from /proc/meminfo, or nil if unreadable."
  []
  (try
    (when (fs/exists? "/proc/meminfo")
      (some->> (str/split-lines (slurp "/proc/meminfo"))
               (some #(second (re-find #"^MemTotal:\s+(\d+)\s+kB" %)))
               (Long/parseLong)
               (* 1024)))
    (catch Exception _ nil)))

(defn ask-swap
  "Ask whether to create a swap partition and return a normalized size
  string (e.g. \"8G\"), or nil for no swap. Swap lets the install spill
  out of the live ISO's RAM-backed store, so it matters most on
  low-RAM machines."
  []
  (when-let [ram (total-ram-bytes)]
    (println (str "Detected RAM: " (human-size ram) ".")))
  (if (sw/confirm "Add a swap partition? (recommended for low-RAM machines)"
                  :default :no)
    (loop []
      (let [s (-> (sw/ask "Swap size (e.g. 8G, 2048M)" :default "8G")
                  str/trim str/upper-case
                  (str/replace #"\s+" "") (str/replace #"B$" ""))]
        (if (re-matches #"\d+(\.\d+)?[KMGT]?" s)
          s
          (do (println "Please enter a size like 8G or 2048M.") (recur)))))
    nil))

(defn ask-encrypt
  "Ask whether to encrypt the disk with LUKS. Returns a boolean. We only
  decide whether to generate the encrypted layout here -- disko itself
  prompts for and confirms the passphrase during formatting."
  [n-disks]
  (sw/confirm (if (= 1 n-disks)
                "Encrypt the disk with LUKS? (disko will prompt for a passphrase during formatting)"
                (str "Encrypt each disk with LUKS? (disko will prompt " n-disks " times during formatting -- one per disk)"))
              :default :no))

(defn valid-raid-levels
  "Btrfs raid levels appropriate for N disks. raid1 works with any 2+,
  raid1c3 needs 3+ copies, raid10 needs 4+ (pairs), raid1c4 needs 4+."
  [n]
  (cond-> []
    (>= n 2) (conj "raid1")
    (>= n 3) (conj "raid1c3")
    (>= n 4) (conj "raid10" "raid1c4")))

(defn ask-raid-level
  "Prompt for the btrfs raid level. Data and metadata are set to the same
  profile (`-d LEVEL -m LEVEL`) -- keeping them aligned is the common
  recommendation and avoids mixed-profile surprises."
  [n]
  (let [levels (valid-raid-levels n)]
    (when (empty? levels)
      (die "no valid btrfs raid level for" n "disks"))
    (sw/choose (str "Btrfs raid level (across " n " disks):") levels)))

(defn ask-layout
  "Choose single-disk vs multi-disk btrfs raid. Only offers raid when
  there are 2+ installable disks. Returns :single or :raid."
  [n-installable]
  (if (< n-installable 2)
    :single
    (let [single "Single disk (btrfs)"
          raid   "Multi-disk btrfs raid (raid1 / raid1c3 / raid10 / raid1c4)"]
      (if (= single (sw/choose "How do you want to lay out the disks?" [single raid]))
        :single :raid))))

(defn select-disks-multi
  "Pick 2+ disks in order for a btrfs raid. The FIRST pick carries the
  ESP/bios_grub (bootloader); subsequent picks are additional pool
  members. Returns the vector of chosen disk maps in pick order. Warns
  (but does not block) on significant size mismatch -- btrfs raid1
  sizes down to the smallest member."
  [disks]
  (let [done-label "Done -- I'm finished picking disks"
        pick-one   (fn [available prompt allow-done?]
                     (let [labels (disk-labels available)
                           opts   (if allow-done?
                                    (conj (vec labels) done-label)
                                    (vec labels))
                           chosen (sw/choose prompt opts)
                           idx    (.indexOf opts chosen)]
                       (cond
                         (nil? chosen)                (do (println "Aborted.") (System/exit 0))
                         (and allow-done?
                              (= idx (count labels))) nil
                         :else                        (nth available idx))))]
    (loop [remaining disks
           picked    []]
      (let [n          (count picked)
            allow-done (>= n 2)
            prompt     (cond
                         (zero? n) "Select the FIRST disk (this one carries the bootloader):"
                         (= 1 n)   "Select the SECOND disk (raid member):"
                         :else     (str "Add another disk (" n " picked), or finish:"))
            _          (when (and (not allow-done) (empty? remaining))
                         (die "not enough disks to build a raid (need 2+)."))
            pick       (pick-one remaining prompt allow-done)]
        (if (nil? pick)
          (do
            ;; Size mismatch warning: btrfs raid1 sizes down to the
            ;; smallest member, so a lopsided set wastes space.
            (let [sizes (map :size picked)
                  mn    (apply min sizes)
                  mx    (apply max sizes)]
              (when (and (pos? mn) (> (/ (- mx mn) (double mn)) 0.05))
                (println)
                (println "⚠️  Selected disks vary in size (>5%):")
                (doseq [d picked]
                  (println (str "     " (:name d) "  " (human-size (:size d)))))
                (println "    btrfs raid1 sizes down to the smallest member.")))
            picked)
          (recur (remove #(= (:name %) (:name pick)) remaining)
                 (conj picked pick)))))))

(defn -main []
  (let [opts (parse-args *command-line-args*)]
    (when-not (fs/which "lsblk") (die "'lsblk' not found."))
    (when (and (:apply opts) (not (fs/which "nix")))
      (die "'nix' not found -- cannot apply the layout (disko runs via 'nix run')."))

    ;; /mnt is reserved for the installer target. Clear any leftover mount
    ;; there before listing disks, or the target would be hidden as in-use.
    (ensure-mnt-free!)
    ;; Active swap on a real disk likewise marks it in-use (lsblk [SWAP]).
    (ensure-swap-off!)

    (let [uefi?     (fs/exists? "/sys/firmware/efi")
          all-disks (list-disks)
          _         (when (empty? all-disks) (die "No disks found."))
          in-use    (filter :in-use? all-disks)
          disks     (if (:include-mounted opts)
                      all-disks
                      (remove :in-use? all-disks))]

      (println "== Configure a disk for NixOS ==")
      (println (str "Firmware detected: " (if uefi? "UEFI" "legacy BIOS")))
      (println)

      ;; The boot medium (and any mounted data disk) is in use and cannot
      ;; be repartitioned -- hide it unless --include-mounted is given.
      (when (and (seq in-use) (not (:include-mounted opts)))
        (println "Skipping in-use disk(s) -- mounted by the running system (e.g. the boot medium):")
        (doseq [d in-use]
          (println (str "  - " (:name d) "  (" (human-size (:size d)) ")")))
        (println "Pass --include-mounted to override (rarely what you want).")
        (println))

      (when (empty? disks)
        (die "No installable disks found (every disk is in use)."))

      ;; Layout fork: single disk (existing behavior) or multi-disk btrfs
      ;; raid. Raid is only offered when 2+ installable disks exist.
      (let [layout   (ask-layout (count disks))
            _        (println)
            selected (case layout
                       :single
                       (let [labels (disk-labels disks)
                             chosen (sw/choose "Select the target disk:" labels)]
                         [(nth disks (.indexOf labels chosen))])
                       :raid
                       (select-disks-multi disks))
            devices  (mapv (fn [d] {:device (:name d) :size (:size d)}) selected)
            n        (count devices)
            _        (println)
            ;; If the disks already carry the @/@home/@nix layout this tool
            ;; creates, offer to reinstall (keep /home + /nix, wipe only /)
            ;; instead of erasing everything. For raid, all pool members
            ;; must be in the selected set. Only when actually applying --
            ;; --output/--no-apply just generate a fresh-install config.
            existing (when (:apply opts) (detect-reinstall devices))
            _        (when existing
                       (let [reinstall "Reinstall -- keep /home and /nix, wipe / and reinstall the bootloader"
                             fresh     "Fresh install -- ERASE and recreate everything"
                             target    (if (= 1 n)
                                         (:device (first devices))
                                         (str "raid: " (str/join ", " (map :device devices))))]
                         (println (str "⚠️  " target " already carries a NixOS btrfs layout (@, @home, @nix)."))
                         (when (= reinstall (sw/choose "How do you want to install?" [reinstall fresh]))
                           (reinstall-flow! (assoc existing :uefi? uefi?))
                           (System/exit 0))
                         (println)))
            ;; Encryption is fresh-install only: an existing encrypted
            ;; disk shows crypto_LUKS (not a btrfs with @/@home/@nix), so
            ;; detect-reinstall above returns nil and we land here.
            encrypt?   (if (nil? (:encrypt opts)) (ask-encrypt n) (:encrypt opts))
            ;; Raid level: prompt only for multi-disk. --raid-level lets
            ;; scripting override the interactive choice.
            raid-level (when (= :raid layout)
                         (let [cli (:raid-level opts)
                               ok  (set (valid-raid-levels n))]
                           (cond
                             (nil? cli)     (ask-raid-level n)
                             (contains? ok cli) cli
                             :else (die (str "--raid-level " cli " is not valid for "
                                             n " disks. Valid: "
                                             (str/join ", " ok))))))
            swap-size  (ask-swap)
            config     (disko-nix {:devices devices :uefi? uefi?
                                   :swap-size swap-size :encrypt? encrypt?
                                   :raid-level raid-level})]

        ;; Config-only mode: write and exit.
        (when (:output opts)
          (spit (:output opts) config)
          (println "Wrote disko config to:" (:output opts))
          (System/exit 0))

        ;; Strong confirmation: make the user re-type each device path.
        ;; One at a time (safer to read one path than a comma-joined list).
        (println)
        (println (if (= 1 n)
                   (str "About to DESTROY everything on: " (:device (first devices)))
                   (str "About to DESTROY everything on all " n " disks below.")))
        (doseq [{:keys [device]} devices]
          (let [typed (sw/ask (str "Type '" device "' to confirm"))]
            (when-not (= (str/trim typed) device)
              (die "Confirmation did not match. Aborting."))))

        (let [workdir     (str (fs/create-temp-dir {:prefix "nixos-disk-"}))
              config-path (str (fs/path workdir "disko.nix"))]
          (spit config-path config)

          (when-not (confirm-review {:devices devices :uefi? uefi?
                                     :swap-size swap-size :encrypt? encrypt?
                                     :raid-level raid-level
                                     :config-path config-path})
            (println "Aborted.")
            (System/exit 0))

          (when-not (:apply opts)
            (println "Skipping apply (--no-apply). Config at:" config-path)
            (System/exit 0))

          (apply-disko! config-path)

          ;; disko activates swap during mount; confirm it's live (and
          ;; activate as a fallback) so nixos-install can use it.
          (when swap-size (ensure-swap-active! devices))

          ;; Persist the layout into the new system so it can be
          ;; imported by the host's NixOS configuration later. /mnt was
          ;; mounted by disko as root, so when this tool runs as the
          ;; unprivileged live-ISO `nixos` user we must write through
          ;; `sh` (sudo) -- raw fs/copy would hit "permission denied",
          ;; leaving disko.nix absent and `setup host` failing with
          ;; "disko.nix not found".
          (let [dest    "/mnt/etc/nixos/disko.nix"
                mkdir-r (sh {:err :string :continue true} "mkdir" "-p" "/mnt/etc/nixos")
                copy-r  (when (zero? (:exit mkdir-r))
                          (sh {:err :string :continue true} "cp" "-f" config-path dest))
                ok?     (and (zero? (:exit mkdir-r)) copy-r (zero? (:exit copy-r)))]
            (when-not ok?
              (stderr "Could not save layout to" dest "--"
                      (str/trim (str (:err (or copy-r mkdir-r)))))
              (stderr "  `setup host` will fail until" dest "exists.")
              (System/exit 1))

            (println)
            (println "✅ Disk ready and mounted under /mnt.")
            (println "   Layout saved to" dest)
            (println)
            (println "Next steps:")
            (println "  1. setup host      # detect hardware + generate the host repo")
            (println "  2. setup install   # nixos-install from that repo")
            (println "  (or just `setup nixos` to run disk -> host -> install in one go.)")))))))

(-main)
