/-!
# Agent state from transcript signals

What one agent is doing at time $t$, read from its own transcript, the lead's queue and `ps`, never from
`meta.finished` (research: `research/notes/2026/10-18-transcript-signals.md`, part B; the rule reproduces the
timelines of the 8 agents studied there).

Facts per agent (all times in one unit, ms on the wire, seconds in the golden timelines):
* **launched** background ids with the time each was launched (Bash `backgroundTaskId`, the text
  `Command running in background with ID: <id>` of a workflow agent's Bash result, child agent ids of `Agent` results);
* **end events** per id: a `<task-notification>` (own transcript or lead queue), or the task output's last line
  `[exited with code N]` / `[killed]`;
* **turn boundaries**: START at the first record and at every user record with a top-level `origin` (a wake),
  END at `stop_reason: end_turn` and at every result with `toolEndsTurn`;
* **handbacks** (a `SubagentHandback` result with `toolEndsTurn`), the lead's **notices** for the agent
  ('finished' or 'waiting on its own background work'), and the **live processes** of its background ids with
  their command kind (reads stdin, sleep loop, other).

Rule (`rule`, the note's table): an open turn is `working`; a closed one is decided by the pending set
$\mathrm{PEND} = \mathrm{BG} \setminus \mathrm{END}$, the handback and the latest lead notice. `classify` adds
`hung(b)`: a closed turn with a pending id $b$ launched more than `hungAfter` ago whose live process reads stdin or
is a sleep loop (port-nav's `cat > file` ran 3 h with no end signal; only `ps` shows it).

Proved: `classify_table`, `classify_total`, `classify_det`, `state_working_iff_open`, `held_iff`, `classify_held_iff`,
`classify_quiet_addEnd` (monotone in END), `classify_metaFinished` (`meta.finished` is never read),
`golden_ok` (the 8 timelines reproduce at all 39 checkpoints).
-/
namespace Fw.Obs.Signals

/-- The hung threshold, in the facts' time unit (default 30; the golden uses 1800 s, the wire passes ms).

$$p = (\mathit{hungAfter}) \in \mathbb N,\quad \text{default } 30$$
-/
structure Params where
  hungAfter : Nat := 30
deriving DecidableEq, Repr

/-- A background id launched by the agent at a time.

$$\ell = (\mathit{id}, \mathit{time}) \in \mathrm{String} \times \mathbb N$$
-/
structure Launch where
  id   : String
  time : Nat
deriving DecidableEq, Repr

/-- How an end was seen: a task notification, the exit marker `[exited with code N]`, or the marker `[killed]`.

$$\mathcal H = \{\mathrm{notified}, \mathrm{killed}\} \cup \{\mathrm{exited}(n) : n \in \mathbb Z\}$$
-/
inductive How where
  | notified
  | exited (code : Int)
  | killed
deriving DecidableEq, Repr

/-- An end event of a background id at a time.

$$e = (\mathit{id}, \mathit{time}, \mathit{how}) \in \mathrm{String} \times \mathbb N \times \mathcal H$$
-/
structure EndEv where
  id   : String
  time : Nat
  how  : How := .notified
deriving DecidableEq, Repr

/-- A turn boundary: its time and whether it starts a turn (`true`) or ends one (`false`).

$$\beta = (\mathit{time}, \mathit{start}) \in \mathbb N \times \mathbb B$$
-/
structure Bound where
  time  : Nat
  start : Bool
deriving DecidableEq, Repr

/-- A lead notice for the agent: its time and whether it says 'finished' (`false`: 'waiting on its own background
work').

$$n = (\mathit{time}, \mathit{fin}) \in \mathbb N \times \mathbb B$$
-/
structure Notice where
  time     : Nat
  finished : Bool
deriving DecidableEq, Repr

/-- What a live process of a background id does, read from its command: it reads stdin (`cat > file` with no
input), it is a sleep loop (`until …; do sleep …`), or anything else.

$$\mathcal P = \{\mathrm{stdin}, \mathrm{sleepLoop}, \mathrm{other}\}$$
-/
inductive ProcKind where
  | stdin
  | sleepLoop
  | other
deriving DecidableEq, Repr

/-- A live process of a background id: the id, its pid and its kind.

$$q = (\mathit{id}, \mathit{pid}, k) \in \mathrm{String} \times \mathbb N \times \mathcal P$$
-/
structure Proc where
  id   : String
  pid  : Nat
  kind : ProcKind
deriving DecidableEq, Repr

/-- The signal facts of one agent: its id, launched ids, end events, turn boundaries (in file order), handback
times, lead notices (in file order), live processes, and the times `meta.finished` was written (recorded, never read
by the rule).

$$f = (a, L, E, B, H, N, Q, M)$$
-/
structure Facts where
  agent        : String
  launched     : List Launch := []
  ends         : List EndEv := []
  bounds       : List Bound := []
  handbacks    : List Nat := []
  notices      : List Notice := []
  procs        : List Proc := []
  metaFinished : List Nat := []
deriving DecidableEq, Repr

/-- The agent's state: working (open turn), waiting on its own background ids, handed back but held by pending ids,
handed back and done, finished (lead notice), idle after a turn, or hung on one id.

$$\mathcal S = \{\mathrm{working}, \mathrm{done}, \mathrm{finished}, \mathrm{idle}\} \cup \{\mathrm{waiting}(P), \mathrm{held}(P) : P \in \mathrm{String}^*\} \cup \{\mathrm{hung}(b) : b \in \mathrm{String}\}$$
-/
inductive State where
  | working
  | waitingOwnBg (ids : List String)
  | handedBackHeld (ids : List String)
  | handedBackDone
  | finished
  | idle
  | hung (id : String)
deriving DecidableEq, Repr

/-! ## The sets at time t -/

/-- Whether id $b$ has an end event at or before $t$.

$$\operatorname{END}(t, f, b) \iff \exists e \in E(f).\ \mathit{id}(e) = b \wedge \mathit{time}(e) \le t$$
-/
def endedB (t : Nat) (f : Facts) (b : String) : Bool :=
  f.ends.any fun e => e.id == b && decide (e.time ≤ t)

/-- The ids launched at or before $t$, first launch order, without repeats.

$$\operatorname{BG}(t, f) = \operatorname{dedup}\,[\mathit{id}(\ell) : \ell \in L(f),\ \mathit{time}(\ell) \le t]$$
-/
def bg (t : Nat) (f : Facts) : List String :=
  ((f.launched.filter fun l => decide (l.time ≤ t)).map (·.id)).eraseDups

/-- The pending ids: launched and not ended at $t$.

$$\operatorname{PEND}(t, f) = [b \in \operatorname{BG}(t, f) : \neg\operatorname{END}(t, f, b)]$$
-/
def pend (t : Nat) (f : Facts) : List String :=
  (bg t f).filter fun b => !endedB t f b

/-- Whether the agent handed back at or before $t$.

$$\operatorname{HB}(t, f) \iff \exists h \in H(f).\ h \le t$$
-/
def hbB (t : Nat) (f : Facts) : Bool := f.handbacks.any fun h => decide (h ≤ t)

/-- The latest handback at or before $t$ (`none`: none).

$$\operatorname{lastHB}(t, f) = \max\{h \in H(f) : h \le t\}\ (\bot \text{ if empty})$$
-/
def lastHandback (t : Nat) (f : Facts) : Option Nat := (f.handbacks.filter fun h => decide (h ≤ t)).max?

/-- Whether the turn is open at $t$: the last boundary (in file order) with time at or before $t$ is a START. No such
boundary: closed.

$$\operatorname{open}(t, f) \iff \exists \beta.\ \operatorname{last}[\beta' \in B(f) : \mathit{time}(\beta') \le t] = \beta \wedge \mathit{start}(\beta)$$
-/
def openB (t : Nat) (f : Facts) : Bool :=
  match (f.bounds.filter fun b => decide (b.time ≤ t)).getLast? with
  | some b => b.start
  | none => false

/-- Whether the latest lead notice (in file order) at or before $t$ says 'finished'. No notice: no.

$$\operatorname{fin}(t, f) \iff \exists n.\ \operatorname{last}[n' \in N(f) : \mathit{time}(n') \le t] = n \wedge \mathit{fin}(n)$$
-/
def finNoticeB (t : Nat) (f : Facts) : Bool :=
  match (f.notices.filter fun n => decide (n.time ≤ t)).getLast? with
  | some n => n.finished
  | none => false

/-- The time of the first launch of id $b$ at or before $t$ (`none`: not launched by $t$).

$$\operatorname{at}(t, f, b) = \mathit{time}\bigl(\operatorname{first}[\ell \in L(f) : \mathit{id}(\ell) = b \wedge \mathit{time}(\ell) \le t]\bigr)\ (\bot \text{ if empty})$$
-/
def launchAt (t : Nat) (f : Facts) (b : String) : Option Nat :=
  (f.launched.find? fun l => l.id == b && decide (l.time ≤ t)).map (·.time)

/-- A process kind that never ends on its own: it reads stdin or it is a sleep loop.

$$\operatorname{waits}(k) \iff k \in \{\mathrm{stdin}, \mathrm{sleepLoop}\}$$
-/
def waitsB (k : ProcKind) : Bool := k == .stdin || k == .sleepLoop

/-- Whether id $b$ is hung at $t$: launched strictly more than `hungAfter` before $t$, and a live process of $b$
reads stdin or is a sleep loop. (Used on pending ids only.)

$$\operatorname{hung}(p, t, f, b) \iff \bigl(\exists a.\ \operatorname{at}(t, f, b) = a \wedge \mathit{hungAfter}(p) < t \mathbin{\dot-} a\bigr) \wedge \exists q \in Q(f).\ \mathit{id}(q) = b \wedge \operatorname{waits}(k(q))$$
-/
def hungB (p : Params) (t : Nat) (f : Facts) (b : String) : Bool :=
  (match launchAt t f b with
   | some a => decide (p.hungAfter < t - a)
   | none => false) &&
  f.procs.any fun q => q.id == b && waitsB q.kind

/-- The hung pending ids, in pending order.

$$\operatorname{HUNG}(p, t, f) = [b \in \operatorname{PEND}(t, f) : \operatorname{hung}(p, t, f, b)]$$
-/
def hungIds (p : Params) (t : Nat) (f : Facts) : List String := (pend t f).filter (hungB p t f)

/-! ## The rule and the classification -/

/-- **The note's rule.** Open turn: working. Closed: pending ids and a handback: held; pending ids, no handback:
waiting; nothing pending: finished if the latest lead notice says so, else done if handed back, else idle.

$$\operatorname{rule}(t, f) = \begin{cases} \mathrm{working} & \operatorname{open}(t, f) \\ \mathrm{held}(P) & \neg\operatorname{open} \wedge \operatorname{PEND}(t, f) = P \ne [\,] \wedge \operatorname{HB}(t, f) \\ \mathrm{waiting}(P) & \neg\operatorname{open} \wedge \operatorname{PEND}(t, f) = P \ne [\,] \wedge \neg\operatorname{HB}(t, f) \\ \mathrm{finished} & \neg\operatorname{open} \wedge \operatorname{PEND}(t, f) = [\,] \wedge \operatorname{fin}(t, f) \\ \mathrm{done} & \neg\operatorname{open} \wedge \operatorname{PEND}(t, f) = [\,] \wedge \neg\operatorname{fin}(t, f) \wedge \operatorname{HB}(t, f) \\ \mathrm{idle} & \text{otherwise} \end{cases}$$
-/
def rule (t : Nat) (f : Facts) : State :=
  if openB t f then .working
  else match pend t f with
    | [] => if finNoticeB t f then .finished else if hbB t f then .handedBackDone else .idle
    | b :: bs => if hbB t f then .handedBackHeld (b :: bs) else .waitingOwnBg (b :: bs)

/-- **The classification.** Open turn: working; closed with a hung pending id: hung on the first one; otherwise
the rule.

$$\operatorname{classify}(p, t, f) = \begin{cases} \mathrm{working} & \operatorname{open}(t, f) \\ \mathrm{hung}(b) & \neg\operatorname{open}(t, f) \wedge \operatorname{HUNG}(p, t, f) = b :: \_ \\ \operatorname{rule}(t, f) & \text{otherwise} \end{cases}$$
-/
def classify (p : Params) (t : Nat) (f : Facts) : State :=
  if openB t f then .working
  else match hungIds p t f with
    | b :: _ => .hung b
    | [] => rule t f

/-- The states in which nothing of the agent's own is pending: done, finished, idle.

$$\operatorname{quiet}(s) \iff s \in \{\mathrm{done}, \mathrm{finished}, \mathrm{idle}\}$$
-/
def quietB : State → Bool
  | .handedBackDone | .finished | .idle => true
  | _ => false

/-- A producer counts as exited (for a loop watching its output) when it is finished or handed back and done.

$$\operatorname{producerDone}(s) \iff s \in \{\mathrm{finished}, \mathrm{done}\}$$
-/
def producerDoneB : State → Bool
  | .handedBackDone | .finished => true
  | _ => false

/-- The ids a state names: the pending ids of waiting and held, the id of hung, else none.

$$\operatorname{ids}(s) = \begin{cases} P & s \in \{\mathrm{waiting}(P), \mathrm{held}(P)\} \\ [b] & s = \mathrm{hung}(b) \\ [\,] & \text{otherwise} \end{cases}$$
-/
def State.ids : State → List String
  | .waitingOwnBg P | .handedBackHeld P => P
  | .hung b => [b]
  | _ => []

/-- The wire name of a state.

$$\operatorname{name} : \mathcal S \to \mathrm{String}$$
-/
def State.name : State → String
  | .working => "working" | .waitingOwnBg _ => "waitingOwnBg" | .handedBackHeld _ => "handedBackHeld"
  | .handedBackDone => "handedBackDone" | .finished => "finished" | .idle => "idle" | .hung _ => "hung"

/-- One more end event, appended.

$$\operatorname{addEnd}(e, f) = f[E := E(f) \mathbin{+\!\!+} [e]]$$
-/
def addEnd (e : EndEv) (f : Facts) : Facts := { f with ends := f.ends ++ [e] }

/-! ## Proofs -/

/-- **Deterministic.** The classification is a function: two results for the same input are equal.

$$\forall p, t, f, s, s':\quad s = \operatorname{classify}(p, t, f) \wedge s' = \operatorname{classify}(p, t, f) \Rightarrow s = s'$$
-/
theorem classify_det (p : Params) (t : Nat) (f : Facts) (s s' : State)
    (h : s = classify p t f) (h' : s' = classify p t f) : s = s' := h.trans h'.symm

/-- **The case table** (first match, so the cases do not overlap): open turn; a hung id; pending ids with and without a
handback; nothing pending with a 'finished' notice, with a handback, or neither.

$$\forall p, t, f:\quad \operatorname{classify}(p, t, f) = \begin{cases} \mathrm{working} & \operatorname{open}(t, f) \\ \mathrm{hung}(b) & \neg\operatorname{open} \wedge \operatorname{HUNG}(p, t, f) = b :: \_ \\ \mathrm{held}(P) & \neg\operatorname{open} \wedge \operatorname{HUNG} = [\,] \wedge \operatorname{PEND}(t, f) = P \ne [\,] \wedge \operatorname{HB}(t, f) \\ \mathrm{waiting}(P) & \neg\operatorname{open} \wedge \operatorname{HUNG} = [\,] \wedge \operatorname{PEND}(t, f) = P \ne [\,] \wedge \neg\operatorname{HB}(t, f) \\ \mathrm{finished} & \neg\operatorname{open} \wedge \operatorname{HUNG} = [\,] \wedge \operatorname{PEND} = [\,] \wedge \operatorname{fin}(t, f) \\ \mathrm{done} & \neg\operatorname{open} \wedge \operatorname{HUNG} = [\,] \wedge \operatorname{PEND} = [\,] \wedge \neg\operatorname{fin} \wedge \operatorname{HB}(t, f) \\ \mathrm{idle} & \neg\operatorname{open} \wedge \operatorname{HUNG} = [\,] \wedge \operatorname{PEND} = [\,] \wedge \neg\operatorname{fin} \wedge \neg\operatorname{HB}(t, f) \end{cases}$$
-/
theorem classify_table (p : Params) (t : Nat) (f : Facts) :
    classify p t f =
      if openB t f then .working
      else match hungIds p t f with
        | b :: _ => .hung b
        | [] => match pend t f with
          | [] => if finNoticeB t f then .finished else if hbB t f then .handedBackDone else .idle
          | b :: bs => if hbB t f then .handedBackHeld (b :: bs) else .waitingOwnBg (b :: bs) := by
  unfold classify rule
  cases openB t f
  · simp only [Bool.false_eq_true, ite_false]
  · rfl

/-- The hung ids are pending ids.

$$\forall p, t, f, b:\quad b \in \operatorname{HUNG}(p, t, f) \Rightarrow b \in \operatorname{PEND}(t, f)$$
-/
theorem mem_pend_of_hung (p : Params) (t : Nat) (f : Facts) (b : String) (h : b ∈ hungIds p t f) :
    b ∈ pend t f := (List.mem_filter.1 h).1

/-- **Total**: every input gets one of the seven forms; the id of hung is pending; the ids of waiting and held are
the pending set, non-empty.

$$\forall p, t, f:\quad \operatorname{classify}(p, t, f) \in \{\mathrm{working}, \mathrm{done}, \mathrm{finished}, \mathrm{idle}\} \vee \bigl(\exists b \in \operatorname{PEND}(t, f).\ \operatorname{classify}(p, t, f) = \mathrm{hung}(b)\bigr) \vee \bigl(\operatorname{PEND}(t, f) \ne [\,] \wedge \operatorname{classify}(p, t, f) \in \{\mathrm{waiting}(\operatorname{PEND}(t, f)), \mathrm{held}(\operatorname{PEND}(t, f))\}\bigr)$$
-/
theorem classify_total (p : Params) (t : Nat) (f : Facts) :
    (classify p t f = .working ∨ classify p t f = .handedBackDone ∨ classify p t f = .finished ∨
      classify p t f = .idle) ∨
    (∃ b ∈ pend t f, classify p t f = .hung b) ∨
    (pend t f ≠ [] ∧ (classify p t f = .waitingOwnBg (pend t f) ∨ classify p t f = .handedBackHeld (pend t f))) := by
  rw [classify_table]
  cases ho : openB t f
  · cases hh : hungIds p t f with
    | cons b bs =>
      exact .inr (.inl ⟨b, mem_pend_of_hung p t f b (by rw [hh]; simp), by simp⟩)
    | nil =>
      cases hp : pend t f with
      | nil => cases finNoticeB t f <;> cases hbB t f <;> simp
      | cons b bs => cases hbB t f <;> simp
  · simp

/-- **Working exactly when the turn is open** (for the rule).

$$\forall t, f:\quad \operatorname{rule}(t, f) = \mathrm{working} \iff \operatorname{open}(t, f)$$
-/
theorem rule_working_iff_open (t : Nat) (f : Facts) : rule t f = .working ↔ openB t f = true := by
  unfold rule
  cases openB t f
  · cases pend t f with
    | nil => cases finNoticeB t f <;> cases hbB t f <;> simp
    | cons b bs => cases hbB t f <;> simp
  · simp

/-- **Working exactly when the turn is open.**

$$\forall p, t, f:\quad \operatorname{classify}(p, t, f) = \mathrm{working} \iff \operatorname{open}(t, f)$$
-/
theorem state_working_iff_open (p : Params) (t : Nat) (f : Facts) :
    classify p t f = .working ↔ openB t f = true := by
  unfold classify
  cases ho : openB t f
  · cases hungIds p t f with
    | cons b bs => simp
    | nil => simpa [ho] using rule_working_iff_open t f
  · simp

/-- **Held exactly when handed back with pending ids** (the note's rule): the rule says held on $P$ iff the turn is
closed, the agent handed back, and the pending set is $P \ne [\,]$.

$$\forall t, f, P:\quad \operatorname{rule}(t, f) = \mathrm{held}(P) \iff \neg\operatorname{open}(t, f) \wedge \operatorname{HB}(t, f) \wedge \operatorname{PEND}(t, f) = P \wedge P \ne [\,]$$
-/
theorem held_iff (t : Nat) (f : Facts) (P : List String) :
    rule t f = .handedBackHeld P ↔ openB t f = false ∧ hbB t f = true ∧ pend t f = P ∧ P ≠ [] := by
  unfold rule
  cases openB t f
  · cases hp : pend t f with
    | nil =>
      cases finNoticeB t f <;> cases hbB t f <;> simp <;> intro h <;> exact h.symm
    | cons b bs => cases hbB t f <;> simp [eq_comm] <;> rintro rfl <;> simp
  · simp

/-- **Held, with hung ids.** The classification says held on $P$ iff the turn is closed, no pending id is hung, the
agent handed back, and the pending set is $P \ne [\,]$.

$$\forall p, t, f, P:\quad \operatorname{classify}(p, t, f) = \mathrm{held}(P) \iff \neg\operatorname{open}(t, f) \wedge \operatorname{HUNG}(p, t, f) = [\,] \wedge \operatorname{HB}(t, f) \wedge \operatorname{PEND}(t, f) = P \wedge P \ne [\,]$$
-/
theorem classify_held_iff (p : Params) (t : Nat) (f : Facts) (P : List String) :
    classify p t f = .handedBackHeld P ↔
      openB t f = false ∧ hungIds p t f = [] ∧ hbB t f = true ∧ pend t f = P ∧ P ≠ [] := by
  have hr := held_iff t f P
  unfold classify
  cases ho : openB t f
  · cases hungIds p t f with
    | cons b bs => simp
    | nil => simpa [ho] using hr
  · simp

/-- A quiet classification (done, finished, idle) means a closed turn with nothing pending.

$$\forall p, t, f:\quad \operatorname{quiet}(\operatorname{classify}(p, t, f)) \Rightarrow \neg\operatorname{open}(t, f) \wedge \operatorname{PEND}(t, f) = [\,]$$
-/
theorem closed_nil_of_quiet (p : Params) (t : Nat) (f : Facts) (hq : quietB (classify p t f) = true) :
    openB t f = false ∧ pend t f = [] := by
  rw [classify_table] at hq
  cases ho : openB t f
  · rw [ho] at hq
    cases hh : hungIds p t f with
    | cons b bs => rw [hh] at hq; simp [quietB] at hq
    | nil =>
      rw [hh] at hq
      cases hp : pend t f with
      | nil => simp
      | cons b bs => rw [hp] at hq; cases hb : hbB t f <;> simp [hb, quietB] at hq
  · rw [ho] at hq; simp [quietB] at hq

/-- Ends only grow: an end at $t$ stays an end at every later time.

$$\forall t, t', f, b:\quad t \le t' \wedge \operatorname{END}(t, f, b) \Rightarrow \operatorname{END}(t', f, b)$$
-/
theorem endedB_mono (t t' : Nat) (f : Facts) (b : String) (htt : t ≤ t') (h : endedB t f b = true) :
    endedB t' f b = true := by
  simp only [endedB, List.any_eq_true, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at h ⊢
  obtain ⟨e, he, hb, ht⟩ := h
  exact ⟨e, he, hb, by omega⟩

/-- Adding an end keeps every old end.

$$\forall e, t, f, b:\quad \operatorname{END}(t, f, b) \Rightarrow \operatorname{END}(t, \operatorname{addEnd}(e, f), b)$$
-/
theorem endedB_addEnd (e : EndEv) (t : Nat) (f : Facts) (b : String) (h : endedB t f b = true) :
    endedB t (addEnd e f) b = true := by
  simp only [endedB, addEnd, List.any_append, Bool.or_eq_true] at h ⊢
  exact .inl h

/-- Adding an end only removes pending ids.

$$\forall e, t, f, b:\quad b \in \operatorname{PEND}(t, \operatorname{addEnd}(e, f)) \Rightarrow b \in \operatorname{PEND}(t, f)$$
-/
theorem pend_addEnd (e : EndEv) (t : Nat) (f : Facts) (b : String) (h : b ∈ pend t (addEnd e f)) :
    b ∈ pend t f := by
  simp only [pend, List.mem_filter, Bool.not_eq_true'] at h ⊢
  refine ⟨h.1, ?_⟩
  cases hc : endedB t f b
  · rfl
  · have := endedB_addEnd e t f b hc
    rw [h.2] at this
    exact absurd this (by simp)

/-- A list whose members all lie in the empty list is empty.

$$\forall \ell:\quad (\forall b \in \ell.\ b \in [\,]) \Rightarrow \ell = [\,]$$
-/
theorem nil_of_sub_nil (l : List String) (h : ∀ b ∈ l, b ∈ ([] : List String)) : l = [] := by
  cases l with
  | nil => rfl
  | cons b _ => exact absurd (h b (by simp)) (by simp)

/-- **Monotone in END.** If the agent is done, finished or idle at $t$, adding any end event leaves its state
unchanged: an end never moves it back to held, waiting or hung.

$$\forall p, t, f, e:\quad \operatorname{quiet}(\operatorname{classify}(p, t, f)) \Rightarrow \operatorname{classify}(p, t, \operatorname{addEnd}(e, f)) = \operatorname{classify}(p, t, f)$$
-/
theorem classify_quiet_addEnd (p : Params) (t : Nat) (f : Facts) (e : EndEv)
    (hq : quietB (classify p t f) = true) : classify p t (addEnd e f) = classify p t f := by
  obtain ⟨hc, hP⟩ := closed_nil_of_quiet p t f hq
  have hP' : pend t (addEnd e f) = [] :=
    nil_of_sub_nil _ fun b hb' => hP ▸ pend_addEnd e t f b hb'
  have hH : hungIds p t f = [] := by simp [hungIds, hP]
  have hH' : hungIds p t (addEnd e f) = [] := by simp [hungIds, hP']
  have ho : openB t (addEnd e f) = openB t f := rfl
  have hb : hbB t (addEnd e f) = hbB t f := rfl
  have hn : finNoticeB t (addEnd e f) = finNoticeB t f := rfl
  unfold classify rule
  rw [ho, hb, hn, hH, hH', hP, hP']

/-- **`meta.finished` is never read**: changing the recorded `meta.finished` times changes no state.

$$\forall p, t, f, M:\quad \operatorname{classify}(p, t, f[M := M]) = \operatorname{classify}(p, t, f)$$
-/
theorem classify_metaFinished (p : Params) (t : Nat) (f : Facts) (m : List Nat) :
    classify p t { f with metaFinished := m } = classify p t f := rfl

/-! ## Examples -/

-- open turn → working; closed, a pending id, no handback → waiting; with handback → held
#guard classify {} 5 { agent := "a", bounds := [⟨0, true⟩] } == .working
#guard classify {} 5 { agent := "a", bounds := [⟨0, true⟩, ⟨4, false⟩], launched := [⟨"b1", 1⟩] } == .waitingOwnBg ["b1"]
#guard classify {} 5 { agent := "a", bounds := [⟨0, true⟩, ⟨4, false⟩], launched := [⟨"b1", 1⟩], handbacks := [4] }
  == .handedBackHeld ["b1"]
-- the end arrives → done; a 'finished' notice → finished; no handback → idle
#guard classify {} 5 { agent := "a", bounds := [⟨0, true⟩, ⟨4, false⟩], launched := [⟨"b1", 1⟩], handbacks := [4],
                       ends := [⟨"b1", 5, .killed⟩] } == .handedBackDone
#guard classify {} 5 { agent := "a", bounds := [⟨0, true⟩, ⟨4, false⟩], handbacks := [4], notices := [⟨4, true⟩] }
  == .finished
#guard classify {} 5 { agent := "a", bounds := [⟨0, true⟩, ⟨4, false⟩] } == .idle
-- hung: pending 31 > 30 with a stdin reader; 30 is not enough; a process of kind other never hangs
#guard classify {} 32 { agent := "a", bounds := [⟨0, true⟩, ⟨2, false⟩], launched := [⟨"b1", 1⟩],
                        procs := [⟨"b1", 9, .stdin⟩] } == .hung "b1"
#guard classify {} 31 { agent := "a", bounds := [⟨0, true⟩, ⟨2, false⟩], launched := [⟨"b1", 1⟩],
                        procs := [⟨"b1", 9, .stdin⟩] } == .waitingOwnBg ["b1"]
#guard classify {} 99 { agent := "a", bounds := [⟨0, true⟩, ⟨2, false⟩], launched := [⟨"b1", 1⟩],
                        procs := [⟨"b1", 9, .other⟩] } == .waitingOwnBg ["b1"]
-- boundaries at the same time: file order decides (the later one wins)
#guard classify {} 4 { agent := "a", bounds := [⟨0, true⟩, ⟨4, false⟩, ⟨4, true⟩] } == .working
-- before the first record: no boundary, closed, nothing pending → idle
#guard classify {} 0 { agent := "a", bounds := [⟨3, true⟩] } == .idle

/-! ## The 8 real timelines (research note part B; golden `packages/contracts/golden/obs/signals.jsonl`)

Times are seconds since 2026-10-17 23:00 +07:00 (`hms h m s`: clock time `h:m:s` on 2026-10-18; `hms 23 m s` is the
evening before). Seconds, not minutes, because several windows in the note are shorter than a minute (the
proof-morph-panel wait 3:24:00-3:24:05). The facts were read from the transcripts by the collector's extractor
(`signalsOf`, `withLeadNotes`, the `[exited with code N]` markers); agent ids are cut to 7 characters, the live
processes are those the note names, and `metaFinished` lists every closing boundary (what `meta.finished` would have
said). -/

/-- Seconds since 2026-10-17 23:00 +07:00 for the clock time $h{:}m{:}s$ (hour 23 is the evening before).

$$\operatorname{hms}(h, m, s) = 3600\,((h + 1) \bmod 24) + 60\,m + s$$
-/
def hms (h m s : Nat) : Nat := 3600 * ((h + 1) % 24) + 60 * m + s

/-- The golden parameters: an id is hung after 30 minutes, i.e. 1800 seconds.

$$P_{\mathrm{gold}} = (\mathit{hungAfter} := 1800)$$
-/
def goldenParams : Params := { hungAfter := 1800 }

/-- A golden checkpoint: time, the note's expected rule state, and the expected classification.

$$c = (t, s_{\mathrm{rule}}, s) \in \mathbb N \times \mathcal S^2$$
-/
structure Check where
  t     : Nat
  rule  : State
  state : State
deriving DecidableEq, Repr

/-- A golden timeline: name, facts, checkpoints.

$$\tau = (\mathit{name}, f, C)$$
-/
structure Timeline where
  name   : String
  facts  : Facts
  checks : List Check
deriving DecidableEq, Repr


/-- Golden timeline `port-nav` (research note part B): its facts and checkpoints.

$$\tau_{\mathrm{portNav}} = (\texttt{port-nav}, f, C)$$
-/
def portNav : Timeline where
  name := "port-nav"
  facts :=
    { agent := "port-nav"
      launched := [⟨"bh6n4n7sw", hms 0 54 21⟩, ⟨"btxvry2hv", hms 1 15 0⟩]
      ends := [⟨"btxvry2hv", hms 1 21 5, .notified⟩, ⟨"btxvry2hv", hms 1 21 5, .exited 0⟩, ⟨"bh6n4n7sw", hms 4 2 37, .notified⟩, ⟨"bh6n4n7sw", hms 4 2 37, .exited 144⟩]
      bounds := [⟨hms 0 48 1, true⟩, ⟨hms 1 23 27, false⟩]
      handbacks := [hms 1 23 27]
      notices := [⟨hms 1 23 27, false⟩]
      procs := [⟨"bh6n4n7sw", 10476, .stdin⟩]
      metaFinished := [hms 1 23 27] }
  checks :=
    [ ⟨hms 0 50 0, .working, .working⟩,
      ⟨hms 1 0 0, .working, .working⟩,
      ⟨hms 1 23 0, .working, .working⟩,
      ⟨hms 1 23 30, .handedBackHeld ["bh6n4n7sw"], .handedBackHeld ["bh6n4n7sw"]⟩,
      ⟨hms 1 24 30, .handedBackHeld ["bh6n4n7sw"], .hung "bh6n4n7sw"⟩,
      ⟨hms 3 58 0, .handedBackHeld ["bh6n4n7sw"], .hung "bh6n4n7sw"⟩,
      ⟨hms 4 5 0, .handedBackDone, .handedBackDone⟩ ]

/-- Golden timeline `ghb-runner` (research note part B): its facts and checkpoints.

$$\tau_{\mathrm{ghbRunner}} = (\texttt{ghb-runner}, f, C)$$
-/
def ghbRunner : Timeline where
  name := "ghb-runner"
  facts :=
    { agent := "ghb-runner"
      launched := [⟨"boknfh6jg", hms 2 39 31⟩, ⟨"bxy829o5c", hms 2 45 17⟩]
      ends := [⟨"boknfh6jg", hms 2 40 46, .notified⟩, ⟨"boknfh6jg", hms 2 40 46, .exited 0⟩, ⟨"bxy829o5c", hms 3 2 27, .notified⟩, ⟨"bxy829o5c", hms 3 2 27, .exited 144⟩]
      bounds := [⟨hms 2 31 49, true⟩, ⟨hms 2 45 38, false⟩]
      handbacks := [hms 2 45 38]
      notices := [⟨hms 2 45 39, false⟩]
      procs := [⟨"bxy829o5c", 11343, .sleepLoop⟩]
      metaFinished := [hms 2 45 38] }
  checks :=
    [ ⟨hms 2 35 0, .working, .working⟩,
      ⟨hms 2 46 0, .handedBackHeld ["bxy829o5c"], .handedBackHeld ["bxy829o5c"]⟩,
      ⟨hms 3 0 0, .handedBackHeld ["bxy829o5c"], .handedBackHeld ["bxy829o5c"]⟩,
      ⟨hms 3 5 0, .handedBackDone, .handedBackDone⟩ ]

/-- Golden timeline `wktr-ci-lane` (research note part B): its facts and checkpoints.

$$\tau_{\mathrm{wktrCiLane}} = (\texttt{wktr-ci-lane}, f, C)$$
-/
def wktrCiLane : Timeline where
  name := "wktr-ci-lane"
  facts :=
    { agent := "wktr-ci-lane"
      launched := [⟨"bo3l3w42q", hms 23 46 6⟩, ⟨"bnk9xvb62", hms 0 2 17⟩, ⟨"b37xkdhwk", hms 0 12 35⟩, ⟨"bcnhpjdld", hms 0 28 1⟩, ⟨"bsla5ik1n", hms 1 22 19⟩, ⟨"bgkff8phc", hms 1 22 41⟩, ⟨"brr7ydi4e", hms 1 32 35⟩, ⟨"bfx3xiqre", hms 1 37 40⟩, ⟨"b91tnu6nf", hms 1 47 38⟩, ⟨"b7rt996kn", hms 1 58 8⟩, ⟨"biyz06cmr", hms 1 58 47⟩, ⟨"busaq7jf8", hms 2 8 42⟩, ⟨"bodiephr3", hms 2 19 12⟩, ⟨"bmi65i9id", hms 2 20 14⟩, ⟨"b301x7muk", hms 2 30 9⟩, ⟨"betbu6rpd", hms 2 40 43⟩]
      ends := [⟨"bo3l3w42q", hms 23 58 38, .notified⟩, ⟨"bo3l3w42q", hms 23 58 38, .exited 1⟩, ⟨"bnk9xvb62", hms 0 17 2, .notified⟩, ⟨"bnk9xvb62", hms 0 17 2, .exited 0⟩, ⟨"bcnhpjdld", hms 0 31 43, .notified⟩, ⟨"bcnhpjdld", hms 0 31 43, .exited 0⟩, ⟨"bsla5ik1n", hms 1 22 36, .notified⟩, ⟨"bsla5ik1n", hms 1 22 36, .exited 0⟩, ⟨"bgkff8phc", hms 1 32 51, .notified⟩, ⟨"bgkff8phc", hms 1 32 51, .exited 0⟩, ⟨"brr7ydi4e", hms 1 33 5, .notified⟩, ⟨"brr7ydi4e", hms 1 33 5, .exited 0⟩, ⟨"bfx3xiqre", hms 1 47 50, .notified⟩, ⟨"bfx3xiqre", hms 1 47 50, .exited 0⟩, ⟨"b91tnu6nf", hms 1 48 18, .notified⟩, ⟨"b91tnu6nf", hms 1 48 18, .exited 0⟩, ⟨"b7rt996kn", hms 1 58 26, .notified⟩, ⟨"b7rt996kn", hms 1 58 26, .exited 0⟩, ⟨"biyz06cmr", hms 2 8 56, .notified⟩, ⟨"biyz06cmr", hms 2 8 56, .exited 0⟩, ⟨"busaq7jf8", hms 2 9 21, .notified⟩, ⟨"busaq7jf8", hms 2 9 21, .exited 0⟩, ⟨"bodiephr3", hms 2 19 32, .notified⟩, ⟨"bodiephr3", hms 2 19 32, .exited 0⟩, ⟨"bmi65i9id", hms 2 30 23, .notified⟩, ⟨"bmi65i9id", hms 2 30 23, .exited 0⟩, ⟨"b301x7muk", hms 2 30 49, .notified⟩, ⟨"b301x7muk", hms 2 30 49, .exited 0⟩, ⟨"betbu6rpd", hms 2 41 1, .notified⟩, ⟨"betbu6rpd", hms 2 41 1, .exited 0⟩, ⟨"b37xkdhwk", hms 2 57 19, .notified⟩, ⟨"b37xkdhwk", hms 2 57 19, .exited 144⟩]
      bounds := [⟨hms 23 34 56, true⟩, ⟨hms 2 50 37, false⟩, ⟨hms 2 57 19, true⟩, ⟨hms 2 57 23, false⟩]
      handbacks := [hms 2 50 37]
      notices := [⟨hms 2 50 37, false⟩, ⟨hms 2 57 23, true⟩]
      procs := [⟨"b37xkdhwk", 14919, .sleepLoop⟩]
      metaFinished := [hms 2 50 37, hms 2 57 23] }
  checks :=
    [ ⟨hms 1 0 0, .working, .working⟩,
      ⟨hms 2 51 0, .handedBackHeld ["b37xkdhwk"], .hung "b37xkdhwk"⟩,
      ⟨hms 2 57 20, .working, .working⟩,
      ⟨hms 2 58 0, .finished, .finished⟩ ]

/-- Golden timeline `port-platform` (research note part B): its facts and checkpoints.

$$\tau_{\mathrm{portPlatform}} = (\texttt{port-platform}, f, C)$$
-/
def portPlatform : Timeline where
  name := "port-platform"
  facts :=
    { agent := "port-platform"
      launched := [⟨"biu3n8870", hms 1 24 22⟩, ⟨"bllt3toag", hms 1 30 9⟩, ⟨"ba3831u4g", hms 1 42 37⟩, ⟨"bacokdv9j", hms 1 52 45⟩, ⟨"bj5eod011", hms 2 15 24⟩, ⟨"bo3ksfboe", hms 2 37 49⟩, ⟨"bsyg2ztsj", hms 2 47 50⟩, ⟨"bchejj937", hms 2 58 27⟩, ⟨"b1hwqtb0u", hms 3 8 23⟩]
      ends := [⟨"biu3n8870", hms 1 25 45, .notified⟩, ⟨"biu3n8870", hms 1 25 45, .exited 0⟩, ⟨"bllt3toag", hms 1 31 8, .notified⟩, ⟨"bllt3toag", hms 1 31 8, .exited 0⟩, ⟨"ba3831u4g", hms 1 52 46, .notified⟩, ⟨"ba3831u4g", hms 1 52 46, .exited 0⟩, ⟨"bacokdv9j", hms 1 52 55, .notified⟩, ⟨"bacokdv9j", hms 1 52 55, .exited 0⟩, ⟨"bj5eod011", hms 2 17 13, .notified⟩, ⟨"bj5eod011", hms 2 17 13, .exited 0⟩, ⟨"bo3ksfboe", hms 2 37 59, .notified⟩, ⟨"bo3ksfboe", hms 2 37 59, .exited 0⟩, ⟨"bchejj937", hms 2 58 46, .notified⟩, ⟨"bchejj937", hms 2 58 46, .exited 0⟩, ⟨"bsyg2ztsj", hms 3 13 25, .notified⟩, ⟨"bsyg2ztsj", hms 3 13 25, .exited 144⟩, ⟨"b1hwqtb0u", hms 3 45 21, .notified⟩, ⟨"b1hwqtb0u", hms 3 45 21, .exited 144⟩]
      bounds := [⟨hms 0 48 1, true⟩, ⟨hms 3 8 43, false⟩, ⟨hms 3 13 25, true⟩, ⟨hms 3 13 33, false⟩, ⟨hms 3 45 21, true⟩, ⟨hms 3 45 25, false⟩]
      handbacks := [hms 3 8 43]
      notices := [⟨hms 3 8 43, false⟩, ⟨hms 3 13 33, false⟩, ⟨hms 3 45 25, true⟩]
      procs := [⟨"bsyg2ztsj", 65901, .sleepLoop⟩, ⟨"b1hwqtb0u", 71852, .sleepLoop⟩]
      metaFinished := [hms 3 8 43, hms 3 13 33, hms 3 45 25] }
  checks :=
    [ ⟨hms 3 0 0, .working, .working⟩,
      ⟨hms 3 9 0, .handedBackHeld ["bsyg2ztsj", "b1hwqtb0u"], .handedBackHeld ["bsyg2ztsj", "b1hwqtb0u"]⟩,
      ⟨hms 3 13 30, .working, .working⟩,
      ⟨hms 3 14 0, .handedBackHeld ["b1hwqtb0u"], .handedBackHeld ["b1hwqtb0u"]⟩,
      ⟨hms 3 39 0, .handedBackHeld ["b1hwqtb0u"], .hung "b1hwqtb0u"⟩,
      ⟨hms 3 45 23, .working, .working⟩,
      ⟨hms 3 46 0, .finished, .finished⟩ ]

/-- Golden timeline `integrate-ports` (research note part B): its facts and checkpoints.

$$\tau_{\mathrm{integratePorts}} = (\texttt{integrate-ports}, f, C)$$
-/
def integratePorts : Timeline where
  name := "integrate-ports"
  facts :=
    { agent := "integrate-ports"
      launched := [⟨"brrnark6l", hms 2 11 16⟩, ⟨"bwijlczj7", hms 2 36 32⟩, ⟨"bt1wbtdzw", hms 2 58 38⟩, ⟨"bs7nps5z8", hms 3 8 48⟩, ⟨"b3li7m67k", hms 3 18 53⟩, ⟨"b1lq5ond0", hms 3 22 1⟩, ⟨"b2vhxaiq7", hms 3 23 19⟩]
      ends := [⟨"brrnark6l", hms 2 11 37, .notified⟩, ⟨"brrnark6l", hms 2 11 37, .exited 0⟩, ⟨"bwijlczj7", hms 2 36 41, .notified⟩, ⟨"bwijlczj7", hms 2 36 41, .exited 0⟩, ⟨"bt1wbtdzw", hms 2 58 48, .notified⟩, ⟨"bt1wbtdzw", hms 2 58 48, .exited 0⟩, ⟨"bs7nps5z8", hms 3 8 57, .notified⟩, ⟨"bs7nps5z8", hms 3 8 57, .exited 0⟩, ⟨"b3li7m67k", hms 3 19 12, .notified⟩, ⟨"b3li7m67k", hms 3 19 12, .exited 0⟩, ⟨"b1lq5ond0", hms 3 24 22, .notified⟩, ⟨"b1lq5ond0", hms 3 24 22, .exited 0⟩, ⟨"b2vhxaiq7", hms 3 24 25, .notified⟩, ⟨"b2vhxaiq7", hms 3 24 25, .exited 0⟩]
      bounds := [⟨hms 1 26 48, true⟩]
      handbacks := []
      notices := []
      procs := []
      metaFinished := [] }
  checks :=
    [ ⟨hms 2 0 0, .working, .working⟩,
      ⟨hms 3 30 0, .working, .working⟩,
      ⟨hms 3 51 0, .working, .working⟩ ]

/-- Golden timeline `obs-next-lean` (research note part B): its facts and checkpoints.

$$\tau_{\mathrm{obsNextLean}} = (\texttt{obs-next-lean}, f, C)$$
-/
def obsNextLean : Timeline where
  name := "obs-next-lean"
  facts :=
    { agent := "obs-next-lean"
      launched := [⟨"a8526f8", hms 3 29 50⟩]
      ends := [⟨"a8526f8", hms 3 30 31, .notified⟩]
      bounds := [⟨hms 3 3 23, true⟩, ⟨hms 3 32 56, false⟩]
      handbacks := [hms 3 32 56]
      notices := [⟨hms 3 32 56, true⟩]
      procs := []
      metaFinished := [hms 3 32 56] }
  checks :=
    [ ⟨hms 3 10 0, .working, .working⟩,
      ⟨hms 3 33 0, .finished, .finished⟩ ]

/-- Golden timeline `variant-morph-mount-shift` (research note part B): its facts and checkpoints.

$$\tau_{\mathrm{variantMorphMountShift}} = (\texttt{variant-morph-mount-shift}, f, C)$$
-/
def variantMorphMountShift : Timeline where
  name := "variant-morph-mount-shift"
  facts :=
    { agent := "variant-morph-mount-shift"
      launched := [⟨"bmxas8ezt", hms 3 32 48⟩, ⟨"bxu1oyp6p", hms 3 42 27⟩, ⟨"bbl4re6pg", hms 3 51 37⟩]
      ends := [⟨"bmxas8ezt", hms 3 41 49, .notified⟩, ⟨"bmxas8ezt", hms 3 41 49, .exited 0⟩, ⟨"bxu1oyp6p", hms 3 51 29, .notified⟩, ⟨"bxu1oyp6p", hms 3 51 29, .exited 0⟩, ⟨"bbl4re6pg", hms 3 57 33, .notified⟩, ⟨"bbl4re6pg", hms 3 57 33, .exited 0⟩]
      bounds := [⟨hms 3 30 51, true⟩, ⟨hms 3 32 52, false⟩, ⟨hms 3 32 59, true⟩, ⟨hms 3 42 35, false⟩, ⟨hms 3 51 29, true⟩, ⟨hms 3 51 40, false⟩, ⟨hms 3 57 33, true⟩, ⟨hms 3 57 41, false⟩]
      handbacks := [hms 3 32 52]
      notices := [⟨hms 3 32 52, false⟩, ⟨hms 3 42 35, false⟩, ⟨hms 3 51 40, false⟩, ⟨hms 3 57 41, true⟩]
      procs := []
      metaFinished := [hms 3 32 52, hms 3 42 35, hms 3 51 40, hms 3 57 41] }
  checks :=
    [ ⟨hms 3 31 0, .working, .working⟩,
      ⟨hms 3 32 55, .handedBackHeld ["bmxas8ezt"], .handedBackHeld ["bmxas8ezt"]⟩,
      ⟨hms 3 35 0, .working, .working⟩,
      ⟨hms 3 45 0, .handedBackHeld ["bxu1oyp6p"], .handedBackHeld ["bxu1oyp6p"]⟩,
      ⟨hms 3 51 35, .working, .working⟩,
      ⟨hms 3 52 0, .handedBackHeld ["bbl4re6pg"], .handedBackHeld ["bbl4re6pg"]⟩,
      ⟨hms 3 57 35, .working, .working⟩,
      ⟨hms 3 58 0, .finished, .finished⟩ ]

/-- Golden timeline `proof-morph-panel` (research note part B): its facts and checkpoints.

$$\tau_{\mathrm{proofMorphPanel}} = (\texttt{proof-morph-panel}, f, C)$$
-/
def proofMorphPanel : Timeline where
  name := "proof-morph-panel"
  facts :=
    { agent := "proof-morph-panel"
      launched := [⟨"bn2yh3tk6", hms 3 23 19⟩, ⟨"a0481ef", hms 3 23 27⟩]
      ends := [⟨"a0481ef", hms 3 24 5, .notified⟩, ⟨"bn2yh3tk6", hms 3 24 23, .notified⟩, ⟨"bn2yh3tk6", hms 3 24 23, .exited 0⟩]
      bounds := [⟨hms 2 54 21, true⟩, ⟨hms 3 24 0, false⟩, ⟨hms 3 24 5, true⟩, ⟨hms 3 24 48, false⟩]
      handbacks := [hms 3 24 48]
      notices := [⟨hms 3 24 48, true⟩]
      procs := []
      metaFinished := [hms 3 24 0, hms 3 24 48] }
  checks :=
    [ ⟨hms 3 0 0, .working, .working⟩,
      ⟨hms 3 24 2, .waitingOwnBg ["bn2yh3tk6", "a0481ef"], .waitingOwnBg ["bn2yh3tk6", "a0481ef"]⟩,
      ⟨hms 3 24 10, .working, .working⟩,
      ⟨hms 3 25 0, .finished, .finished⟩ ]


/-- The 8 golden timelines, in the note's order.

$$G = [\tau_{\mathrm{portNav}}, \tau_{\mathrm{ghbRunner}}, \tau_{\mathrm{wktrCiLane}}, \tau_{\mathrm{portPlatform}},
\tau_{\mathrm{integratePorts}}, \tau_{\mathrm{obsNextLean}}, \tau_{\mathrm{variantMorphMountShift}},
\tau_{\mathrm{proofMorphPanel}}]$$
-/
def golden : List Timeline :=
  [portNav, ghbRunner, wktrCiLane, portPlatform, integratePorts, obsNextLean, variantMorphMountShift, proofMorphPanel]

/-- A timeline reproduces when, at every checkpoint, the rule gives the note's rule state and the classification
(with the golden parameters) gives the expected state.

$$\operatorname{ok}(\tau) \iff \forall c \in C_\tau,\ \operatorname{rule}(c.t, f_\tau) = c.s_{\mathrm{rule}} \wedge
\operatorname{classify}(P_{\mathrm{gold}}, c.t, f_\tau) = c.s$$
-/
def Timeline.ok (τ : Timeline) : Bool :=
  τ.checks.all fun c => rule c.t τ.facts == c.rule && classify goldenParams c.t τ.facts == c.state

/-- **The golden reproduces**: all 8 real timelines give the note's states at every checkpoint, including
port-nav `hung(bh6n4n7sw)` after 30 minutes. `classify` never reads `meta.finished`
(`classify_metaFinished`), so this is the classification without it.

$$\forall \tau \in G,\ \operatorname{ok}(\tau)$$
-/
theorem golden_ok : golden.all Timeline.ok = true := by decide +kernel

/-- The naive reading the incident replaced: an agent counts as done once any `meta.finished` time is at or before
$t$.

$$\operatorname{naiveDone}(t, f) \iff \exists m \in f.\mathit{metaFinished},\ m \le t$$
-/
def naiveDone (t : Nat) (f : Facts) : Bool := f.metaFinished.any (· ≤ t)

/-- The checkpoints where the naive `meta.finished` reading says done but the classification is not quiet (held,
waiting, working or hung), as (timeline, time) pairs.

$$\operatorname{wrong}(G) = [(\tau.\mathit{name}, c.t) \mid \tau \in G,\ c \in C_\tau,\
\operatorname{naiveDone}(c.t, f_\tau) \wedge \neg\operatorname{quiet}(\operatorname{classify}(P_{\mathrm{gold}}, c.t,
f_\tau))]$$
-/
def naiveWrong (g : List Timeline) : List (String × Nat) :=
  g.flatMap fun τ => (τ.checks.filter fun c =>
    naiveDone c.t τ.facts && !quietB (classify goldenParams c.t τ.facts)).map fun c => (τ.name, c.t)

-- `meta.finished` would have called 20 of the 39 checkpoints done while the agent was working again (resumed), held, waited or hung.
#guard (naiveWrong golden).length == 20
-- port-nav: held, then hung, while `meta.finished` already said done.
#guard (naiveWrong [portNav]).map (·.2) == [hms 1 23 30, hms 1 24 30, hms 3 58 0]
#guard golden.length == 8 && (golden.map (·.checks.length)).sum == 39


end Fw.Obs.Signals
