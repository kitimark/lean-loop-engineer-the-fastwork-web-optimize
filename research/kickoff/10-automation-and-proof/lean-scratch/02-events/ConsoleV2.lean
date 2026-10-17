/-!
# Console reducer v2 (scratch; fixes from the 2026-10-17 verification of note 10/02)

Differences from `Console.lean`:
1. A key is marked seen **only when the event is accepted**. A rejected event leaves the state
   exactly as it was, so a fact that arrived too early is applied when the reconciler re-sends it
   with the same key (the "out-of-order facts never converge" bug).
2. Landing is split. `landRequested` is a *decision* (lead or user), accepted only when `ready`.
   `landed` is an observed git *fact* and is never refused for a known card: if it arrives without
   an accepted request for that sha, the card is marked landed **and** `violation` is set.
3. A review carries `signedBy` (an agent identity, verified outside Lean), and is refused when the
   signer owns the card or built any commit on it.
4. `stale` exempts rows with a live wait.

Lean core only. `lean ConsoleV2.lean` on 4.35.0.
-/
namespace Fw.Console2

inductive Actor where
  | user | lead | owner | reviewer | script | git | hook
deriving Repr, DecidableEq

structure Card where
  id          : String
  owner       : String
  needsDevice : Bool
  approved    : Bool := false
  head        : Option String := none
  builders    : List String := []
  screenAt    : Option String := none
  reviewAt    : Option String := none
  reviewedBy  : Option String := none
  deviceAt    : Option String := none
  landReq     : Option String := none
  landed      : Bool := false
  violation   : Bool := false
  lastAt      : Nat := 0
deriving Repr, DecidableEq

inductive StepStatus where
  | waiting | answered | cancelled
deriving Repr, DecidableEq

structure Step where
  id     : String
  card   : String
  status : StepStatus := .waiting
  answer : Option String := none
  lastAt : Nat := 0
deriving Repr, DecidableEq

inductive Body where
  | opened        (card owner : String) (needsDevice : Bool)
  | approved      (card : String)
  | built         (card sha agent : String)
  | screened      (card sha : String) (pass : Bool)
  | reviewed      (card sha signedBy : String) (accept : Bool)
  | swiped        (card sha : String) (better : Bool)
  | landRequested (card sha : String)
  | landed        (card sha : String)
  | stepPosted    (step card : String)
  | stepAnswered  (step answer : String)
  | stepCancelled (step : String)
deriving Repr, DecidableEq

structure Event where
  key   : String
  ts    : Nat
  actor : Actor
  body  : Body
deriving Repr, DecidableEq

structure State where
  seen  : List String := []
  cards : List Card := []
  steps : List Step := []
deriving Repr

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
  | .lead,     .landRequested .. => true
  | .user,     .landRequested .. => true
  | .git,      .landed ..        => true
  | .script,   .stepPosted ..    => true
  | .owner,    .stepPosted ..    => true
  | .user,     .stepAnswered ..  => true
  | .script,   .stepCancelled _  => true
  | .user,     .stepCancelled _  => true
  | _,         _                 => false

def ready (c : Card) : Bool :=
  c.approved && c.head.isSome && decide (c.screenAt = c.head) && decide (c.reviewAt = c.head)
    && (!c.needsDevice || decide (c.deviceAt = c.head))

def touch (t : Nat) (c : Card) : Card := { c with lastAt := max c.lastAt t }

def cardStep (t : Nat) : Body → Card → Card
  | .approved _,          c => if c.landed then c else touch t { c with approved := true }
  | .built _ sha a,       c => if c.landed then c else
      touch t { c with head := some sha, builders := a :: c.builders, screenAt := none,
                       reviewAt := none, reviewedBy := none, deviceAt := none, landReq := none }
  | .screened _ sha pass, c => if c.landed || !pass || c.head != some sha then c
                               else touch t { c with screenAt := some sha }
  | .reviewed _ sha r ok, c => if c.landed || !ok || c.head != some sha || r == c.owner
                                  || c.builders.contains r then c
                               else touch t { c with reviewAt := some sha, reviewedBy := some r }
  | .swiped _ sha better, c => if c.landed || !better || c.head != some sha then c
                               else touch t { c with deviceAt := some sha }
  | .landRequested _ sha, c => if c.landed || c.head != some sha || !ready c then c
                               else touch t { c with landReq := some sha }
  | .landed _ sha,        c => if c.landed then c
                               else touch t { c with landed := true,
                                                     violation := !(c.landReq == some sha && ready c) }
  | _,                    c => c

def cardOf : Body → Option String
  | .approved c | .built c _ _ | .screened c _ _ | .reviewed c _ _ _ | .swiped c _ _
  | .landRequested c _ | .landed c _ => some c
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

/-- `none` = accepted. A `landed` fact for a known card is never refused. -/
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
  | .landed id _ => if s.cards.any (·.id == id) then none else some "no such card"
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

/-- The reducer. Seen key: no-op. Rejected: no-op (the rejection is logged by console-api,
not stored in the state). Accepted: apply and remember the key. -/
def apply (s : State) (e : Event) : State :=
  if e.key ∈ s.seen then s
  else match check s e with
    | none   => { accept s e with seen := e.key :: s.seen }
    | some _ => s

def project (log : List Event) : State := log.foldl apply {}

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

/-- Stale: no live wait on the row, and no event for at least `lim` ms. `lim` is the limit
frozen when the card entered its current stage. -/
def stale (lim now liveWaits : Nat) (c : Card) : Bool :=
  liveWaits == 0 && decide (lim ≤ now - c.lastAt)

/-! ## Theorems -/

theorem apply_seen {s : State} {e : Event} (h : e.key ∈ s.seen) : apply s e = s := by
  simp [apply, h]

/-- A rejected event changes nothing at all (not even `seen`). -/
theorem reject_keeps {s : State} {e : Event} {why : String} (h : check s e = some why) :
    apply s e = s := by
  unfold apply; split
  · rfl
  · simp [h]

/-- Idempotency: applying the same event twice equals applying it once. -/
theorem apply_idem (s : State) (e : Event) : apply (apply s e) e = apply s e := by
  by_cases hk : e.key ∈ s.seen
  · rw [apply_seen hk, apply_seen hk]
  · cases hc : check s e with
    | some why => rw [reject_keeps hc, reject_keeps hc]
    | none =>
      have : apply s e = { accept s e with seen := e.key :: s.seen } := by simp [apply, hk, hc]
      rw [this]; exact apply_seen (by simp)

theorem unauthorized_rejected {s : State} {e : Event} (h : may e.actor e.body = false) :
    check s e = some "actor may not cause this event" := by
  simp [check, h]

theorem only_user_answers {s : State} {e : Event} {id a : String}
    (hb : e.body = .stepAnswered id a) (ha : e.actor ≠ .user) : apply s e = s := by
  have : may e.actor e.body = false := by
    rw [hb]; cases h : e.actor <;> simp_all [may]
  exact reject_keeps (unauthorized_rejected this)

/-- A git `landed` fact for a known card is never refused. -/
theorem landed_fact_accepted {s : State} {e : Event} {id sha : String}
    (hb : e.body = .landed id sha) (ha : e.actor = .git) (hc : s.cards.any (·.id == id) = true) :
    check s e = none := by
  simp [check, hb, ha, may, hc]

theorem project_append (l₁ l₂ : List Event) : project (l₁ ++ l₂) = l₂.foldl apply (project l₁) := by
  simp [project, List.foldl_append]

/-! ### Card invariant -/

def CardInv (c : Card) : Prop :=
  (c.landed = true → c.violation = false → ready c = true) ∧
  (c.landReq.isSome = true → c.landed = false → ready c = true) ∧
  (∀ r, c.reviewedBy = some r → r ≠ c.owner ∧ r ∉ c.builders)

def Inv (s : State) : Prop := ∀ c ∈ s.cards, CardInv c

theorem cardStep_inv (t : Nat) (b : Body) (c : Card) (h : CardInv c) : CardInv (cardStep t b c) := by
  obtain ⟨h1, h2, h3⟩ := h
  cases b <;> simp only [cardStep] <;> (try exact ⟨h1, h2, h3⟩) <;> (repeat' split) <;>
    (try exact ⟨h1, h2, h3⟩) <;> refine ⟨?_, ?_, ?_⟩ <;> simp_all [touch, ready] <;>
    (try (cases hd : c.needsDevice <;> simp_all)) <;> (try grind)

theorem inv_init : Inv {} := by simp [Inv]

theorem accept_inv {s : State} (e : Event) (h : Inv s) : Inv (accept s e) := by
  unfold accept
  split
  · intro c hc; simp only [List.mem_append, List.mem_singleton] at hc
    rcases hc with hc | rfl
    · exact h c hc
    · simp [CardInv]
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

theorem project_inv (l : List Event) : Inv (project l) := by
  suffices ∀ s, Inv s → Inv (l.foldl apply s) from this _ inv_init
  induction l with
  | nil => intro s h; exact h
  | cons e l ih => intro s h; exact ih _ (apply_inv e h)

/-- A landing without a violation had all its evidence at the landed commit. -/
theorem land_requires (l : List Event) (c : Card) (hc : c ∈ (project l).cards)
    (hl : c.landed = true) (hv : c.violation = false) :
    c.approved = true ∧ c.head.isSome = true ∧ c.screenAt = c.head ∧ c.reviewAt = c.head ∧
      (c.needsDevice = false ∨ c.deviceAt = c.head) := by
  have := (project_inv l c hc).1 hl hv
  simp [ready] at this
  obtain ⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩ := this
  refine ⟨h1, by simpa using h2, h3, h4, ?_⟩
  cases hd : c.needsDevice <;> simp_all

/-- An accepted land request is only ever held by a ready card. -/
theorem landReq_ready (l : List Event) (c : Card) (hc : c ∈ (project l).cards)
    (hr : c.landReq.isSome = true) (hl : c.landed = false) : ready c = true :=
  (project_inv l c hc).2.1 hr hl

/-- Reviews are independent: the recorded reviewer neither owns the card nor built on it. -/
theorem review_independent (l : List Event) (c : Card) (hc : c ∈ (project l).cards) (r : String)
    (hr : c.reviewedBy = some r) : r ≠ c.owner ∧ r ∉ c.builders :=
  (project_inv l c hc).2.2 r hr

/-- A new build resets the stage to `screen` (for an approved, unlanded card). -/
theorem built_resets (t : Nat) (id sha a : String) (c : Card)
    (hl : c.landed = false) (ha : c.approved = true) :
    stage (cardStep t (.built id sha a) c) = .screen := by
  simp [cardStep, hl, touch, stage, ha]

theorem stale_mono {lim now now' w : Nat} {c : Card} (h : now ≤ now')
    (hs : stale lim now w c = true) : stale lim now' w c = true := by
  simp [stale] at *; omega

theorem stale_live {lim now w : Nat} {c : Card} (hw : 0 < w) : stale lim now w c = false := by
  simp [stale]; omega

/-! ## Examples run at build time -/

def ev (k : String) (t : Nat) (a : Actor) (b : Body) : Event := ⟨k, t, a, b⟩

def demo : List Event := [
  ev "o1" 1 .owner (.opened "exp-a" "agent-o" false),
  ev "a1" 2 .lead (.approved "exp-a"),
  ev "b1" 3 .git (.built "exp-a" "s1" "agent-b"),
  ev "x1" 4 .script (.screened "exp-a" "s1" true),
  ev "r1" 5 .reviewer (.reviewed "exp-a" "s1" "agent-r" true)]

#guard (project demo).cards.map stage == [.landReady]
-- out of order: a screen result that arrives before its build is refused, then applied on re-send
def ooo : List Event := [
  ev "o1" 1 .owner (.opened "J" "agent-o" false),
  ev "a1" 2 .lead (.approved "J"),
  ev "job:J:result" 3 .script (.screened "J" "s1" true),
  ev "b1" 4 .git (.built "J" "s1" "agent-b"),
  ev "job:J:result" 5 .script (.screened "J" "s1" true)]
#guard (project ooo).cards.map stage == [.review]
-- a landing on main without an accepted request is recorded as landed + violation
def rogue : List Event := [
  ev "o1" 1 .owner (.opened "K" "agent-o" false),
  ev "b9" 2 .git (.built "K" "s9" "agent-b"),
  ev "l9" 3 .git (.landed "K" "s9")]
#guard (project rogue).cards.map (fun c => (c.landed, c.violation)) == [(true, true)]
-- the normal path: request, then the git fact; no violation
#guard (project (demo ++ [ev "q1" 6 .lead (.landRequested "exp-a" "s1"),
                          ev "l1" 7 .git (.landed "exp-a" "s1")])).cards.map
        (fun c => (c.landed, c.violation)) == [(true, false)]
-- a land request on an unready card is refused
#guard (project (demo.take 4 ++ [ev "q1" 6 .lead (.landRequested "exp-a" "s1")])).cards.map
        (·.landReq) == [none]
-- the builder cannot review its own work, even under the reviewer role
#guard (project (demo.take 4 ++ [ev "r9" 5 .reviewer (.reviewed "exp-a" "s1" "agent-b" true)])).cards.map
        stage == [.review]
-- duplicate delivery changes nothing
#guard (project (demo ++ demo)).cards.map stage == [.landReady]

end Fw.Console2
