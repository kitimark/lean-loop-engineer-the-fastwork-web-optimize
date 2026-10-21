import Lean.Data.Json

/-! fw-sup client routing: `routeOf` sends a service to the daemon only when the daemon is present, the service's stage
is on and the daemon's binary hash matches; every other case keeps today's path. -/
namespace Fw.Sup.Route

/-- A migration stage of the daemon design (docs/team/daemon/design.md section 5). -/
inductive Stage where
  | s0 | s1a | s1b | s2 | s3 | s4
deriving DecidableEq, Repr

/-- The stage order. -/
def Stage.rank : Stage → Nat
  | .s0 => 0 | .s1a => 1 | .s1b => 2 | .s2 => 3 | .s3 => 4 | .s4 => 5

/-- The stage as the goldens spell it. -/
def Stage.name : Stage → String
  | .s0 => "0" | .s1a => "1a" | .s1b => "1b" | .s2 => "2" | .s3 => "3" | .s4 => "4"

def Stage.all : List Stage := [.s0, .s1a, .s1b, .s2, .s3, .s4]

/-- A client path that a stage moves behind the daemon. -/
inductive Service where
  | cliOp | ghBudgetOp | watchOp | guardOp
  | lakeSlot | heavyLock | simLock | runLease | lspIdle
  | ghPoller | watchCollect | landQueue | ciWait | consoleApi | hooks
  | testBudget | landPool
  | simPool | chromiumPool | previews
deriving DecidableEq, Repr

/-- The stage that moves the service. -/
def Service.stage : Service → Stage
  | .cliOp | .ghBudgetOp | .watchOp | .guardOp => .s1a
  | .lakeSlot | .heavyLock | .simLock | .runLease | .lspIdle => .s1b
  | .ghPoller | .watchCollect | .landQueue | .ciWait | .consoleApi | .hooks => .s2
  | .testBudget | .landPool => .s3
  | .simPool | .chromiumPool | .previews => .s4

/-- The service as the goldens spell it. -/
def Service.name : Service → String
  | .cliOp => "cliOp" | .ghBudgetOp => "ghBudgetOp" | .watchOp => "watchOp" | .guardOp => "guardOp"
  | .lakeSlot => "lakeSlot" | .heavyLock => "heavyLock" | .simLock => "simLock" | .runLease => "runLease"
  | .lspIdle => "lspIdle" | .ghPoller => "ghPoller" | .watchCollect => "watchCollect" | .landQueue => "landQueue"
  | .ciWait => "ciWait" | .consoleApi => "consoleApi" | .hooks => "hooks" | .testBudget => "testBudget"
  | .landPool => "landPool" | .simPool => "simPool" | .chromiumPool => "chromiumPool" | .previews => "previews"

def Service.all : List Service :=
  [.cliOp, .ghBudgetOp, .watchOp, .guardOp, .lakeSlot, .heavyLock, .simLock, .runLease, .lspIdle, .ghPoller,
    .watchCollect, .landQueue, .ciWait, .consoleApi, .hooks, .testBudget, .landPool, .simPool, .chromiumPool, .previews]

/-- Where a client sends its work. -/
inductive Route where
  | daemon | today
deriving DecidableEq, Repr

def Route.name : Route → String
  | .daemon => "daemon" | .today => "today"

/-- Whether the configured stage has reached the service's stage. -/
def on (st : Stage) (svc : Service) : Bool := svc.stage.rank ≤ st.rank

/-- The daemon when it is present, the service's stage is on and the binary hash matches; else today's path. -/
def routeOf (st : Stage) (svc : Service) (present hashOk : Bool) : Route :=
  if present && on st svc && hashOk then .daemon else .today

/-- The route of each listed service, each decided by `routeOf` alone. -/
def routeAll (st : Stage) (present hashOk : Bool) (svcs : List Service) : List (Service × Route) :=
  svcs.map fun svc => (svc, routeOf st svc present hashOk)

#guard Stage.all.map Stage.rank == [0, 1, 2, 3, 4, 5]
#guard on .s1a .cliOp && !on .s0 .cliOp && on .s4 .previews && !on .s3 .previews && on .s2 .lakeSlot
#guard (Service.all.filter (on .s1b)).length == 9
#guard routeOf .s1a .cliOp true true == .daemon
#guard routeOf .s1a .cliOp false true == .today
#guard routeOf .s1a .cliOp true false == .today
#guard routeOf .s1a .lakeSlot true true == .today
#guard routeOf .s4 .previews true true == .daemon
#guard Service.all.all fun s => routeOf .s0 s true true == .today
#guard routeAll .s1b true true [.cliOp, .hooks] == [(.cliOp, .daemon), (.hooks, .today)]
#guard routeAll .s4 false true [.cliOp, .hooks] == [(.cliOp, .today), (.hooks, .today)]
#guard routeAll .s4 true true [] == []

/-! ## Theorems -/

theorem routeOf_absent (st : Stage) (svc : Service) (hashOk : Bool) : routeOf st svc false hashOk = .today := by
  simp [routeOf]

theorem routeOf_off {st : Stage} {svc : Service} (h : on st svc = false) (present hashOk : Bool) :
    routeOf st svc present hashOk = .today := by
  simp [routeOf, h]

theorem routeOf_hash (st : Stage) (svc : Service) (present : Bool) : routeOf st svc present false = .today := by
  simp [routeOf]

theorem routeOf_daemon {st : Stage} {svc : Service} (h : on st svc = true) : routeOf st svc true true = .daemon := by
  simp [routeOf, h]

theorem routeOf_daemon_iff (st : Stage) (svc : Service) (present hashOk : Bool) :
    routeOf st svc present hashOk = .daemon ↔ present = true ∧ on st svc = true ∧ hashOk = true := by
  cases present <;> cases hashOk <;> cases h : on st svc <;> simp [routeOf, h]

theorem routeOf_today_iff (st : Stage) (svc : Service) (present hashOk : Bool) :
    routeOf st svc present hashOk = .today ↔ present = false ∨ on st svc = false ∨ hashOk = false := by
  cases present <;> cases hashOk <;> cases h : on st svc <;> simp [routeOf, h]

theorem routeOf_total (st : Stage) (svc : Service) (present hashOk : Bool) :
    routeOf st svc present hashOk = .daemon ∨ routeOf st svc present hashOk = .today := by
  unfold routeOf; split <;> simp

theorem stage_moves (svc : Service) : 0 < svc.stage.rank := by
  cases svc <;> decide

theorem routeOf_s0 (svc : Service) (present hashOk : Bool) : routeOf .s0 svc present hashOk = .today :=
  routeOf_off (by cases svc <;> decide) present hashOk

theorem routeOf_mono {st st' : Stage} (hle : st.rank ≤ st'.rank) {svc : Service} {present hashOk : Bool}
    (h : routeOf st svc present hashOk = .daemon) : routeOf st' svc present hashOk = .daemon := by
  rw [routeOf_daemon_iff] at h ⊢
  refine ⟨h.1, ?_, h.2.2⟩
  have := h.2.1
  simp only [on, decide_eq_true_eq] at this ⊢
  omega

theorem routeAll_lookup (st : Stage) (present hashOk : Bool) {svcs : List Service} {svc : Service} (h : svc ∈ svcs) :
    (routeAll st present hashOk svcs).lookup svc = some (routeOf st svc present hashOk) := by
  induction svcs with
  | nil => cases h
  | cons a t ih =>
    by_cases ha : svc = a
    · subst ha; simp [routeAll]
    · have ht : svc ∈ t := by simpa [ha] using h
      have hne : (svc == a) = false := by simpa using ha
      simpa [routeAll, List.lookup, hne] using ih ht

theorem routeAll_own (st : Stage) (present hashOk : Bool) {l l' : List Service} {svc : Service} (h : svc ∈ l)
    (h' : svc ∈ l') : (routeAll st present hashOk l).lookup svc = (routeAll st present hashOk l').lookup svc := by
  rw [routeAll_lookup st present hashOk h, routeAll_lookup st present hashOk h']

theorem Stage.all_complete (st : Stage) : st ∈ Stage.all := by
  cases st <;> decide

theorem Service.all_complete (svc : Service) : svc ∈ Service.all := by
  cases svc <;> decide

/-! ## Goldens -/

open Lean (Json)

def bools : List Bool := [false, true]

set_option compiler.extract_closed false in
/-- One golden line per (stage, service, present, hashOk): the whole input domain. -/
def goldenLines (_ : Unit := ()) : List String :=
  Stage.all.flatMap fun st => Service.all.flatMap fun svc => bools.flatMap fun present => bools.map fun hashOk =>
    (Json.mkObj [("name", .str s!"{st.name} {svc.name} present={present} hashOk={hashOk}"),
      ("request", Json.mkObj [("op", "sup.route"), ("stage", .str st.name), ("service", .str svc.name),
        ("present", .bool present), ("hashOk", .bool hashOk)]),
      ("response", Json.mkObj [("route", .str (routeOf st svc present hashOk).name),
        ("serviceStage", .str svc.stage.name)])]).compress

#guard (goldenLines ()).length == 6 * 20 * 4

def genPath : System.FilePath := "../packages/contracts/golden/sup/route.jsonl"

set_option compiler.extract_closed false in
def genText (_ : Unit := ()) : String := String.join ((goldenLines ()).map (· ++ "\n"))

/-- Write `genPath`, or with `--check` throw when the file differs from `genText`. -/
def gen (args : List String) : IO Unit := do
  if args.contains "--check" then
    let cur ← IO.FS.readFile genPath
    if cur != genText () then
      throw (IO.userError s!"sup-route: {genPath} is stale; regenerate with Fw.Sup.Route.gen []")
    IO.println s!"sup-route: {genPath} equals the Lean output"
  else
    IO.FS.createDirAll "../packages/contracts/golden/sup"
    IO.FS.writeFile genPath (genText ())

end Fw.Sup.Route
