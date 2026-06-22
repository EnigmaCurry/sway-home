#!/usr/bin/env bb

;;; ============================================================
;;; setup-nixos.bb
;;; ============================================================
;;;
;;; Orchestrator that runs the full install in order:
;;;
;;;   setup disk     ->  partition / format / mount the target
;;;   setup host     ->  generate the per-host flake repo on /mnt
;;;   setup install  ->  nixos-install + passwords + ownership
;;;
;;; Each phase is its own `setup-*` tool with its own prompts and review
;;; screens; this just chains them and stops on the first failure.
;;;
;;; Run as `setup-nixos`, or via the dispatcher as `setup nixos`.
;;; ============================================================

(ns setup-nixos
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [clojure.string :as str]))

(defn die [& msg]
  (when (seq msg) (binding [*out* *err*] (apply println "ERROR:" msg)))
  (System/exit 1))

(defn step [name & args]
  (println)
  (println (str "################ setup " name " ################"))
  (let [bin (str "setup-" name)]
    (when-not (fs/which bin) (die (str "'" bin "' not found on PATH.")))
    (let [r (apply proc/shell {:continue true} bin args)]
      (when-not (zero? (:exit r))
        (die (str "'" bin "' exited " (:exit r) " -- stopping. Fix the issue and"
                  " re-run, or run the remaining steps individually."))))))

(defn host-repo-exists?
  "True if a per-host flake repo is already present on the mounted target.
  A `setup disk` reinstall keeps /home, so the config repo survives and we
  must NOT regenerate it with `setup host` (that would clobber it)."
  [root]
  (boolean (seq (fs/glob (fs/path root "home") "*/nixos/flake.nix"))))

(defn usage []
  (println "Usage: setup nixos   (or: setup-nixos)")
  (println)
  (println "Run the full NixOS install: disk -> host -> install, in order.")
  (println "Each phase has its own prompts; this chains them.")
  (println "To run a phase alone: setup disk | setup host | setup install."))

(defn -main []
  (when (some #{"-h" "--help"} *command-line-args*)
    (usage) (System/exit 0))
  (println "== Install NixOS (disk -> host -> install) ==")
  (step "disk")
  ;; A reinstall (via `setup disk`) preserves /home and the config repo on
  ;; it, so skip `setup host` rather than overwrite the existing config.
  (if (host-repo-exists? "/mnt")
    (do (println)
        (println "Existing host config found on /mnt/home -- skipping `setup host`")
        (println "(reinstall: the preserved config will be rebuilt)."))
    (step "host"))
  (step "install")
  (println)
  (println "✅ All phases complete."))

(-main)
