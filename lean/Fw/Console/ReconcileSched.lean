import Lean.Data.Json
/-!
# Reconcile requests: one running pass, at most one pending

Each request is answered by the next pass that starts after it. Golden: `golden/console/reconcile-sched.jsonl`.
-/
namespace Fw.Console.ReconcileSched

/-- The scheduler state: passes started, passes finished, requests waiting for the next pass (kept at most one). -/
structure S where
  started : Nat
  finished : Nat
  pending : Nat
deriving DecidableEq, Repr

/-- The empty scheduler. -/
def init : S := ⟨0, 0, 0⟩

/-- A request: idle starts a pass now; a running pass leaves one pending request, however many arrive. -/
def req (s : S) : S :=
  if s.finished < s.started then { s with pending := min 1 (s.pending + 1) }
  else { s with started := s.started + 1 }

/-- The running pass finishes: a pending request starts the next pass; with no pass running nothing happens. -/
def fin (s : S) : S :=
  if s.finished < s.started then
    if s.pending = 0 then { s with finished := s.finished + 1 }
    else ⟨s.started + 1, s.finished + 1, 0⟩
  else s

/-- The index of the pass that answers a request made in state `s`: the first pass not yet started. -/
def ticket (s : S) : Nat := s.started

/-- Reachable-state invariant. -/
def Inv (s : S) : Prop :=
  s.finished ≤ s.started ∧ s.started ≤ s.finished + 1 ∧ s.pending ≤ 1 ∧ (s.pending = 1 → s.started = s.finished + 1)

/-- The empty scheduler satisfies the invariant. -/
theorem inv_init : Inv init := by simp [Inv, init]

/-- A request keeps the invariant. -/
theorem inv_req (s : S) (h : Inv s) : Inv (req s) := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  unfold req Inv
  split <;> simp_all <;> omega

/-- A finish keeps the invariant. -/
theorem inv_fin (s : S) (h : Inv s) : Inv (fin s) := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  unfold fin Inv
  by_cases hb : s.finished < s.started
  · by_cases hp : s.pending = 0 <;> simp [hb, hp] <;> omega
  · simp [hb]; omega

/-- **Pending is at most one**, after any request. -/
theorem pending_le_one_req (s : S) (h : Inv s) : (req s).pending ≤ 1 := (inv_req s h).2.2.1

/-- **Pending is at most one**, after any finish. -/
theorem pending_le_one_fin (s : S) (h : Inv s) : (fin s).pending ≤ 1 := (inv_fin s h).2.2.1

/-- At most one pass runs. -/
theorem one_running (s : S) (h : Inv s) : s.started - s.finished ≤ 1 := by
  obtain ⟨h1, h2, _, _⟩ := h; omega

/-- **Idle request**: the answering pass starts at the request itself. -/
theorem req_idle_starts (s : S) (h : s.finished = s.started) : ticket s < (req s).started := by
  unfold req ticket; simp [h]

/-- **Busy request**: the answering pass has not started when the request arrives, and one request is pending for it. -/
theorem req_busy_waits (s : S) (h : s.finished < s.started) :
    (req s).started = ticket s ∧ (req s).pending = 1 := by
  unfold req ticket; simp [h]

/-- **Busy request, already pending**: the new request joins the pending one and has the same ticket. -/
theorem req_coalesces (s : S) (h : s.finished < s.started) (hp : s.pending = 1) : req s = s := by
  obtain ⟨a, b, c⟩ := s
  simp_all [req]

/-- A pass finishing with a request pending starts the answering pass, whose index is the ticket. -/
theorem fin_starts_pending (s : S) (h : s.finished < s.started) (hp : s.pending ≠ 0) :
    ticket s < (fin s).started := by
  unfold fin ticket; simp [h, hp]

/-- **Every request is answered by a pass that starts after it**, busy case: the next finish starts the request's pass. -/
theorem answered_after_busy (s : S) (hb : s.finished < s.started) :
    ticket s < (fin (req s)).started := by
  have hw := req_busy_waits s hb
  have hr : (req s).finished < (req s).started := by
    unfold req; simp [hb]
  have hp : (req s).pending ≠ 0 := by omega
  have := fin_starts_pending (req s) hr hp
  unfold ticket at *
  omega

/-- **Idle case of the same**: the pass starts at the request. -/
theorem answered_after_idle (s : S) (h : s.finished = s.started) : ticket s < (req s).started :=
  req_idle_starts s h

/-- **No request waits for more than two passes**: after a request, two finishes leave its pass finished. -/
theorem wait_le_two (s : S) (h : Inv s) : ticket s < (fin (fin (req s))).finished := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  unfold ticket
  by_cases hb : s.finished < s.started
  · have e : s.started = s.finished + 1 := by omega
    have e1 : req s = ⟨s.started, s.finished, 1⟩ := by simp [req, hb]
    rw [e1]
    simp [fin, e]
  · have e : s.finished = s.started := by omega
    have e1 : req s = ⟨s.started + 1, s.finished, s.pending⟩ := by simp [req, hb]
    rw [e1]
    by_cases hp : s.pending = 0 <;> simp [fin, e, hp] <;> omega

/-- A request waits for one pass when none is running: one finish leaves its pass finished. -/
theorem wait_le_one_idle (s : S) (h : s.finished = s.started) : ticket s < (fin (req s)).finished := by
  unfold req fin ticket
  by_cases hp : s.pending = 0 <;> simp [h, hp]

open Lean

/-- Event of a golden case. -/
inductive Ev where | request | finish
deriving DecidableEq

/-- The event applied. -/
def Ev.apply (s : S) : Ev → S | .request => req s | .finish => fin s

/-- A sequence of events applied in order. -/
def run (s : S) : List Ev → S
  | [] => s
  | e :: r => run (Ev.apply s e) r

/-- Passes started never decrease: a request or finish only raises `started`. -/
theorem started_mono_apply (s : S) (e : Ev) : s.started ≤ (Ev.apply s e).started := by
  cases e <;> simp only [Ev.apply, req, fin] <;> split <;> (try split) <;> simp <;> omega

/-- Passes started never decrease along any event sequence. -/
theorem started_mono_run (s : S) (es : List Ev) : s.started ≤ (run s es).started := by
  induction es generalizing s with
  | nil => simp [run]
  | cons e r ih => exact Nat.le_trans (started_mono_apply s e) (ih _)

/-- The invariant holds along any event sequence. -/
theorem inv_run (s : S) (h : Inv s) (es : List Ev) : Inv (run s es) := by
  induction es generalizing s with
  | nil => simpa [run] using h
  | cons e r ih =>
    apply ih
    cases e
    · exact inv_req s h
    · exact inv_fin s h

/-- The first safety tick strictly after time `t`, for ticks at the multiples of `p`. -/
def nextTick (p t : Nat) : Nat := (t / p + 1) * p

/-- A tick is strictly after the event it covers. -/
theorem nextTick_gt (p t : Nat) (hp : 0 < p) : t < nextTick p t := by
  unfold nextTick
  have h := Nat.div_add_mod t p
  have h2 := Nat.mod_lt t hp
  rw [Nat.add_mul, Nat.one_mul]
  have : p * (t / p) = (t / p) * p := Nat.mul_comm _ _
  omega

/-- A tick is at most one safety period after the event: the lag of a dropped event is bounded by `p`. -/
theorem nextTick_le (p t : Nat) (hp : 0 < p) : nextTick p t ≤ t + p := by
  unfold nextTick
  have h := Nat.div_add_mod t p
  have h2 := Nat.mod_lt t hp
  rw [Nat.add_mul, Nat.one_mul]
  have : p * (t / p) = (t / p) * p := Nat.mul_comm _ _
  omega

/-- **A dropped event is drained by a pass that starts after it.** The event arrived while the state was `s`; the events
that followed (`es`) are anything, requests and finishes in any order. The safety tick's request is answered by the pass
whose index is at least the number of passes started when the event arrived, so that pass starts after the event. -/
theorem tick_pass_after_event (s : S) (es : List Ev) : ticket s ≤ ticket (run s es) := by
  unfold ticket; exact started_mono_run s es

/-- **A dropped event is drained within one safety period plus two passes.** The tick is at most `p` after the event, and
the pass answering the tick finishes after at most two finishes (`wait_le_two`), with the answering pass starting after
the event (`tick_pass_after_event`). -/
theorem dropped_event_drained (p t : Nat) (hp : 0 < p) (s : S) (hs : Inv s) (es : List Ev) :
    t < nextTick p t ∧ nextTick p t ≤ t + p ∧ ticket s ≤ ticket (run s es) ∧
    ticket (run s es) < (fin (fin (req (run s es)))).finished :=
  ⟨nextTick_gt p t hp, nextTick_le p t hp, tick_pass_after_event s es, wait_le_two _ (inv_run s hs es)⟩

/-- The scheduler with a clock: the state `s` and the start time `since` of the pass running now (read only while one runs). -/
structure T where
  s : S
  since : Nat

/-- A request at time `r`; a pass it starts begins at `r`. -/
def reqT (x : T) (r : Nat) : T := ⟨req x.s, if x.s.finished < x.s.started then x.since else r⟩

/-- A finish at time `e`; the pending pass it starts begins at `e`. -/
def finT (x : T) (e : Nat) : T :=
  ⟨fin x.s, if x.s.finished < x.s.started ∧ x.s.pending ≠ 0 then e else x.since⟩

/-- The state after a request at `r` has been answered: an idle scheduler started the pass at `r`; a busy one holds the
request until the running pass finishes at `e`, which starts it (unfolds `req` and `fin`). One request per call: requests
coalesced into `pending` meanwhile are not modelled. -/
def answered (x : T) (r e : Nat) : T :=
  if x.s.finished < x.s.started then finT (reqT x r) e else reqT x r

/-- **Idle request**: its pass is the one started, and it starts at the request. -/
theorem answer_idle (x : T) (r e : Nat) (h : x.s.finished = x.s.started) :
    ticket x.s + 1 = (answered x r e).s.started ∧ (answered x r e).since = r := by
  have hb : ¬ x.s.finished < x.s.started := by omega
  unfold answered reqT ticket req
  simp [hb]

/-- **Busy request**: the running pass finishes at `e` and starts the request's pass then. -/
theorem answer_busy (x : T) (r e : Nat) (h : Inv x.s) (hb : x.s.finished < x.s.started) :
    ticket x.s + 1 = (answered x r e).s.started ∧ (answered x r e).since = e := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  unfold answered finT reqT ticket req fin
  simp [hb]

/-- **A request is answered within one pass length.** Assume only that the pass running at the request `r` began no later and
ends at `e ≤ since + pass`. Then the pass numbered `ticket` (the first not yet started) is the last one started, and it begins
between `r` and `r + pass`. -/
theorem answer_start_le (x : T) (r e pass : Nat) (h : Inv x.s) (hs : x.since ≤ r)
    (he : x.s.finished < x.s.started → r ≤ e ∧ e ≤ x.since + pass) :
    ticket x.s + 1 = (answered x r e).s.started ∧ r ≤ (answered x r e).since ∧ (answered x r e).since ≤ r + pass := by
  by_cases hb : x.s.finished < x.s.started
  · obtain ⟨hr, hp⟩ := he hb
    obtain ⟨a, b⟩ := answer_busy x r e h hb
    exact ⟨a, by omega, by omega⟩
  · have hi : x.s.finished = x.s.started := by obtain ⟨h1, _⟩ := h; omega
    obtain ⟨a, b⟩ := answer_idle x r e hi
    exact ⟨a, by omega, by omega⟩

/-- The start bound of a woken pass: the settle window (or the safety period) plus the length of the pass running then. -/
def wakeStartBound (settle pass : Nat) : Nat := settle + pass

/-- The finish bound: the answering pass itself runs at most `pass` more. -/
def wakeDoneBound (settle pass : Nat) : Nat := settle + 2 * pass

/-- **A file event at `t` is answered by a pass that starts at or after the request and by `t + wakeStartBound settle pass`.**
The first poke of the settle window came at `f ≤ t`; the request `f + settle` is not before `t`. -/
theorem poke_wake_le (x : T) (t f e settle pass : Nat) (h : Inv x.s) (hs : x.since ≤ f + settle) (hf : f ≤ t)
    (ht : t ≤ f + settle) (he : x.s.finished < x.s.started → f + settle ≤ e ∧ e ≤ x.since + pass) :
    ticket x.s + 1 = (answered x (f + settle) e).s.started ∧ t ≤ (answered x (f + settle) e).since ∧
      (answered x (f + settle) e).since ≤ t + wakeStartBound settle pass := by
  obtain ⟨a, b, c⟩ := answer_start_le x (f + settle) e pass h hs he
  unfold wakeStartBound
  exact ⟨a, by omega, by omega⟩

/-- The answering pass of `poke_wake_le` is done within `wakeDoneBound`, when it runs at most `pass`. -/
theorem poke_done_le (x : T) (t f e settle pass : Nat) (h : Inv x.s) (hs : x.since ≤ f + settle) (hf : f ≤ t)
    (ht : t ≤ f + settle) (he : x.s.finished < x.s.started → f + settle ≤ e ∧ e ≤ x.since + pass) :
    (answered x (f + settle) e).since + pass ≤ t + wakeDoneBound settle pass := by
  obtain ⟨_, _, c⟩ := poke_wake_le x t f e settle pass h hs hf ht he
  unfold wakeStartBound at c
  unfold wakeDoneBound; omega

/-- **A dropped event** (no file event at all): the safety tick `nextTick p t` is the request, and its pass starts at or after
the event and by `t + wakeStartBound p pass`. -/
theorem tick_wake_le (x : T) (p t e pass : Nat) (h : Inv x.s) (hp : 0 < p) (hs : x.since ≤ nextTick p t)
    (he : x.s.finished < x.s.started → nextTick p t ≤ e ∧ e ≤ x.since + pass) :
    ticket x.s + 1 = (answered x (nextTick p t) e).s.started ∧ t ≤ (answered x (nextTick p t) e).since ∧
      (answered x (nextTick p t) e).since ≤ t + wakeStartBound p pass := by
  obtain ⟨a, b, c⟩ := answer_start_le x (nextTick p t) e pass h hs he
  have h1 := nextTick_gt p t hp
  have h2 := nextTick_le p t hp
  unfold wakeStartBound
  exact ⟨a, by omega, by omega⟩

/-- The start bound is at least the settle window. -/
theorem wakeStartBound_ge (settle pass : Nat) : settle ≤ wakeStartBound settle pass := by
  unfold wakeStartBound; omega

/-- **Assumption, not a theorem** (golden row `pass_max_ms`): no sweep of the console-api drain test runs longer than this. The
bounds above hold for any `pass`; the test fails, with a trail, the moment a pass exceeds it. -/
def passMaxMs : Nat := 2000

/-- Margin the test adds for timer rounding and event-loop lag; a stall beyond it fails the test and names the lag. -/
def wakeMarginMs : Nat := 500

/-- The safety period of the tick-rescue test. -/
def rescueTickMs : Nat := 1000

/-- The settle window of the drain (TS `DRAIN_SETTLE_MS`). -/
def settleMs : Nat := 50

/-- Deadline of the event-path test: the proved bound for a file event plus the margin. -/
def eventDeadlineMs : Nat := wakeStartBound settleMs passMaxMs + wakeMarginMs

/-- Deadline of the tick-rescue test: the proved bound for a dropped event plus the margin. -/
def rescueDeadlineMs : Nat := wakeStartBound rescueTickMs passMaxMs + wakeMarginMs

/-- The deadlines are the sums the golden states. -/
theorem deadlines_eq : eventDeadlineMs = 2550 ∧ rescueDeadlineMs = 3500 := by decide

/-- State as JSON. -/
def sJson (s : S) : Json := Json.mkObj [("started", s.started), ("finished", s.finished), ("pending", s.pending)]

/-- The steps of a case: the state and the answering ticket (requests only) after each event. -/
def steps (s : S) : List Ev → List Json
  | [] => []
  | e :: r =>
    let s' := e.apply s
    let t : Json := match e with | .request => toJson (ticket s) | .finish => Json.null
    Json.mkObj [("state", sJson s'), ("ticket", t)] :: steps s' r

/-- Name of an event. -/
def Ev.name : Ev → String | .request => "req" | .finish => "fin"

/-- One golden case. -/
def case (name : String) (es : List Ev) : Json :=
  Json.mkObj [("name", name), ("events", .arr (es.toArray.map fun e => Json.str e.name)),
    ("steps", .arr (steps init es).toArray)]

/-- Golden cases. -/
def cases : List Json := [
  case "idle request starts a pass" [.request],
  case "request while running is pending" [.request, .request],
  case "many requests coalesce" [.request, .request, .request, .request],
  case "finish with none pending is idle" [.request, .finish],
  case "finish with one pending starts the next" [.request, .request, .finish],
  case "pending served then idle" [.request, .request, .finish, .finish],
  case "request during the pending pass" [.request, .request, .finish, .request, .finish, .finish],
  case "finish when idle is a no-op" [.finish, .request, .finish, .finish],
  case "safety tick after a dropped event" [.request, .finish, .request, .finish],
  case "safety tick while a pass runs" [.request, .request, .finish, .finish],
  case "burst" [.request, .request, .request, .finish, .request, .request, .finish, .finish, .request]]

/-- The golden text. -/
def goldenText : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- Golden path, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/reconcile-sched.jsonl"

/-- Wake-bound rows `(settle, pass)`: the bounds the console-api wake test waits for. -/
def wakeRows : List (Nat × Nat) := [(50, 0), (50, 1), (50, 315), (50, 3000), (0, 0), (200, 10), (10000, 2000)]

/-- The wake-bound golden text. -/
def wakeText : String :=
  String.join (wakeRows.map fun (s, p) => (Json.mkObj [("settle", s), ("pass", p), ("start", wakeStartBound s p),
    ("done", wakeDoneBound s p)]).compress ++ "\n")

/-- Wake-bound golden path, relative to `lean/`. -/
def wakePath : System.FilePath := "../packages/contracts/golden/console/wake-bound.jsonl"

/-- Test parameters of the wake tests: each name, its value and whether it is an ASSUMPTION (stated, not proved) or DERIVED. -/
def paramRows : List (String × Nat × String) :=
  [("pass_max_ms", passMaxMs, "ASSUMPTION"), ("wake_margin_ms", wakeMarginMs, "ASSUMPTION"), ("settle_ms", settleMs, "DRAIN_SETTLE_MS"),
   ("rescue_tick_ms", rescueTickMs, "ASSUMPTION"), ("event_deadline_ms", eventDeadlineMs, "DERIVED"),
   ("rescue_deadline_ms", rescueDeadlineMs, "DERIVED")]

/-- The wake-test parameter golden text. -/
def paramText : String :=
  String.join (paramRows.map fun (n, v, k) => (Json.mkObj [("name", n), ("value", v), ("kind", k)]).compress ++ "\n")

/-- Wake-test parameter golden path, relative to `lean/`. -/
def paramPath : System.FilePath := "../packages/contracts/golden/console/wake-params.jsonl"

/-- Write the golden files. -/
def writeGolden : IO Unit := do
  IO.FS.writeFile goldenPath goldenText; IO.FS.writeFile wakePath wakeText; IO.FS.writeFile paramPath paramText

/-- Are the golden files the Lean output? -/
def checkGolden : IO Bool := do
  return (← IO.FS.readFile goldenPath) == goldenText && (← IO.FS.readFile wakePath) == wakeText &&
    (← IO.FS.readFile paramPath) == paramText

end Fw.Console.ReconcileSched
