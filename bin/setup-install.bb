#!/usr/bin/env bb

;;; ============================================================
;;; setup-install.bb
;;; ============================================================
;;;
;;; Install NixOS from the per-host repo that `setup host` generated:
;;;
;;;   1. nixos-install --root /mnt --flake <repo>#<host>
;;;   2. set the user's password (root's is set by nixos-install)
;;;   3. chown the repo to the user, inside the new system, so it's a
;;;      normal user-owned flake repo after reboot
;;;
;;; Run AFTER `setup disk` and `setup host`. Reboot when it finishes.
;;;
;;; One of the `setup-*` installer tools: run as `setup-install`, or via
;;; the dispatcher as `setup install`.
;;; ============================================================

(require '[babashka.pods :as pods])
(pods/load-pod ["script-wizard" "pod"])

(ns setup-install
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [clojure.string :as str]
            [pod.enigmacurry.script-wizard :as sw]))

;;; ============================================================
;;; Output / command helpers
;;; ============================================================

(defn stderr [& args]
  (binding [*out* *err*] (apply println args)))

(defn die [& msg]
  (when (seq msg) (binding [*out* *err*] (apply println "ERROR:" msg)))
  (System/exit 1))

(defn root? []
  (= "0" (str/trim (:out (proc/shell {:out :string :continue true} "id" "-u")))))

(defn run!
  "Echo and run a command, inheriting stdio. Dies on non-zero unless
  :check false. :dir sets the working directory."
  [{:keys [check dir] :or {check true}} & args]
  (println (str "+ " (str/join " " args)))
  (let [opts (cond-> {:continue true} dir (assoc :dir dir))
        r (apply proc/shell opts args)]
    (when (and check (not (zero? (:exit r))))
      (die (str "command failed (exit " (:exit r) "): " (str/join " " args))))
    r))

(defn capture [& args]
  (let [r (apply proc/shell {:out :string :err :string :continue true} args)]
    (if (zero? (:exit r)) (str/trim (:out r)) "")))

;;; ============================================================
;;; Discovery
;;; ============================================================

(defn discover-repos
  "Per-host flake repos under <root>/home/*/nixos (those with a flake.nix)."
  [root]
  (->> (fs/glob (fs/path root "home") "*/nixos/flake.nix")
       (map (comp str fs/parent))
       sort vec))

(defn repo-user
  "Username inferred from a repo path .../home/<user>/nixos."
  [repo]
  (str (fs/file-name (fs/parent repo))))

(defn flake-hosts
  "nixosConfigurations attr names exposed by the repo flake. Warns (rather
  than silently returning empty) if the eval fails, so a real error isn't
  hidden behind an unexpected 'enter the host name' prompt."
  [repo]
  (let [r (proc/shell {:out :string :err :string :continue true}
                      "nix" "--extra-experimental-features" "nix-command flakes"
                      "eval" "--raw" (str repo "#nixosConfigurations")
                      "--apply" "cfgs: builtins.concatStringsSep \"\\n\" (builtins.attrNames cfgs)")]
    (when-not (zero? (:exit r))
      (stderr (str "Warning: could not read hosts from " repo ":"))
      (stderr (str/trim (str (:err r)))))
    (->> (str/split-lines (str (:out r))) (map str/trim) (remove str/blank?) vec)))

(defn copy-network-config!
  "Copy the live ISO's NetworkManager connection profiles (e.g. the
  pre-seeded WiFi from `nix_build_iso.bb`) into the target, so a headless
  machine keeps network access after reboot. These are NetworkManager's
  own runtime store -- plain files, root:root 0600 -- so the secret stays
  out of the config repo. No-op if there are no profiles."
  [root]
  (let [src "/etc/NetworkManager/system-connections"
        dst (str (fs/path root "etc/NetworkManager/system-connections"))
        conns (when (fs/exists? src)
                (filter #(str/ends-with? (str %) ".nmconnection") (fs/list-dir src)))]
    (when (seq conns)
      (println)
      (println "== Copying NetworkManager connections into the target ==")
      (fs/create-dirs dst)
      (fs/set-posix-file-permissions dst "rwx------")
      (doseq [c conns]
        (let [name (str (fs/file-name c))
              out  (str (fs/path dst name))]
          ;; live files are symlinks into /nix/store -- deref to a real file
          (fs/copy (fs/real-path c) out {:replace-existing true})
          (fs/set-posix-file-permissions out "rw-------")
          (println (str "  " name)))))))

(defn copy-host-keys!
  "Copy the live ISO's SSH host keys (/etc/ssh/ssh_host_*_key[.pub]) into
  the target so the installed machine keeps the same SSH identity after
  reboot -- anyone who trusted the live host key over SSH won't hit a
  'REMOTE HOST IDENTIFICATION HAS CHANGED' warning, and NixOS leaves
  existing host keys in place rather than regenerating them on first boot.
  Private keys are written root:root 0600, public keys 0644. No-op if the
  live system has no host keys."
  [root]
  (let [src  "/etc/ssh"
        dst  (str (fs/path root "etc/ssh"))
        keys (when (fs/exists? src)
               (filter #(re-matches #"ssh_host_.*_key(\.pub)?" (str (fs/file-name %)))
                       (fs/list-dir src)))]
    (when (seq keys)
      (println)
      (println "== Copying SSH host keys into the target ==")
      (fs/create-dirs dst)
      (doseq [k keys]
        (let [name (str (fs/file-name k))
              out  (str (fs/path dst name))
              pub? (str/ends-with? name ".pub")]
          ;; deref in case the live file is a symlink into /nix/store
          (fs/copy (fs/real-path k) out {:replace-existing true})
          (fs/set-posix-file-permissions out (if pub? "rw-r--r--" "rw-------"))
          (println (str "  " name)))))))

;;; ============================================================
;;; CLI
;;; ============================================================

(defn usage []
  (println "Usage: setup-install [options]   (or: setup install [options])")
  (println)
  (println "Install NixOS from the host repo generated by `setup host`.")
  (println)
  (println "Options:")
  (println "  --flake DIR    Host repo (default: auto-discover under /mnt/home/*/nixos).")
  (println "  --host NAME    nixosConfigurations entry (default: auto/prompt).")
  (println "  --root DIR     Target mount (default: /mnt).")
  (println "  --no-update         Don't re-pin sway-home; install from the committed lock.")
  (println "  --no-passwd         Skip setting the user password.")
  (println "  --no-network-copy   Don't copy NetworkManager (WiFi) profiles into the target.")
  (println "  --no-host-keys      Don't copy the live SSH host keys (let NixOS generate new ones).")
  (println "  -h, --help          Show help."))

(defn parse-args [args]
  (loop [args args opts {:root "/mnt" :passwd true :update true :net-copy true :host-keys true}]
    (if-let [a (first args)]
      (case a
        "--flake"     (recur (drop 2 args) (assoc opts :flake (second args)))
        "--host"      (recur (drop 2 args) (assoc opts :host (second args)))
        "--root"      (recur (drop 2 args) (assoc opts :root (second args)))
        "--no-update" (recur (rest args) (assoc opts :update false))
        "--no-passwd" (recur (rest args) (assoc opts :passwd false))
        "--no-network-copy" (recur (rest args) (assoc opts :net-copy false))
        "--no-host-keys" (recur (rest args) (assoc opts :host-keys false))
        ("-h" "--help") (do (usage) (System/exit 0))
        (do (stderr "Unknown option:" a) (usage) (System/exit 2)))
      opts)))

;;; ============================================================
;;; Main
;;; ============================================================

(defn -main []
  (let [opts (parse-args *command-line-args*)
        root (:root opts)]
    (when-not (root?) (die "must run as root."))
    (doseq [bin ["nix" "nixos-install" "nixos-enter"]]
      (when-not (fs/which bin) (die (str "'" bin "' not found."))))
    (when-not (fs/exists? root) (die (str root " does not exist -- run `setup disk` first.")))

    (let [repo (or (:flake opts)
                   (let [repos (discover-repos root)]
                     (cond
                       (empty? repos) (die (str "no host repo under " root "/home/*/nixos -- run `setup host` first."))
                       (= 1 (count repos)) (first repos)
                       :else (sw/choose "Select the host repo to install:" (vec repos)))))
          _    (when-not (fs/exists? (str (fs/path repo "flake.nix")))
                 (die (str "no flake.nix in " repo)))
          ;; A reinstall keeps the repo on /home, owned by the target user
          ;; rather than the root user running the installer. Mark it safe
          ;; BEFORE flake-hosts -- otherwise `nix eval` on the git flake
          ;; fails with "dubious ownership" and we'd see zero hosts and
          ;; fall back to prompting. Harmless on a fresh (root-owned) repo.
          _    (run! {:check false} "git" "config" "--global" "--add" "safe.directory" repo)
          user (repo-user repo)
          hosts (flake-hosts repo)
          host (or (:host opts)
                   (cond
                     (= 1 (count hosts)) (first hosts)
                     (seq hosts) (sw/choose "Select the host to install:" hosts)
                     :else (str/trim (sw/ask "Host name (nixosConfigurations entry)"))))]

      (when (str/blank? host) (die "no host selected."))

      (println)
      (println "================ Review =================")
      (println "Host repo:    " repo)
      (println "Host:         " host)
      (println "User:         " user)
      (println "Target root:  " root)
      (println "=========================================")
      (println)
      (println (str "This builds and installs NixOS into " root " (downloads the system"))
      (println "    closure from the binary cache) and sets passwords.")
      (println)
      (when-not (sw/confirm "Proceed with install?" :default :yes)
        (println "Aborted.") (System/exit 0))

      ;; 1. Re-pin sway-home to latest so a fresh fix is picked up without
      ;; regenerating the repo. nixos-install builds the COMMITTED git tree,
      ;; so the updated lock must be committed (else the old pin is used).
      (when (:update opts)
        (println)
        (println "== Re-pinning sway-home (nix flake update sway-home) ==")
        (run! {:dir repo} "nix" "--extra-experimental-features" "nix-command flakes"
              "flake" "update" "sway-home")
        (if (str/blank? (capture "git" "-C" repo "status" "--porcelain" "flake.lock"))
          (println "Already at the latest sway-home pin.")
          (do (run! {:dir repo} "git" "add" "flake.lock")
              (run! {:dir repo} "git"
                    "-c" "user.name=setup-install" "-c" "user.email=setup-install@localhost"
                    "commit" "-q" "-m" "Update sway-home pin"))))

      ;; 2. Install. nixos-install prompts for the root password at the end.
      (println)
      (println "== Installing NixOS ==")
      (run! {} "nixos-install" "--root" root "--flake" (str repo "#" host))

      ;; 3. Set the user's password inside the new system.
      (when (:passwd opts)
        (println)
        (println (str "== Set a password for user '" user "' =="))
        (run! {:check false} "nixos-enter" "--root" root "-c" (str "passwd " user)))

      ;; 4. Make the repo user-owned, resolving <user> inside the new system.
      (println)
      (println "== Fixing ownership of the host repo ==")
      (run! {:check false} "nixos-enter" "--root" root "-c"
            (str "chown -R " user ":users /home/" user))

      ;; 5. Carry the live WiFi/NetworkManager profiles into the target.
      (when (:net-copy opts)
        (copy-network-config! root))

      ;; 6. Carry the live SSH host keys into the target so the installed
      ;; machine keeps the same SSH identity after reboot.
      (when (:host-keys opts)
        (copy-host-keys! root))

      (println)
      (println "✅ Install complete.")
      (println (str "   Config repo: /home/" user "/nixos  (owned by " user " after reboot)"))
      (println "   Apply future changes with:  sudo nixos-rebuild switch --flake .#" host)
      (println)
      (when (sw/confirm "Reboot now?" :default :no)
        (run! {:check false} "reboot")))))

(-main)
