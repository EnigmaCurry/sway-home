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

(defn flake-nix [{:keys [host user system ref adopt?]}]
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
   ;; Desktop vs server is chosen in config.nix via my.profiles.sway.enable
   ;; (along with every other profile), so there is no profile arg here.
   ;; system defaults to x86_64-linux in mkHost; only emit it otherwise.
   (when (not= system "x86_64-linux")
     (str "      system = \"" system "\";\n"))
   "\n"
   ;; Adopt reuses the installer's hardware-configuration.nix (filesystems
   ;; and all) in place of a disko.nix; the ISO flow generates disko + a
   ;; filesystem-less hardware.nix instead.
   (if adopt?
     (str "      # Per-host config: hardware.nix (the installer's existing\n"
          "      # hardware-configuration.nix, kept WITH its filesystems) and\n"
          "      # config.nix (everything else: locale, packages, services).\n")
     (str "      # Per-host config: disko.nix (disk layout), hardware.nix (detected\n"
          "      # hardware, no filesystems), config.nix (everything else, incl.\n"
          "      # locale, packages, services).\n"))
   "      modules = [\n"
   (when-not adopt? "        ./disko.nix\n")
   "        ./hardware.nix\n"
   "        ./config.nix\n"
   "      ];\n"
   "    };\n"
   "  };\n"
   "}\n"))

;; The composable profiles offered by `setup host` and rendered into the
;; generated config.nix as `my.profiles.<key>.enable` toggles. Each maps to a
;; module in sway-home's nixos/modules/profiles/.
(def profile-catalog
  [["dotfiles" "Shell/CLI home environment (bashrc, ~/.config dotfiles, emacs, CLI tools) -- no GUI"]
   ["sway"    "Sway desktop (greetd login, sway, fonts, firefox; implies dotfiles)"]
   ["sound"   "PipeWire audio"]
   ["podman"  "Podman containers (Docker-compatible)"]
   ["flatpak" "Flatpak + Flathub remote"]
   ["libvirt" "libvirt/KVM virtualization (the `vm` command, virt-manager)"]])

;; Render one aligned `my.profiles.<key>.enable = true;` line: uncommented
;; when selected, a commented example otherwise.
(defn- profile-line [selected [key desc]]
  (let [enabled (contains? selected key)
        lead    (str (if enabled "  " "  # ") "my.profiles." key ".enable")
        pad     (apply str (repeat (max 1 (- 31 (count lead))) \space))]
    (str lead pad "= true;   # " desc "\n")))

(defn config-nix [{:keys [user ssh-keys tz profiles]}]
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
     (str "  # (Pre-filled from the keys already authorized for you -- add/remove.)\n"
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
   "  # services.qemuGuest.enable = true;   # QEMU guest agent (when this host is a QEMU/KVM VM)\n\n"
   "  # --- Profiles (sway-home) --------------------------------------------\n"
   "  # Composable toggles -- each enables a fully-wired subsystem (daemon,\n"
   "  # groups, packages and all). Defined in nixos/modules/profiles/ in\n"
   "  # sway-home. sway = the graphical desktop; the rest are additive add-ons.\n"
   "  # (Chosen at install time; flip any of these and run `just switch`.)\n"
   (apply str (map #(profile-line profiles %) profile-catalog))
   "\n"
   "  # --- Optional: Solokey (FIDO2) sudo authentication -------------------\n"
   "  # Touch a hardware key instead of typing a password for sudo. Full\n"
   "  # walkthrough (PIN, registration, the modes, escape hatches) is in the\n"
   "  # book: https://book.rymcg.tech/nixos-workstation/sudo-solokey/\n"
   "  #\n"
   "  # Register your key(s) first, paste the pamu2fcfg line below, uncomment\n"
   "  # this block, then pick ONE mode.\n"
   "  #\n"
   "  # environment.etc.\"u2f_keys\".text = ''\n"
   "  #   " user ":hQ2k...,es256,+presence:tZ9p...,es256,+presence\n"
   "  # '';\n"
   "  # security.pam.u2f.settings = { cue = true; authfile = \"/etc/u2f_keys\"; };\n"
   "  # # Turn u2f on for the sudo PAM service ONLY (not login, ssh, greetd):\n"
   "  # security.pam.services.sudo.u2fAuth = true;\n"
   "  #\n"
   "  # -- Pick ONE mode --\n"
   "  # Mode 1 -- KEY ONLY (no password asked; lose every key => no sudo):\n"
   "  # security.pam.u2f.control            = \"sufficient\";\n"
   "  # security.pam.services.sudo.unixAuth = false;\n"
   "  # Mode 2 -- KEY OR PASSWORD (touch, or fall back to your password):\n"
   "  # security.pam.u2f.control            = \"sufficient\";\n"
   "  # Mode 3 -- KEY AND PASSWORD (real two-factor; both every time):\n"
   "  # security.pam.u2f.control            = \"required\";\n"
   "  #\n"
   "  # -- Optional: also unlock sudo REMOTELY over SSH (Mode 1 or 2 only) --\n"
   "  # Authenticate against a FIDO2 (-sk) SSH key in your forwarded agent, so\n"
   "  # the touch happens on the key in your laptop. Create it with\n"
   "  # `ssh-keygen -t ed25519-sk` and add the public key to authorizedKeys\n"
   "  # above. Connect with `ssh -A`. Do NOT combine with Mode 3 (this path\n"
   "  # is sufficient and short-circuits the second factor).\n"
   "  # security.pam.sshAgentAuth.enable        = true;\n"
   "  # security.pam.services.sudo.sshAgentAuth = true;\n\n"
   "  # --- Desktop programs ---\n"
   "  # programs.firefox.enable = true;\n"
   "  # programs.gnupg.agent = { enable = true; enableSSHSupport = true; };\n"
   "}\n"))

(defn justfile [{:keys [host]}]
  (str
   "set shell := [\"bash\", \"-eu\", \"-o\", \"pipefail\", \"-c\"]\n"
   "set positional-arguments\n\n"
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
   "upgrade: update switch\n\n"
   "# Run git in this config repo from any directory (e.g. admin git status)\n"
   "git *args:\n"
   "    @git -C \"{{justfile_directory()}}\" \"$@\"\n"))

(def gitignore "result\nresult-*\n")

;;; ============================================================
;;; CLI
;;; ============================================================

(defn usage []
  (println "Usage: setup-host [options]   (or: setup host [options])")
  (println)
  (println "Generate a per-host NixOS flake repo that depends on sway-home, then")
  (println "commit it. Two flows:")
  (println)
  (println "  (default)  ISO install: writes /mnt/home/<user>/nixos, run as root")
  (println "             after `setup disk` (uses disko + a filesystem-less hardware.nix).")
  (println "  --adopt    Adopt an existing install (e.g. the official NixOS installer):")
  (println "             writes ~/nixos as your normal user, reusing the existing")
  (println "             /etc/nixos/hardware-configuration.nix instead of disko. Run")
  (println "             `sudo nixos-rebuild switch` yourself afterward.")
  (println)
  (println "Options:")
  (println "  --host NAME           Hostname (prompted if omitted).")
  (println "  --user NAME           Primary username (prompted; --adopt defaults to you).")
  (println "  --profiles LIST       Comma-separated profiles to enable: sway,sound,podman,flatpak,libvirt.")
  (println "                        Multi-select prompt if omitted; none = minimal server.")
  (println "  --adopt               Adopt the running system instead of a /mnt install target.")
  (println "  --sway-home-ref REF   Override the sway-home flake ref.")
  (println "  --root DIR            Target mount (default: /mnt; ignored with --adopt).")
  (println "  -h, --help            Show help."))

(defn parse-args [args]
  (loop [args args opts {:root "/mnt" :ref default-sway-home-ref}]
    (if-let [a (first args)]
      (case a
        "--host"          (recur (drop 2 args) (assoc opts :host (second args)))
        "--user"          (recur (drop 2 args) (assoc opts :user (second args)))
        "--profiles"      (recur (drop 2 args) (assoc opts :profiles (set (remove str/blank? (str/split (second args) #",")))))
        "--profile"       (recur (drop 2 args) (update opts :profiles (fnil conj #{}) (second args)))
        "--sway-home-ref" (recur (drop 2 args) (assoc opts :ref (second args)))
        "--adopt"         (recur (drop 1 args) (assoc opts :adopt true))
        "--root"          (recur (drop 2 args) (assoc opts :root (second args)))
        ("-h" "--help")   (do (usage) (System/exit 0))
        (do (stderr "Unknown option:" a) (usage) (System/exit 2)))
      opts)))

;;; ============================================================
;;; Main
;;; ============================================================

(defn -main []
  (let [opts   (parse-args *command-line-args*)
        adopt? (:adopt opts)
        ;; ISO flow installs into a mounted target (/mnt); adopt runs on the
        ;; already-booted system and builds the repo in the live root.
        root   (if adopt? "/" (:root opts))]
    (when (and (not adopt?) (not (root?)))
      (die "must run as root (it writes under" (str root "/home") "and runs nixos-generate-config)."))
    (when (and adopt? (root?))
      (die "run --adopt as your normal user, not root -- it builds ~/nixos and git-inits it as you."))
    (doseq [bin (cond-> ["nix" "git"] (not adopt?) (conj "nixos-generate-config"))]
      (when-not (fs/which bin) (die (str "'" bin "' not found."))))
    (when-not (fs/exists? root)
      (die (str root " does not exist -- run `setup disk` first to mount the target.")))
    (let [disko-src   (str (fs/path root "etc/nixos/disko.nix"))
          hw-existing (str (fs/path root "etc/nixos/hardware-configuration.nix"))]
      (when (and (not adopt?) (not (fs/exists? disko-src)))
        (die (str disko-src " not found -- run `setup disk` first.")))
      (when (and adopt? (not (fs/exists? hw-existing)))
        (die (str hw-existing " not found -- expected on a machine installed by\n"
                  "the official NixOS installer. --adopt reuses it instead of disko.")))

      (println (if adopt?
                 "== Adopt this machine as a sway-home host =="
                 "== Generate a per-host NixOS config =="))
      (println)

      (let [host (or (:host opts) (str/trim (sw/ask "Hostname" :default "nixos")))
            user (or (:user opts)
                     (if adopt?
                       (str/trim (sw/ask "Primary username" :default (str/trim (capture {} "id" "-un"))))
                       (loop []
                         (let [u (str/trim (sw/ask "Primary username"))]
                           (if (str/blank? u)
                             (do (println "Username is required.") (recur))
                             u)))))
            tz   (str/trim (sw/ask "Time zone" :default "America/Denver"))
            profiles (or (:profiles opts)
                         (let [labels     (mapv (fn [[k d]] (str k " - " d)) profile-catalog)
                               label->key (zipmap labels (map first profile-catalog))
                               chosen     (sw/select "Select profiles to enable (space toggles, enter confirms; none = minimal server):" labels)]
                           (set (keep label->key chosen))))
            ssh-keys (authorized-keys)
            system (str/trim (capture {} "nix" "eval" "--impure" "--raw" "--expr" "builtins.currentSystem"))
            system (if (str/blank? system) "x86_64-linux" system)
            repo (if adopt?
                   (str (fs/path (System/getProperty "user.home") "nixos"))
                   (str (fs/path root "home" user "nixos")))]

        (when (and (str/blank? host) (str/blank? user))
          (die "hostname and username are required."))

        (let [exists? (fs/exists? repo)]
          (println)
          (println "================ Review =================")
          (println "Hostname:     " host)
          (println "Username:     " user)
          (println "Profiles:     " (if (seq profiles) (str/join " " (sort profiles)) "(none -- minimal server, sshd only)"))
          (println "Time zone:    " tz)
          (println "System:       " system)
          (println "Disk:         " (if adopt? "reuse existing partitions (no disko)" "disko (from `setup disk`)"))
          (println "SSH keys:     " (if (seq ssh-keys)
                                      (str (count ssh-keys) (if adopt? " (from your authorized_keys)" " (seeded from ISO)"))
                                      "NONE FOUND -- you must add one in config.nix"))
          (println "sway-home:    " (:ref opts))
          (println "Host repo:    " repo (when exists? "  (EXISTS -- will be overwritten)"))
          (println "=========================================")
          (println)
          (when-not (sw/confirm "Generate this host config?" :default :yes)
            (println "Aborted.") (System/exit 0))
          ;; Overwrite an existing repo (re-runnable dev loop) after confirm.
          (when exists? (fs/delete-tree repo)))

        ;; 1. Hardware. ISO: generate it WITHOUT filesystems (disko owns those).
        ;;    Adopt: reuse the installer's hardware-configuration.nix as-is,
        ;;    keeping the filesystems it detected (there is no disko).
        (println)
        (if adopt?
          (println "== Reusing existing hardware-configuration.nix (with filesystems) ==")
          (do (println "== Detecting hardware (nixos-generate-config --no-filesystems) ==")
              (run! {} "nixos-generate-config" "--root" root "--no-filesystems")))
        (let [hw-src hw-existing]
          (when-not (fs/exists? hw-src)
            (die (str "expected " hw-src " after nixos-generate-config.")))

          ;; 2. Assemble the host repo.
          (println)
          (println "== Writing host repo:" repo "==")
          (fs/create-dirs repo)
          (when-not adopt?
            (fs/copy disko-src (fs/path repo "disko.nix") {:replace-existing true}))
          (fs/copy hw-src (fs/path repo "hardware.nix") {:replace-existing true})
          (spit (str (fs/path repo "flake.nix"))
                (flake-nix {:host host :user user :system system :ref (:ref opts) :adopt? adopt?}))
          (spit (str (fs/path repo "config.nix")) (config-nix {:user user :ssh-keys ssh-keys :tz tz :profiles profiles}))
          (spit (str (fs/path repo "Justfile")) (justfile {:host host}))
          (spit (str (fs/path repo ".gitignore")) gitignore)
          (doseq [f (cond->> ["flake.nix" "hardware.nix" "config.nix" "Justfile" ".gitignore"]
                      (not adopt?) (cons "disko.nix"))]
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
          (when-not adopt?
            (println "   (still root-owned; `setup install` fixes ownership after install.)"))
          (println)
          (println "Next step:")
          (if adopt?
            (println (str "  cd " repo " && sudo nixos-rebuild switch --flake .#" host))
            (println (str "  setup install   # nixos-install --flake " repo "#" host))))))))

(-main)
