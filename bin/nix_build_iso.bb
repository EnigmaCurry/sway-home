#!/usr/bin/env -S nix shell --extra-experimental-features "nix-command flakes" nixpkgs#babashka github:EnigmaCurry/script-wizard --command bb

;;; ============================================================
;;; nix_build_iso.bb
;;; ============================================================
;;;
;;; Interactive wizard that generates a Nix flake workspace, builds a
;;; customized headless NixOS installer ISO (SSH + serial + WiFi +
;;; webhook), and copies the result to ~/Downloads.
;;;
;;; The shebang launches this with `nix shell`, providing both babashka
;;; and the script-wizard pod binary from flakes, so the only host
;;; requirement is a working Nix install -- flakes are enabled on-the-fly
;;; via --extra-experimental-features. The pod is loaded directly from
;;; the script-wizard binary (no babashka pod-registry network lookup).
;;;
;;; Run it remotely without cloning anything:
;;;
;;;   nix shell --extra-experimental-features "nix-command flakes" \
;;;     nixpkgs#babashka github:EnigmaCurry/script-wizard --command \
;;;     bb -e '(load-string (slurp "https://raw.githubusercontent.com/EnigmaCurry/sway-home/master/bin/nix_build_iso.bb"))'
;;;
;;; ============================================================

(require '[babashka.pods :as pods])
;; Load the script-wizard pod from the binary provided by the shebang's
;; `nix shell ... github:EnigmaCurry/script-wizard` (no pod-registry).
(pods/load-pod ["script-wizard" "pod"])

(ns nix-build-iso
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [clojure.string :as str]
            [pod.enigmacurry.script-wizard :as sw]))

(def home (System/getProperty "user.home"))

;; nixpkgs flake ref the generated installer ISO is built from.
;; Change this to track a different channel/branch/commit.
(def nixpkgs-ref "github:NixOS/nixpkgs/nixos-26.05")

;; Flake providing the setup-* installer tools (this repo). The
;; generated ISO flake pulls them in as an input so the tools are baked
;; in identically whether this script is run from a clone or remotely.
;; Change the branch/ref here as the tools land on other branches.
(def installer-flake-ref "github:EnigmaCurry/sway-home/master")

;;; ============================================================
;;; Output / control helpers
;;; ============================================================

(defn stderr [& args]
  (binding [*out* *err*] (apply println args)))

(defn errln [& args] (apply stderr "ERROR:" args))

;; Mutable run state, consulted by the shutdown-hook cleanup (the
;; babashka equivalent of bash `trap cleanup EXIT`).
(def state (atom {:workdir nil :is-temp false :keep false :success false}))

(defn cleanup []
  (let [{:keys [success workdir is-temp keep]} @state]
    (when workdir
      (cond
        (not success)
        (stderr (if is-temp
                  (str "Failed. Temp dir kept at: " workdir)
                  (str "Failed. Workspace is at: " workdir)))
        (and is-temp keep) (println "Keeping temp dir:" workdir)
        is-temp (fs/delete-tree workdir)))))

(defn die [& msg]
  (when (seq msg) (apply errln msg))
  (System/exit 1))

(defn finish-ok []
  (swap! state assoc :success true)
  (System/exit 0))

;;; ============================================================
;;; String helpers
;;; ============================================================

(defn nix-escape
  "Escape a string for a Nix double-quoted string literal."
  [s]
  (-> (or s "")
      (str/replace "\r" "")
      (str/replace "\\" "\\\\")
      (str/replace "\"" "\\\"")
      (str/replace "$" "\\$")))

(defn mask-psk
  "Show only length + last 2 chars of a secret."
  [s]
  (let [s (or s "") n (count s)]
    (cond
      (zero? n) ""
      (<= n 2) (apply str (repeat n "*"))
      :else (str (apply str (repeat (- n 2) "*")) (subs s (- n 2))))))

(defn ssh-keys->nix
  "Render a Nix list literal of SSH public keys."
  [keys]
  (str "[\n"
       (str/join "" (map #(str "  \"" (nix-escape %) "\"\n") keys))
       "]"))

;;; ============================================================
;;; Generated file contents
;;; ============================================================

(def webhook-notify-sh
  "#!/usr/bin/env bash
set -euo pipefail

WEBHOOK_URL=\"${WEBHOOK_URL:-}\"
if [[ -z \"$WEBHOOK_URL\" ]]; then
  echo \"WEBHOOK_URL is empty; exiting.\"
  exit 0
fi

# Avoid relying on `hostname` being in PATH: read kernel hostname directly.
HOSTNAME=\"$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)\"

# Best-effort primary IPv4: ask the routing table what we'd use to reach the internet.
IPV4=\"$(
  ip -4 route get 1.1.1.1 2>/dev/null \\
    | awk '/src/ { for (i=1;i<=NF;i++) if ($i==\"src\") { print $(i+1); exit } }'
)\"

# Fallback: first global IPv4 address we can find.
if [[ -z \"$IPV4\" ]]; then
  IPV4=\"$(ip -4 addr show scope global 2>/dev/null | awk '/inet / { sub(/\\/.*/, \"\", $2); print $2; exit }')\"
fi
IPV4=\"${IPV4:-}\"

payload=\"$(printf '{\"hostname\":\"%s\",\"ip\":\"%s\",\"user\":\"root\",\"ssh\":\"ssh root@%s\"}\\n' \"$HOSTNAME\" \"$IPV4\" \"$IPV4\")\"

echo \"Posting to webhook: $WEBHOOK_URL\"
echo \"Payload: $payload\"

# Retry forever: this is a one-time notification, so keep trying until it
# succeeds no matter how long the network takes to come up -- even days
# later. On a fresh boot the clock is also often not NTP-synced yet, which
# makes TLS verification fail (\"certificate is not yet valid\"); retrying
# rides that out too. Backoff grows to a 60s cap to keep the journal quiet.
errfile=\"$(mktemp)\"
trap 'rm -f \"$errfile\"' EXIT

delay=5
max_delay=60
attempt=0
while true; do
  # Capture the HTTP status (stdout) and any curl error (stderr -> errfile)
  # separately, so transport errors don't spam the journal on every retry.
  # Any received response (2xx/4xx/5xx) means we reached the server, so we
  # stop -- success or not, the one-time job is done. A transport-level
  # failure (no network, DNS, refused, or a TLS error from clock skew)
  # yields code 000, so we keep retrying.
  resp=\"$(curl -sSL -X POST -H 'Content-Type: application/json' --data \"$payload\" -w 'HTTPSTATUS:%{http_code}' \"$WEBHOOK_URL\" 2>\"$errfile\")\" || true
  code=\"${resp##*HTTPSTATUS:}\"
  body=\"${resp%HTTPSTATUS:*}\"
  if [ \"$code\" != \"000\" ]; then
    echo \"Server responded with HTTP $code: $body\"
    exit 0
  fi
  attempt=$(( attempt + 1 ))
  # Don't spam the journal: log the first failure, then only every 10th
  # retry, surfacing the latest curl error so it stays diagnosable.
  if [ \"$attempt\" -eq 1 ] || [ $(( attempt % 10 )) -eq 0 ]; then
    err=\"$(cat \"$errfile\")\"
    echo \"No response after $attempt attempts: ${err:-no network}; still retrying every ${delay}s...\"
  fi
  sleep \"$delay\"
  delay=$(( delay * 2 > max_delay ? max_delay : delay * 2 ))
done
")

(def build-sh
  "#!/usr/bin/env bash
set -euo pipefail
nix --extra-experimental-features \"nix-command flakes\" build .#iso -L

# Print the ISO path for convenience
if [[ -d result/iso ]]; then
  iso=\"$(find result/iso -maxdepth 1 -type f -name '*.iso' | head -n 1 || true)\"
  if [[ -n \"$iso\" ]]; then
    echo \"Built ISO: $iso\"
  fi
fi
")

(defn nmconnection [{:keys [conn ssid psk]}]
  (str "[connection]\n"
       "id=" conn "\n"
       "type=wifi\n"
       "autoconnect=true\n\n"
       "[wifi]\n"
       "mode=infrastructure\n"
       "ssid=" ssid "\n\n"
       "[wifi-security]\n"
       "key-mgmt=wpa-psk\n"
       "psk=" psk "\n\n"
       "[ipv4]\n"
       "method=auto\n\n"
       "[ipv6]\n"
       "method=auto\n"))

;;; ============================================================
;;; flake.nix assembly
;;; ============================================================

(defn serial-block [serial]
  (if serial
    (str "\n    # --- Serial console ---\n"
         "    boot.kernelParams = [ \"console=" (:dev serial) "," (:baud serial) "\" ];\n\n"
         "    systemd.services.\"serial-getty@" (:dev serial) "\" = {\n"
         "      enable = true;\n"
         "      wantedBy = [ \"getty.target\" ];\n"
         "    };\n")
    ""))

(defn wifi-block [wifi]
  (if wifi
    (str "\n    # --- NetworkManager + pre-seeded WiFi ---\n"
         "    networking.networkmanager.enable = true;\n\n"
         "    environment.etc.\"NetworkManager/system-connections/" (:conn wifi) ".nmconnection\" = {\n"
         "      mode = \"0600\";\n"
         "      source = ./" (:file wifi) ";\n"
         "    };\n")
    (str "\n    # --- NetworkManager (useful for ethernet too) ---\n"
         "    networking.networkmanager.enable = true;\n")))

(defn webhook-block [url]
  (if url
    (str "\n    # --- Webhook fires once network is up ---\n"
         "    environment.etc.\"webhook-notify.sh\" = {\n"
         "      mode = \"0755\";\n"
         "      source = ./webhook-notify.sh;\n"
         "    };\n\n"
         "    systemd.services.webhook-notify = {\n"
         "      description = \"POST hostname + local IP to webhook once network is up\";\n"
         "      wantedBy = [ \"multi-user.target\" ];\n\n"
         "      after = [ \"network-online.target\" \"NetworkManager-wait-online.service\" ];\n"
         "      wants = [ \"network-online.target\" \"NetworkManager-wait-online.service\" ];\n\n"
         "      path = with pkgs; [ bash curl iproute2 gawk coreutils ];\n\n"
         "      serviceConfig = {\n"
         "        Type = \"oneshot\";\n"
         "        TimeoutStartSec = \"infinity\";\n"
         "        StandardOutput = \"journal+console\";\n"
         "        StandardError = \"journal+console\";\n"
         "        Environment = [ \"WEBHOOK_URL=" (nix-escape url) "\" ];\n"
         "      };\n\n"
         "      script = ''\n"
         "        exec /etc/webhook-notify.sh\n"
         "      '';\n"
         "    };\n")
    ""))

(defn flake-nix [{:keys [system ssh-keys hostname serial wifi webhook-url nixpkgs-ref]}]
  (str
   "{\n"
   "  description = \"Headless NixOS installer ISO (SSH + serial + WiFi + tools)\";\n\n"
   "  inputs.nixpkgs.url = \"" nixpkgs-ref "\";\n"
   "  inputs.script-wizard.url = \"github:EnigmaCurry/script-wizard\";\n"
   "  inputs.sway-home-installer.url = \"" installer-flake-ref "\";\n"
   "  inputs.sway-home-installer.inputs.nixpkgs.follows = \"nixpkgs\";\n"
   "  inputs.sway-home-installer.inputs.script-wizard.follows = \"script-wizard\";\n\n"
   "  outputs = { self, nixpkgs, script-wizard, sway-home-installer, ... }:\n"
   "    let\n"
   "      system = \"" system "\";\n"
   "      lib = nixpkgs.lib;\n"
   "      scriptWizard = script-wizard.packages.${system}.default;\n"
   "      installerTools = sway-home-installer.packages.${system}.default;\n"
   "    in {\n"
   "      nixosConfigurations.installer = lib.nixosSystem {\n"
   "        inherit system;\n"
   "        modules = [\n"
   "          \"${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix\"\n\n"
   "          ({ config, pkgs, lib, ... }:\n"
   "            let\n"
   "              sshPubKeys = " (ssh-keys->nix ssh-keys) ";\n"
   "            in\n"
   "            {\n"
   "              networking.hostName = \"" (nix-escape hostname) "\";\n"
   "              networking.useDHCP = lib.mkDefault true;\n\n"
   "              services.openssh.enable = true;\n"
   "              services.openssh.settings = {\n"
   "                PasswordAuthentication = false;\n"
   "                KbdInteractiveAuthentication = false;\n"
   "                PermitRootLogin = \"prohibit-password\";\n"
   "              };\n\n"
   "              users.users.root.openssh.authorizedKeys.keys = sshPubKeys;\n"
   (serial-block serial)
   (wifi-block wifi)
   "\n"
   "              environment.systemPackages = with pkgs; [\n"
   "                git curl wget openssh rsync\n"
   "                parted gptfdisk e2fsprogs btrfs-progs xfsprogs dosfstools\n"
   "                cryptsetup lvm2 mdadm\n"
   "                tmux neovim nano htop\n"
   "                pciutils usbutils\n"
   "                iproute2 iputils dnsutils\n"
   "                babashka\n"
   "                scriptWizard\n"
   "                installerTools\n"
   "              ];\n"
   (webhook-block webhook-url)
   "            })\n"
   "        ];\n"
   "      };\n\n"
   "      packages.${system}.iso =\n"
   "        self.nixosConfigurations.installer.config.system.build.isoImage;\n"
   "    };\n"
   "}\n"))

;;; ============================================================
;;; Filesystem helper
;;; ============================================================

(defn write-file! [path content perms]
  (spit (str path) content)
  (when perms (fs/set-posix-file-permissions (str path) perms)))

;;; ============================================================
;;; CLI parsing
;;; ============================================================

(defn usage []
  (println "Usage: nix_build_iso.bb [options]")
  (println)
  (println "Options:")
  (println "  --keep              Keep temporary build directory (also kept on failure).")
  (println "  --outdir DIR        Where to copy the resulting ISO (default: ~/Downloads).")
  (println "  --system SYSTEM     Nix system (default: x86_64-linux), e.g. aarch64-linux.")
  (println "  --output DIR        Write workspace to DIR and exit without building")
  (println "                      (unless --build).")
  (println "  --build             Build ISO even if --output is set.")
  (println "  -h, --help          Show help."))

(defn need [v name]
  (when (nil? v) (die (str "missing argument for " name)))
  v)

(defn parse-args [args]
  (loop [args args
         opts {:keep false
               :outdir (str home "/Downloads")
               :system "x86_64-linux"
               :workdir nil
               :do-build true}]
    (if-let [a (first args)]
      (case a
        "--keep"   (recur (rest args) (assoc opts :keep true))
        "--outdir" (recur (drop 2 args) (assoc opts :outdir (need (second args) "--outdir")))
        "--system" (recur (drop 2 args) (assoc opts :system (need (second args) "--system")))
        "--output" (recur (drop 2 args) (assoc opts :workdir (need (second args) "--output")
                                                     :do-build false))
        "--build"  (recur (rest args) (assoc opts :do-build true))
        ("-h" "--help") (do (usage) (finish-ok))
        (do (stderr "Unknown option:" a) (usage) (System/exit 2)))
      opts)))

;;; ============================================================
;;; Review screen
;;; ============================================================

(defn confirm-review [{:keys [workdir system hostname nixpkgs-ref ssh-keys wifi serial webhook-url outdir]}]
  (println)
  (println "================ Review =================")
  (println "Workspace:    " workdir)
  (println "System:       " system)
  (println "Nixpkgs:      " nixpkgs-ref)
  (println "Hostname:     " hostname)
  (println "SSH user:      root")
  (println "SSH keys:     " (str (count ssh-keys) " key(s)"))
  (doseq [k ssh-keys]
    (println (str "  - " (subs k 0 (min 48 (count k))) "...")))
  (println "WiFi:         " (if wifi
                              (str "enabled\n    SSID: " (:ssid wifi)
                                   "\n    PSK:  " (mask-psk (:psk wifi))
                                   "\n    NM:   " (:conn wifi))
                              "disabled"))
  (println "Serial:       " (if serial
                              (str "enabled (" (:dev serial) "@" (:baud serial) ")")
                              "disabled"))
  (println "Webhook:      " (if webhook-url (str "enabled (" webhook-url ")") "disabled"))
  (println "ISO outdir:   " outdir)
  (println "=========================================")
  (println)
  (sw/confirm "Proceed?" :default :yes))

;;; ============================================================
;;; Main
;;; ============================================================

(defn ssh-agent-keys
  "Inspect the local ssh-agent. Returns a map with :status of
  :keys, :empty (agent running, no keys), or :none (no agent /
  ssh-add unavailable). For :keys, :keys is the vector of full public
  key lines (ssh-add -L) and :labels is the matching human-readable
  fingerprint listing (ssh-add -l)."
  []
  (if (or (str/blank? (or (System/getenv "SSH_AUTH_SOCK") ""))
          (not (fs/which "ssh-add")))
    {:status :none}
    (let [r (proc/shell {:out :string :err :string :continue true} "ssh-add" "-L")
          keys (->> (str/split-lines (:out r))
                    (map str/trim)
                    (filter #(re-find #"^(ssh-|ecdsa-|sk-)" %))
                    vec)]
      (if (and (zero? (:exit r)) (seq keys))
        (let [rl (proc/shell {:out :string :err :string :continue true} "ssh-add" "-l")
              labels (->> (str/split-lines (:out rl))
                          (map str/trim)
                          (remove str/blank?)
                          vec)
              labels (if (= (count labels) (count keys)) labels keys)]
          {:status :keys :keys keys :labels labels})
        {:status :empty}))))

(defn read-manual-ssh-keys []
  (println "Paste one or more SSH public keys. End with an empty line:")
  (loop [keys []]
    (let [line (read-line)]
      (if (or (nil? line) (str/blank? line))
        keys
        (recur (conj keys (str/trim line)))))))

(defn read-ssh-keys []
  (let [{:keys [status keys labels]} (ssh-agent-keys)]
    (case status
      :keys
      (let [label->key (zipmap labels keys)
            chosen (sw/select "Select SSH keys from your ssh-agent (or select none to enter keys manually)" labels)
            sel (->> chosen (keep label->key) vec)]
        (if (seq sel)
          sel
          (do (println "No keys selected; enter keys manually.")
              (read-manual-ssh-keys))))
      :empty
      (do (println "ssh-agent detected but no keys are loaded; enter keys manually.")
          (read-manual-ssh-keys))
      :none
      (do (println "No ssh-agent detected; enter keys manually.")
          (read-manual-ssh-keys)))))

(defn available-nixpkgs-refs
  "Query the nixpkgs repo for selectable branches (the 5 most recent
  release channels, newest first, followed by unstable) and return
  them as flake refs. Returns nil if git is unavailable or the query
  fails."
  []
  (when (fs/which "git")
    (let [r (proc/shell {:out :string :err :string :continue true}
                        "git" "ls-remote" "--heads"
                        "https://github.com/NixOS/nixpkgs" "refs/heads/nixos-*")]
      (when (zero? (:exit r))
        (let [branches  (->> (str/split-lines (:out r))
                             (keep #(second (re-find #"refs/heads/(nixos-\S+)" %)))
                             distinct)
              releases  (->> branches
                             (filter #(re-matches #"nixos-\d+\.\d+" %))
                             sort reverse (take 5))
              unstable  (filter #(= % "nixos-unstable") branches)]
          (->> (concat releases unstable)
               (map #(str "github:NixOS/nixpkgs/" %))
               vec))))))

(defn choose-nixpkgs-ref
  "Use the default nixpkgs source unless the user wants to pick another."
  []
  (if (sw/confirm (str "Build from the default nixpkgs source (" nixpkgs-ref ")?")
                  :default :yes)
    nixpkgs-ref
    (let [custom-label "Custom flake ref..."
          options (-> (or (available-nixpkgs-refs) [nixpkgs-ref])
                      vec
                      (conj custom-label))
          choice  (sw/choose "Choose a nixpkgs source:" options)
          chosen  (if (= choice custom-label)
                    (let [r (str/trim (sw/ask "Enter a nixpkgs flake ref"))]
                      (if (str/blank? r) nixpkgs-ref r))
                    choice)]
      (when (not= chosen nixpkgs-ref)
        (println (str "⚠️  " chosen " is untested. Only the default ("
                      nixpkgs-ref ") is known to build a working ISO.")))
      chosen)))

(defn -main []
  (let [opts (parse-args *command-line-args*)]
    (when-not (fs/which "nix")
      (die "'nix' not found. Install Nix first."))

    (let [is-temp (nil? (:workdir opts))
          workdir (if is-temp
                    (str (fs/create-temp-dir {:prefix "nixos-iso-"}))
                    (let [d (:workdir opts)]
                      (fs/create-dirs d)
                      (str (fs/absolutize d))))]
      (swap! state assoc :workdir workdir :is-temp is-temp :keep (:keep opts))
      (.addShutdownHook (Runtime/getRuntime) (Thread. ^Runnable cleanup))
      (fs/create-dirs (:outdir opts))

      (println "Workspace:" workdir)
      (println)
      (println "== Customize your NixOS ISO ==")

      (let [hostname  (sw/ask "Installer hostname" :default "nixos-installer")
            _         (println)
            nixpkgs-src (choose-nixpkgs-ref)
            _         (println)
            ssh-keys  (read-ssh-keys)
            _         (when (empty? ssh-keys) (die "No SSH keys provided."))
            _         (println)
            wifi      (when (sw/confirm "Pre-seed WiFi credentials into the ISO?" :default :no)
                        (let [ssid (sw/ask "WiFi SSID")
                              psk  (sw/ask "WiFi PSK (password)")
                              conn (sw/ask "NetworkManager connection name" :default "bootstrap-wifi")]
                          (when (or (str/blank? ssid) (str/blank? psk))
                            (die "WiFi enabled but SSID/PSK missing."))
                          {:ssid ssid :psk psk :conn conn :file (str conn ".nmconnection")}))
            _         (println)
            serial    (when (sw/confirm "Enable serial console (kernel + serial getty)?" :default :no)
                        {:dev (sw/ask "Serial device" :default "ttyS0")
                         :baud (sw/ask "Serial baud rate" :default "115200")})
            _         (println)
            webhook-url (when (sw/confirm "Enable webhook notify after network-online?" :default :no)
                          (let [u (sw/ask "Webhook URL (will receive JSON POST)")]
                            (when (str/blank? u) (die "webhook enabled but URL is empty."))
                            u))]

        (when wifi
          (write-file! (fs/path workdir (:file wifi)) (nmconnection wifi) "rw-------"))
        (when webhook-url
          (write-file! (fs/path workdir "webhook-notify.sh") webhook-notify-sh "rwxr-xr-x"))
        (write-file! (fs/path workdir "flake.nix")
                     (flake-nix {:system (:system opts)
                                 :ssh-keys ssh-keys
                                 :hostname hostname
                                 :nixpkgs-ref nixpkgs-src
                                 :serial serial
                                 :wifi wifi
                                 :webhook-url webhook-url})
                     nil)
        (write-file! (fs/path workdir "build.sh") build-sh "rwxr-xr-x")

        (println)
        (println "Workspace generated at:" workdir)
        (println "Convenience build script:" (str (fs/path workdir "build.sh")))

        (when-not (:do-build opts)
          (println "Skipping build (config-only mode).")
          (finish-ok))

        (when-not (confirm-review {:workdir workdir :system (:system opts) :hostname hostname
                                   :nixpkgs-ref nixpkgs-src
                                   :ssh-keys ssh-keys :wifi wifi
                                   :serial serial :webhook-url webhook-url :outdir (:outdir opts)})
          (println "Aborted.")
          (finish-ok))

        (println)
        (println "== Building ISO ==")
        (let [r (proc/shell {:dir workdir :continue true}
                            "nix" "--extra-experimental-features" "nix-command flakes"
                            "build" ".#iso" "-L")]
          (when-not (zero? (:exit r)) (die "nix build failed")))

        (let [iso-dir (fs/path workdir "result" "iso")
              iso (when (fs/exists? iso-dir)
                    (first (filter #(str/ends-with? (str %) ".iso") (fs/list-dir iso-dir))))]
          (when-not iso
            (die (str "Could not find built ISO under " iso-dir)))
          (let [username (System/getProperty "user.name")
                date (.format (java.time.LocalDate/now)
                              (java.time.format.DateTimeFormatter/ofPattern "yyyyMMdd"))
                dest (fs/path (:outdir opts) (str hostname "-" username "-custom-" date ".iso"))]
            (fs/copy iso dest {:replace-existing true})
            (swap! state assoc :success true)
            (println)
            (println (str "✅ ISO copied to: " dest))))))))

(-main)
