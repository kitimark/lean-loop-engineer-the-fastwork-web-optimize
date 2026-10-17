/-!
# Console projection: State × Event → State (scratch for note 10/02)

The console's every view is a pure function of the event log:
  `project log = log.foldl apply init`.
Agents never write State; they can only cause events, and the reducer decides.

Lean core only (no Mathlib). Builds with `lean Console.lean` on 4.35.0.
-/
namespace Fw.Console

/-- Who caused an event. console-api stamps this from the channel the event came in on
(hook endpoint, git hook, CLI socket, console-web session); the producer cannot choose it. -/
inductive Actor where
  | user | lead | owner | reviewer | script | git | hook
deriving Repr, DecidableEq

/-- Experiment card evidence. Evidence is keyed by the build commit (`head`), so a new
build automatically voids older screen/review/device evidence. -/
structure Card where
  id          : String
  owner       : String
  needsDevice : Bool
  approved    : Bool := false
  head        : Option String := none
  screenAt    : Option String := none
  reviewAt    : Option String := none
  deviceAt    : Option String := none
  landed      : Bool := false
  lastAt      : Nat := 0
deriving Repr, DecidableEq

inductive StepStatus where
  | waiting | answered | cancelled
deriving Repr, DecidableEq

/-- A console step: something only the user can do (swipe, plug, decide). -/
structure Step where
  id     : String
  card   : String
  status : StepStatus := .waiting
  answer : Option String := none
  lastAt : Nat := 0
deriving Repr, DecidableEq

inductive Body where
  | opened    (card owner : String) (needsDevice : Bool)
  | approved  (card : String)
  | built     (card sha : String)
  | screened  (card sha : String) (pass : Bool)
  | reviewed  (card sha : String) (accept : Bool)
  | swiped    (card sha : String) (better : Bool)
  | landed    (card sha : String)
  | stepPosted    (step card : String)
  | stepAnswered  (step answer : String)
  | stepCancelled (step : String)
deriving Repr, DecidableEq

/-- `ts` is console-api's receive time (ms); `key` is the producer's idempotency key. -/
structure Event where
  key   : String
  ts    : Nat
  actor : Actor
  body  : Body
deriving Repr, DecidableEq

structure State where
  seen     : List String := []
  cards    : List Card := []
  steps    : List Step := []
  rejected : Nat := 0
deriving Repr

/-! ## Authority: which actor may cause which event -/

def may : Actor → Body → Bool
  | .owner,    .opened ..        => true
  | .lead,     .opened ..        => true
  | .user,     .opened ..        => true
  | .lead,     .approved _       => true
  | .user,     .approved _       => true
  | .git,      .built ..         => true
  | .script,   .screened ..      => true
  | .reviewer, .reviewed ..      => true
  | .script,   .swiped ..        => true
  | .git,      .landed ..        => true
  | .script,   .stepPosted ..    => true
  | .owner,    .stepPosted ..    => true
  | .user,     .stepAnswered ..  => true
  | .script,   .stepCancelled _  => true
  | .user,     .stepCancelled _  => true
  | _,         _                 => false

/-! ## The landing rule, as a Boolean the reducer checks -/

def ready (c : Card) : Bool :=
  c.approved && c.head.isSome && decide (c.screenAt = c.head) && decide (c.reviewAt = c.head)
    && (!c.needsDevice || decide (c.deviceAt = c.head))

/-! ## Card and step updates (total; each guard sits inside the update itself) -/

def touch (t : Nat) (c : Card) : Card := { c with lastAt := max c.lastAt t }

def cardStep (t : Nat) : Body → Card → Card
  | .approved _,          c => if c.landed then c else touch t { c with approved := true }
  | .built _ sha,         c => if c.landed then c else
                                 touch t { c with head := some sha, screenAt := none, reviewAt := none,
                                                  deviceAt := none }
  | .screened _ sha pass, c => if c.landed || !pass || c.head != some sha then c
                               else touch t { c with screenAt := some sha }
  | .reviewed _ sha ok,   c => if c.landed || !ok || c.head != some sha then c
                               else touch t { c with reviewAt := some sha }
  | .swiped _ sha better, c => if c.landed || !better || c.head != some sha then c
                               else touch t { c with deviceAt := some sha }
  | .landed _ sha,        c => if c.landed || c.head != some sha || !ready c then c
                               else touch t { c with landed := true }
  | _,                    c => c

def cardOf : Body → Option String
  | .approved c | .built c _ | .screened c _ _ | .reviewed c _ _ | .swiped c _ _ | .landed c _ => some c
  | _ => none

def updCards (t : Nat) (b : Body) (id : String) (cs : List Card) : List Card :=
  cs.map fun c => if c.id = id then cardStep t b c else c

def stepStep (t : Nat) : Body → Step → Step
  | .stepAnswered _ a, s => if s.status = .waiting then { s with status := .answered, answer := some a,
                                                                 lastAt := max s.lastAt t } else s
  | .stepCancelled _,  s => if s.status = .waiting then { s with status := .cancelled,
                                                                 lastAt := max s.lastAt t } else s
  | _,                 s => s

def updSteps (t : Nat) (b : Body) (id : String) (ss : List Step) : List Step :=
  ss.map fun s => if s.id = id then stepStep t b s else s

/-- Validation: `none` = accepted, `some why` = rejected (the state only records the rejection). -/
def check (s : State) (e : Event) : Option String :=
  if !may e.actor e.body then some "actor may not cause this event" else
  match e.body with
  | .opened id _ _ => if s.cards.any (·.id == id) then some "card exists" else none
  | .stepPosted id card =>
      if s.steps.any (·.id == id) then some "step exists"
      else if !(s.cards.any (·.id == card)) then some "no such card" else none
  | .stepAnswered id _ | .stepCancelled id =>
      match s.steps.find? (·.id == id) with
      | none => some "no such step"
      | some st => if st.status = .waiting then none else some "step already closed"
  | b => match cardOf b with
      | none => none
      | some id => match s.cards.find? (·.id == id) with
          | none => some "no such card"
          | some c => if cardStep e.ts b c = c then some "no change (gate not met or stale sha)" else none

def accept (s : State) (e : Event) : State :=
  match e.body with
  | .opened id owner dev => { s with cards := s.cards ++ [{ id, owner, needsDevice := dev, lastAt := e.ts }] }
  | .stepPosted id card  => { s with steps := s.steps ++ [{ id, card, lastAt := e.ts }] }
  | .stepAnswered id _ | .stepCancelled id => { s with steps := updSteps e.ts e.body id s.steps }
  | b => match cardOf b with
      | some id => { s with cards := updCards e.ts b id s.cards }
      | none => s

/-- The reducer. A duplicate key is a no-op; a rejected event changes nothing but the counter. -/
def apply (s : State) (e : Event) : State :=
  if e.key ∈ s.seen then s
  else
    let s' := match check s e with
      | none   => accept s e
      | some _ => { s with rejected := s.rejected + 1 }
    { s' with seen := e.key :: s'.seen }

def project (log : List Event) : State := log.foldl apply {}

/-! ## Derived views (nobody writes these) -/

inductive Stage where
  | question | build | screen | review | device | landReady | land
deriving Repr, DecidableEq

def stage (c : Card) : Stage :=
  if c.landed then .land
  else if !c.approved then .question
  else if c.head.isNone then .build
  else if c.screenAt != c.head then .screen
  else if c.reviewAt != c.head then .review
  else if c.needsDevice && c.deviceAt != c.head then .device
  else .landReady

def needsYou (s : State) (card : String) : Bool :=
  s.steps.any fun st => st.card == card && st.status == .waiting

def stale (limit now : Nat) (c : Card) : Bool := decide (limit ≤ now - c.lastAt)

/-! ## Theorems -/

/-- Duplicate delivery is harmless: an event whose key was seen changes nothing. -/
theorem apply_seen {s : State} {e : Event} (h : e.key ∈ s.seen) : apply s e = s := by
  simp [apply, h]

theorem key_mem_apply (s : State) (e : Event) : e.key ∈ (apply s e).seen := by
  unfold apply
  split
  · assumption
  · simp

/-- Idempotency: applying the same event twice equals applying it once. -/
theorem apply_idem (s : State) (e : Event) : apply (apply s e) e = apply s e :=
  apply_seen (key_mem_apply s e)

theorem accept_seen (s : State) (e : Event) : (accept s e).seen = s.seen := by
  unfold accept; split <;> try rfl
  split <;> rfl

theorem seen_mono (s : State) (e : Event) {k : String} (h : k ∈ s.seen) : k ∈ (apply s e).seen := by
  unfold apply
  split
  · exact h
  · simp only [List.mem_cons]; right
    split
    · rw [accept_seen]; exact h
    · exact h

theorem seen_mono_foldl (l : List Event) (s : State) {k : String} (h : k ∈ s.seen) :
    k ∈ (l.foldl apply s).seen := by
  induction l generalizing s with
  | nil => exact h
  | cons e l ih => exact ih _ (seen_mono s e h)

theorem keys_seen (l : List Event) (s : State) : ∀ e ∈ l, e.key ∈ (l.foldl apply s).seen := by
  induction l generalizing s with
  | nil => simp
  | cons e l ih =>
    intro x hx
    simp only [List.mem_cons] at hx
    rcases hx with rfl | hx
    · exact seen_mono_foldl l _ (key_mem_apply s x)
    · exact ih _ x hx

/-- Replaying a log with a re-delivered event appended gives the same state. -/
theorem project_redeliver (l : List Event) (e : Event) (h : e ∈ l) :
    project (l ++ [e]) = project l := by
  simp only [project, List.foldl_append, List.foldl_cons, List.foldl_nil]
  exact apply_seen (keys_seen l {} e h)

/-- Rejection: a rejected event leaves every card and step as it was. -/
theorem reject_keeps {s : State} {e : Event} {why : String} (h : check s e = some why) :
    (apply s e).cards = s.cards ∧ (apply s e).steps = s.steps := by
  unfold apply
  split
  · exact ⟨rfl, rfl⟩
  · simp [h]

/-- Authority: an event its actor may not cause is always rejected. -/
theorem unauthorized_rejected {s : State} {e : Event} (h : may e.actor e.body = false) :
    check s e = some "actor may not cause this event" := by
  simp [check, h]

/-- Only you answer steps: an answer from any other actor changes no card and no step. -/
theorem only_user_answers {s : State} {e : Event} {id a : String}
    (hb : e.body = .stepAnswered id a) (ha : e.actor ≠ .user) :
    (apply s e).cards = s.cards ∧ (apply s e).steps = s.steps := by
  have : may e.actor e.body = false := by
    rw [hb]; cases h : e.actor <;> simp_all [may]
  exact reject_keeps (unauthorized_rejected this)

/-- Snapshots are sound: resuming from a snapshot of a prefix equals replaying the whole log. -/
theorem project_append (l₁ l₂ : List Event) : project (l₁ ++ l₂) = l₂.foldl apply (project l₁) := by
  simp [project, List.foldl_append]

/-- A step is answered at most once: an answer or cancel for a closed step changes nothing. -/
theorem answer_once {s : State} {e : Event} {id a : String} {st : Step}
    (hf : s.steps.find? (·.id == id) = some st) (hs : st.status ≠ .waiting)
    (hb : e.body = .stepAnswered id a) :
    (apply s e).cards = s.cards ∧ (apply s e).steps = s.steps := by
  apply reject_keeps (why := if may e.actor e.body then "step already closed"
                              else "actor may not cause this event")
  unfold check
  cases hm : may e.actor e.body <;> simp [hb, hf, hs] at hm ⊢ <;> simp [hm]

/-! ### The landing invariant: every landed card had all its evidence at its landed commit -/

def Inv (s : State) : Prop := ∀ c ∈ s.cards, c.landed = true → ready c = true

theorem ready_touch (t : Nat) (c : Card) : ready (touch t c) = ready c := rfl

theorem cardStep_inv (t : Nat) (b : Body) (c : Card) (h : c.landed = true → ready c = true) :
    (cardStep t b c).landed = true → ready (cardStep t b c) = true := by
  cases b <;> simp only [cardStep] <;> (try exact h) <;> (repeat' split) <;> simp_all [touch, ready]
    <;> (cases hd : c.needsDevice <;> simp_all)

theorem inv_init : Inv {} := by simp [Inv]

theorem accept_inv {s : State} (e : Event) (h : Inv s) : Inv (accept s e) := by
  unfold accept
  split
  · intro c hc; simp only [List.mem_append, List.mem_singleton] at hc
    rcases hc with hc | rfl
    · exact h c hc
    · simp
  · exact h
  · exact h
  · exact h
  · split
    · intro c hc
      simp only [updCards, List.mem_map] at hc
      obtain ⟨c0, hc0, rfl⟩ := hc
      split
      · exact cardStep_inv _ _ _ (h c0 hc0)
      · exact h c0 hc0
    · exact h

theorem apply_inv {s : State} (e : Event) (h : Inv s) : Inv (apply s e) := by
  unfold apply
  split
  · exact h
  · split
    · exact accept_inv e h
    · exact h

/-- Every state replayed from any log satisfies the landing rule. -/
theorem project_inv (l : List Event) : Inv (project l) := by
  suffices ∀ s, Inv s → Inv (l.foldl apply s) from this _ inv_init
  induction l with
  | nil => intro s h; exact h
  | cons e l ih => intro s h; exact ih _ (apply_inv e h)

/-- Landing requires: approved, screen passed, review accepted, device verdict if needed,
all at the landed commit. -/
theorem land_requires (l : List Event) (c : Card) (hc : c ∈ (project l).cards) (hl : c.landed = true) :
    c.approved = true ∧ c.head.isSome = true ∧ c.screenAt = c.head ∧ c.reviewAt = c.head ∧
      (c.needsDevice = false ∨ c.deviceAt = c.head) := by
  have := project_inv l c hc hl
  simp [ready] at this
  obtain ⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩ := this
  refine ⟨h1, by simpa using h2, h3, h4, ?_⟩
  cases hd : c.needsDevice <;> simp_all

/-- Staleness grows with time: once stale, a row stays stale until a new event touches it. -/
theorem stale_mono {limit now now' : Nat} {c : Card} (h : now ≤ now') (hs : stale limit now c = true) :
    stale limit now' c = true := by
  simp [stale] at *; omega

/-- Event age never runs backwards: `lastAt` only grows, whatever clock a producer has. -/
theorem lastAt_mono (t : Nat) (b : Body) (c : Card) : c.lastAt ≤ (cardStep t b c).lastAt := by
  cases b <;> simp only [cardStep] <;> (repeat' split) <;> simp [touch] <;> omega

/-! ## Examples run at build time -/

def ev (k : String) (t : Nat) (a : Actor) (b : Body) : Event := ⟨k, t, a, b⟩

def demo : List Event := [
  ev "o1" 1 .owner (.opened "exp-a" "exp-a" false),
  ev "a1" 2 .lead (.approved "exp-a"),
  ev "b1" 3 .git (.built "exp-a" "s1"),
  ev "x1" 4 .script (.screened "exp-a" "s1" true),
  ev "r1" 5 .reviewer (.reviewed "exp-a" "s1" true)]

#guard (project demo).cards.map stage == [.landReady]
-- an agent claiming a screen pass is rejected:
#guard (project (demo ++ [ev "x2" 6 .owner (.screened "exp-a" "s1" true)])).rejected == 1
-- a rebuild voids the evidence; landing the old sha is rejected:
#guard (project (demo ++ [ev "b2" 6 .git (.built "exp-a" "s2"), ev "l1" 7 .git (.landed "exp-a" "s1")])).cards.map stage
        == [.screen]
-- duplicate delivery changes nothing:
#guard (project (demo ++ demo)).cards.map stage == [.landReady]
#guard (project (demo ++ demo)).rejected == 0

end Fw.Console
