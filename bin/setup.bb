#!/usr/bin/env bb

;;; ============================================================
;;; setup.bb
;;; ============================================================
;;;
;;; Dispatcher for the `setup-*` installer tools, in the style of git
;;; extensions: `setup <name> [args...]` runs the executable
;;; `setup-<name>` found on $PATH, forwarding the remaining arguments.
;;;
;;;   setup disk            ->  setup-disk
;;;   setup disk --no-apply ->  setup-disk --no-apply
;;;
;;; With no arguments it opens an interactive menu to run the install
;;; steps (disk -> host -> install) in the order you choose, looping back
;;; until you pick `Done`. `setup help` lists the available `setup-*`
;;; commands.
;;;
;;; The menu is driven by script-wizard's `choose` (via the Babashka pod)
;;; rather than `script-wizard menu`: the menu subcommand spawns the
;;; chosen command itself, and older script-wizard builds (as baked into
;;; an already-built ISO -- `setup dev` updates these tools but not the
;;; script-wizard binary) panic when that spawn fails. Selecting here and
;;; running the subcommand through this dispatcher reuses the same proven
;;; spawn path as `setup <command>`.
;;; ============================================================

(ns setup
  (:require [babashka.fs :as fs]
            [babashka.pods :as pods]
            [babashka.process :as proc]
            [clojure.string :as str]))

(defn die [& msg]
  (binding [*out* *err*] (apply println "ERROR:" msg))
  (System/exit 1))

(defn available
  "Names (without the `setup-` prefix) of `setup-*` executables on PATH."
  []
  (let [sep  (re-pattern (java.util.regex.Pattern/quote java.io.File/pathSeparator))
        dirs (->> (str/split (or (System/getenv "PATH") "") sep)
                  (remove str/blank?)
                  (filter fs/directory?))]
    (->> dirs
         (mapcat (fn [d] (try (fs/list-dir d "setup-*") (catch Exception _ []))))
         (map (comp str fs/file-name))
         (filter #(str/starts-with? % "setup-"))
         (map #(subs % (count "setup-")))
         distinct
         sort
         vec)))

(defn run-tool!
  "Run `setup-<name>` (inheriting stdio so its prompts work), returning its
  exit code. Returns nil -- after printing an error -- if it isn't on PATH."
  [name & args]
  (let [bin (str "setup-" name)]
    (if-not (fs/which bin)
      (binding [*out* *err*] (println (str "ERROR: '" bin "' not found on PATH.")) nil)
      (:exit (apply proc/shell {:continue true} bin args)))))

(defn usage []
  (println "Usage: setup <command> [args...]")
  (println)
  (println "Installer tools (git-extension style: `setup <command>` runs `setup-<command>`).")
  (println)
  (let [cmds (available)]
    (if (seq cmds)
      (do (println "Available commands:")
          (doseq [c cmds] (println (str "  " c))))
      (println "No setup-* commands found on PATH.")))
  (println)
  (println "Run `setup` with no arguments for an interactive menu."))

(defn run-menu
  "Interactive main menu (bare `setup`): pick an install step, run it, then
  return to the menu -- in any order -- until `Done` (or ESC). Each step is
  dispatched through `run-tool!`, the same path as `setup <command>`."
  []
  (when-not (fs/which "script-wizard")
    (die "'script-wizard' not found -- needed for the interactive menu."))
  (pods/load-pod ["script-wizard" "pod"])
  (require 'pod.enigmacurry.script-wizard)
  (let [choose (resolve 'pod.enigmacurry.script-wizard/choose)
        steps  [["Configure Disk" "disk"]
                ["Configure Host" "host"]
                ["Install"        "install"]]
        labels (conj (mapv first steps) "Done")]
    (loop []
      (let [chosen (choose "sway-home NixOS setup main menu" labels)]
        (if-let [name (some (fn [[label n]] (when (= label chosen) n)) steps)]
          (do (run-tool! name) (println) (recur))
          ;; "Done" or ESC (nil) -> leave the menu.
          (println "Done.")))))
  (System/exit 0))

(defn -main [& args]
  (let [[sub & rest-args] args]
    (cond
      (nil? sub)
      (run-menu)

      (#{"-h" "--help" "help"} sub)
      (usage)

      :else
      (let [bin (str "setup-" sub)]
        (when-not (fs/which bin)
          (die (str "Unknown command '" sub "'. Run `setup help` to list available commands.")))
        ;; Inherit stdio so the delegated tool's interactive prompts work.
        (let [r (apply proc/shell {:continue true} bin rest-args)]
          (System/exit (:exit r)))))))

(apply -main *command-line-args*)
