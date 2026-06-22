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
;;;   - pick a single target disk
;;;   - GPT layout: ESP (UEFI) or bios_grub (legacy BIOS) + btrfs root
;;;   - btrfs subvolumes: @ (/), @home (/home), @nix (/nix)
;;;   - optional swap partition
;;;   - optional full-disk LUKS encryption of the btrfs root (and, when
;;;     swap is present, random-key encryption of swap)
;;;   - apply declaratively with `disko` and mount everything under /mnt
;;;
;;; Encryption note: we never touch the passphrase ourselves. With no
;;; key/password file in the generated config, disko's `askPassword`
;;; defaults on -- it prompts for (and confirms) the passphrase via
;;; cryptsetup at format time. `initrdUnlock` likewise defaults on, so
;;; the disko NixOS module (imported by the host flake) generates the
;;; boot.initrd.luks unlock entry and the system prompts at boot.
;;;
;;; Future features (ext4/xfs, multi-disk) slot into the same
;;; generate-a-Nix-file-then-apply structure.
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

(defn detect-reinstall
  "If `device` already holds a btrfs with @, @home and @nix subvolumes,
  return {:btrfs-part :esp-part :swap-part}; otherwise nil. This is the
  layout `setup disk` itself creates, so its presence means we can wipe
  just the root (@) and keep the user's /home and /nix."
  [device]
  (when-let [btrfs-part (partition-of-fstype device "btrfs")]
    (let [subvols (btrfs-subvol-paths btrfs-part)]
      (when (every? subvols ["@" "@home" "@nix"])
        {:btrfs-part btrfs-part
         :esp-part   (partition-of-fstype device "vfat")
         :swap-part  (partition-of-fstype device "swap")}))))

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
  block when the disk is encrypted."
  [pad]
  (str
   pad "type = \"btrfs\";\n"
   pad "extraArgs = [ \"-f\" ];\n"
   (btrfs-subvolumes pad)))

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
  "The 100% root partition. When `encrypt?`, the btrfs lives inside a
  LUKS container exposed as /dev/mapper/cryptroot: disko prompts for the
  passphrase interactively at format time (askPassword defaults on with
  no key/password file) and the disko NixOS module adds the
  boot.initrd.luks unlock entry (initrdUnlock) automatically.
  allowDiscards passes TRIM through to the SSD."
  [encrypt?]
  (str
   "            root = {\n"
   "              size = \"100%\";\n"
   "              content = {\n"
   (if encrypt?
     (str
      "                type = \"luks\";\n"
      "                name = \"cryptroot\";\n"
      "                settings = { allowDiscards = true; };\n"
      "                content = {\n"
      (btrfs-content "                  ")
      "                };\n")
     (btrfs-content "                "))
   "              };\n"
   "            };\n"))

(defn disko-nix [{:keys [device uefi? swap-size encrypt?]}]
  (str
   "# Generated by disk_config.bb -- declarative disk layout (disko).\n"
   "# Apply:  disko --mode destroy,format,mount ./disko.nix\n"
   "{\n"
   "  disko.devices = {\n"
   "    disk = {\n"
   "      main = {\n"
   "        type = \"disk\";\n"
   "        device = \"" device "\";\n"
   "        content = {\n"
   "          type = \"gpt\";\n"
   "          partitions = {\n"
   (if uefi? (esp-partition) (bios-boot-partition))
   (when swap-size (swap-partition swap-size encrypt?))
   (root-partition encrypt?)
   "          };\n"
   "        };\n"
   "      };\n"
   "    };\n"
   "  };\n"
   "}\n"))

;;; ============================================================
;;; Review + apply
;;; ============================================================

(defn confirm-review [{:keys [device uefi? swap-size encrypt? config-path]}]
  (println)
  (println "================ Review =================")
  (println "Target disk: " device)
  (println "Firmware:    " (if uefi? "UEFI (ESP /boot)" "Legacy BIOS (bios_grub)"))
  (println "Filesystem:   btrfs")
  (println "Encryption:  " (if encrypt? "LUKS2 (passphrase set during format, prompted at boot)" "none"))
  (println "Subvolumes:   @ -> /, @home -> /home, @nix -> /nix")
  (println "Swap:        " (cond (and swap-size encrypt?) (str swap-size " (random-key encrypted)")
                                 swap-size                 swap-size
                                 :else                     "none"))
  (println "Config:      " config-path)
  (println "=========================================")
  (println)
  (println (str "⚠️  This ERASES ALL DATA on " device " and mounts the new"))
  (println "    filesystems under /mnt.")
  (when encrypt?
    (println)
    (println "    disko will prompt you to set the LUKS passphrase during"))
  (when encrypt?
    (println "    formatting -- keep it safe, it cannot be recovered."))
  (println)
  (sw/confirm "Proceed?" :default :no))

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
  "Make sure the swap partition(s) on `device` are active for the rest of
  the install (nixos-install can spill there instead of the live ISO's
  RAM-backed store). disko's mount phase already runs `swapon` with a
  no-double-activation guard, so this is a confirmation + fallback."
  [device]
  (doseq [p (swap-partitions device)]
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
  any swap. Mount options mirror what `setup disk` writes into disko.nix."
  [{:keys [btrfs-part esp-part swap-part uefi?]}]
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
    (when swap-part
      (let [r   (sh {:out :string :err :string :continue true} "swapon" swap-part)
            err (str/trim (str (:err r)))]
        (cond
          (zero? (:exit r))             (println (str "Swap activated: " swap-part))
          (str/includes? err "already") (println (str "Swap active: " swap-part))
          :else (stderr (str "Warning: could not activate swap on " swap-part ": " err)))))))

(defn reinstall-flow!
  "The keep-data reinstall path: review, confirm, wipe @, remount. Returns
  after /mnt is ready for `setup install` (which reuses the preserved
  config repo on /home -- no `setup host` needed)."
  [{:keys [device uefi?] :as layout}]
  (println)
  (println "================ Reinstall ================")
  (println "Target disk:  " device)
  (println "Keep:          @home -> /home, @nix -> /nix   (data preserved)")
  (println "Recreate:      @ -> /                         (root WIPED)")
  (println "Bootloader:   " (if uefi?
                              (str "reformat ESP " (:esp-part layout))
                              "GRUB to existing bios_grub partition"))
  (println "Swap:         " (or (:swap-part layout) "none"))
  (println "===========================================")
  (println)
  (println (str "⚠️  This ERASES the root filesystem (@) on " device ", but keeps"))
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
  (println "  (skip `setup host` -- the config repo in /home/<user>/nixos is preserved.)"))

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
;;; CLI
;;; ============================================================

(defn usage []
  (println "Usage: setup-disk [options]   (or: setup disk [options])")
  (println)
  (println "Partition, format, and mount a disk for NixOS install (btrfs).")
  (println)
  (println "Options:")
  (println "  --output FILE       Write disko.nix to FILE and exit (no changes made).")
  (println "  --no-apply          Generate the config but do not run disko.")
  (println "  --encrypt           Encrypt the root (LUKS) without prompting.")
  (println "  --no-encrypt        Skip encryption without prompting.")
  (println "                      (Default: ask interactively.)")
  (println "  --include-mounted   Also list disks with active mounts (e.g. the")
  (println "                      live boot medium). Off by default for safety.")
  (println "  -h, --help          Show help."))

(defn parse-args [args]
  (loop [args args opts {:apply true :output nil :include-mounted false :encrypt nil}]
    (if-let [a (first args)]
      (case a
        "--output"   (recur (drop 2 args) (assoc opts :output (second args) :apply false))
        "--no-apply" (recur (rest args) (assoc opts :apply false))
        "--encrypt"    (recur (rest args) (assoc opts :encrypt true))
        "--no-encrypt" (recur (rest args) (assoc opts :encrypt false))
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
  []
  (sw/confirm "Encrypt the disk with LUKS? (disko will prompt for a passphrase during formatting)"
              :default :no))

(defn -main []
  (let [opts (parse-args *command-line-args*)]
    (when-not (fs/which "lsblk") (die "'lsblk' not found."))
    (when (and (:apply opts) (not (fs/which "nix")))
      (die "'nix' not found -- cannot apply the layout (disko runs via 'nix run')."))

    ;; /mnt is reserved for the installer target. Clear any leftover mount
    ;; there before listing disks, or the target would be hidden as in-use.
    (ensure-mnt-free!)

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

      (let [labels  (disk-labels disks)
            chosen  (sw/choose "Select the target disk:" labels)
            disk    (nth disks (.indexOf labels chosen))
            device  (:name disk)
            _       (println)
            ;; If the disk already carries the @/@home/@nix layout this tool
            ;; creates, offer to reinstall (keep /home + /nix, wipe only /)
            ;; instead of erasing everything. Only when actually applying --
            ;; --output/--no-apply just generate a fresh-install config.
            existing (when (:apply opts) (detect-reinstall device))
            _       (when existing
                      (let [reinstall "Reinstall -- keep /home and /nix, wipe / and reinstall the bootloader"
                            fresh     "Fresh install -- ERASE the entire disk and recreate everything"]
                        (println (str "⚠️  " device " already has a NixOS btrfs layout (@, @home, @nix)."))
                        (when (= reinstall (sw/choose "How do you want to install?" [reinstall fresh]))
                          (reinstall-flow! (assoc existing :device device :uefi? uefi?))
                          (System/exit 0))
                        (println)))
            ;; Encryption is fresh-install only: an existing encrypted
            ;; disk shows crypto_LUKS (not a btrfs with @/@home/@nix), so
            ;; detect-reinstall above returns nil and we land here.
            encrypt?  (if (nil? (:encrypt opts)) (ask-encrypt) (:encrypt opts))
            swap-size (ask-swap)
            config  (disko-nix {:device device :uefi? uefi? :swap-size swap-size :encrypt? encrypt?})]

        ;; Config-only mode: write and exit.
        (when (:output opts)
          (spit (:output opts) config)
          (println "Wrote disko config to:" (:output opts))
          (System/exit 0))

        ;; Strong confirmation: make the user re-type the device path.
        (println)
        (println (str "About to DESTROY everything on: " device))
        (let [typed (sw/ask (str "Type '" device "' to confirm"))]
          (when-not (= (str/trim typed) device)
            (die "Confirmation did not match. Aborting.")))

        (let [workdir     (str (fs/create-temp-dir {:prefix "nixos-disk-"}))
              config-path (str (fs/path workdir "disko.nix"))]
          (spit config-path config)

          (when-not (confirm-review {:device device :uefi? uefi? :swap-size swap-size :encrypt? encrypt? :config-path config-path})
            (println "Aborted.")
            (System/exit 0))

          (when-not (:apply opts)
            (println "Skipping apply (--no-apply). Config at:" config-path)
            (System/exit 0))

          (apply-disko! config-path)

          ;; disko activates swap during mount; confirm it's live (and
          ;; activate as a fallback) so nixos-install can use it.
          (when swap-size (ensure-swap-active! device))

          ;; Persist the layout into the new system so it can be
          ;; imported by the host's NixOS configuration later.
          (let [dest "/mnt/etc/nixos/disko.nix"]
            (try
              (fs/create-dirs "/mnt/etc/nixos")
              (fs/copy config-path dest {:replace-existing true})
              (catch Exception e
                (stderr "Could not copy config to" dest ":" (.getMessage e))))

            (println)
            (println "✅ Disk ready and mounted under /mnt.")
            (println "   Layout saved to" dest)
            (println)
            (println "Next steps:")
            (println "  1. setup host      # detect hardware + generate the host repo")
            (println "  2. setup install   # nixos-install from that repo")
            (println "  (or just `setup nixos` to run disk -> host -> install in one go.)")))))))

(-main)
