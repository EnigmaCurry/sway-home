#!/usr/bin/env bb

;;; ============================================================
;;; setup-dev.bb
;;; ============================================================
;;;
;;; Pull the latest development setup-* installer tools from GitHub and
;;; install them into root's nix profile, which is already on $PATH ahead
;;; of the ISO-bundled versions -- so the dev tools take effect
;;; immediately, with no ISO rebuild and no $PATH growth. Re-run it any
;;; time to pull new commits; a reboot (root's home is tmpfs) reverts to
;;; the baked-in tools.
;;;
;;; One of the `setup-*` tools: run as `setup-dev`, or `setup dev`.
;;;
;;;   setup dev                                  # default branch
;;;   setup dev github:EnigmaCurry/sway-home/SOMEBRANCH
;;; ============================================================

(require '[babashka.pods :as pods])
;; script-wizard is on this tool's wrapped PATH (see flake.nix); load the
;; pod from the binary, not the pod registry.
(pods/load-pod ["script-wizard" "pod"])

(ns setup-dev
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [cheshire.core :as json]
            [clojure.string :as str]
            [pod.enigmacurry.script-wizard :as sw]))

;; Flake ref built by default. Change as the tools move to other
;; branches (keep in sync with installer-flake-ref in nix_build_iso.bb).
(def default-ref "github:EnigmaCurry/sway-home/master")

;; Package pname (from flake.nix) used to find our profile element.
(def pname "sway-home-installer")

;; Per-boot marker: /run is tmpfs, so it is cleared on every reboot. Once
;; the upgrade is confirmed this boot, later runs proceed without asking.
(def confirm-marker "/run/setup-dev.confirmed")

(defn die [& msg]
  (binding [*out* *err*] (apply println "ERROR:" msg))
  (System/exit 1))

(defn nix
  "Run `nix` with flakes enabled. opts is a babashka.process options map."
  [opts & args]
  (apply proc/shell (merge {:continue true} opts)
         "nix" "--extra-experimental-features" "nix-command flakes" args))

(defn confirm-once!
  "Confirm the upgrade-to-dev-source the first time this boot. No-op once
  the marker exists."
  []
  (when-not (fs/exists? confirm-marker)
    (when-not (sw/confirm
               "Upgrade this live ISO to the development setup-* tools from GitHub?"
               :default :yes)
      (println "Aborted.")
      (System/exit 0))
    (try (spit confirm-marker "") (catch Exception _ nil))))

(defn installed-element
  "Name of the nix profile element providing our installer tools (matched
  by store path name), or nil if not installed."
  []
  (let [r (nix {:out :string :err :string} "profile" "list" "--json")]
    (when (zero? (:exit r))
      (let [elements (:elements (json/parse-string (:out r) true))]
        (when (map? elements)
          (some (fn [[k el]]
                  (when (some #(str/includes? (str %) pname) (:storePaths el))
                    (name k)))
                elements))))))

(defn -main [& args]
  (when-not (fs/which "nix") (die "'nix' not found."))
  (confirm-once!)
  (let [ref (or (first args) (System/getenv "SETUP_DEV_REF") default-ref)]
    ;; Re-adding the same flake ref is a no-op, so remove any prior dev
    ;; install first to guarantee we pick up new commits.
    (when-let [el (installed-element)]
      (println "Removing previous dev install ...")
      (nix {:out :string :err :string} "profile" "remove" el))
    (println (str "Installing " ref " into root's nix profile ..."))
    (let [r (nix {:err :inherit} "profile" "add" "--refresh" ref)]
      (when-not (zero? (:exit r)) (die "nix profile add failed.")))
    (println)
    (println "Done -- the dev setup-* tools are on your PATH (nix profile),")
    (println "ahead of the ISO-bundled versions. Run `setup` to list them;")
    (println "re-run `setup dev` anytime to pull the latest commits.")))

(apply -main *command-line-args*)
