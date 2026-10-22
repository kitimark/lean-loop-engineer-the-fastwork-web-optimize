import Lean.Data.Json
import Fw.Ops.LakeGc
import Fw.Ops.Wire

namespace Fw.Ops.DiskGc

inductive Cls where
  | lake
  | landed
  | idle
  | scratch
  | sim
  | console
  | usertmp
deriving Repr, DecidableEq

def Cls.num : Cls → Nat
  | .lake => 1
  | .landed => 2
  | .idle => 3
  | .scratch => 4
  | .sim => 5
  | .console => 6
  | .usertmp => 7

def Cls.name : Cls → String
  | .lake => "lake"
  | .landed => "landed"
  | .idle => "idle"
  | .scratch => "scratch"
  | .sim => "sim"
  | .console => "console"
  | .usertmp => "usertmp"

def Cls.all : List Cls := [.lake, .landed, .idle, .scratch, .sim, .console, .usertmp]

def Cls.parse (s : String) : Option Cls := Cls.all.find? fun c => toString c.num == s || c.name == s

inductive Lock where
  | free
  | held (pid : Nat) (start : String)
  | unknown
deriving Repr, DecidableEq

structure Proc where
  pid : Nat
  start : String
deriving Repr, DecidableEq

structure Roots where
  repo : String
  lake : String
  scratch : String
  devices : String
  utmp : String := ""
deriving Repr

structure Cand where
  cls : Cls
  path : String
  bytes : Nat
  uid : Option Nat
  tracked : Bool
  newest : Nat
  dir : Bool
  sym : Bool := false
  owner : Option (String × String) := none
  lake : Option LakeGc.Fact := none
  branch : String := ""
  merged : Option Bool := none
  dirty : Option Bool := none
  lock : Lock := .free
  device : Option (String × String) := none
deriving Repr

def defaultTmpH : Nat := 2

structure Config where
  roots : Roots
  classes : List Cls
  uid : Nat
  now : Nat
  idleH : Nat
  scratchH : Nat
  keepDays : Nat
  lake : Option LakeGc.Config
  opens : Option (List String)
  procs : Option (List Proc)
  queued : Option (List String)
  cited : Option (List String)
  named : Option (List String)
  simLock : Option Bool
  tmpH : Nat := defaultTmpH
  pressure : Bool := false
  liveAgents : Option (List String) := none
  landedTasks : Option (List String) := none
  finishedRuns : Option (List String) := none
deriving Repr

def defaultIdleH : Nat := 24

def defaultScratchH : Nat := 8

def defaultKeepDays : Nat := 7

def pressureScratchH : Nat := 2

def ownerFloorS : Nat := 3600

def rootSegs (r : String) : List String := (r.splitOn "/").drop 1

def absOk (r : String) : Bool :=
  r.startsWith "/" && r.all LakeGc.rootChar &&
    (rootSegs r).all fun s => s != "" && s != "." && s != ".." && s != ".local"

def wtRoot (r : Roots) : String := r.repo ++ "/.claude/worktrees"

def consoleRoot (r : Roots) : String := r.repo ++ "/.fw-console"

def classRoot (r : Roots) : Cls → String
  | .lake => r.lake
  | .landed | .idle => wtRoot r
  | .scratch => r.scratch
  | .sim => r.devices
  | .console => consoleRoot r
  | .usertmp => r.utmp

def scratchRootOk (s : String) : Bool :=
  absOk s && match (rootSegs s).reverse with
    | _ :: p :: _ => p.startsWith "claude-"
    | _ => false

def utmpRootOk (s : String) : Bool :=
  absOk s && match (rootSegs s).reverse with
    | "T" :: _ :: _ :: "folders" :: _ => true
    | _ => false

def rootOk (r : Roots) : Cls → Bool
  | .lake => LakeGc.rootOk r.lake && absOk r.lake
  | .landed | .idle | .console => absOk r.repo
  | .scratch => scratchRootOk r.scratch
  | .sim => absOk r.devices && r.devices.endsWith "/CoreSimulator/Devices"
  | .usertmp => utmpRootOk r.utmp

def hexChar (x : Char) : Bool := x.isDigit || ('A' ≤ x && x ≤ 'F') || ('a' ≤ x && x ≤ 'f')

def udidOk (u : String) : Bool :=
  (u.splitOn "-").map String.length == [8, 4, 4, 4, 12] && (u.splitOn "-").all (·.all hexChar)

def tmpPrefixes : List String := ["fw", "oracle", "ghb", "engine-check", "premises", "land-base", "lint", "var"]

def tmpNameOk (n : String) : Bool :=
  LakeGc.nameOk n && (tmpPrefixes.any (fun p => n.startsWith p) || (n.startsWith "instruments" && n.endsWith ".ktrace"))

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

def segsOf (root p : String) : Option (List String) :=
  if p.startsWith (root ++ "/") then some ((p.drop (root.length + 1)).toString.splitOn "/") else none

def underOk (root p : String) (c : Cls) : Bool :=
  match segsOf root p with
  | none => false
  | some ss => p == root ++ "/" ++ "/".intercalate ss && shape c ss && !ss.contains ".local"

def pathOk (r : Roots) (c : Cls) (p : String) : Bool := rootOk r c && underOk (classRoot r c) p c

def under (d p : String) : Bool := p == d || p.startsWith (d ++ "/")

def openIn (cfg : Config) (x : Cand) : Bool :=
  match cfg.opens with
  | none => true
  | some os => os.any (under x.path)

def words (s : String) : List String := (s.splitOn " ").filter (· != "")

def lockLive (cfg : Config) : Lock → Bool
  | .free => false
  | .unknown => true
  | .held pid st =>
    match cfg.procs with
    | none => true
    | some ps => ps.any fun p => p.pid == pid && words p.start == words st

def queuedB (cfg : Config) (b : String) : Bool :=
  match cfg.queued with
  | none => true
  | some q => q.contains b

def live (cfg : Config) (x : Cand) : Bool :=
  openIn cfg x || lockLive cfg x.lock || (x.branch != "" && queuedB cfg x.branch)

def olderThan (cfg : Config) (x : Cand) (s : Nat) : Bool := decide (x.newest + s ≤ cfg.now)

def lastSeg (p : String) : String := ((p.splitOn "/").getLast?).getD p

def cited (cfg : Config) (x : Cand) : Bool :=
  match cfg.cited with
  | none => true
  | some l => l.contains ("scratchpad/" ++ lastSeg x.path)

def named (cfg : Config) (n : String) : Bool :=
  match cfg.named with
  | none => true
  | some l => l.contains n

def ruleLake (cfg : Config) (x : Cand) : Bool :=
  match cfg.lake, x.lake with
  | some lc, some f => lc.root == cfg.roots.lake && x.path == LakeGc.pathOf lc.root f.name && LakeGc.ok lc f
  | _, _ => false

def ruleLanded (x : Cand) : Bool := x.dir && x.branch != "" && x.merged == some true && x.dirty == some false

def ruleIdle (cfg : Config) (x : Cand) : Bool :=
  x.dir && x.branch != "" && x.merged == some false && olderThan cfg x (cfg.idleH * 3600)

def agentLive (cfg : Config) (x : Cand) : Bool :=
  match cfg.liveAgents with
  | none => true
  | some l => l.contains (lastSeg x.path)

def scratchAge (cfg : Config) (x : Cand) : Bool := olderThan cfg x (cfg.scratchH * 3600)

def scratchPressure (cfg : Config) (x : Cand) : Bool :=
  cfg.pressure && !agentLive cfg x && olderThan cfg x (pressureScratchH * 3600)

def scratchOwner (cfg : Config) (x : Cand) : Bool :=
  match x.owner, cfg.landedTasks, cfg.finishedRuns with
  | some (t, r), some lt, some fr => lt.contains t && fr.contains r && olderThan cfg x ownerFloorS
  | _, _, _ => false

def ruleScratch (cfg : Config) (x : Cand) : Bool :=
  x.dir && !cited cfg x && (scratchAge cfg x || scratchPressure cfg x || scratchOwner cfg x)

def ruleSim (cfg : Config) (x : Cand) : Bool :=
  match x.device with
  | some (n, st) => n.startsWith "fw-" && st == "Shutdown" && !named cfg n && cfg.simLock == some false
  | none => false

def ruleConsole (cfg : Config) (x : Cand) : Bool := !x.sym && olderThan cfg x (cfg.keepDays * 86400)

def ruleUsertmp (cfg : Config) (x : Cand) : Bool := !x.sym && olderThan cfg x (cfg.tmpH * 3600)

def rule (cfg : Config) (x : Cand) : Bool :=
  match x.cls with
  | .lake => ruleLake cfg x
  | .landed => ruleLanded x
  | .idle => ruleIdle cfg x
  | .scratch => ruleScratch cfg x
  | .sim => ruleSim cfg x
  | .console => ruleConsole cfg x
  | .usertmp => ruleUsertmp cfg x

def guard (cfg : Config) (x : Cand) : Bool :=
  pathOk cfg.roots x.cls x.path && x.uid == some cfg.uid && !x.tracked && !live cfg x

def chosen (cfg : Config) (x : Cand) : Bool := cfg.classes.contains x.cls && guard cfg x && rule cfg x

def select (cfg : Config) (xs : List Cand) : List Cand := xs.filter (chosen cfg)

def tally (l : List Cand) (c : Cls) : Nat × Nat :=
  let m := l.filter (·.cls == c)
  (m.length, (m.map (·.bytes)).sum)

def ruleLakeIx (cfg : Config) (ix : Option LakeGc.Index) (x : Cand) : Bool :=
  match cfg.lake, ix, x.lake with
  | some lc, some i, some f => lc.root == cfg.roots.lake && x.path == LakeGc.pathOf lc.root f.name && LakeGc.okFast lc i f
  | _, _, _ => false

def chosenIx (cfg : Config) (ix : Option LakeGc.Index) (x : Cand) : Bool :=
  cfg.classes.contains x.cls && guard cfg x && (if x.cls = .lake then ruleLakeIx cfg ix x else rule cfg x)

def selectFast (cfg : Config) (xs : List Cand) : List Cand := xs.filter (chosenIx cfg (cfg.lake.map LakeGc.Index.of))

def exRoots : Roots :=
  ⟨"/u/r", "/u/.elan/c/artifacts", "/private/tmp/claude-1/-u-r", "/u/Library/Developer/CoreSimulator/Devices",
    "/private/var/folders/ab/cd/T"⟩

def exCfg : Config :=
  { roots := exRoots, classes := Cls.all, uid := 1, now := 1000000, idleH := 24, scratchH := 8, keepDays := 7,
    lake := some ⟨exRoots.lake, 1000000, 7200, 0, some [], some [], some []⟩, opens := some [], procs := some [],
    queued := some [], cited := some [], named := some ["fw-iphone-27"], simLock := some false }

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
def exWt (c : Cls) (rel : String) (merged : Bool) (k : Lock) : Cand :=
  { cls := c, path := s!"/u/r/.claude/worktrees/{rel}", bytes := 1, uid := some 1, tracked := false, newest := 0,
    dir := true, branch := "b", merged := some merged, dirty := some false, lock := k }

def exSim (n : String) : Cand :=
  { cls := .sim, path := "/u/Library/Developer/CoreSimulator/Devices/0a1b2c3d-0000-1111-2222-333344445555",
    bytes := 1, uid := some 1, tracked := false, newest := 0, dir := true, device := some (n, "Shutdown") }

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

def exOwned (d : String) (newest : Nat) : Cand := { exScratch d newest with owner := some ("t1", "r1") }

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

theorem chosen_iff (cfg : Config) (x : Cand) :
    chosen cfg x = true ↔ x.cls ∈ cfg.classes ∧ guard cfg x = true ∧ rule cfg x = true := by
  simp [chosen, and_assoc]

theorem mem_select (cfg : Config) (xs : List Cand) (x : Cand) : x ∈ select cfg xs ↔ x ∈ xs ∧ chosen cfg x = true := by
  simp [select]

theorem guard_iff (cfg : Config) (x : Cand) : guard cfg x = true ↔
    pathOk cfg.roots x.cls x.path = true ∧ x.uid = some cfg.uid ∧ x.tracked = false ∧ live cfg x = false := by
  simp [guard, and_assoc]

theorem selected_enabled (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : x.cls ∈ cfg.classes :=
  ((chosen_iff cfg x).1 ((mem_select cfg xs x).1 h).2).1

theorem selected_guard (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : guard cfg x = true :=
  ((chosen_iff cfg x).1 ((mem_select cfg xs x).1 h).2).2.1

theorem selected_rule (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : rule cfg x = true :=
  ((chosen_iff cfg x).1 ((mem_select cfg xs x).1 h).2).2.2

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

theorem never_tracked (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : x.tracked = false :=
  ((guard_iff cfg x).1 (selected_guard cfg xs x h)).2.2.1

theorem owned_only (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : x.uid = some cfg.uid :=
  ((guard_iff cfg x).1 (selected_guard cfg xs x h)).2.1

theorem unknown_owner_kept (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) : x.uid ≠ none := by
  rw [owned_only cfg xs x h]; simp

theorem never_live (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) :
    openIn cfg x = false ∧ lockLive cfg x.lock = false ∧ (x.branch = "" ∨ queuedB cfg x.branch = false) := by
  have hl := ((guard_iff cfg x).1 (selected_guard cfg xs x h)).2.2.2
  simp only [live, Bool.or_eq_false_iff, Bool.and_eq_false_iff, bne_eq_false_iff_eq] at hl
  exact ⟨hl.1.1, hl.1.2, hl.2⟩

theorem never_open (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) :
    ∃ os, cfg.opens = some os ∧ ∀ o ∈ os, under x.path o = false := by
  have ho := (never_live cfg xs x h).1
  unfold openIn at ho
  cases hc : cfg.opens with
  | none => rw [hc] at ho; exact absurd ho (by simp)
  | some os =>
    rw [hc] at ho
    exact ⟨os, rfl, fun o hm => by simpa using List.any_eq_false.1 ho o hm⟩

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

theorem never_queued (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hb : x.branch ≠ "") :
    ∃ q, cfg.queued = some q ∧ x.branch ∉ q := by
  rcases (never_live cfg xs x h).2.2 with he | hq
  · exact absurd he hb
  · unfold queuedB at hq
    cases hc : cfg.queued with
    | none => rw [hc] at hq; exact absurd hq (by simp)
    | some q => rw [hc] at hq; exact ⟨q, rfl, by simpa using hq⟩

theorem independent (cfg : Config) (xs ys : List Cand) (x : Cand) (hx : x ∈ xs) (hy : x ∈ ys) :
    x ∈ select cfg xs ↔ x ∈ select cfg ys := by
  simp [mem_select, hx, hy]

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

theorem rule_landed (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .landed) :
    x.dir = true ∧ x.branch ≠ "" ∧ x.merged = some true ∧ x.dirty = some false := by
  have hr := selected_rule cfg xs x h
  simpa [rule, hc, ruleLanded, and_assoc] using hr

theorem rule_idle (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .idle) :
    x.dir = true ∧ x.branch ≠ "" ∧ x.merged = some false ∧ x.newest + cfg.idleH * 3600 ≤ cfg.now := by
  have hr := selected_rule cfg xs x h
  simpa [rule, hc, ruleIdle, olderThan, and_assoc] using hr

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

theorem scratchAge_spec (cfg : Config) (x : Cand) (h : scratchAge cfg x = true) :
    x.newest + cfg.scratchH * 3600 ≤ cfg.now := by
  simpa [scratchAge, olderThan] using h

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

theorem scratchOwner_spec (cfg : Config) (x : Cand) (h : scratchOwner cfg x = true) :
    ∃ t r lt fr, x.owner = some (t, r) ∧ cfg.landedTasks = some lt ∧ cfg.finishedRuns = some fr ∧ t ∈ lt ∧ r ∈ fr ∧
      x.newest + ownerFloorS ≤ cfg.now := by
  unfold scratchOwner at h
  split at h
  · rename_i t r lt fr hx hl hf
    simp only [Bool.and_eq_true, olderThan, decide_eq_true_eq, List.contains_iff_mem] at h
    exact ⟨t, r, lt, fr, hx, hl, hf, h.1.1, h.1.2, h.2⟩
  · exact absurd h (by simp)

theorem no_pressure_no_branch (cfg : Config) (x : Cand) (h : cfg.pressure = false) : scratchPressure cfg x = false := by
  simp [scratchPressure, h]

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

theorem rule_console (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .console) :
    x.sym = false ∧ x.newest + cfg.keepDays * 86400 ≤ cfg.now := by
  have hr := selected_rule cfg xs x h
  simpa [rule, hc, ruleConsole, olderThan] using hr

theorem rule_usertmp (cfg : Config) (xs : List Cand) (x : Cand) (h : x ∈ select cfg xs) (hc : x.cls = .usertmp) :
    x.sym = false ∧ x.newest + cfg.tmpH * 3600 ≤ cfg.now := by
  have hr := selected_rule cfg xs x h
  simpa [rule, hc, ruleUsertmp, olderThan] using hr

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

namespace Fw.Wire.DiskGc
open Lean Fw.Ops.DiskGc Fw.Wire.Ops

def clsOf (j : Json) : Except String Cls :=
  let s := match j with
    | .str s => s
    | .num n => toString n
    | _ => ""
  match Cls.parse s with
  | some c => .ok c
  | none => .error s!"unknown class {j.compress}"

def rootsOf (j : Json) : Except String Roots := do
  pure ⟨← str j "repo", ← str j "lake", ← str j "scratch", ← str j "devices", ← strD j "utmp" ""⟩

def lockOf (c : Cls) (j : Json) : Except String Lock :=
  match opt j "lock" with
  | none => pure (if c == .landed || c == .idle then .unknown else .free)
  | some (.str "free") => pure .free
  | some v@(.obj _) => do pure (.held (← nat v "pid") (← str v "start"))
  | some _ => pure .unknown

def optBool (j : Json) (k : String) : Except String (Option Bool) :=
  match opt j k with
  | none => pure none
  | some v => some <$> asBool k v

def optNat (j : Json) (k : String) : Option Nat :=
  match opt j k with
  | some v => match v.getNat? with
    | .ok n => some n
    | .error _ => none
  | none => none

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

def procOf (j : Json) : Except String Proc := do pure ⟨← nat j "pid", ← str j "start"⟩

def lakeOf (root : String) (now : Nat) (j : Json) : Except String Fw.Ops.LakeGc.Config := do
  pure ⟨root, now, ← natD j "ageFloor" Fw.Ops.LakeGc.defaultAgeFloor, Fw.Ops.LakeGc.budgetBytes,
    ← Fw.Wire.LakeGc.optList j "checkouts" Fw.Wire.LakeGc.checkoutOfJson,
    ← Fw.Wire.LakeGc.optList j "procs" Fw.Wire.LakeGc.procOf,
    ← Fw.Wire.LakeGc.optList j "outputs" (asStr "outputs")⟩

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

def opDiskGcPath (req : Json) : Except String Reply := do
  let roots ← rootsOf (← field req "roots")
  let oks ← (← arr req "items").toList.mapM fun j => do
    pure (pathOk roots (← clsOf (← field j "cls")) (← str j "path"))
  pure [("ok", .arr (oks.toArray.map .bool))]

def ops : List String := ["ops.diskGc", "ops.diskGcPath"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.diskGc" => some (opDiskGc req)
  | "ops.diskGcPath" => some (opDiskGcPath req)
  | _ => none

#guard ops.all fun o => (handle o (Json.mkObj [("roots", Json.mkObj [("repo", .str "/r"),
  ("lake", .str "/a/artifacts"), ("scratch", .str "/t/claude-1/p"), ("devices", .str "/d/CoreSimulator/Devices")]),
  ("classes", .arr #[]), ("uid", toJson 1), ("now", toJson 0), ("cands", .arr #[]), ("items", .arr #[])])).isSome

end Fw.Wire.DiskGc
