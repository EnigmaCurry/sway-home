#!/usr/bin/env bb

;;; ============================================================
;;; setup-host.bb
;;; ============================================================
;;;
;;; Generate a fresh, self-contained NixOS flake repo for ONE host and
;;; place it on the target install at /mnt/home/<user>/nixos.
;;;
;;; The generated repo holds only this host's config (disko.nix +
;;; hardware.nix + config.nix) and pulls in sway-home as a pinned flake
;;; input -- sway-home itself holds no per-host config. After install it
;;; becomes a normal user-owned git repo you edit and `sudo nixos-rebuild
;;; switch` from (ownership is fixed up by `setup install`, once the user
;;; exists in the installed system).
;;;
;;; Run AFTER `setup disk` (which writes /mnt/etc/nixos/disko.nix and
;;; mounts the target under /mnt). Run `setup install` next.
;;;
;;; One of the `setup-*` installer tools: run as `setup-host`, or via the
;;; dispatcher as `setup host`.
;;; ============================================================

(require '[babashka.pods :as pods])
(pods/load-pod ["script-wizard" "pod"])

(ns setup-host
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [clojure.string :as str]
            [pod.enigmacurry.script-wizard :as sw]))

;; sway-home flake ref the generated host repo depends on (it exports
;; lib.mkHost). Override at runtime with `setup host --sway-home-ref REF`.
(def default-sway-home-ref "github:EnigmaCurry/sway-home/master")

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
  "Echo and run a command, inheriting stdio. Dies on a non-zero exit
  unless :check false. Pass :dir to set the working directory."
  [{:keys [check dir] :or {check true}} & args]
  (println (str "+ " (str/join " " args)))
  (let [opts (cond-> {:continue true} dir (assoc :dir dir))
        r (apply proc/shell opts args)]
    (when (and check (not (zero? (:exit r))))
      (die (str "command failed (exit " (:exit r) "): " (str/join " " args))))
    r))

(defn capture
  "Run a command, return trimmed stdout (empty string on failure)."
  [{:keys [dir]} & args]
  (let [opts (cond-> {:out :string :err :string :continue true} dir (assoc :dir dir))
        r (apply proc/shell opts args)]
    (if (zero? (:exit r)) (str/trim (:out r)) "")))

(defn authorized-keys
  "SSH public keys currently authorized to log into the live ISO (baked
  into the image by nix_build_iso.bb). Seeded into the host's config.nix
  so the installed machine is reachable -- public keys, safe to commit."
  []
  (->> ["/etc/ssh/authorized_keys.d/root"
        "/root/.ssh/authorized_keys"
        (str (fs/path (System/getProperty "user.home") ".ssh/authorized_keys"))]
       (mapcat (fn [f] (when (fs/exists? f) (str/split-lines (slurp f)))))
       (map str/trim)
       (filter #(re-find #"^(ssh-|ecdsa-|sk-)" %))
       distinct
       vec))

;;; ============================================================
;;; Generated file contents
;;; ============================================================

(defn flake-nix [{:keys [host user system ref profile]}]
  (str
   "{\n"
   "  description = \"NixOS host: " host "\";\n\n"
   "  # sway-home is the shared config library; this repo holds only the\n"
   "  # per-host bits below. Update the pin with `nix flake update`.\n"
   "  inputs.sway-home.url = \"" ref "\";\n\n"
   "  outputs = { self, sway-home, ... }: {\n"
   "    nixosConfigurations." host " = sway-home.lib.mkHost {\n"
   "      hostName = \"" host "\";\n"
   "      userName = \"" user "\";\n"
   "      # \"sway\" = full desktop; \"minimal\" = bare server (sshd, no desktop).\n"
   "      profile = \"" profile "\";\n"
   ;; system defaults to x86_64-linux in mkHost; only emit it otherwise.
   (when (not= system "x86_64-linux")
     (str "      system = \"" system "\";\n"))
   "\n"
   "      # Per-host config: disko.nix (disk layout), hardware.nix (detected\n"
   "      # hardware, no filesystems), config.nix (everything else, incl.\n"
   "      # locale, packages, services).\n"
   "      modules = [\n"
   "        ./disko.nix\n"
   "        ./hardware.nix\n"
   "        ./config.nix\n"
   "      ];\n"
   "    };\n"
   "  };\n"
   "}\n"))

(defn config-nix [{:keys [user ssh-keys tz]}]
  (str
   "{ inputs, host, config, pkgs, unstablePkgs, lib, ... }:\n\n"
   "{\n"
   "  # Host-specific overrides. This is imported into the shared sway-home\n"
   "  # configuration, so anything set here wins (use lib.mkForce to beat a\n"
   "  # value that merges).\n\n"
   "  # --- Locale / keyboard ---\n"
   "  time.timeZone = \"" tz "\";\n"
   "  i18n.defaultLocale = \"en_US.UTF-8\";\n"
   "  services.xserver.xkb = { layout = \"us\"; variant = \"\"; options = \"ctrl:nocaps\"; };\n"
   "  console.useXkbConfig = true;\n\n"
   "  # SSH is enabled (key-only) by the shared config. These are the public\n"
   "  # keys allowed to log in as " user ".\n"
   (if (seq ssh-keys)
     (str "  # (Seeded from the install ISO -- add/remove keys here.)\n"
          "  users.users.\"" user "\".openssh.authorizedKeys.keys = [\n"
          (str/join "" (map #(str "    \"" % "\"\n") ssh-keys))
          "  ];\n\n")
     (str "  # WARNING: no keys were found on the ISO. Add at least one or you\n"
          "  # will be locked out (sshd is key-only):\n"
          "  # users.users.\"" user "\".openssh.authorizedKeys.keys = [ \"ssh-ed25519 AAAA...\" ];\n\n"))
   "  # Let `sudo nixos-rebuild --flake ~/nixos` (root) read this\n"
   "  # user-owned repo without git's \"dubious ownership\" error.\n"
   "  programs.git.config.safe.directory = \"/home/" user "/nixos\";\n\n"
   "  # --- Allow incoming network ports ------\n"
   "  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];\n\n"
   "  # --- Packages: stable and unstable in one list, no flake.nix edits ---\n"
   "  # environment.systemPackages = [\n"
   "  #   pkgs.btop            # from the stable channel\n"
   "  #   unstablePkgs.zellij  # from nixpkgs-unstable\n"
   "  # ];\n\n"
   "  # --- Enable services ---\n"
   "  # services.printing.enable = true;\n"
   "}\n"))

(defn justfile [{:keys [host]}]
  (str
   "set shell := [\"bash\", \"-eu\", \"-o\", \"pipefail\", \"-c\"]\n\n"
   "# print help\n"
   "help:\n"
   "    @just -l\n\n"
   "# Rebuild NixOS and switch to the new generation\n"
   "switch:\n"
   "    sudo nixos-rebuild switch --flake .#" host "\n\n"
   "# Rebuild and test (reverts on reboot)\n"
   "test:\n"
   "    sudo nixos-rebuild test --flake .#" host "\n\n"
   "# Update the sway-home pin (and other inputs)\n"
   "update:\n"
   "    nix flake update\n\n"
   "# Update inputs, then rebuild and switch\n"
   "upgrade: update switch\n"))

(def gitignore "result\nresult-*\n")

;;; ============================================================
;;; CLI
;;; ============================================================

(defn usage []
  (println "Usage: setup-host [options]   (or: setup host [options])")
  (println)
  (println "Generate a per-host NixOS flake repo at /mnt/home/<user>/nixos that")
  (println "depends on sway-home, then commit it. Run after `setup disk`.")
  (println)
  (println "Options:")
  (println "  --host NAME           Hostname (prompted if omitted).")
  (println "  --user NAME           Primary username (prompted if omitted).")
  (println "  --profile NAME        'minimal' (server, default) or 'sway' (full desktop). Prompted if omitted.")
  (println "  --sway-home-ref REF   Override the sway-home flake ref.")
  (println "  --root DIR            Target mount (default: /mnt).")
  (println "  -h, --help            Show help."))

(defn parse-args [args]
  (loop [args args opts {:root "/mnt" :ref default-sway-home-ref}]
    (if-let [a (first args)]
      (case a
        "--host"          (recur (drop 2 args) (assoc opts :host (second args)))
        "--user"          (recur (drop 2 args) (assoc opts :user (second args)))
        "--profile"       (recur (drop 2 args) (assoc opts :profile (second args)))
        "--sway-home-ref" (recur (drop 2 args) (assoc opts :ref (second args)))
        "--root"          (recur (drop 2 args) (assoc opts :root (second args)))
        ("-h" "--help")   (do (usage) (System/exit 0))
        (do (stderr "Unknown option:" a) (usage) (System/exit 2)))
      opts)))

;;; ============================================================
;;; Main
;;; ============================================================

(defn -main []
  (let [opts (parse-args *command-line-args*)
        root (:root opts)]
    (when-not (root?) (die "must run as root (it writes under" (str root "/home") "and runs nixos-generate-config)."))
    (doseq [bin ["nix" "git" "nixos-generate-config"]]
      (when-not (fs/which bin) (die (str "'" bin "' not found."))))
    (when-not (fs/exists? root)
      (die (str root " does not exist -- run `setup disk` first to mount the target.")))
    (let [disko-src (str (fs/path root "etc/nixos/disko.nix"))]
      (when-not (fs/exists? disko-src)
        (die (str disko-src " not found -- run `setup disk` first.")))

      (println "== Generate a per-host NixOS config ==")
      (println)

      (let [host (or (:host opts) (str/trim (sw/ask "Hostname" :default "nixos")))
            user (or (:user opts)
                     (loop []
                       (let [u (str/trim (sw/ask "Primary username"))]
                         (if (str/blank? u)
                           (do (println "Username is required.") (recur))
                           u))))
            tz   (str/trim (sw/ask "Time zone" :default "America/Denver"))
            profile (or (:profile opts)
                        (let [choices [["minimal" "Minimal server (sshd only, no desktop)"]
                                       ["sway"    "Sway desktop (full environment)"]]
                              labels  (mapv second choices)
                              chosen  (sw/choose "Select an install profile:" labels)]
                          (first (first (filter #(= (second %) chosen) choices)))))
            ssh-keys (authorized-keys)
            system (str/trim (capture {} "nix" "eval" "--impure" "--raw" "--expr" "builtins.currentSystem"))
            system (if (str/blank? system) "x86_64-linux" system)
            repo (str (fs/path root "home" user "nixos"))]

        (when (and (str/blank? host) (str/blank? user))
          (die "hostname and username are required."))

        (let [exists? (fs/exists? repo)]
          (println)
          (println "================ Review =================")
          (println "Hostname:     " host)
          (println "Username:     " user)
          (println "Profile:      " profile (if (= profile "sway") "(full desktop)" "(minimal server, sshd only)"))
          (println "Time zone:    " tz)
          (println "System:       " system)
          (println "SSH keys:     " (if (seq ssh-keys) (str (count ssh-keys) " (seeded from ISO)") "NONE FOUND -- you must add one in config.nix"))
          (println "sway-home:    " (:ref opts))
          (println "Host repo:    " repo (when exists? "  (EXISTS -- will be overwritten)"))
          (println "=========================================")
          (println)
          (when-not (sw/confirm "Generate this host config?" :default :yes)
            (println "Aborted.") (System/exit 0))
          ;; Overwrite an existing repo (re-runnable dev loop) after confirm.
          (when exists? (fs/delete-tree repo)))

        ;; 1. Detect hardware WITHOUT filesystems (disko owns those).
        (println)
        (println "== Detecting hardware (nixos-generate-config --no-filesystems) ==")
        (run! {} "nixos-generate-config" "--root" root "--no-filesystems")
        (let [hw-src (str (fs/path root "etc/nixos/hardware-configuration.nix"))]
          (when-not (fs/exists? hw-src)
            (die (str "expected " hw-src " after nixos-generate-config.")))

          ;; 2. Assemble the host repo.
          (println)
          (println "== Writing host repo:" repo "==")
          (fs/create-dirs repo)
          (fs/copy disko-src (fs/path repo "disko.nix") {:replace-existing true})
          (fs/copy hw-src (fs/path repo "hardware.nix") {:replace-existing true})
          (spit (str (fs/path repo "flake.nix"))
                (flake-nix {:host host :user user :system system :ref (:ref opts) :profile profile}))
          (spit (str (fs/path repo "config.nix")) (config-nix {:user user :ssh-keys ssh-keys :tz tz}))
          (spit (str (fs/path repo "Justfile")) (justfile {:host host}))
          (spit (str (fs/path repo ".gitignore")) gitignore)
          (doseq [f ["flake.nix" "disko.nix" "hardware.nix" "config.nix" "Justfile" ".gitignore"]]
            (println (str "  wrote " f)))

          ;; 3. Show the generated flake (the part that wires it together).
          (println)
          (println "---------------- flake.nix ----------------")
          (print (slurp (str (fs/path repo "flake.nix"))))
          (println "-------------------------------------------")

          ;; 4. Init git and pin sway-home (fetches it -> flake.lock).
          (println)
          (println "== Initializing git + pinning inputs ==")
          (run! {:dir repo} "git" "init" "-q" "-b" "main")
          (run! {:dir repo} "git" "add" "-A")
          (println)
          (println "== Resolving sway-home (nix flake lock) ==")
          (run! {:dir repo} "nix" "--extra-experimental-features" "nix-command flakes"
                "flake" "lock")
          (run! {:dir repo} "git" "add" "flake.lock")
          (run! {:dir repo} "git"
                "-c" "user.name=setup-host" "-c" "user.email=setup-host@localhost"
                "commit" "-q" "-m" (str "Initial config for " host))

          (println)
          (println "== git log ==")
          (run! {:dir repo} "git" "--no-pager" "log" "--oneline" "-1" "--stat")

          (println)
          (println "✅ Host repo ready at" repo)
          (println "   (still root-owned; `setup install` fixes ownership after install.)")
          (println)
          (println "Next step:")
          (println (str "  setup install   # nixos-install --flake " repo "#" host)))))))

(-main)
