#!/usr/bin/env bb

;;; ============================================================
;;; flake-sync.bb
;;; ============================================================
;;;
;;; Keep the flake pin chain honest.
;;;
;;; A host's config repo (~/nixos) pins sway-home; sway-home's own
;;; flake.lock -- and the separate home-manager/flake.lock -- pin the
;;; source repos (emacs, script-wizard, nixos-vm-template,
;;; blog.rymcg.tech). So a commit pushed to one of those repos does not
;;; reach the machine until every lock in the chain is bumped and pushed.
;;;
;;; `nix flake update` in the host repo cannot shortcut this: a
;;; transitive input is inherited from sway-home's lockfile, and
;;; `nix flake update emacs_enigmacurry` there only warns
;;; "'emacs_enigmacurry' does not match any input of this flake".
;;;
;;; Subcommands:
;;;   check      Report which pins are behind their git upstreams and
;;;              which local checkouts have unpushed commits. Read-only
;;;              (no fetch, no lock writes); exits 3 when something of
;;;              yours needs attention.
;;;   preflight  The same check, quiet when all is well, then asks
;;;              whether to continue. Run as a dependency of
;;;              `admin upgrade`. NO_FLAKE_CHECK=1 skips it; an
;;;              unreachable network warns but never blocks.
;;;   upgrade    Print a plan -- push source repos, bump + commit + push
;;;              sway-home's locks, then update the host lock -- confirm
;;;              it once, then run it.
;;;
;;; "Yours" means repos owned by the github owner of the host flake's
;;; sway-home input (so a fork is detected, not hardcoded). Everything
;;; else (nixpkgs, home-manager, disko, ...) is reported as
;;; informational drift and never blocks: those move constantly and
;;; `upgrade` bumps them anyway via a plain `nix flake update`.
;;; ============================================================

(ns flake-sync
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [cheshire.core :as json]
            [clojure.string :as str]))

(def home (System/getProperty "user.home"))
(def tty? (some? (System/console)))

;;; ============================================================
;;; Output helpers
;;; ============================================================

(def color?
  (and (nil? (System/getenv "NO_COLOR"))
       (or tty? (some? (System/getenv "FORCE_COLOR")))))

(defn- c [code s]
  (if color? (str "\u001b[" code "m" s "\u001b[0m") (str s)))

(defn bold   [s] (c "1" s))
(defn dim    [s] (c "2" s))
(defn red    [s] (c "31" s))
(defn green  [s] (c "32" s))
(defn yellow [s] (c "33" s))
(defn blue   [s] (c "34" s))

(defn stderr [& xs] (binding [*out* *err*] (apply println xs)))
(defn die [& xs] (stderr (red "ERROR:") (str/join " " xs)) (System/exit 1))

(defn tilde
  "Shorten $HOME to ~ for display."
  [p]
  (let [p (str p)]
    (if (str/starts-with? p home) (str "~" (subs p (count home))) p)))

(defn short-rev [rev] (if (and rev (>= (count rev) 7)) (subs rev 0 7) (or rev "?")))

(defn pad
  "Left-justify `s` in a column sized to the longest entry in `all`, so a
  long repo name or path widens the column instead of shunting the rest
  of its line out of alignment."
  [all s]
  (let [w (min 56 (max 24 (apply max 0 (map (comp count str) all))))]
    (format (str "%-" w "s") (str s))))

;;; ============================================================
;;; git helpers
;;; ============================================================

(defn git
  "Run git in `dir`, capturing output. Never throws; returns
  {:exit n :out s :err s}. Terminal prompts are disabled so a missing
  credential fails fast instead of hanging the check."
  [dir & args]
  (let [r (apply proc/sh {:dir (str dir)
                          :continue true
                          :extra-env {"GIT_TERMINAL_PROMPT" "0"}}
                 "git" args)]
    {:exit (:exit r)
     :out (str/trim (or (:out r) ""))
     ;; Untrimmed, for output whose leading whitespace is significant --
     ;; `status --porcelain` encodes staged/unstaged in two columns, so the
     ;; first line of an unstaged change begins with a space.
     :raw (or (:out r) "")
     :err (str/trim (or (:err r) ""))}))

(defn git-ok?
  "True when git in `dir` succeeds, i.e. the thing exists / holds."
  [dir & args]
  (zero? (:exit (apply git dir args))))

(defn git-out
  "Trimmed stdout of a git command, or nil if it failed or was empty."
  [dir & args]
  (let [{:keys [exit out]} (apply git dir args)]
    (when (zero? exit) (not-empty out))))

(defn run!
  "Echo a command, then run it with inherited stdio. Returns the exit code."
  [dir & args]
  (println (blue "   +") (dim (str "(" (tilde dir) ")")) (str/join " " args))
  (:exit (apply proc/shell {:dir (str dir) :continue true} args)))

(defn run-or-die! [dir & args]
  (let [exit (apply run! dir args)]
    (when-not (zero? exit)
      (die (str/join " " args) "failed in" (tilde dir)))
    exit))

;;; ============================================================
;;; Flake locks
;;; ============================================================

(defn forge-url
  "Clone URL for a lock node's forge. https:// so the check needs no ssh key."
  [{:keys [type owner repo]}]
  (case type
    "github" (str "https://github.com/" owner "/" repo)
    "gitlab" (str "https://gitlab.com/" owner "/" repo)
    nil))

(defn lock-pins
  "Pins declared by one flake.lock, as a seq of maps. `label` names the
  lock in the report. Only forge-backed nodes (github/gitlab) can be
  compared against an upstream; everything else (tarball, file, path) is
  skipped, since there is no ref to resolve."
  [lockfile label]
  (let [lock (try (json/parse-string (slurp (str lockfile)) true)
                  (catch Exception e
                    (die "cannot read" (str lockfile) "--" (.getMessage e))))]
    (for [[node-name node] (:nodes lock)
          :when (not= node-name :root)
          :let [locked (:locked node)
                orig (:original node)]
          :when (contains? #{"github" "gitlab"} (:type locked))]
      {:node (name node-name)
       :type (:type locked)
       :owner (:owner locked)
       :repo (:repo locked)
       ;; original.ref carries the tracked branch (nixos-26.05, master);
       ;; absent means the repo's default branch, i.e. HEAD.
       :ref (or (:ref orig) (:ref locked))
       :rev (:rev locked)
       :lock label})))

(defn lock-graph
  "The lock's node table plus its root input map, for walking the graph."
  [lockfile]
  (let [lock (json/parse-string (slurp (str lockfile)) true)]
    {:nodes (:nodes lock)
     :root (get-in lock [:nodes :root :inputs])}))

(defn- node-locked [nodes node-name]
  (get-in nodes [(keyword (str node-name)) :locked]))

(defn root-input-nodes
  "The lock's direct (root) inputs, one map each."
  [{:keys [nodes root]}]
  (for [[in-name node-name] root
        :let [node (get nodes (keyword (str node-name)))]
        :when node]
    {:input (name in-name)
     :locked (:locked node)
     ;; A lock node carries "flake": false for an input declared
     ;; `flake = false`; a real flake omits the key entirely.
     :flake? (not (false? (:flake node)))
     :inputs (:inputs node)}))

(defn library-input?
  "True for a config library of ours: a flake we own whose own lockfile
  pins other repos we own. Those transitive pins can only be moved by
  bumping that repo's lock, which is the whole reason this tool exists.

  The last clause is what keeps this honest. In sway-home's standalone
  home-manager flake, script-wizard is also a flake we own -- but it
  pins nothing of ours, so relocking, committing and pushing it would be
  none of our business. And emacs et al are `flake = false` source
  inputs with no lock to bump at all."
  [{:keys [nodes]} mine? {:keys [locked flake? inputs]}]
  (and flake?
       (contains? #{"github" "gitlab"} (:type locked))
       (boolean (mine? (:owner locked)))
       ;; An input's value is a node name, or a vector for a `follows`
       ;; path -- only the former names a node to inspect.
       (boolean (some (fn [[_ node-name]]
                        (when (string? node-name)
                          (mine? (:owner (node-locked nodes node-name)))))
                      inputs))))

(defn infer-owner
  "Whose repos count as yours. Inferred rather than hardcoded so a fork
  of sway-home reports on the fork's own repos."
  [graph flake]
  (or
   ;; A forge-pinned sway-home input names its owner outright (the
   ;; per-host NixOS repo case).
   (->> (root-input-nodes graph)
        (map :locked)
        (filter #(contains? #{"github" "gitlab"} (:type %)))
        (some (fn [{:keys [owner repo]}] (when (= "sway-home" repo) owner))))
   ;; sway-home's own standalone home-manager flake pins sway-home as
   ;; `path:..`, which names no owner -- so fall back to the owner of the
   ;; repo the flake itself lives in.
   (some->> (git-out flake "remote" "get-url" "origin")
            (re-find #"[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$")
            second)))

(defn nested-locks
  "Every flake.lock in `repo`: the root one plus any one level down
  (sway-home keeps a second flake under home-manager/)."
  [repo]
  (let [root (fs/path repo "flake.lock")]
    (->> (concat (when (fs/exists? root) [root])
                 (sort (fs/glob repo "*/flake.lock")))
         (map str))))

(defn lock-label
  "Report label for a lock: <repo-dir>/<path within repo>."
  [repo lockfile]
  (str (fs/file-name repo) "/" (fs/relativize (str repo) (str lockfile))))

;;; ============================================================
;;; Upstream resolution
;;; ============================================================

(defn resolve-upstream
  "Current upstream rev for {:type :owner :repo :ref} via `git ls-remote`
  -- no clone, no local state. Returns {:rev s} or {:error s}."
  [{:keys [ref] :as target}]
  (if-let [url (forge-url target)]
    (let [want (or ref "HEAD")
          {:keys [exit out err]} (git home "ls-remote" url want)]
      (if-not (zero? exit)
        {:error (or (not-empty (last (str/split-lines (str err)))) "ls-remote failed")}
        (let [rows (for [line (str/split-lines out)
                         :let [[rev ref-name] (str/split line #"\t" 2)]
                         :when (and rev ref-name)]
                     [ref-name rev])
              by-name (into {} rows)]
          (if-let [rev (or (get by-name (str "refs/heads/" want))
                           (get by-name (str "refs/tags/" want))
                           (get by-name want)
                           (get by-name "HEAD")
                           (second (first rows)))]
            {:rev rev}
            {:error (str "no ref matching '" want "'")}))))
    {:error (str "unsupported forge type " (:type target))}))

;;; ============================================================
;;; Local checkouts
;;; ============================================================

(defn vendor-path
  "The ~/git/vendor/{org}/{repo} convention git-vendor clones into: the
  org is lowercased, the repo name kept as-is."
  [vendor-root owner repo]
  (str (fs/path vendor-root (str/lower-case (str owner)) (str repo))))

(defn checkout-status
  "Inspect a local clone: is it dirty, and is its HEAD pushed? Compared
  against the ls-remote rev, so nothing is fetched or written."
  [dir upstream-rev]
  (when (and dir (fs/directory? (fs/path dir ".git")))
    (let [head (git-out dir "rev-parse" "HEAD")
          branch (git-out dir "rev-parse" "--abbrev-ref" "HEAD")
          tracking (git-out dir "rev-parse" "--abbrev-ref" "@{u}")
          status (git dir "status" "--porcelain")
          dirty-paths (when (zero? (:exit status))
                        (->> (str/split-lines (:raw status))
                             (remove str/blank?)
                             ;; porcelain v1 is "XY PATH": a two-column
                             ;; status then a space. Split the raw output,
                             ;; never a trimmed blob -- trimming would eat
                             ;; the first line's leading status column.
                             (map #(str/trim (subs % (min 3 (count %)))))
                             (remove str/blank?)
                             vec))
          ;; Only count when the upstream commit is an object we already
          ;; have; otherwise we can say "differs" but not by how much.
          ;; left/right of upstream...HEAD = commits only upstream has
          ;; (behind, e.g. pushed from another machine) / only we have.
          counts (when (and head upstream-rev (not= head upstream-rev)
                            (git-ok? dir "cat-file" "-e" (str upstream-rev "^{commit}")))
                   (some-> (git-out dir "rev-list" "--left-right" "--count"
                                    (str upstream-rev "..." head))
                           (str/split #"\s+")))
          behind (some-> (first counts) parse-long)
          ahead (some-> (second counts) parse-long)
          differs? (boolean (and head upstream-rev (not= head upstream-rev)))]
      {:dir dir
       :head head
       :branch branch
       :tracking tracking
       :dirty-paths dirty-paths
       ;; Only an ahead count means there is something to push. Unknown
       ;; counts (shallow/never-fetched) fall back to "differs".
       :unpushed? (if ahead (pos? ahead) differs?)
       :ahead ahead
       :behind behind})))

(defn lock-only-dirt?
  "True when the only uncommitted changes are lockfiles -- which
  `upgrade` is about to regenerate and commit anyway."
  [{:keys [dirty-paths]}]
  (and (seq dirty-paths)
       (every? #(str/ends-with? % "flake.lock") dirty-paths)))

;;; ============================================================
;;; Survey: gather everything both subcommands need
;;; ============================================================

(defn survey
  "Read the locks, resolve every distinct upstream once (in parallel),
  and inspect the local checkouts of your own repos."
  [{:keys [flake vendor owner]}]
  (let [host-lock (str (fs/path flake "flake.lock"))]
    (when-not (fs/exists? host-lock)
      (die "no flake.lock in" (tilde flake) "-- is this a flake repo?"))
    (let [graph (lock-graph host-lock)
          owner (or owner
                    (infer-owner graph flake)
                    (die "could not infer your github owner from"
                         (tilde host-lock) "-- pass --owner NAME"))
          mine? (fn [o] (and o (= (str/lower-case (str o)) (str/lower-case owner))))
          ;; The repos whose locks must be bumped and pushed. Often just
          ;; sway-home; empty for a flake that reads it from the working
          ;; tree (`path:..`), where there is no upstream lock to move.
          libraries (->> (root-input-nodes graph)
                         (filter #(library-input? graph mine? %))
                         (map (fn [{{:keys [owner repo] :as locked} :locked}]
                                (let [dir (vendor-path vendor owner repo)]
                                  (assoc locked :dir (when (fs/directory? dir) dir)))))
                         distinct
                         vec)
          ;; Pins from the host lock plus every lock inside each library
          ;; checkout. The host lock already carries transitive nodes, so
          ;; a missing checkout still yields a useful report.
          pins (concat
                (lock-pins host-lock (str (fs/file-name flake) "/flake.lock"))
                (for [{:keys [dir]} libraries
                      :when dir
                      lockfile (nested-locks dir)
                      pin (lock-pins lockfile (lock-label dir lockfile))]
                  pin))
          ;; One ls-remote per distinct repo+ref, not per lock entry.
          targets (distinct (map #(select-keys % [:type :owner :repo :ref]) pins))
          upstream (into {} (pmap (fn [t] [t (resolve-upstream t)]) targets))
          ;; Collapse the same repo+ref+rev across locks into one row.
          groups (->> pins
                      (group-by #(select-keys % [:type :owner :repo :ref :rev]))
                      (map (fn [[k v]]
                             (let [t (select-keys k [:type :owner :repo :ref])
                                   {:keys [rev error]} (get upstream t)]
                               (assoc k
                                      :locks (vec (sort (distinct (map :lock v))))
                                      :nodes (vec (sort (distinct (map :node v))))
                                      :mine? (boolean (mine? (:owner k)))
                                      :upstream-rev rev
                                      :upstream-error error
                                      :state (cond error :unknown
                                                   (= rev (:rev k)) :current
                                                   :else :stale)))))
                      (sort-by (juxt (complement :mine?) :owner :repo :ref))
                      vec)
          ;; Checkout status for each of your repos vendored locally.
          checkouts (->> groups
                         (filter :mine?)
                         (map (fn [{:keys [owner repo upstream-rev]}]
                                (let [dir (vendor-path vendor owner repo)]
                                  [(str owner "/" repo)
                                   (some-> (checkout-status dir upstream-rev)
                                           (assoc :owner owner :repo repo))])))
                         (remove (comp nil? second))
                         (into {}))]
      {:flake flake
       :owner owner
       :libraries libraries
       :groups groups
       :checkouts checkouts})))

;;; ============================================================
;;; Report
;;; ============================================================

(defn commit-distance
  "'(5 commits)' when both revs are objects in the local checkout."
  [{:keys [checkouts]} {:keys [owner repo rev upstream-rev]}]
  (when-let [dir (:dir (get checkouts (str owner "/" repo)))]
    (when (and rev upstream-rev
               (git-ok? dir "cat-file" "-e" (str rev "^{commit}"))
               (git-ok? dir "cat-file" "-e" (str upstream-rev "^{commit}")))
      (when-let [n (some-> (git-out dir "rev-list" "--count" (str rev ".." upstream-rev))
                           parse-long)]
        (when (pos? n) (str "(" n " commit" (when (> n 1) "s") ")"))))))

(defn pin-name [{:keys [owner repo ref]}]
  (str owner "/" repo (when ref (str "#" ref))))

(defn collapse-by-repo
  "Fold rows for the same repo+ref -- which differ only in which rev each
  lock pinned -- into one line. Two locks pinning two different nixpkgs
  revs is one fact about nixpkgs, not two."
  [groups]
  (->> groups
       (group-by #(select-keys % [:owner :repo :ref]))
       (map (fn [[k rows]]
              (assoc k
                     :revs (vec (distinct (map :rev rows)))
                     :nodes (vec (sort (distinct (mapcat :nodes rows))))
                     :upstream-rev (:upstream-rev (first rows))
                     :upstream-error (:upstream-error (first rows))
                     :state (cond (:upstream-error (first rows)) :unknown
                                  (every? #(= :current (:state %)) rows) :current
                                  :else :stale))))
       (sort-by (juxt :owner :repo :ref))))

(defn report!
  "Print the staleness report. Returns a map of what needs attention.

  With :relock the caller is about to regenerate the lock itself (that is
  what sway-home's `hm-update` does), so a stale pin is not a finding --
  it is about to move. Only local work that the relock would leave behind
  counts."
  [{:keys [groups checkouts owner flake] :as s} {:keys [verbose relock]}]
  (let [mine (filter :mine? groups)
        theirs (collapse-by-repo (remove :mine? groups))
        stale (filter #(= :stale (:state %)) mine)
        unknown (filter #(= :unknown (:state %)) groups)
        to-push (->> (vals checkouts) (filter :unpushed?) (sort-by :repo))
        dirty (->> (vals checkouts) (filter (comp seq :dirty-paths)) (sort-by :repo))]
    (println)
    (println (bold "flake pins")
             (dim (str "-- host flake " (tilde flake) ", your repos: " owner)))
    (println)

    (println (bold " your repos"))
    (doseq [{:keys [rev state locks upstream-rev upstream-error] :as g} mine]
      (println "  "
               (case state
                 ;; Under :relock this pin is about to be bumped by the
                 ;; caller, so name it as pending work, not as a problem.
                 :stale (if relock (blue "bump  ") (red "STALE "))
                 :current (green "ok    ")
                 :unknown (yellow "?     "))
               (pad (map pin-name mine) (pin-name g))
               (case state
                 :stale (str (short-rev rev) " " (dim "->") " " (bold (short-rev upstream-rev))
                             (when-let [d (commit-distance s g)] (str "  " (dim d))))
                 :current (dim (short-rev rev))
                 :unknown (str (dim (short-rev rev)) "  " (yellow upstream-error))))
      (when (or verbose (and (= state :stale) (not relock)))
        (println "         " (dim (str "pinned by " (str/join ", " locks))))))
    (when (empty? mine) (println "   " (dim "(none)")))

    (when (seq checkouts)
      (println)
      (println (bold " your checkouts"))
      (doseq [{:keys [dir repo branch tracking unpushed? ahead behind dirty-paths]}
              (sort-by :repo (vals checkouts))]
        (let [todo (cond-> []
                     (seq dirty-paths)
                     (conj (red (str (count dirty-paths) " uncommitted change"
                                     (when (> (count dirty-paths) 1) "s"))))
                     unpushed?
                     (conj (yellow (if ahead
                                     (str ahead " unpushed commit" (when (> ahead 1) "s"))
                                     "HEAD differs from upstream")))
                     (nil? tracking)
                     (conj (yellow (str "no upstream for " branch))))
              ;; Behind means another machine pushed past this checkout.
              ;; Harmless for pinning -- the lock bump reads the remote, not
              ;; here -- so note it without flagging the row.
              fyi (when (and behind (pos? behind))
                    [(dim (str behind " behind origin"))])
              notes (concat todo fyi)]
          (println "  "
                   (if (seq todo) (yellow "needs ") (green "ok    "))
                   (pad (map (comp tilde :dir) (vals checkouts)) (tilde dir))
                   (if (seq notes)
                     (str/join ", " notes)
                     (dim (str "clean, " (or tracking branch) " pushed")))))))

    (when (seq theirs)
      (println)
      (println (bold " third party")
               (dim "(informational -- flake-upgrade bumps these too)"))
      (doseq [{:keys [revs state upstream-rev upstream-error nodes] :as g} theirs]
        (let [pinned (str/join "," (map short-rev revs))]
          (println "  "
                   (case state
                     :stale (yellow "behind")
                     :current (green "ok    ")
                     :unknown (yellow "?     "))
                   (pad (map pin-name theirs) (pin-name g))
                   (case state
                     :stale (str pinned " " (dim "->") " " (short-rev upstream-rev)
                                 "  " (dim (str/join "," nodes)))
                     :current (dim pinned)
                     :unknown (str (dim pinned) "  " (yellow upstream-error)))))))

    (println)
    {:stale stale :to-push to-push :dirty dirty :unknown unknown
     :actionable? (boolean (or (and (not relock) (seq stale)) (seq to-push)))}))

(defn findings
  "What needs attention, computed without printing. Lets `preflight` stay
  silent on a clean run instead of dumping the whole table in front of
  every rebuild."
  [s opts]
  (binding [*out* (java.io.StringWriter.)]
    (report! s opts)))

;;; ============================================================
;;; Plan + execute (upgrade)
;;; ============================================================

(defn build-plan
  "Ordered steps to get every pin current. Source repos are pushed
  before the library locks are regenerated, so the new revs exist to be
  picked up; the host lock is updated last, once sway-home's new commit
  is on its remote."
  [{:keys [flake libraries checkouts]}]
  (let [lib-repos (set (map :repo libraries))
        pushable (->> (vals checkouts) (filter :unpushed?) (sort-by :repo))
        source-pushes (remove #(lib-repos (:repo %)) pushable)
        lib-pushes (filter #(lib-repos (:repo %)) pushable)]
    (vec
     (concat
      ;; 1. Your source repos: get the commits onto their remotes first.
      (for [{:keys [dir repo]} source-pushes]
        {:kind :push :dir dir
         :desc (str "push " (tilde dir) " -> origin")
         :why (str repo " has commits the locks cannot pin until they are pushed")})
      ;; 2. The library repos (sway-home): push their own work, fast-forward,
      ;;    regenerate every lock they own, then commit and push.
      (mapcat
       (fn [{:keys [dir repo]}]
         (when dir
           (concat
            (for [{d :dir} (filter #(= repo (:repo %)) lib-pushes)]
              {:kind :push :dir d
               :desc (str "push " (tilde d) " -> origin")
               :why "its own commits must land before the lock bump"})
            [{:kind :pull :dir dir
              :desc (str "git pull --ff-only in " (tilde dir))
              :why "avoids a rejected push after the lock bump"}]
            (for [lockfile (nested-locks dir)
                  :let [fdir (str (fs/parent lockfile))]]
              {:kind :update :dir fdir
               :desc (str "nix flake update in " (tilde fdir))
               :why (str "rewrites " (lock-label dir lockfile))})
            [{:kind :commit-push :dir dir
              :desc (str "commit + push the lock changes in " (tilde dir))
              :why "the host flake pins this repo by commit, so the bump must be on the remote"}])))
       libraries)
      ;; 3. The host repo last: only now can it see the library's new commit.
      [{:kind :update :dir (str flake)
        :desc (str "nix flake update in " (tilde flake))
        :why (if (seq libraries)
               "picks up the new library rev and, through it, every repin"
               "repins the source repos straight from their remotes")}]))))

(defn confirm?
  "Ask once. Without a tty, refuse rather than guess."
  [prompt {:keys [yes]}]
  (cond
    yes true
    (not tty?) (do (stderr (yellow "Not a tty and --yes was not given; refusing to act."))
                   false)
    :else (do (print (str prompt " ")) (flush)
              (contains? #{"y" "yes"} (str/lower-case (str/trim (or (read-line) "")))))))

(defn execute-step! [{:keys [kind dir]}]
  (case kind
    :push (run-or-die! dir "git" "push")
    :pull (if (git-out dir "rev-parse" "--abbrev-ref" "@{u}")
            (run-or-die! dir "git" "pull" "--ff-only")
            (println "   " (dim "skipped: no upstream branch")))
    :update (run-or-die! dir "nix" "flake" "update")
    :commit-push
    (let [locks (mapv #(str (fs/relativize (str dir) (str %))) (nested-locks dir))
          changed (apply git-out dir "status" "--porcelain" "--" locks)]
      (if-not changed
        (println "   " (dim "nothing to commit: the locks were already current"))
        (do (apply run-or-die! dir "git" "add" "--" locks)
            (run-or-die! dir "git" "commit" "-m" "flake update")
            (run-or-die! dir "git" "push"))))))

(defn- show-dirt [{:keys [dir dirty-paths]}]
  (println "  " (tilde dir)
           (dim (str "-- " (str/join ", " (take 5 dirty-paths))
                     (when (> (count dirty-paths) 5) ", ...")))))

(defn upgrade! [s opts]
  (let [{:keys [dirty]} (report! s opts)
        lib-repos (set (map :repo (:libraries s)))
        ;; Dirt only blocks where we actually commit -- the library repo,
        ;; whose lock commit would otherwise sweep up unrelated edits.
        ;; Lock churn there is fine; we are about to rewrite those anyway.
        blockers (->> dirty (filter #(lib-repos (:repo %))) (remove lock-only-dirt?))
        ;; Elsewhere a push is still safe, but the pin will capture HEAD
        ;; and silently leave the working tree behind -- say so.
        unpinned (remove #(lib-repos (:repo %)) dirty)
        plan (build-plan s)]
    (when (seq blockers)
      (println (red "Uncommitted changes block the lock bump:"))
      (doseq [d blockers] (show-dirt d))
      (println)
      (println "Commit or stash them (a lock commit would sweep them up), then re-run.")
      (System/exit 1))
    (when (seq unpinned)
      (println (yellow "warning:") "uncommitted work will NOT reach the machine --"
               "the new pins capture each repo's HEAD, not its working tree:")
      (doseq [d unpinned] (show-dirt d))
      (println))
    (when-let [missing (seq (remove :dir (:libraries s)))]
      (doseq [{:keys [owner repo]} missing]
        (println (yellow "note:") (str owner "/" repo)
                 "has no local checkout, so its locks cannot be bumped here."))
      (println (dim "      Clone it with `git vendor`, or run flake-upgrade where it lives."))
      (println))
    (println (bold "upgrade plan"))
    (doseq [[i {:keys [desc why]}] (map-indexed vector plan)]
      (println (format "  %2d. %s" (inc i) desc))
      (println "      " (dim why)))
    (println)
    (if-not (confirm? (str "Run these " (count plan) " steps?" (dim " [y/N]")) opts)
      (do (println "Aborted; nothing was changed.") (System/exit 1))
      (do
        (println)
        (doseq [[i step] (map-indexed vector plan)]
          (println (bold (format "[%d/%d]" (inc i) (count plan))) (:desc step))
          (execute-step! step))
        (println)
        (println (green "Pins updated.") "Run" (bold "`admin upgrade`") "to rebuild and switch.")))))

;;; ============================================================
;;; CLI
;;; ============================================================

(defn usage []
  (println "Usage: flake-sync <check|preflight|upgrade> [options]")
  (println)
  (println "Keep the flake pin chain (host repo -> sway-home -> source repos) in sync.")
  (println)
  (println "Subcommands:")
  (println "  check      Report pins behind their git upstreams and checkouts with")
  (println "             unpushed commits. Read-only; exits 3 if action is needed.")
  (println "  preflight  Same check, quiet when clean, then asks whether to continue.")
  (println "             Skipped entirely when NO_FLAKE_CHECK is set.")
  (println "  upgrade    Push source repos, bump + commit + push sway-home's locks, then")
  (println "             update the host lock -- after showing the plan and confirming.")
  (println)
  (println "Options:")
  (println "  --flake DIR    Host flake repo (default: current directory).")
  (println "  --owner NAME   Github owner whose repos are yours (default: inferred from")
  (println "                 the sway-home input in the host flake.lock).")
  (println "  --vendor DIR   Local checkout root (default: ~/git/vendor).")
  (println "  --relock       The caller regenerates the lock itself (sway-home's")
  (println "                 hm-update), so a stale pin is not a finding -- only")
  (println "                 local work the relock would leave behind is.")
  (println "  --verbose      Also show which locks pin each up-to-date repo.")
  (println "  --yes          Skip the confirmation prompt (upgrade).")
  (println "  -h, --help     Show this help."))

(defn parse-args [args]
  (loop [args args opts {:flake (str (fs/cwd))
                         :vendor (str (fs/path home "git" "vendor"))}]
    (if-let [a (first args)]
      (case a
        "--flake"   (recur (drop 2 args) (assoc opts :flake (str (fs/absolutize (second args)))))
        "--owner"   (recur (drop 2 args) (assoc opts :owner (second args)))
        "--vendor"  (recur (drop 2 args) (assoc opts :vendor (str (fs/absolutize (second args)))))
        "--relock"  (recur (rest args) (assoc opts :relock true))
        "--verbose" (recur (rest args) (assoc opts :verbose true))
        "--yes"     (recur (rest args) (assoc opts :yes true))
        ("-h" "--help") (do (usage) (System/exit 0))
        (if (and (nil? (:cmd opts)) (not (str/starts-with? a "-")))
          (recur (rest args) (assoc opts :cmd a))
          (do (stderr "Unknown option:" a) (usage) (System/exit 2))))
      opts)))

(defn -main []
  (let [opts (parse-args *command-line-args*)
        cmd (:cmd opts)]
    (when (and cmd (not (fs/directory? (:flake opts))))
      (die "no such directory:" (:flake opts)))
    (case cmd
      "check"
      (let [{:keys [actionable? unknown]} (report! (survey opts) opts)]
        (cond
          actionable?
          (do (if (:relock opts)
                ;; The caller relocks, so pushing is the only thing left
                ;; for a human to do.
                (println "Push the checkouts above first; the relock reads their remotes.")
                (println "Run" (bold "`admin flake-upgrade`")
                         "to update the pins, then" (bold "`admin upgrade`.")))
              (System/exit 3))
          (seq unknown)
          (do (println (yellow "Some upstreams were unreachable; everything else is current."))
              (System/exit 0))
          :else
          (do (println (green "All of your pins are current.")) (System/exit 0))))

      "preflight"
      (if (System/getenv "NO_FLAKE_CHECK")
        (System/exit 0)
        (let [s (survey opts)
              {:keys [actionable? stale to-push]} (findings s opts)]
          (if-not actionable?
            ;; Nothing to say: fall through to the rebuild silently.
            (System/exit 0)
            (do
              (report! s opts)
              (if (:relock opts)
                (do (println (yellow "The lock about to be written will NOT include:")
                             (dim (str (count to-push) " unpushed checkout(s)")))
                    (println "It is rebuilt from the remotes, so push those first to include them."))
                (do (println (yellow "This rebuild will NOT include:")
                             (dim (str (count stale) " stale pin(s), "
                                       (count to-push) " unpushed checkout(s)")))
                    (println "Run" (bold "`admin flake-upgrade`")
                             "first to pull everything forward.")))
              (println)
              (cond
                (System/getenv "FLAKE_CHECK_WARN_ONLY") (System/exit 0)
                ;; Unattended (cron, piped shell): warn, never block.
                (not tty?) (do (println (dim "Not a tty; continuing without asking."))
                               (System/exit 0))
                (confirm? (str (if (:relock opts)
                                 "Continue without that work?"
                                 "Rebuild with the current pins anyway?")
                               (dim " [y/N]"))
                          opts)
                (System/exit 0)
                :else (do (println "Aborted.") (System/exit 1)))))))

      "upgrade" (upgrade! (survey opts) opts)

      (nil "help") (do (usage) (System/exit (if cmd 0 2)))
      (do (stderr "Unknown subcommand:" cmd) (usage) (System/exit 2)))))

(-main)
