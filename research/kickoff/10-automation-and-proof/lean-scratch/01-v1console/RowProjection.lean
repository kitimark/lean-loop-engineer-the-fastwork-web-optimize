/-!
# Status row as a projection of events (scratch for note 10/01, v1 console forensics)

The v1 bug class "board shows a stale or wrong state" (I-145 and 7 more) came from rows
that only an agent could change. Here a row is `fold step init log`. Three properties:

* `close_wins`     : a wait closed by its event is gone, whatever self-reports follow.
* `says_inert`     : a self-report (`say`) never changes a derived field.
* `landed_sticky`  : once a `landed` event is in the log, the row stays landed.
-/
namespace Fw.Row

/-- Derived lifecycle of a row (judgement-free part). -/
inductive Phase where
  | open | measuring | landed
deriving Repr, DecidableEq

/-- Events. `w` names a wait target (step, proposal, lease, review) by a number. -/
inductive Ev where
  | waitOpen  (w : Nat)       -- a step/proposal/lease-queue entry naming this row was created
  | waitClose (w : Nat)       -- that step answered/skipped, proposal decided, lease granted
  | holdStart                 -- a timing/testing hold for this row started
  | holdEnd
  | landed                    -- the row's commit reached main
  | say (note : String)       -- the only free-text input: an agent's note
deriving Repr

structure Row where
  waits : Nat → Bool := fun _ => false
  phase : Phase := .open
  note  : String := ""

def step (r : Row) : Ev → Row
  | .waitOpen w  => { r with waits := fun x => if x = w then true else r.waits x }
  | .waitClose w => { r with waits := fun x => if x = w then false else r.waits x }
  | .holdStart   => if r.phase = .landed then r else { r with phase := .measuring }
  | .holdEnd     => if r.phase = .landed then r else { r with phase := .open }
  | .landed      => { r with phase := .landed }
  | .say n       => { r with note := n }

def project (r : Row) (log : List Ev) : Row := log.foldl step r

def opens (w : Nat) : Ev → Bool
  | .waitOpen v => v == w
  | _ => false

/-- Later events that do not reopen `w` keep it closed. -/
theorem stays_closed (w : Nat) : ∀ (l : List Ev) (r : Row),
    r.waits w = false → (∀ e ∈ l, opens w e = false) → (project r l).waits w = false := by
  intro l
  induction l with
  | nil => intro r h _; simpa [project] using h
  | cons e l ih =>
    intro r h hl
    have he := hl e (by simp)
    have hrest : ∀ e' ∈ l, opens w e' = false := fun e' he' => hl e' (by simp [he'])
    apply ih (step r e) _ hrest
    cases e with
    | waitOpen v =>
      simp [opens] at he
      simp [step]; exact ⟨fun hv => he hv.symm, h⟩
    | waitClose v => simp [step]; intro _; exact h
    | holdStart => simp only [step]; split <;> simp [h]
    | holdEnd => simp only [step]; split <;> simp [h]
    | landed => simp [step, h]
    | say n => simp [step, h]

/-- I-145 as a theorem: once the closing event is logged, the wait is gone,
    whatever self-reports or other events follow (unless the wait is opened again). -/
theorem close_wins (w : Nat) (r : Row) (pre post : List Ev)
    (hpost : ∀ e ∈ post, opens w e = false) :
    (project r (pre ++ Ev.waitClose w :: post)).waits w = false := by
  simp only [project, List.foldl_append, List.foldl_cons]
  exact stays_closed w post _ (by simp [step]) hpost

def isSay : Ev → Bool
  | .say _ => true
  | _ => false

/-- Self-reports are inert on derived fields: waits and phase. -/
theorem says_inert : ∀ (l : List Ev) (r : Row), (∀ e ∈ l, isSay e = true) →
    (project r l).waits = r.waits ∧ (project r l).phase = r.phase := by
  intro l
  induction l with
  | nil => intro r _; simp [project]
  | cons e l ih =>
    intro r hl
    have he := hl e (by simp)
    have hrest : ∀ e' ∈ l, isSay e' = true := fun e' he' => hl e' (by simp [he'])
    cases e with
    | say n => have := ih (step r (.say n)) hrest; simpa [project, step] using this
    | _ => simp [isSay] at he

/-- Landed is sticky: no later event moves a landed row back. -/
theorem landed_stays : ∀ (l : List Ev) (r : Row), r.phase = .landed → (project r l).phase = .landed := by
  intro l
  induction l with
  | nil => intro r h; simpa [project] using h
  | cons e l ih =>
    intro r h
    apply ih
    cases e <;> simp [step, h]

theorem landed_sticky (r : Row) (pre post : List Ev) :
    (project r (pre ++ Ev.landed :: post)).phase = .landed := by
  simp only [project, List.foldl_append, List.foldl_cons]
  exact landed_stays post _ (by simp [step])

end Fw.Row
