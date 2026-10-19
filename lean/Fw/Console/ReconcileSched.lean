import Lean.Data.Json
/-!
# Reconcile requests: one running pass, at most one pending

Each request is answered by the next pass that starts after it. Golden: `golden/console/reconcile-sched.jsonl`.
-/
namespace Fw.Console.ReconcileSched

/-- The scheduler state: passes started, passes finished, requests waiting for the next pass (kept at most one).
$$s = (\mathit{started}, \mathit{finished}, \mathit{pending})$$ -/
structure S where
  started : Nat
  finished : Nat
  pending : Nat
deriving DecidableEq, Repr

/-- The empty scheduler.
$$s_0 = (0, 0, 0)$$ -/
def init : S := ⟨0, 0, 0⟩

/-- A request: idle starts a pass now; a running pass leaves one pending request, however many arrive.
$$\operatorname{req}(s) = \begin{cases} (a+1, f, p) & f = a \\ (a, f, \min(1, p+1)) & f < a \end{cases}$$ -/
def req (s : S) : S :=
  if s.finished < s.started then { s with pending := min 1 (s.pending + 1) }
  else { s with started := s.started + 1 }

/-- The running pass finishes: a pending request starts the next pass; with no pass running nothing happens.
$$\operatorname{fin}(s) = \begin{cases} (a, f+1, 0) \text{ if } p = 0,\ (a+1, f+1, 0) \text{ if } p \ge 1 & f < a \\ s & f = a \end{cases}$$ -/
def fin (s : S) : S :=
  if s.finished < s.started then
    if s.pending = 0 then { s with finished := s.finished + 1 }
    else ⟨s.started + 1, s.finished + 1, 0⟩
  else s

/-- The index of the pass that answers a request made in state `s`: the first pass not yet started.
$$\operatorname{ticket}(s) = \mathit{started}$$ -/
def ticket (s : S) : Nat := s.started

/-- Reachable-state invariant.
$$\mathrm{Inv}(s) \iff f \le a \le f+1 \,\wedge\, p \le 1 \,\wedge\, (p = 1 \Rightarrow a = f+1)$$ -/
def Inv (s : S) : Prop :=
  s.finished ≤ s.started ∧ s.started ≤ s.finished + 1 ∧ s.pending ≤ 1 ∧ (s.pending = 1 → s.started = s.finished + 1)

/-- The empty scheduler satisfies the invariant.
$$\mathrm{Inv}(s_0)$$ -/
theorem inv_init : Inv init := by simp [Inv, init]

/-- A request keeps the invariant.
$$\mathrm{Inv}(s) \Rightarrow \mathrm{Inv}(\operatorname{req}(s))$$ -/
theorem inv_req (s : S) (h : Inv s) : Inv (req s) := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  unfold req Inv
  split <;> simp_all <;> omega

/-- A finish keeps the invariant.
$$\mathrm{Inv}(s) \Rightarrow \mathrm{Inv}(\operatorname{fin}(s))$$ -/
theorem inv_fin (s : S) (h : Inv s) : Inv (fin s) := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  unfold fin Inv
  by_cases hb : s.finished < s.started
  · by_cases hp : s.pending = 0 <;> simp [hb, hp] <;> omega
  · simp [hb]; omega

/-- **Pending is at most one**, after any request.
$$\mathrm{Inv}(s) \Rightarrow \mathit{pending}(\operatorname{req}(s)) \le 1$$ -/
theorem pending_le_one_req (s : S) (h : Inv s) : (req s).pending ≤ 1 := (inv_req s h).2.2.1

/-- **Pending is at most one**, after any finish.
$$\mathrm{Inv}(s) \Rightarrow \mathit{pending}(\operatorname{fin}(s)) \le 1$$ -/
theorem pending_le_one_fin (s : S) (h : Inv s) : (fin s).pending ≤ 1 := (inv_fin s h).2.2.1

/-- At most one pass runs.
$$\mathrm{Inv}(s) \Rightarrow \mathit{started} - \mathit{finished} \le 1$$ -/
theorem one_running (s : S) (h : Inv s) : s.started - s.finished ≤ 1 := by
  obtain ⟨h1, h2, _, _⟩ := h; omega

/-- **Idle request**: the answering pass starts at the request itself.
$$f = a \Rightarrow \operatorname{ticket}(s) < \mathit{started}(\operatorname{req}(s))$$ -/
theorem req_idle_starts (s : S) (h : s.finished = s.started) : ticket s < (req s).started := by
  unfold req ticket; simp [h]

/-- **Busy request**: the answering pass has not started when the request arrives, and one request is pending for it.
$$f < a \Rightarrow \mathit{started}(\operatorname{req}(s)) = \operatorname{ticket}(s) \,\wedge\, \mathit{pending}(\operatorname{req}(s)) = 1$$ -/
theorem req_busy_waits (s : S) (h : s.finished < s.started) :
    (req s).started = ticket s ∧ (req s).pending = 1 := by
  unfold req ticket; simp [h]

/-- **Busy request, already pending**: the new request joins the pending one and has the same ticket.
$$f < a \wedge p = 1 \Rightarrow \operatorname{req}(s) = s$$ -/
theorem req_coalesces (s : S) (h : s.finished < s.started) (hp : s.pending = 1) : req s = s := by
  obtain ⟨a, b, c⟩ := s
  simp_all [req]

/-- A pass finishing with a request pending starts the answering pass, whose index is the ticket.
$$f < a \wedge p \ne 0 \Rightarrow \operatorname{ticket}(s) < \mathit{started}(\operatorname{fin}(s))$$ -/
theorem fin_starts_pending (s : S) (h : s.finished < s.started) (hp : s.pending ≠ 0) :
    ticket s < (fin s).started := by
  unfold fin ticket; simp [h, hp]

/-- **Every request is answered by a pass that starts after it**, busy case: the next finish starts the request's pass.
$$f < a \Rightarrow \operatorname{ticket}(s) < \mathit{started}(\operatorname{fin}(\operatorname{req}(s)))$$ -/
theorem answered_after_busy (s : S) (hb : s.finished < s.started) :
    ticket s < (fin (req s)).started := by
  have hw := req_busy_waits s hb
  have hr : (req s).finished < (req s).started := by
    unfold req; simp [hb]
  have hp : (req s).pending ≠ 0 := by omega
  have := fin_starts_pending (req s) hr hp
  unfold ticket at *
  omega

/-- **Idle case of the same**: the pass starts at the request.
$$f = a \Rightarrow \operatorname{ticket}(s) < \mathit{started}(\operatorname{req}(s))$$ -/
theorem answered_after_idle (s : S) (h : s.finished = s.started) : ticket s < (req s).started :=
  req_idle_starts s h

/-- **No request waits for more than two passes**: after a request, two finishes leave its pass finished.
$$\mathrm{Inv}(s) \Rightarrow \operatorname{ticket}(s) < \mathit{finished}(\operatorname{fin}(\operatorname{fin}(\operatorname{req}(s))))$$ -/
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

/-- A request waits for one pass when none is running: one finish leaves its pass finished.
$$f = a \Rightarrow \operatorname{ticket}(s) < \mathit{finished}(\operatorname{fin}(\operatorname{req}(s)))$$ -/
theorem wait_le_one_idle (s : S) (h : s.finished = s.started) : ticket s < (fin (req s)).finished := by
  unfold req fin ticket
  by_cases hp : s.pending = 0 <;> simp [h, hp]

open Lean

/-- Event of a golden case.
$$e \in \{\mathrm{req}, \mathrm{fin}\}$$ -/
inductive Ev where | request | finish
deriving DecidableEq

/-- The event applied.
$$\operatorname{apply}(s, e)$$ -/
def Ev.apply (s : S) : Ev → S | .request => req s | .finish => fin s

/-- State as JSON.
$$s \mapsto \{started, finished, pending\}$$ -/
def sJson (s : S) : Json := Json.mkObj [("started", s.started), ("finished", s.finished), ("pending", s.pending)]

/-- The steps of a case: the state and the answering ticket (requests only) after each event.
$$\operatorname{steps}(s, es)$$ -/
def steps (s : S) : List Ev → List Json
  | [] => []
  | e :: r =>
    let s' := e.apply s
    let t : Json := match e with | .request => toJson (ticket s) | .finish => Json.null
    Json.mkObj [("state", sJson s'), ("ticket", t)] :: steps s' r

/-- Name of an event.
$$\mathrm{name}(e)$$ -/
def Ev.name : Ev → String | .request => "req" | .finish => "fin"

/-- One golden case.
$$\operatorname{case}(n, es)$$ -/
def case (name : String) (es : List Ev) : Json :=
  Json.mkObj [("name", name), ("events", .arr (es.toArray.map fun e => Json.str e.name)),
    ("steps", .arr (steps init es).toArray)]

/-- Golden cases.
$$\mathrm{cases}$$ -/
def cases : List Json := [
  case "idle request starts a pass" [.request],
  case "request while running is pending" [.request, .request],
  case "many requests coalesce" [.request, .request, .request, .request],
  case "finish with none pending is idle" [.request, .finish],
  case "finish with one pending starts the next" [.request, .request, .finish],
  case "pending served then idle" [.request, .request, .finish, .finish],
  case "request during the pending pass" [.request, .request, .finish, .request, .finish, .finish],
  case "finish when idle is a no-op" [.finish, .request, .finish, .finish],
  case "burst" [.request, .request, .request, .finish, .request, .request, .finish, .finish, .request]]

/-- The golden text.
$$\mathrm{goldenText}$$ -/
def goldenText : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- Golden path, relative to `lean/`.
$$\mathrm{goldenPath}$$ -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/reconcile-sched.jsonl"

/-- Write the golden file.
$$\mathrm{writeGolden}$$ -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output?
$$\mathrm{checkGolden}$$ -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.ReconcileSched
