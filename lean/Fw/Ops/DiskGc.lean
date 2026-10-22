import Lean.Data.Json
import Fw.Ops.LakeGc
import Fw.Ops.Wire

/-!
# Which local files `fw disk-gc` may delete (task `disk-auto-gc`)
Seven classes, each decided on its own over a closed allowlist of path shapes under fixed roots. Task `disk-gc-tmp`
adds class 7 (the user temp folder), an unknown owner that keeps a candidate, a disk-pressure floor for class 4 and
class 4 for the scratch of a landed task.
-/
namespace Fw.Ops.DiskGc

/-- The seven cleanup classes, numbered 1 to 7 in this order. -/
inductive Cls where
  | lake
  | landed
  | idle
  | scratch
  | sim
  | console
  | usertmp
deriving Repr, DecidableEq

/-- The number of a class, 1 to 7. -/
def Cls.num : Cls → Nat
  | .lake => 1
  | .landed => 2
  | .idle => 3
  | .scratch => 4
  | .sim => 5
  | .console => 6
  | .usertmp => 7

/-- The name of a class. -/
def Cls.name : Cls → String
  | .lake => "lake"
  | .landed => "landed"
  | .idle => "idle"
  | .scratch => "scratch"
  | .sim => "sim"
  | .console => "console"
  | .usertmp => "usertmp"

/-- Every class, by number. -/
def Cls.all : List Cls := [.lake, .landed, .idle, .scratch, .sim, .console, .usertmp]

/-- The class with number or name `s`. -/
def Cls.parse (s : String) : Option Cls := Cls.all.find? fun c => toString c.num == s || c.name == s

/-- A worktree's lock as `git worktree list --porcelain` reports it: none, held by a process (pid and start time as
`ps -o lstart` prints it), or a reason that names no process. -/
inductive Lock where
  | free
  | held (pid : Nat) (start : String)
  | unknown
deriving Repr, DecidableEq

/-- A live process: pid and start time as `ps -o lstart` prints it. -/
structure Proc where
  pid : Nat
  start : String
deriving Repr, DecidableEq

/-- The allowed roots: the main checkout, the Lake artifacts directory, the project's session scratch directory
(`<tmp>/claude-<uid>/<project>`), the CoreSimulator devices directory and the user temp folder
(`…/folders/<a>/<b>/T`, empty when not given). -/
structure Roots where
  repo : String
  lake : String
  scratch : String
  devices : String
  utmp : String := ""
deriving Repr

/-- One candidate as the glue reads it; an absent class fact keeps it. -/
structure Cand where
  cls : Cls
  /-- The resolved absolute path. -/
  path : String
  bytes : Nat
  /-- The owner's uid; `none` when it could not be read (a vanished path), which keeps the candidate. -/
  uid : Option Nat
  tracked : Bool
  /-- The newest modification time it holds (epoch seconds); for class 3, that of its worktree's other files. -/
  newest : Nat
  /-- A directory (lstat, so not a symlink). -/
  dir : Bool
  /-- A symbolic link (lstat). -/
  sym : Bool := false
  /-- The task and workflow run a scratch directory's `.fw-owner` marker names (class 4). -/
  owner : Option (String × String) := none
  /-- The Lake cache fact (class 1). -/
  lake : Option LakeGc.Fact := none
  /-- The worktree's branch (classes 2 and 3; empty when detached). -/
  branch : String := ""
  /-- The branch is landed in main (classes 2 and 3). -/
  merged : Option Bool := none
  /-- The worktree has uncommitted or untracked changes (classes 2 and 3). -/
  dirty : Option Bool := none
  lock : Lock := .free
  /-- The device name and state (class 5). -/
  device : Option (String × String) := none
deriving Repr

/-- The default age floor of class 7: 2 hours. -/
def defaultTmpH : Nat := 2

/-- The run's inputs besides the candidates; a fact family that is `none` was not gathered and keeps what it guards. -/
structure Config where
  roots : Roots
  /-- The classes this run may delete. -/
  classes : List Cls
  /-- The uid of the user running it. -/
  uid : Nat
  now : Nat
  /-- The age floors of classes 3, 4 (hours) and 6 (days). -/
  idleH : Nat
  scratchH : Nat
  keepDays : Nat
  /-- The `Fw.Ops.LakeGc` config of class 1. -/
  lake : Option LakeGc.Config
  /-- Every path a process holds open or works in. -/
  opens : Option (List String)
  /-- The process table, for worktree locks. -/
  procs : Option (List Proc)
  /-- The branches with a pending land. -/
  queued : Option (List String)
  /-- The `scratchpad/<dir>` strings committed files hold. -/
  cited : Option (List String)
  /-- The `fw-*` names the workflows and packages hold. -/
  named : Option (List String)
  /-- The Simulator lock is held. -/
  simLock : Option Bool
  /-- The age floor of class 7 (hours). -/
  tmpH : Nat := defaultTmpH
  /-- The run is a response to low disk (`sys.diskLow`): class 4 uses the pressure floor. -/
  pressure : Bool := false
  /-- The names of the agents that are running (fails closed when not gathered). -/
  liveAgents : Option (List String) := none
  /-- The tasks whose branch has a commit contained in main. -/
  landedTasks : Option (List String) := none
  /-- The workflow runs that have finished. -/
  finishedRuns : Option (List String) := none
deriving Repr

/-- The default idle floor of class 3: 24 hours. -/
def defaultIdleH : Nat := 24

/-- The default age floor of class 4: 8 hours, the lead's rule of 2026-10-21. -/
def defaultScratchH : Nat := 8

/-- The default age floor of class 6: 7 days. -/
def defaultKeepDays : Nat := 7

/-- The age floor of class 4 under disk pressure: 2 hours. -/
def pressureScratchH : Nat := 2

/-- The age of a scratch directory whose task has landed and whose run has finished: 1 hour. -/
def ownerFloorS : Nat := 3600

/-! ## Paths -/

/-- The `/`-segments of `r` after its leading `/`. -/
def rootSegs (r : String) : List String := (r.splitOn "/").drop 1

/-- An allowed root: absolute, only `LakeGc.rootChar`s, every segment non-empty and none of `.`, `..`, `.local`. -/
def absOk (r : String) : Bool :=
  r.startsWith "/" && r.all LakeGc.rootChar &&
    (rootSegs r).all fun s => s != "" && s != "." && s != ".." && s != ".local"

/-- The worktrees root of the main checkout. -/
def wtRoot (r : Roots) : String := r.repo ++ "/.claude/worktrees"

/-- The console directory of the main checkout. -/
def consoleRoot (r : Roots) : String := r.repo ++ "/.fw-console"

/-- The root a class deletes under. -/
def classRoot (r : Roots) : Cls → String
  | .lake => r.lake
  | .landed | .idle => wtRoot r
  | .scratch => r.scratch
  | .sim => r.devices
  | .console => consoleRoot r
  | .usertmp => r.utmp

/-- A scratch root: allowed, and its parent directory is named `claude-…`. -/
def scratchRootOk (s : String) : Bool :=
  absOk s && match (rootSegs s).reverse with
    | _ :: p :: _ => p.startsWith "claude-"
    | _ => false

/-- A user temp root: allowed, and it is `…/folders/<a>/<b>/T`. -/
def utmpRootOk (s : String) : Bool :=
  absOk s && match (rootSegs s).reverse with
    | "T" :: _ :: _ :: "folders" :: _ => true
    | _ => false

/-- The root of a class is allowed. -/
def rootOk (r : Roots) : Cls → Bool
  | .lake => LakeGc.rootOk r.lake && absOk r.lake
  | .landed | .idle | .console => absOk r.repo
  | .scratch => scratchRootOk r.scratch
  | .sim => absOk r.devices && r.devices.endsWith "/CoreSimulator/Devices"
  | .usertmp => utmpRootOk r.utmp

/-- A hex digit. -/
def hexChar (x : Char) : Bool := x.isDigit || ('A' ≤ x && x ≤ 'F') || ('a' ≤ x && x ≤ 'f')

/-- A device UDID: five groups of 8, 4, 4, 4 and 12 hex digits joined by `-`. -/
def udidOk (u : String) : Bool :=
  (u.splitOn "-").map String.length == [8, 4, 4, 4, 12] && (u.splitOn "-").all (·.all hexChar)

/-- The name prefixes of our own temp entries in the user temp folder. -/
def tmpPrefixes : List String := ["fw", "oracle", "ghb", "engine-check", "premises", "land-base", "lint", "var"]

/-- An entry of the user temp folder we may delete: an allowed name that starts with one of `tmpPrefixes`, or an
Instruments kernel trace `instruments….ktrace`. -/
def tmpNameOk (n : String) : Bool :=
  LakeGc.nameOk n && (tmpPrefixes.any (fun p => n.startsWith p) || (n.startsWith "instruments" && n.endsWith ".ktrace"))

/-- The segments below the root a class allows. -/
def shape : Cls → List String → Bool
  | .lake, [n] => LakeGc.nameOk n
  | .landed, [w] => LakeGc.nameOk w
  | .idle, [w, "node_modules"] => LakeGc.nameOk w
  | .idle, [w, "lean", ".lake"] => LakeGc.nameOk w
  | .idle, [w, "apps", x, "node_modules"] => LakeGc.nameOk w && LakeGc.nameOk x
  | .idle, [w, "packages", x, "node_modules"] => LakeGc.nameOk w && LakeGc.nameOk x
  | .scratch, [s, m, d] => m == "scratchpad" && LakeGc.nameOk s && LakeGc.nameOk d && !d.startsWith "fable"
  | .sim, [u] => udidOk u
  | .console, ["tmp", n] => LakeGc.nameOk n
  | .console, ["land-logs", n] => LakeGc.nameOk n
  | .usertmp, [n] => tmpNameOk n
  | _, _ => false

/-- The segments of `p` below `root`, when `p` starts with `root/`. -/
def segsOf (root p : String) : Option (List String) :=
  if p.startsWith (root ++ "/") then some ((p.drop (root.length + 1)).toString.splitOn "/") else none

/-- `p` is `root/` and segments the class allows, none of them `.local`. -/
def underOk (root p : String) (c : Cls) : Bool :=
  match segsOf root p with
  | none => false
  | some ss => p == root ++ "/" ++ "/".intercalate ss && shape c ss && !ss.contains ".local"

/-- **The allowlist.** `p` lies under the allowed root of class `c` in one of its allowed shapes. -/
def pathOk (r : Roots) (c : Cls) (p : String) : Bool := rootOk r c && underOk (classRoot r c) p c

/-! ## Liveness -/

/-- `p` is `d` or lies below it. -/
def under (d p : String) : Bool := p == d || p.startsWith (d ++ "/")

/-- Some process holds a path in `x` open or works in it (fails closed when not gathered). -/
def openIn (cfg : Config) (x : Cand) : Bool :=
  match cfg.opens with
  | none => true
  | some os => os.any (under x.path)

/-- The non-empty space-separated words of a start time (`ps` pads single-digit days). -/
def words (s : String) : List String := (s.splitOn " ").filter (· != "")

/-- The lock's holder is live: same pid and start time in the process table. An unknown lock, or a held one with no
process table, counts as live. -/
def lockLive (cfg : Config) : Lock → Bool
  | .free => false
  | .unknown => true
  | .held pid st =>
    match cfg.procs with
    | none => true
    | some ps => ps.any fun p => p.pid == pid && words p.start == words st

/-- A pending land names the branch (fails closed when not gathered). -/
def queuedB (cfg : Config) (b : String) : Bool :=
  match cfg.queued with
  | none => true
  | some q => q.contains b

/-- The candidate is in use: a process holds or works in it, its worktree lock is live, or a land is queued for its
branch. -/
def live (cfg : Config) (x : Cand) : Bool :=
  openIn cfg x || lockLive cfg x.lock || (x.branch != "" && queuedB cfg x.branch)

/-! ## The class rules -/

/-- The newest time in `x` is at least `s` seconds before now. -/
def olderThan (cfg : Config) (x : Cand) (s : Nat) : Bool := decide (x.newest + s ≤ cfg.now)

/-- The last `/`-segment of a path. -/
def lastSeg (p : String) : String := ((p.splitOn "/").getLast?).getD p

/-- A committed file cites the scratch directory `x` (fails closed when not gathered). -/
def cited (cfg : Config) (x : Cand) : Bool :=
  match cfg.cited with
  | none => true
  | some l => l.contains ("scratchpad/" ++ lastSeg x.path)

/-- A workflow or package names the device (fails closed when not gathered). -/
def named (cfg : Config) (n : String) : Bool :=
  match cfg.named with
  | none => true
  | some l => l.contains n

/-- Class 1: the Lake fact of `x` is listed by `Fw.Ops.LakeGc.ok` under the same root. -/
def ruleLake (cfg : Config) (x : Cand) : Bool :=
  match cfg.lake, x.lake with
  | some lc, some f => lc.root == cfg.roots.lake && x.path == LakeGc.pathOf lc.root f.name && LakeGc.ok lc f
  | _, _ => false

/-- Class 2: a worktree directory on a named branch merged into main, with no uncommitted or untracked change. -/
def ruleLanded (x : Cand) : Bool := x.dir && x.branch != "" && x.merged == some true && x.dirty == some false

/-- Class 3: a folder of a worktree on a named branch not merged into main, whose other files are older than
`idleH` hours. -/
def ruleIdle (cfg : Config) (x : Cand) : Bool :=
  x.dir && x.branch != "" && x.merged == some false && olderThan cfg x (cfg.idleH * 3600)

/-- An agent of this name is running (fails closed when not gathered). -/
def agentLive (cfg : Config) (x : Cand) : Bool :=
  match cfg.liveAgents with
  | none => true
  | some l => l.contains (lastSeg x.path)

/-- Class 4, by age: no file newer than `scratchH` hours. -/
def scratchAge (cfg : Config) (x : Cand) : Bool := olderThan cfg x (cfg.scratchH * 3600)

/-- Class 4, under disk pressure: no running agent has the directory's name, and no file is newer than
`pressureScratchH` hours. -/
def scratchPressure (cfg : Config) (x : Cand) : Bool :=
  cfg.pressure && !agentLive cfg x && olderThan cfg x (pressureScratchH * 3600)

/-- Class 4, by identity: the directory's `.fw-owner` marker names a task whose branch has landed and a workflow run
that has finished, and no file is newer than `ownerFloorS` seconds. -/
def scratchOwner (cfg : Config) (x : Cand) : Bool :=
  match x.owner, cfg.landedTasks, cfg.finishedRuns with
  | some (t, r), some lt, some fr => lt.contains t && fr.contains r && olderThan cfg x ownerFloorS
  | _, _, _ => false

/-- Class 4: a scratch directory no committed file cites that is old (`scratchAge`), idle under pressure
(`scratchPressure`) or finished (`scratchOwner`). -/
def ruleScratch (cfg : Config) (x : Cand) : Bool :=
  x.dir && !cited cfg x && (scratchAge cfg x || scratchPressure cfg x || scratchOwner cfg x)

/-- Class 5: a shut-down device named `fw-…` that no workflow or package names, with the Simulator lock free. -/
def ruleSim (cfg : Config) (x : Cand) : Bool :=
  match x.device with
  | some (n, st) => n.startsWith "fw-" && st == "Shutdown" && !named cfg n && cfg.simLock == some false
  | none => false

/-- Class 6: an entry that is not a symbolic link and is older than `keepDays` days. -/
def ruleConsole (cfg : Config) (x : Cand) : Bool := !x.sym && olderThan cfg x (cfg.keepDays * 86400)

/-- Class 7: an entry that is not a symbolic link, with no file newer than `tmpH` hours. Its name is in the allowlist
by `shape`. -/
def ruleUsertmp (cfg : Config) (x : Cand) : Bool := !x.sym && olderThan cfg x (cfg.tmpH * 3600)

/-- The rule of the candidate's class. -/
def rule (cfg : Config) (x : Cand) : Bool :=
  match x.cls with
  | .lake => ruleLake cfg x
  | .landed => ruleLanded x
  | .idle => ruleIdle cfg x
  | .scratch => ruleScratch cfg x
  | .sim => ruleSim cfg x
  | .console => ruleConsole cfg x
  | .usertmp => ruleUsertmp cfg x

/-- What every class requires besides being enabled: an allowed path, owned by the user, not tracked, not in use. -/
def guard (cfg : Config) (x : Cand) : Bool :=
  pathOk cfg.roots x.cls x.path && x.uid == some cfg.uid && !x.tracked && !live cfg x

/-- One candidate, decided alone: its class is enabled, it passes the guard and its class rule. -/
def chosen (cfg : Config) (x : Cand) : Bool := cfg.classes.contains x.cls && guard cfg x && rule cfg x

/-- The candidates to delete, in input order. -/
def select (cfg : Config) (xs : List Cand) : List Cand := xs.filter (chosen cfg)

/-- The count and bytes of class `c` in `l`. -/
def tally (l : List Cand) (c : Cls) : Nat × Nat :=
  let m := l.filter (·.cls == c)
  (m.length, (m.map (·.bytes)).sum)

/-- Class 1's rule with the `LakeGc` index computed once per run. -/
def ruleLakeIx (cfg : Config) (ix : Option LakeGc.Index) (x : Cand) : Bool :=
  match cfg.lake, ix, x.lake with
  | some lc, some i, some f => lc.root == cfg.roots.lake && x.path == LakeGc.pathOf lc.root f.name && LakeGc.okFast lc i f
  | _, _, _ => false

/-- `chosen` with class 1 decided over the index. -/
def chosenIx (cfg : Config) (ix : Option LakeGc.Index) (x : Cand) : Bool :=
  cfg.classes.contains x.cls && guard cfg x && (if x.cls = .lake then ruleLakeIx cfg ix x else rule cfg x)

/-- The run's selection: `select` with the index built once. -/
def selectFast (cfg : Config) (xs : List Cand) : List Cand := xs.filter (chosenIx cfg (cfg.lake.map LakeGc.Index.of))

/-! ## Examples -/

/-- Roots for the examples. -/
def exRoots : Roots :=
  ⟨"/u/r", "/u/.elan/c/artifacts", "/private/tmp/claude-1/-u-r", "/u/Library/Developer/CoreSimulator/Devices",
    "/private/var/folders/ab/cd/T"⟩

/-- A config for the examples: every class, every fact gathered, nothing open, queued, cited or named. -/
def exCfg : Config :=
  { roots := exRoots, classes := Cls.all, uid := 1, now := 1000000, idleH := 24, scratchH := 8, keepDays := 7,
    lake := some ⟨exRoots.lake, 1000000, 7200, 0, some [], some [], some []⟩, opens := some [], procs := some [],
    queued := some [], cited := some [], named := some ["fw-iphone-27"], simLock := some false }

/-- A scratch directory candidate. -/
def exScratch (d : String) (newest : Nat) : Cand :=
  { cls := .scratch, path := s!"/private/tmp/claude-1/-u-r/s1/scratchpad/{d}", bytes := 10, uid := some 1, tracked := false,
    newest, dir := true }

#guard chosen exCfg (exScratch "old" 0)
#guard !chosen exCfg (exScratch "young" 990000)
#guard !chosen exCfg (exScratch "fable-x" 0)
#guard !chosen { exCfg with cited := some ["scratchpad/old"] } (exScratch "old" 0)
#guard !chosen { exCfg with opens := some ["/private/tmp/claude-1/-u-r/s1/scratchpad/old/f"] } (exScratch "old" 0)
#guard chosen { exCfg with opens := some ["/private/tmp/claude-1/-u-r/s1/scratchpad/older"] } (exScratch "old" 0)
#guard !chosen { exCfg with opens := none } (exScratch "old" 0)
#guard !chosen exCfg { exScratch "old" 0 with path := "/private/tmp/claude-1/-u-r/s1/scratchpad/../x" }
#guard !chosen exCfg { exScratch "old" 0 with path := "/private/tmp/claude-1/-u-r/s1/scratchpad/a/b" }
#guard !chosen exCfg { exScratch "old" 0 with uid := some 2 }
#guard !chosen { exCfg with classes := [.lake] } (exScratch "old" 0)
/-- A worktree candidate of class `c` at `rel` below the worktrees root, merged or not, with lock `k`. -/
def exWt (c : Cls) (rel : String) (merged : Bool) (k : Lock) : Cand :=
  { cls := c, path := s!"/u/r/.claude/worktrees/{rel}", bytes := 1, uid := some 1, tracked := false, newest := 0,
    dir := true, branch := "b", merged := some merged, dirty := some false, lock := k }

/-- A device candidate named `n`. -/
def exSim (n : String) : Cand :=
  { cls := .sim, path := "/u/Library/Developer/CoreSimulator/Devices/0a1b2c3d-0000-1111-2222-333344445555",
    bytes := 1, uid := some 1, tracked := false, newest := 0, dir := true, device := some (n, "Shutdown") }

/-- A console candidate at `rel` below `.fw-console`. -/
def exConsole (rel : String) : Cand :=
  { cls := .console, path := s!"/u/r/.fw-console/{rel}", bytes := 1, uid := some 1, tracked := false, newest := 0,
    dir := false }

#guard chosen exCfg (exWt .landed "w1" true .free)
#guard !chosen exCfg (exWt .landed "w1" false .free)
#guard !chosen exCfg (exWt .landed "w1" true .unknown)
#guard !chosen { exCfg with queued := some ["b"] } (exWt .landed "w1" true .free)
#guard chosen exCfg (exWt .landed "w1" true (.held 7 "Mon Oct  9 1"))
#guard !chosen { exCfg with procs := some [⟨7, "Mon Oct 9 1"⟩] } (exWt .landed "w1" true (.held 7 "Mon Oct  9 1"))
#guard chosen exCfg (exWt .idle "w1/lean/.lake" false .free)
#guard chosen exCfg (exWt .idle "w1/apps/site/node_modules" false .free)
#guard !chosen exCfg (exWt .idle "w1/lean" false .free)
#guard !chosen exCfg (exWt .idle "w1/lean/.lake" true .free)
#guard chosen exCfg (exSim "fw-iphone-17")
#guard !chosen exCfg (exSim "fw-iphone-27")
#guard !chosen exCfg (exSim "iPhone 17")
#guard !chosen { exCfg with simLock := some true } (exSim "fw-iphone-17")
#guard chosen exCfg (exConsole "land-logs/t-abc1234.log")
#guard chosen exCfg (exConsole "tmp/chromium-1")
#guard !chosen exCfg (exConsole "events.jsonl")
#guard Cls.parse "4" == some .scratch && Cls.parse "sim" == some .sim && Cls.parse "7" == some .usertmp &&
  Cls.parse "8" == none
#guard !chosen exCfg { exScratch "old" 0 with uid := none }
#guard !chosen exCfg { exConsole "tmp/chromium-1" with sym := true }

/-- A scratch directory of a task `t1` run `r1`. -/
def exOwned (d : String) (newest : Nat) : Cand := { exScratch d newest with owner := some ("t1", "r1") }

/-- The pressure floor: 2 h instead of 8 h, and only when no agent of that name runs. -/
def exPress : Config := { exCfg with pressure := true, liveAgents := some ["busy"] }

#guard !chosen exCfg (exScratch "mid" (1000000 - 3 * 3600))
#guard chosen exPress (exScratch "mid" (1000000 - 3 * 3600))
#guard !chosen exPress (exScratch "busy" (1000000 - 3 * 3600))
#guard !chosen { exPress with liveAgents := none } (exScratch "mid" (1000000 - 3 * 3600))
#guard !chosen exPress (exScratch "young" (1000000 - 3600))
#guard !chosen exPress { exScratch "mid" (1000000 - 3 * 3600) with dir := false }
#guard !chosen { exPress with cited := some ["scratchpad/mid"] } (exScratch "mid" (1000000 - 3 * 3600))
#guard !chosen { exPress with opens := some ["/private/tmp/claude-1/-u-r/s1/scratchpad/mid"] } (exScratch "mid" (1000000 - 3 * 3600))
#guard chosen { exCfg with landedTasks := some ["t1"], finishedRuns := some ["r1"] } (exOwned "m" (1000000 - 7200))
#guard !chosen { exCfg with landedTasks := some ["t1"], finishedRuns := some ["r1"] } (exOwned "m" (1000000 - 60))
#guard !chosen { exCfg with landedTasks := some ["t2"], finishedRuns := some ["r1"] } (exOwned "m" (1000000 - 7200))
#guard !chosen { exCfg with landedTasks := some ["t1"], finishedRuns := some ["r2"] } (exOwned "m" (1000000 - 7200))
#guard !chosen { exCfg with landedTasks := none, finishedRuns := some ["r1"] } (exOwned "m" (1000000 - 7200))
#guard !chosen { exCfg with landedTasks := some ["t1"], finishedRuns := none } (exOwned "m" (1000000 - 7200))
#guard !chosen { exCfg with landedTasks := some ["t1"], finishedRuns := some ["r1"] } (exScratch "m" (1000000 - 7200))

/-- A user temp candidate named `n`. -/
def exTmp (n : String) : Cand :=
  { cls := .usertmp, path := s!"/private/var/folders/ab/cd/T/{n}", bytes := 1, uid := some 1, tracked := false,
    newest := 0, dir := true }

#guard chosen exCfg (exTmp "fw-land-abc")
#guard chosen exCfg (exTmp "oracle1")
#guard chosen exCfg (exTmp "engine-check-x")
#guard chosen exCfg { exTmp "instruments-1.ktrace" with dir := false }
#guard !chosen exCfg (exTmp "instruments-1.trace")
#guard !chosen exCfg (exTmp "com.apple.x")
#guard !chosen exCfg (exTmp "xfw")
#guard !chosen exCfg (exTmp ".fw")
#guard !chosen exCfg { exTmp "fw1" with path := "/private/var/folders/ab/cd/T" }
#guard !chosen exCfg { exTmp "fw1" with path := "/private/var/folders/ab/cd/T/" }
#guard !chosen exCfg { exTmp "fw1" with path := "/private/var/folders/ab/cd/T/fw1/x" }
#guard !chosen exCfg { exTmp "fw1" with path := "/private/var/folders/ab/cd/T/../fw1" }
#guard !chosen exCfg { exTmp "fw1" with sym := true }
#guard !chosen exCfg { exTmp "fw1" with uid := some 2 }
#guard !chosen exCfg { exTmp "fw1" with uid := none }
#guard !chosen exCfg { exTmp "fw1" with newest := 1000000 - 3600 }
#guard chosen exCfg { exTmp "fw1" with newest := 1000000 - 7200 }
#guard !chosen { exCfg with opens := some ["/private/var/folders/ab/cd/T/fw1/f"] } (exTmp "fw1")
#guard !chosen { exCfg with opens := none } (exTmp "fw1")
#guard !chosen { exCfg with roots := { exRoots with utmp := "/private/var/folders/ab/T" } } (exTmp "fw1")
#guard !chosen { exCfg with roots := { exRoots with utmp := "/private/tmp/ab/cd/T" } } (exTmp "fw1")
#guard !chosen { exCfg with roots := { exRoots with utmp := "" } } (exTmp "fw1")
#guard !chosen { exCfg with classes := [.scratch] } (exTmp "fw1")

/-! ## Theorems -/

/-- A chosen candidate's class is enabled and it passes the guard and its class rule. -/
theorem chosen_iff (cfg : Config) (x : Cand) :
    chosen cfg x = true ↔ x.cls ∈ cfg.classes ∧ guard cfg x = true ∧ rule cfg x = true := by
  simp [chosen, and_assoc]

/-- The members of `select`. -/
theorem mem_select (cfg : Config) (xs : List Cand) (x : Cand) : x ∈ select cfg xs ↔ x ∈ xs ∧ chosen cfg x = true := by
  simp [select]

/-- The guard, field by field. -/
theorem guard_iff (cfg : Config) (x : Cand) : guard cfg x = true ↔
    pathOk cfg.roots x.cls x.path = true ∧ x.uid = some cfg.uid ∧ x.tracked = false ∧ live cfg x = false := by
  simp [guard, and_assoc]

/-- A selected candidate's class is enabled. -/
theorem selected_enabled (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : x.cls ∈ cfg.classes :=
  ((chosen_iff cfg x).1 ((mem_select cfg xs x).1 h).2).1

/-- A selected candidate passes the guard. -/
theorem selected_guard (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : guard cfg x = true :=
  ((chosen_iff cfg x).1 ((mem_select cfg xs x).1 h).2).2.1

/-- A selected candidate passes its class rule. -/
theorem selected_rule (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : rule cfg x = true :=
  ((chosen_iff cfg x).1 ((mem_select cfg xs x).1 h).2).2.2

/-- **Deletes only from the allowlist.** A selected candidate is one of the inputs, of a class this run enables, under
that class's allowed root, and its path is the root, `/` and segments the class's shape allows, none of them `.local`. -/
theorem deletes_subset_allowlist (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) :
    x ∈ xs ∧ x.cls ∈ cfg.classes ∧ rootOk cfg.roots x.cls = true ∧
      ∃ ss, x.path = classRoot cfg.roots x.cls ++ "/" ++ "/".intercalate ss ∧ shape x.cls ss = true ∧
        ".local" ∉ ss := by
  have hg := (guard_iff cfg x).1 (selected_guard cfg xs x h)
  refine ⟨((mem_select cfg xs x).1 h).1, selected_enabled cfg xs x h, ?_⟩
  have hp := hg.1
  simp only [pathOk, Bool.and_eq_true] at hp
  refine ⟨hp.1, ?_⟩
  have hu := hp.2
  unfold underOk at hu
  cases hs : segsOf (classRoot cfg.roots x.cls) x.path with
  | none => rw [hs] at hu; exact absurd hu (by simp)
  | some ss =>
    rw [hs] at hu
    simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hu
    refine ⟨ss, hu.1.1, hu.1.2, fun hm => ?_⟩
    have := hu.2
    simp at this
    exact this hm

/-- **Never deletes a tracked file.** -/
theorem never_tracked (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : x.tracked = false :=
  ((guard_iff cfg x).1 (selected_guard cfg xs x h)).2.2.1

/-- **Never deletes what the user does not own.** -/
theorem owned_only (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : x.uid = some cfg.uid :=
  ((guard_iff cfg x).1 (selected_guard cfg xs x h)).2.1

/-- **An unknown owner keeps the candidate.** A candidate whose uid could not be read is never selected. -/
theorem unknown_owner_kept (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : x.uid ≠ none := by
  rw [owned_only cfg xs x h]; simp

/-- **Never deletes anything live.** A selected candidate holds no open file and no process's working directory, has
no live worktree lock, and no land is queued for its branch. -/
theorem never_live (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) :
    openIn cfg x = false ∧ lockLive cfg x.lock = false ∧ (x.branch = "" ∨ queuedB cfg x.branch = false) := by
  have hl := ((guard_iff cfg x).1 (selected_guard cfg xs x h)).2.2.2
  simp only [live, Bool.or_eq_false_iff, Bool.and_eq_false_iff, bne_eq_false_iff_eq] at hl
  exact ⟨hl.1.1, hl.1.2, hl.2⟩

/-- **No open file inside.** The open paths were gathered and none lies in a selected candidate. -/
theorem never_open (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) :
    ∃ os, cfg.opens = some os ∧ ∀ o ∈ os, under x.path o = false := by
  have ho := (never_live cfg xs x h).1
  unfold openIn at ho
  cases hc : cfg.opens with
  | none => rw [hc] at ho; exact absurd ho (by simp)
  | some os =>
    rw [hc] at ho
    exact ⟨os, rfl, fun o hm => by simpa using List.any_eq_false.1 ho o hm⟩

/-- **No live lock.** A selected candidate's lock is free, or held by a pid whose start time no process of the
gathered table shares. -/
theorem never_locked_live (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) :
    x.lock = .free ∨ ∃ pid st ps, x.lock = .held pid st ∧ cfg.procs = some ps ∧
      ∀ p ∈ ps, ¬ (p.pid = pid ∧ words p.start = words st) := by
  have hl := (never_live cfg xs x h).2.1
  cases hk : x.lock with
  | free => exact .inl rfl
  | unknown => rw [hk] at hl; exact absurd hl (by simp [lockLive])
  | held pid st =>
    rw [hk] at hl
    unfold lockLive at hl
    cases hp : cfg.procs with
    | none => rw [hp] at hl; exact absurd hl (by simp)
    | some ps =>
      rw [hp] at hl
      refine .inr ⟨pid, st, ps, rfl, rfl, fun p hm hpq => ?_⟩
      have := List.any_eq_false.1 hl p hm
      simp [hpq.1, hpq.2] at this

/-- **No queued land.** A selected candidate on a branch has its branch in the gathered queue nowhere. -/
theorem never_queued (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hb : x.branch ≠ "") :
    ∃ q, cfg.queued = some q ∧ x.branch ∉ q := by
  rcases (never_live cfg xs x h).2.2 with he | hq
  · exact absurd he hb
  · unfold queuedB at hq
    cases hc : cfg.queued with
    | none => rw [hc] at hq; exact absurd hq (by simp)
    | some q => rw [hc] at hq; exact ⟨q, rfl, by simpa using hq⟩

/-- **Each candidate is decided on its own.** Whether a candidate is selected does not depend on the other candidates
of the run. -/
theorem independent (cfg : Config) (xs ys : List Cand) (x : Cand) (hx : x ∈ xs) (hy : x ∈ ys) :
    x ∈ select cfg xs ↔ x ∈ select cfg ys := by
  simp [mem_select, hx, hy]

/-- **Class decisions are independent.** Running one class alone selects exactly that class's part of a run of every
enabled class, whatever the candidates of the other classes are. -/
theorem class_alone (cfg : Config) (xs : List Cand) (c : Cls) (hc : c ∈ cfg.classes) :
    select { cfg with classes := [c] } xs = (select cfg xs).filter (·.cls == c) := by
  unfold select
  rw [List.filter_filter]
  congr 1
  funext x
  have hg : guard { cfg with classes := [c] } x = guard cfg x := rfl
  have hr : rule { cfg with classes := [c] } x = rule cfg x := by
    cases x.cls <;> rfl
  simp only [chosen, hg, hr]
  by_cases h : x.cls = c
  · subst h; simp [hc]
  · have : (x.cls == c) = false := by simpa using h
    simp [this, h]

/-- **Class 1 is `LakeGc`.** A selected Lake candidate is the artifact path of a fact `Fw.Ops.LakeGc.ok` accepts. -/
theorem rule_lake (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .lake) :
    ∃ lc f, cfg.lake = some lc ∧ x.lake = some f ∧ x.path = LakeGc.pathOf cfg.roots.lake f.name ∧
      LakeGc.ok lc f = true := by
  have hr := selected_rule cfg xs x h
  simp only [rule, hc, ruleLake] at hr
  cases hl : cfg.lake with
  | none => rw [hl] at hr; exact absurd hr (by simp)
  | some lc =>
    cases hf : x.lake with
    | none => rw [hl, hf] at hr; exact absurd hr (by simp)
    | some f =>
      rw [hl, hf] at hr
      simp only [Bool.and_eq_true, beq_iff_eq] at hr
      exact ⟨lc, f, rfl, rfl, hr.1.1.symm ▸ hr.1.2, hr.2⟩

/-- **Class 2 removes only merged, clean worktrees.** -/
theorem rule_landed (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .landed) :
    x.dir = true ∧ x.branch ≠ "" ∧ x.merged = some true ∧ x.dirty = some false := by
  have hr := selected_rule cfg xs x h
  simpa [rule, hc, ruleLanded, and_assoc] using hr

/-- **Class 3 only clears unmerged, idle worktrees.** -/
theorem rule_idle (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .idle) :
    x.dir = true ∧ x.branch ≠ "" ∧ x.merged = some false ∧ x.newest + cfg.idleH * 3600 ≤ cfg.now := by
  have hr := selected_rule cfg xs x h
  simpa [rule, hc, ruleIdle, olderThan, and_assoc] using hr

/-- **Class 4 deletes only uncited directories that are old, idle under pressure, or finished.** -/
theorem rule_scratch (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .scratch) :
    x.dir = true ∧ (∃ l, cfg.cited = some l ∧ ("scratchpad/" ++ lastSeg x.path) ∉ l) ∧
      (scratchAge cfg x = true ∨ scratchPressure cfg x = true ∨ scratchOwner cfg x = true) := by
  have hr := selected_rule cfg xs x h
  simp only [rule, hc, ruleScratch, Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_true] at hr
  refine ⟨hr.1.1, ?_, by rcases hr.2 with (h1 | h1) | h1 <;> simp [h1]⟩
  have hn := hr.1.2
  unfold cited at hn
  cases hl : cfg.cited with
  | none => rw [hl] at hn; exact absurd hn (by simp)
  | some l => rw [hl] at hn; exact ⟨l, rfl, by simpa using hn⟩

/-- **Branch 1 of class 4: the age floor.** No file is newer than `scratchH` hours. -/
theorem scratchAge_spec (cfg : Config) (x : Cand) (h : scratchAge cfg x = true) :
    x.newest + cfg.scratchH * 3600 ≤ cfg.now := by
  simpa [scratchAge, olderThan] using h

/-- **Branch 2 of class 4: pressure.** The run is a response to low disk, no running agent has the directory's name
(the list was gathered), and no file is newer than `pressureScratchH` hours. -/
theorem scratchPressure_spec (cfg : Config) (x : Cand) (h : scratchPressure cfg x = true) :
    cfg.pressure = true ∧ (∃ l, cfg.liveAgents = some l ∧ lastSeg x.path ∉ l) ∧
      x.newest + pressureScratchH * 3600 ≤ cfg.now := by
  simp only [scratchPressure, Bool.and_eq_true, Bool.not_eq_true', olderThan, decide_eq_true_eq] at h
  refine ⟨h.1.1, ?_, h.2⟩
  have hn := h.1.2
  unfold agentLive at hn
  cases hl : cfg.liveAgents with
  | none => rw [hl] at hn; exact absurd hn (by simp)
  | some l => rw [hl] at hn; exact ⟨l, rfl, by simpa using hn⟩

/-- **Branch 3 of class 4: identity.** The marker names a task in the landed list and a run in the finished list
(both gathered), and no file is newer than `ownerFloorS` seconds. -/
theorem scratchOwner_spec (cfg : Config) (x : Cand) (h : scratchOwner cfg x = true) :
    ∃ t r lt fr, x.owner = some (t, r) ∧ cfg.landedTasks = some lt ∧ cfg.finishedRuns = some fr ∧ t ∈ lt ∧ r ∈ fr ∧
      x.newest + ownerFloorS ≤ cfg.now := by
  unfold scratchOwner at h
  split at h
  · rename_i t r lt fr hx hl hf
    simp only [Bool.and_eq_true, olderThan, decide_eq_true_eq, List.contains_iff_mem] at h
    exact ⟨t, r, lt, fr, hx, hl, hf, h.1.1, h.1.2, h.2⟩
  · exact absurd h (by simp)

/-- **Without pressure the pressure branch is off.** -/
theorem no_pressure_no_branch (cfg : Config) (x : Cand) (h : cfg.pressure = false) : scratchPressure cfg x = false := by
  simp [scratchPressure, h]

/-- **Pressure only lowers the floor.** Whatever a run without pressure selects, the same run with pressure selects:
the guard does not read `pressure`, and the pressure branch only adds a candidate. -/
theorem pressure_only_lowers (cfg : Config) (x : Cand) (h : chosen { cfg with pressure := false } x = true) :
    chosen { cfg with pressure := true } x = true := by
  have hg : guard { cfg with pressure := true } x = guard { cfg with pressure := false } x := rfl
  have hr : rule { cfg with pressure := true } x = true := by
    have h' := ((chosen_iff _ x).1 h).2.2
    cases hc : x.cls
    case scratch =>
      have e1 : scratchAge { cfg with pressure := true } x = scratchAge { cfg with pressure := false } x := rfl
      have e2 : scratchOwner { cfg with pressure := true } x = scratchOwner { cfg with pressure := false } x := rfl
      have e3 : cited { cfg with pressure := true } x = cited { cfg with pressure := false } x := rfl
      simp only [rule, hc, ruleScratch, e1, e2, e3,
        no_pressure_no_branch { cfg with pressure := false } x rfl] at h' ⊢
      generalize x.dir = a at h' ⊢
      generalize cited { cfg with pressure := false } x = c at h' ⊢
      generalize scratchAge { cfg with pressure := false } x = g at h' ⊢
      generalize scratchOwner { cfg with pressure := false } x = o at h' ⊢
      generalize scratchPressure { cfg with pressure := true } x = p at h' ⊢
      cases a <;> cases c <;> cases g <;> cases o <;> cases p <;> simp_all
    all_goals (simp only [rule, hc] at h' ⊢; exact h')
  rw [chosen_iff] at h ⊢
  exact ⟨h.1, hg ▸ h.2.1, hr⟩

/-- **Class 4 never deletes a `fable…` directory.** -/
theorem never_fable (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .scratch) :
    ∃ s d, x.path = classRoot cfg.roots .scratch ++ "/" ++ "/".intercalate [s, "scratchpad", d] ∧
      d.startsWith "fable" = false := by
  obtain ⟨-, -, -, ss, hp, hs, -⟩ := deletes_subset_allowlist cfg xs x h
  rw [hc] at hp hs
  match ss, hs, hp with
  | [s, m, d], hs, hp =>
    simp only [shape, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hs
    rw [hs.1.1.1] at hp
    exact ⟨s, d, hp, hs.2⟩

/-- **Class 5 deletes only shut-down `fw-…` devices nothing names, with the Simulator lock free.** -/
theorem rule_sim (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .sim) :
    ∃ n st, x.device = some (n, st) ∧ n.startsWith "fw-" = true ∧ st = "Shutdown" ∧ cfg.simLock = some false ∧
      ∃ l, cfg.named = some l ∧ n ∉ l := by
  have hr := selected_rule cfg xs x h
  simp only [rule, hc, ruleSim] at hr
  cases hd : x.device with
  | none => rw [hd] at hr; exact absurd hr (by simp)
  | some p =>
    obtain ⟨n, st⟩ := p
    rw [hd] at hr
    simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hr
    refine ⟨n, st, rfl, hr.1.1.1, hr.1.1.2, hr.2, ?_⟩
    have hn := hr.1.2
    unfold named at hn
    cases hl : cfg.named with
    | none => rw [hl] at hn; exact absurd hn (by simp)
    | some l => rw [hl] at hn; exact ⟨l, rfl, by simpa using hn⟩

/-- **Class 6 deletes only entries that are not symbolic links and are older than `keepDays`.** -/
theorem rule_console (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .console) :
    x.sym = false ∧ x.newest + cfg.keepDays * 86400 ≤ cfg.now := by
  have hr := selected_rule cfg xs x h
  simpa [rule, hc, ruleConsole, olderThan] using hr

/-- **Class 7 deletes only old, non-link entries.** No file in the entry is newer than `tmpH` hours. -/
theorem rule_usertmp (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .usertmp) :
    x.sym = false ∧ x.newest + cfg.tmpH * 3600 ≤ cfg.now := by
  have hr := selected_rule cfg xs x h
  simpa [rule, hc, ruleUsertmp, olderThan] using hr

/-- **Class 7 deletes only our own names, one level below the user temp folder.** A selected class 7 candidate is the
folder, `/` and one allowed name: an `fw…`, `oracle…`, `ghb…`, `engine-check…`, `premises…`, `land-base…`, `lint…` or
`var…` entry, or an `instruments….ktrace` file. It is never the folder itself, and the folder is `…/folders/<a>/<b>/T`. -/
theorem usertmp_named (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .usertmp) :
    ∃ n, x.path = cfg.roots.utmp ++ "/" ++ n ∧ tmpNameOk n = true ∧ n ≠ "" ∧ x.path ≠ cfg.roots.utmp ∧
      utmpRootOk cfg.roots.utmp = true := by
  obtain ⟨-, -, hr, ss, hp, hs, -⟩ := deletes_subset_allowlist cfg xs x h
  rw [hc] at hp hs hr
  simp only [classRoot] at hp
  match ss, hs, hp with
  | [n], hs, hp =>
    simp only [shape, tmpNameOk] at hs
    have hne : n ≠ "" := by
      intro e; subst e; simp [LakeGc.nameOk] at hs
    have hp' : x.path = cfg.roots.utmp ++ "/" ++ n := by simpa using hp
    refine ⟨n, hp', by simpa [tmpNameOk] using hs, hne, ?_, by simpa [rootOk] using hr⟩
    intro e
    have : (cfg.roots.utmp ++ "/" ++ n).length = cfg.roots.utmp.length := by
      rw [← hp', e]
    have hlen : n.length ≠ 0 := fun z => hne (String.length_eq_zero_iff.1 z)
    simp [String.length_append] at this
    omega

/-- **The run's selection is the spec's.** -/
theorem selectFast_eq (cfg : Config) (xs : List Cand) : selectFast cfg xs = select cfg xs := by
  unfold selectFast select
  congr 1
  funext x
  unfold chosenIx chosen
  by_cases h : x.cls = .lake
  · simp only [h, ite_true, rule, ruleLake, ruleLakeIx]
    cases cfg.lake <;> cases x.lake <;> simp [LakeGc.okFast_eq]
  · simp [h]

end Fw.Ops.DiskGc

/-! ## Wire: `ops.diskGc`, `ops.diskGcPath` -/

namespace Fw.Wire.DiskGc
open Lean Fw.Ops.DiskGc Fw.Wire.Ops

/-- A class from JSON: its number (as a number or string) or its name. -/
def clsOf (j : Json) : Except String Cls :=
  let s := match j with
    | .str s => s
    | .num n => toString n
    | _ => ""
  match Cls.parse s with
  | some c => .ok c
  | none => .error s!"unknown class {j.compress}"

/-- The roots from JSON: `repo`, `lake`, `scratch`, `devices` required, `utmp` (empty: class 7 refused). -/
def rootsOf (j : Json) : Except String Roots := do
  pure ⟨← str j "repo", ← str j "lake", ← str j "scratch", ← str j "devices", ← strD j "utmp" ""⟩

/-- A worktree lock from JSON: absent (`unknown` for classes 2 and 3, else `free`), `"free"`, `{pid, start}`, or any
other value (`unknown`). -/
def lockOf (c : Cls) (j : Json) : Except String Lock :=
  match opt j "lock" with
  | none => pure (if c == .landed || c == .idle then .unknown else .free)
  | some (.str "free") => pure .free
  | some v@(.obj _) => do pure (.held (← nat v "pid") (← str v "start"))
  | some _ => pure .unknown

/-- An optional Boolean (absent or null: `none`). -/
def optBool (j : Json) (k : String) : Except String (Option Bool) :=
  match opt j k with
  | none => pure none
  | some v => some <$> asBool k v

/-- An optional non-negative integer: absent, null, negative or not a number is `none`. -/
def optNat (j : Json) (k : String) : Option Nat :=
  match opt j k with
  | some v => match v.getNat? with
    | .ok n => some n
    | .error _ => none
  | none => none

/-- One candidate from JSON: `cls`, `path`, `bytes`, `tracked`, `newest`, `dir` required, `uid`? (`none` when absent or
not a non-negative integer: the candidate is kept), `sym`?, `owner`? {task, run}; `lake`? (a
`ops.lakeGc` fact), `branch`?, `merged`?, `dirty`?, `lock`?, `device`? {name, state}. -/
def candOf (j : Json) : Except String Cand := do
  let c ← clsOf (← field j "cls")
  let lake ← match opt j "lake" with
    | none => pure none
    | some v => some <$> Fw.Wire.LakeGc.factOf v
  let device ← match opt j "device" with
    | none => pure none
    | some v => do pure (some (← str v "name", ← str v "state"))
  let owner ← match opt j "owner" with
    | none => pure none
    | some v => do pure (some (← str v "task", ← str v "run"))
  pure {
    cls := c, path := ← str j "path", bytes := ← nat j "bytes", uid := optNat j "uid",
    tracked := ← asBool "tracked" (← field j "tracked"), newest := ← nat j "newest",
    dir := ← asBool "dir" (← field j "dir"), sym := (← optBool j "sym").getD false, owner, lake, branch := ← strD j "branch" "", merged := ← optBool j "merged",
    dirty := ← optBool j "dirty", lock := ← lockOf c j, device }

/-- A process from JSON: `pid`, `start`. -/
def procOf (j : Json) : Except String Proc := do pure ⟨← nat j "pid", ← str j "start"⟩

/-- The `LakeGc` config of class 1 from the `lake` object: `ageFloor`?, `checkouts`?, `procs`?, `outputs`? as in
`ops.lakeGc`; its root is `roots.lake` and its now the run's. -/
def lakeOf (root : String) (now : Nat) (j : Json) : Except String Fw.Ops.LakeGc.Config := do
  pure ⟨root, now, ← natD j "ageFloor" Fw.Ops.LakeGc.defaultAgeFloor, Fw.Ops.LakeGc.budgetBytes,
    ← Fw.Wire.LakeGc.optList j "checkouts" Fw.Wire.LakeGc.checkoutOfJson,
    ← Fw.Wire.LakeGc.optList j "procs" Fw.Wire.LakeGc.procOf,
    ← Fw.Wire.LakeGc.optList j "outputs" (asStr "outputs")⟩

/-- The config from a request. -/
def configOf (req : Json) : Except String Config := do
  let roots ← rootsOf (← field req "roots")
  let now ← nat req "now"
  let lake ← match opt req "lake" with
    | none => pure none
    | some v => some <$> lakeOf roots.lake now v
  pure {
    roots, classes := ← (← arr req "classes").toList.mapM clsOf, uid := ← nat req "uid", now,
    idleH := ← natD req "idleH" defaultIdleH, scratchH := ← natD req "scratchH" defaultScratchH,
    keepDays := ← natD req "keepDays" defaultKeepDays, lake,
    opens := ← Fw.Wire.LakeGc.optList req "opens" (asStr "opens"),
    procs := ← Fw.Wire.LakeGc.optList req "procs" procOf,
    queued := ← Fw.Wire.LakeGc.optList req "queued" (asStr "queued"),
    cited := ← Fw.Wire.LakeGc.optList req "cited" (asStr "cited"),
    named := ← Fw.Wire.LakeGc.optList req "named" (asStr "named"), simLock := ← optBool req "simLock",
    tmpH := ← natD req "tmpH" defaultTmpH, pressure := (← optBool req "pressure").getD false,
    liveAgents := ← Fw.Wire.LakeGc.optList req "liveAgents" (asStr "liveAgents"),
    landedTasks := ← Fw.Wire.LakeGc.optList req "landedTasks" (asStr "landedTasks"),
    finishedRuns := ← Fw.Wire.LakeGc.optList req "finishedRuns" (asStr "finishedRuns") }

/-- `ops.diskGc`: `roots` {repo, lake, scratch, devices}, `classes` [number or name], `uid`, `now`, `idleH`?,
`scratchH`?, `keepDays`?, `tmpH`?, `pressure`?, `liveAgents`?, `landedTasks`?, `finishedRuns`?, `lake`? {ageFloor?, checkouts?, procs?, outputs?}, `opens`?, `procs`? [{pid, start}],
`queued`?, `cited`?, `named`?, `simLock`?, `cands` [candidate] → `items` [{cls, num, path, bytes}] (`select`, in input
order), `classes` [{cls, num, count, bytes}] (one per enabled class), `kept` (candidates not selected), `rootsOk`
[{cls, num, ok}], `lakeFallback` (`Fw.Ops.LakeGc.fallback` of class 1, or null). -/
def opDiskGc (req : Json) : Except String Reply := do
  let cfg ← configOf req
  let xs ← (← arr req "cands").toList.mapM candOf
  let l := selectFast cfg xs
  let enabled := Cls.all.filter (cfg.classes.contains ·)
  pure [("items", .arr (l.toArray.map fun x => Json.mkObj [("cls", .str x.cls.name), ("num", toJson x.cls.num),
      ("path", .str x.path), ("bytes", toJson x.bytes)])),
    ("classes", .arr (enabled.toArray.map fun c =>
      Json.mkObj [("cls", .str c.name), ("num", toJson c.num), ("count", toJson (tally l c).1),
        ("bytes", toJson (tally l c).2)])),
    ("kept", toJson (xs.length - l.length)),
    ("rootsOk", .arr (Cls.all.toArray.map fun c =>
      Json.mkObj [("cls", .str c.name), ("num", toJson c.num), ("ok", .bool (rootOk cfg.roots c))])),
    ("lakeFallback", match cfg.lake.bind Fw.Ops.LakeGc.fallback with
      | some r => .str (Fw.Wire.LakeGc.fallbackName r)
      | none => .null)]

/-- `ops.diskGcPath`: `roots`, `items` [{cls, path}] → `ok` [bool] (`pathOk` of each, in order): the recheck the glue
runs on each resolved path right before it deletes it. -/
def opDiskGcPath (req : Json) : Except String Reply := do
  let roots ← rootsOf (← field req "roots")
  let oks ← (← arr req "items").toList.mapM fun j => do
    pure (pathOk roots (← clsOf (← field j "cls")) (← str j "path"))
  pure [("ok", .arr (oks.toArray.map .bool))]

/-- The ops of this module. -/
def ops : List String := ["ops.diskGc", "ops.diskGcPath"]

/-- Dispatch (`none` when the op is not one of `ops`). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.diskGc" => some (opDiskGc req)
  | "ops.diskGcPath" => some (opDiskGcPath req)
  | _ => none

#guard ops.all fun o => (handle o (Json.mkObj [("roots", Json.mkObj [("repo", .str "/r"),
  ("lake", .str "/a/artifacts"), ("scratch", .str "/t/claude-1/p"), ("devices", .str "/d/CoreSimulator/Devices")]),
  ("classes", .arr #[]), ("uid", toJson 1), ("now", toJson 0), ("cands", .arr #[]), ("items", .arr #[])])).isSome

end Fw.Wire.DiskGc
