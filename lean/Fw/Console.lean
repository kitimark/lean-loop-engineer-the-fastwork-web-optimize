import Fw.Plan.Core
import Fw.Console.ReviewFeedback
/-!
# Console reducer

Ported from the kickoff scratch `02-events/ConsoleV2.lean` and extended to the console-mvp
contract (`packages/contracts`: steps with kinds and start/answer/done/cancel, runs with
start/finish, the `MAY` actor table and the exact refusal reasons), so `fwcore console.apply`
answers the same JSON as the TypeScript stand-in it replaces.

1. A key is marked seen **only when the event is accepted**. A refused event leaves the state
   exactly as it was, so a fact that arrived too early is applied when it is re-sent with the
   same key. A seen key is a no-op reported as a duplicate.
2. Landing is split. `card.land_request` is a *decision* (lead or user), accepted only when
   `ready`. `card.landed` is an observed git *fact*: for a known, unlanded card it is never
   refused; without an accepted request for that sha the card is marked landed **and** `violation`.
3. A review is refused when its signer owns the card or built any commit on it.
4. Every decision is here; console-api only stamps `ts`, appends and forwards.
5. The work graph (`task.define`, `task.drop`, `task.claim`, `task.done`, `milestone.define`) is the
   `plan` part of the state, reduced by `Fw.Plan.check` / `Fw.Plan.exec` (`Fw/Plan/Core.lean`).
-/
namespace Fw.Console

/-- Who caused an event (stamped by console-api, never by the sender). -/
inductive Actor where
  | user | lead | owner | reviewer | script | git | hook
deriving Repr, DecidableEq

/-- The wire name of an actor. -/
def Actor.name : Actor → String
  | .user => "user" | .lead => "lead" | .owner => "owner" | .reviewer => "reviewer"
  | .script => "script" | .git => "git" | .hook => "hook"

/-- The kind of a step (what the user is asked to do). -/
inductive StepKind where
  | action | yes_no | choice | text
deriving Repr, DecidableEq

/-- The kind of a run. -/
inductive RunKind where
  | screen | gate | run | device
deriving Repr, DecidableEq

/-- The status of a step. -/
inductive StepStatus where
  | waiting | started | answered | done | cancelled
deriving Repr, DecidableEq

/-- The wire name of a step status. -/
def StepStatus.name : StepStatus → String
  | .waiting => "waiting" | .started => "started" | .answered => "answered" | .done => "done"
  | .cancelled => "cancelled"

/-- A step is open while it is waiting or started. -/
def StepStatus.isOpen : StepStatus → Bool
  | .waiting | .started => true
  | _ => false

/-- The status of a run. -/
inductive RunStatus where
  | running | passed | failed
deriving Repr, DecidableEq

/-- A card (one experiment row) and the evidence on it, each piece keyed by the commit it is about. -/
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

/-- Whom a step is for: `user` is the console's owner (a device step, an approval, a login, a decision only the
owner can make); `lead` is the lead agent (everything an agent or the lead can fix). The console shows `lead`
steps under the lead's work, not under YOU.
-/
inductive Audience where
  | user | lead
deriving Repr, DecidableEq

/-- The wire name of an audience. -/
def Audience.name : Audience → String
  | .user => "user" | .lead => "lead"

/-- A step: a question or action put to the user (or, by `audience`, to the lead), optionally about a card.
`body` is the plain text under the title (what happened, impact, action, details; empty when the poster gave none);
`answer` also holds the note of an automatic resolution.
-/
structure Step where
  id       : String
  card     : Option String
  title    : String
  kind     : StepKind
  options  : Option (List String)
  status   : StepStatus := .waiting
  answer   : Option String := none
  postedAt : Nat
  lastAt   : Nat
  audience : Audience := .user
  body     : String := ""
deriving Repr, DecidableEq

/-- A run (screen, gate, run or device job) on a card. -/
structure Run where
  id        : String
  card      : String
  kind      : RunKind
  status    : RunStatus := .running
  startedAt : Nat
deriving Repr, DecidableEq

/-- Event bodies (one per command type of the contract). -/
inductive Body where
  | cardOpen        (card owner : String) (needsDevice : Bool)
  | cardApprove     (card : String)
  | cardBuild       (card sha agent : String)
  | cardScreen      (card sha : String) (pass : Bool)
  | cardReview      (card sha signedBy : String) (accept : Bool)
  | cardSwipe       (card sha : String) (better : Bool)
  | cardLandRequest (card sha : String)
  | cardLanded      (card sha : String)
  | stepPost        (step : String) (card : Option String) (title : String) (kind : StepKind)
                    (options : Option (List String)) (audience : Audience := .user) (body : String := "")
  | stepStart       (step : String)
  | stepAnswer      (step answer : String)
  | stepDone        (step : String) (note : Option String := none)
  | stepCancel      (step : String)
  | runStart        (run card : String) (kind : RunKind)
  | runFinish       (run : String) (ok : Bool)
  | reviewPreviewed (flag device : String)
  | reviewFeedback  (flag id text : String)
  | reviewFeedbackReply (flag to text : String)
  | plan            (c : Fw.Plan.Cmd)
deriving Repr, DecidableEq

/-- The 18 card/step/run/review event types and the 7 plan command types (the `type` field on the wire). -/
inductive EvType where
  | cardOpen | cardApprove | cardBuild | cardScreen | cardReview | cardSwipe | cardLandRequest
  | cardLanded | stepPost | stepStart | stepAnswer | stepDone | stepCancel | runStart | runFinish
  | reviewPreviewed | reviewFeedback | reviewFeedbackReply
  | plan (t : Fw.Plan.CmdType)
deriving Repr, DecidableEq

/-- The wire name of an event type. -/
def EvType.name : EvType → String
  | .cardOpen => "card.open" | .cardApprove => "card.approve" | .cardBuild => "card.build"
  | .cardScreen => "card.screen" | .cardReview => "card.review" | .cardSwipe => "card.swipe"
  | .cardLandRequest => "card.land_request" | .cardLanded => "card.landed"
  | .stepPost => "step.post" | .stepStart => "step.start" | .stepAnswer => "step.answer"
  | .stepDone => "step.done" | .stepCancel => "step.cancel" | .runStart => "run.start"
  | .runFinish => "run.finish" | .reviewPreviewed => "review.previewed"
  | .reviewFeedback => "review.feedback" | .reviewFeedbackReply => "review.feedback.reply" | .plan t => t.name

/-- The type of a body. -/
def Body.type : Body → EvType
  | .cardOpen .. => .cardOpen | .cardApprove .. => .cardApprove | .cardBuild .. => .cardBuild
  | .cardScreen .. => .cardScreen | .cardReview .. => .cardReview | .cardSwipe .. => .cardSwipe
  | .cardLandRequest .. => .cardLandRequest | .cardLanded .. => .cardLanded
  | .stepPost .. => .stepPost | .stepStart .. => .stepStart | .stepAnswer .. => .stepAnswer
  | .stepDone .. => .stepDone | .stepCancel .. => .stepCancel | .runStart .. => .runStart
  | .runFinish .. => .runFinish | .reviewPreviewed .. => .reviewPreviewed
  | .reviewFeedback .. => .reviewFeedback | .reviewFeedbackReply .. => .reviewFeedbackReply | .plan c => .plan c.type

/-- An event: an idempotency key, the stamp time (ms, by console-api), the actor and the body. -/
structure Event where
  key   : String
  ts    : Nat
  actor : Actor
  body  : Body
deriving Repr, DecidableEq

/-- The console state: the accepted keys (newest first), the cards, steps and runs (each in
creation order), and the plan (the work graph, `Fw.Plan.State`).
-/
structure State where
  seen  : List String := []
  cards : List Card := []
  steps : List Step := []
  runs  : List Run := []
  plan  : Fw.Plan.State := {}
  fb    : List Fw.Console.ReviewFeedback.Fb := []
deriving Repr, DecidableEq

/-- The authority table (`MAY`): the actors allowed to cause each event type.

Edge: the actor `hook` may cause only `task.claim`, `agent.spawn`, `agent.stop`, `agent.label` and `task.handback` (agent starts, stops and handbacks observed by a hook); only `lead`, `user` and `script` may park or unpark.
-/
def mayList : EvType → List Actor
  | .cardOpen => [.owner, .lead, .user]
  | .cardApprove => [.lead, .user]
  | .cardBuild => [.git]
  | .cardScreen => [.script]
  | .cardReview => [.reviewer]
  | .cardSwipe => [.script]
  | .cardLandRequest => [.lead, .user]
  | .cardLanded => [.git]
  | .stepPost => [.script, .owner, .lead]
  | .stepStart => [.user]
  | .stepAnswer => [.user]
  | .stepDone => [.user, .owner, .script, .lead]
  | .stepCancel => [.script, .user, .lead]
  | .runStart => [.script, .owner, .lead]
  | .runFinish => [.script]
  | .reviewPreviewed => [.user]
  | .reviewFeedback => [.user]
  | .reviewFeedbackReply => [.lead]
  | .plan .define | .plan .drop | .plan .milestone => [.lead, .user, .script]
  | .plan .claim => [.hook, .script, .lead]
  | .plan .done => [.git, .lead, .user]
  | .plan .spawn | .plan .stop | .plan .label | .plan .handback => [.hook, .script, .lead]
  | .plan .integrate => [.git, .script, .lead]
  | .plan .park | .plan .unpark => [.lead, .user, .script]

/-- An actor may cause an event type iff it is in the table. -/
def may (a : Actor) (t : EvType) : Bool := (mayList t).contains a

/-- A card is ready to land: approved, built, and screened, reviewed and (if it needs the device)
swiped, all at its current head.
-/
def ready (c : Card) : Bool :=
  c.approved && c.head.isSome && decide (c.screenAt = c.head) && decide (c.reviewAt = c.head)
    && (!c.needsDevice || decide (c.deviceAt = c.head))

/-- Record activity at time `t` (the last-event time never moves back). -/
def touch (t : Nat) (c : Card) : Card := { c with lastAt := max c.lastAt t }

/-- Why a card event is refused on card `c` (`none` = acceptable). First match wins; with
`L = "card already landed"` and `Σ = "stale sha: not the head commit"`.
-/
def cardRefusal (c : Card) : Body → Option String
  | .cardApprove _ =>
    if c.landed then some "card already landed"
    else if c.approved then some "already approved" else none
  | .cardBuild .. => if c.landed then some "card already landed" else none
  | .cardScreen _ sha pass =>
    if c.landed then some "card already landed"
    else if c.head != some sha then some "stale sha: not the head commit"
    else if pass then none else some "failed screen does not advance the card"
  | .cardReview _ sha r ok =>
    if c.landed then some "card already landed"
    else if c.head != some sha then some "stale sha: not the head commit"
    else if r == c.owner || c.builders.contains r then some "reviewer owns or built this card"
    else if ok then none else some "rejected review does not advance the card"
  | .cardSwipe _ sha better =>
    if c.landed then some "card already landed"
    else if c.head != some sha then some "stale sha: not the head commit"
    else if better then none else some "not better: device evidence not recorded"
  | .cardLandRequest _ sha =>
    if c.landed then some "card already landed"
    else if c.head != some sha then some "stale sha: not the head commit"
    else if ready c then none else some "card is not land-ready"
  | .cardLanded .. => if c.landed then some "card already landed" else none
  | _ => none

/-- The card transition at time `t`: a refused body leaves the card unchanged. -/
def cardStep (t : Nat) (b : Body) (c : Card) : Card :=
  if (cardRefusal c b).isSome then c else
  match b with
  | .cardApprove _ => touch t { c with approved := true }
  | .cardBuild _ sha a =>
    touch t { c with head := some sha, builders := a :: c.builders, screenAt := none,
                     reviewAt := none, reviewedBy := none, deviceAt := none, landReq := none }
  | .cardScreen _ sha _ => touch t { c with screenAt := some sha }
  | .cardReview _ sha r _ => touch t { c with reviewAt := some sha, reviewedBy := some r }
  | .cardSwipe _ sha _ => touch t { c with deviceAt := some sha }
  | .cardLandRequest _ sha => touch t { c with landReq := some sha }
  | .cardLanded _ sha => touch t { c with landed := true, violation := !(c.landReq == some sha && ready c) }
  | _ => c

/-- The card a card body acts on through `cardStep` (none for `cardOpen`, steps and runs). -/
def cardOf : Body → Option String
  | .cardApprove c | .cardBuild c _ _ | .cardScreen c _ _ | .cardReview c _ _ _ | .cardSwipe c _ _
  | .cardLandRequest c _ | .cardLanded c _ => some c
  | _ => none

/-- Apply `f` to every card with the given id. -/
def mapCards (id : String) (f : Card → Card) (cs : List Card) : List Card :=
  cs.map fun c => if c.id = id then f c else c

/-- Apply `f` to every step with the given id, and record activity at `t` on it. -/
def mapSteps (t : Nat) (id : String) (f : Step → Step) (ss : List Step) : List Step :=
  ss.map fun s => if s.id = id then { f s with lastAt := max s.lastAt t } else s

/-- Why a step event is refused on the step `st` it names (`none` = acceptable); first match wins. -/
def stepRefusal (st : Step) (actor : Actor) : Body → Option String
  | .stepStart _ =>
    if st.status = .waiting then none else some s!"step is {st.status.name}, not waiting"
  | .stepCancel _ => if st.status.isOpen then none else some s!"step already {st.status.name}"
  | .stepDone _ _ =>
    if actor = .lead && st.audience ≠ .lead then some "the lead closes only its own lead steps"
    else if st.status = .started then none
    else if (actor = .script || actor = .lead) && st.status = .waiting && st.audience = .lead then none
    else some s!"step is {st.status.name}, only a started step can be done"
  | .stepAnswer _ a =>
    if !st.status.isOpen then some s!"step already {st.status.name}"
    else if st.kind = .action then some "an action step is finished with step.done, not an answer"
    else if st.kind = .yes_no && a != "yes" && a != "no" then some "answer must be yes or no"
    else if st.kind = .choice && !((st.options.getD []).contains a) then
      some "answer is not one of the options"
    else none
  | _ => none

/-- **Only a lead step is closed unstarted by the script**: a `step.done` of the script on a step still waiting is
accepted only when the step is for the lead. A step for the user (a device step, an approval, a decision) stays
open until the owner starts and finishes it.
-/
theorem script_done_waiting_is_lead (st : Step) (id : String) (n : Option String)
    (hw : st.status = .waiting) (h : stepRefusal st .script (.stepDone id n) = none) : st.audience = .lead := by
  simp only [stepRefusal, hw] at h
  by_cases ha : st.audience = .lead
  · exact ha
  · simp [ha] at h

/-- **The lead closes only its own steps**: a `step.done` of the lead is accepted only on a step for the lead (an
override record, a lead note), never on a step for the user, started or not. -/
theorem lead_done_is_lead_step (st : Step) (id : String) (n : Option String)
    (h : stepRefusal st .lead (.stepDone id n) = none) : st.audience = .lead := by
  by_cases ha : st.audience = .lead
  · exact ha
  · simp [stepRefusal, ha] at h

/-- **Only the owner finishes a user step**: no actor other than the user finishes a waiting step for the user. -/
theorem user_step_done_needs_start (st : Step) (id : String) (n : Option String) (a : Actor)
    (hw : st.status = .waiting) (hu : st.audience = .user) : stepRefusal st a (.stepDone id n) ≠ none := by
  by_cases hl : a = .lead <;> simp [stepRefusal, hw, hu, hl]

/-- The device words a `review.previewed` event may carry (`Fw.Console.ReviewPreview.Device.word`). -/
def previewDevices : List String := ["desktop", "phone"]

/-- Why a `review.previewed` event is refused (`none` = acceptable): the device must be one of `previewDevices` and the flag a
key `part:variant`. Whether the review is open is decided before the event is made (`Fw.Console.ReviewPreview.record`). -/
def reviewPreviewedRefusal (flag device : String) : Option String :=
  if !previewDevices.contains device then some "device must be desktop or phone"
  else if !flag.contains ':' then some "flag must be a key part:variant"
  else none

/-- Why an event is refused in state `σ` (`none` = accepted). First match wins; "the step", "the
run" and "the card" are the first ones in their list with that id.

Edge: an absent option list counts as having 0 options.
-/
def check (s : State) (e : Event) : Option String :=
  if !may e.actor e.body.type then some s!"actor {e.actor.name} may not cause {e.body.type.name}" else
  match e.body with
  | .cardOpen id _ _ => if s.cards.any (·.id == id) then some "card exists" else none
  | .stepPost id card _ kind opts _ _ =>
    if s.steps.any (·.id == id) then some "step exists"
    else if (match card with | some c => !(s.cards.any (·.id == c)) | none => false) then some "no such card"
    else if kind = .choice && (opts.getD []).length < 2 then some "choice step needs at least 2 options"
    else none
  | .stepStart id | .stepAnswer id _ | .stepDone id _ | .stepCancel id =>
    match s.steps.find? (·.id == id) with
    | none => some "no such step"
    | some st => stepRefusal st e.actor e.body
  | .runStart r card _ =>
    if !(s.cards.any (·.id == card)) then some "no such card"
    else if s.runs.any (·.id == r) then some "run exists" else none
  | .runFinish r _ =>
    match s.runs.find? (·.id == r) with
    | none => some "no such run"
    | some run => if run.status = .running then none else some "run already finished"
  | .reviewPreviewed flag device => reviewPreviewedRefusal flag device
  | .reviewFeedback flag id text => ReviewFeedback.postRefusal s.fb flag id text
  | .reviewFeedbackReply flag to text => ReviewFeedback.replyRefusal s.fb flag to text
  | .plan c => Fw.Plan.check s.plan c
  | b => match cardOf b with
    | none => none
    | some id => match s.cards.find? (·.id == id) with
      | none => some "no such card"
      | some c => cardRefusal c b

/-- The effect of an accepted event on cards, steps and runs (the seen list is handled by `apply`).
With `t = ts(e)`.
-/
def accept (s : State) (e : Event) : State :=
  let t := e.ts
  match e.body with
  | .cardOpen id owner dev =>
    { s with cards := s.cards ++ [{ id, owner, needsDevice := dev, lastAt := t }] }
  | .stepPost id card title kind opts audience body =>
    { s with steps := s.steps ++ [{ id, card, title, kind, options := opts, postedAt := t, lastAt := t, audience, body }] }
  | .stepStart id => { s with steps := mapSteps t id (fun x => { x with status := .started }) s.steps }
  | .stepAnswer id a =>
    { s with steps := mapSteps t id (fun x => { x with status := .answered, answer := some a }) s.steps }
  | .stepDone id note =>
    { s with steps := mapSteps t id (fun x => { x with status := .done, answer := note.orElse fun _ => x.answer }) s.steps }
  | .stepCancel id => { s with steps := mapSteps t id (fun x => { x with status := .cancelled }) s.steps }
  | .runStart r card kind =>
    { s with cards := mapCards card (touch t) s.cards,
             runs := s.runs ++ [{ id := r, card, kind, startedAt := t }] }
  | .runFinish r ok =>
    match s.runs.find? (·.id == r) with
    | some run =>
      { s with cards := mapCards run.card (touch t) s.cards,
               runs := s.runs.map fun x =>
                 if x.id = r then { x with status := if ok then .passed else .failed } else x }
    | none => s
  | .reviewFeedback flag id text => { s with fb := ReviewFeedback.post s.fb flag id text t }
  | .reviewFeedbackReply flag to text => { s with fb := ReviewFeedback.answer s.fb flag to text t }
  | .plan c => { s with plan := Fw.Plan.exec s.plan c }
  | b => match cardOf b with
    | some id => { s with cards := mapCards id (cardStep t b) s.cards }
    | none => s

/-- What the reducer did with an event: accepted (possibly as a duplicate of a seen key) or
refused with a reason.
-/
inductive Outcome where
  | accepted (duplicate : Bool)
  | refused (reason : String)
deriving Repr, DecidableEq

/-- The reducer step: a seen key is a no-op duplicate; a refused event leaves the state untouched
(its key is **not** marked seen); an accepted event is applied and its key put first in the seen
list.
-/
def step (s : State) (e : Event) : State × Outcome :=
  if s.seen.contains e.key then (s, .accepted true)
  else match check s e with
    | some w => (s, .refused w)
    | none   => ({ accept s e with seen := e.key :: s.seen }, .accepted false)

/-- The state after one event. -/
def apply (s : State) (e : Event) : State := (step s e).1

/-- Replay: the state of a log is the left fold of `apply` from the empty state. -/
def project (log : List Event) : State := log.foldl apply {}

/-- The stage of a card. -/
inductive Stage where
  | question | build | screen | review | device | land_ready | land
deriving Repr, DecidableEq

/-- The stage of a card is computed, never written (first match wins). -/
def stage (c : Card) : Stage :=
  if c.landed then .land
  else if !c.approved then .question
  else if c.head.isNone then .build
  else if c.screenAt != c.head then .screen
  else if c.reviewAt != c.head then .review
  else if c.needsDevice && c.deviceAt != c.head then .device
  else .land_ready

/-- Stale: no live wait on the row, and no event for at least `lim` ms. -/
def stale (lim now liveWaits : Nat) (c : Card) : Bool :=
  liveWaits == 0 && decide (lim ≤ now - c.lastAt)

/-! ## Theorems -/

/-- A seen key is a no-op, reported as a duplicate. -/
theorem step_seen {s : State} {e : Event} (h : e.key ∈ s.seen) : step s e = (s, .accepted true) := by
  simp [step, h]

/-- A refused event changes nothing at all (not even the seen list). -/
theorem refused_keeps {s : State} {e : Event} {w : String} (h : (step s e).2 = .refused w) :
    (step s e).1 = s := by
  revert h
  unfold step
  split
  · intro _; rfl
  · split
    · intro _; rfl
    · intro h; simp at h

/-- A refusal from `check` leaves the state unchanged. -/
theorem reject_keeps {s : State} {e : Event} {why : String} (h : check s e = some why) :
    apply s e = s := by
  unfold apply step; split
  · rfl
  · simp [h]

/-- Idempotency: applying the same event twice equals applying it once (states only; for the
reported outcome see `step_twice`).
-/
theorem apply_idem (s : State) (e : Event) : apply (apply s e) e = apply s e := by
  by_cases hk : e.key ∈ s.seen
  · simp [apply, step, hk]
  · cases hc : check s e with
    | some why => rw [reject_keeps hc, reject_keeps hc]
    | none =>
      have : apply s e = { accept s e with seen := e.key :: s.seen } := by simp [apply, step, hk, hc]
      rw [this]; simp [apply, step]

/-- The second delivery of an event is reported as a duplicate or with the same outcome as the
first (the same refusal; a first duplicate stays a duplicate).
-/
theorem step_twice (s : State) (e : Event) :
    (step (apply s e) e).2 = .accepted true ∨ (step (apply s e) e).2 = (step s e).2 := by
  by_cases hk : e.key ∈ s.seen
  · left; simp [apply, step, hk]
  · cases hc : check s e with
    | some why => right; rw [reject_keeps hc]
    | none =>
      left
      have : apply s e = { accept s e with seen := e.key :: s.seen } := by simp [apply, step, hk, hc]
      rw [this]; simp [step]

/-- Only actors in the `MAY` table get a fresh event accepted. -/
theorem accepted_may {s : State} {e : Event} (h : (step s e).2 = .accepted false) :
    may e.actor e.body.type = true := by
  unfold step at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i hc
      cases hm : may e.actor e.body.type
      · simp [check, hm] at hc
      · rfl

/-- An actor outside the `MAY` table is refused with the table's reason. -/
theorem unauthorized_rejected {s : State} {e : Event} (h : may e.actor e.body.type = false) :
    check s e = some s!"actor {e.actor.name} may not cause {e.body.type.name}" := by
  simp [check, h]

/-- Only the user answers or starts steps: an answer or start from anyone else changes nothing. -/
theorem only_user_answers {s : State} {e : Event}
    (hb : (∃ id a, e.body = .stepAnswer id a) ∨ (∃ id, e.body = .stepStart id))
    (ha : e.actor ≠ .user) : apply s e = s := by
  have : may e.actor e.body.type = false := by
    rcases hb with ⟨id, a, hb⟩ | ⟨id, hb⟩ <;>
      (rw [hb]; cases h : e.actor <;> simp_all [may, mayList, Body.type])
  exact reject_keeps (unauthorized_rejected this)

/-- Only the user records a preview: a `review.previewed` event from any other actor changes nothing. -/
theorem previewed_only_user {s : State} {e : Event} {f d : String}
    (hb : e.body = .reviewPreviewed f d) (ha : e.actor ≠ .user) : apply s e = s := by
  have : may e.actor e.body.type = false := by
    rw [hb]; cases h : e.actor <;> simp_all [may, mayList, Body.type]
  exact reject_keeps (unauthorized_rejected this)

/-- A device word outside `previewDevices` is refused. -/
theorem previewed_refuses_device (s : State) (e : Event) (f d : String) (hb : e.body = .reviewPreviewed f d)
    (ha : e.actor = .user) (hd : d ∉ previewDevices) : check s e = some "device must be desktop or phone" := by
  simp [check, hb, ha, may, mayList, Body.type, reviewPreviewedRefusal, hd]

/-- A well-formed `review.previewed` event from the user is accepted. -/
theorem previewed_accepted (s : State) (e : Event) (f d : String) (hb : e.body = .reviewPreviewed f d)
    (ha : e.actor = .user) (hd : d ∈ previewDevices) (hf : f.contains ':' = true) : check s e = none := by
  simp [check, hb, ha, may, mayList, Body.type, reviewPreviewedRefusal, hd, hf]

/-- An accepted `review.previewed` event changes no card, step, run or plan: the log is its only record. -/
theorem previewed_accept_state (s : State) (e : Event) (f d : String) (hb : e.body = .reviewPreviewed f d) :
    accept s e = s := by
  simp [accept, hb, cardOf]

/-- A git `card.landed` fact for a known card that has not landed is never refused. -/
theorem landed_fact_accepted {s : State} {e : Event} {id sha : String} {c : Card}
    (hb : e.body = .cardLanded id sha) (ha : e.actor = .git)
    (hc : s.cards.find? (·.id == id) = some c) (hl : c.landed = false) :
    check s e = none := by
  simp [check, hb, ha, may, mayList, Body.type, cardOf, hc, cardRefusal, hl]

/-- Snapshot plus tail equals the full replay. -/
theorem project_append (l₁ l₂ : List Event) : project (l₁ ++ l₂) = l₂.foldl apply (project l₁) := by
  simp [project, List.foldl_append]

/-! ### Card invariant -/

/-- The card invariant: a landing without a violation was ready; a pending land request is held
only by a ready card; the recorded reviewer neither owns the card nor built on it.
-/
def CardInv (c : Card) : Prop :=
  (c.landed = true → c.violation = false → ready c = true) ∧
  (c.landReq.isSome = true → c.landed = false → ready c = true) ∧
  (∀ r, c.reviewedBy = some r → r ≠ c.owner ∧ r ∉ c.builders)

/-- The state invariant: every card satisfies `CardInv`. -/
def Inv (s : State) : Prop := ∀ c ∈ s.cards, CardInv c

/-- Touching a card keeps its invariant. -/
theorem touch_inv (t : Nat) (c : Card) (h : CardInv c) : CardInv (touch t c) := h

/-- Every card transition keeps the card invariant. -/
theorem cardStep_inv (t : Nat) (b : Body) (c : Card) (h : CardInv c) : CardInv (cardStep t b c) := by
  unfold cardStep
  split
  · exact h
  · rename_i hr
    obtain ⟨h1, h2, h3⟩ := h
    cases b <;> simp only [cardRefusal] at hr <;> simp only <;>
      (try exact ⟨h1, h2, h3⟩) <;> (repeat' split at hr) <;> (try simp at hr) <;>
      refine ⟨?_, ?_, ?_⟩ <;> simp_all [touch, ready] <;>
      (try (cases hd : c.needsDevice <;> simp_all)) <;> (try grind)

/-- Mapping an invariant-keeping function over the cards keeps the state invariant. -/
theorem mapCards_inv {id : String} {f : Card → Card} {cs : List Card}
    (hf : ∀ c, CardInv c → CardInv (f c)) (h : ∀ c ∈ cs, CardInv c) :
    ∀ c ∈ mapCards id f cs, CardInv c := by
  intro c hc
  simp only [mapCards, List.mem_map] at hc
  obtain ⟨c0, hc0, rfl⟩ := hc
  split
  · exact hf c0 (h c0 hc0)
  · exact h c0 hc0

/-- The empty state satisfies the invariant. -/
theorem inv_init : Inv {} := by simp [Inv]

/-- `accept` keeps the invariant. -/
theorem accept_inv {s : State} (e : Event) (h : Inv s) : Inv (accept s e) := by
  unfold accept
  split
  · intro c hc; simp only [List.mem_append, List.mem_singleton] at hc
    rcases hc with hc | rfl
    · exact h c hc
    · simp [CardInv, ready]
  all_goals first
    | exact h
    | exact mapCards_inv (touch_inv _) h
    | (split
       · exact mapCards_inv (touch_inv _) h
       · exact h)
    | (split
       · exact mapCards_inv (cardStep_inv _ _) h
       · exact h)

/-- `apply` keeps the invariant. -/
theorem apply_inv {s : State} (e : Event) (h : Inv s) : Inv (apply s e) := by
  unfold apply step
  split
  · exact h
  · split
    · exact h
    · exact accept_inv e h

/-- Every replayed state satisfies the invariant. -/
theorem project_inv (l : List Event) : Inv (project l) := by
  suffices ∀ s, Inv s → Inv (l.foldl apply s) from this _ inv_init
  induction l with
  | nil => intro s h; exact h
  | cons e l ih => intro s h; exact ih _ (apply_inv e h)

/-- **Land only when ready.** A landing without a violation had all its evidence at the landed
commit.
-/
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

/-- A new build sends an approved, unlanded card back to `screen`. -/
theorem built_resets (t : Nat) (id sha a : String) (c : Card)
    (hl : c.landed = false) (ha : c.approved = true) :
    stage (cardStep t (.cardBuild id sha a) c) = .screen := by
  simp [cardStep, cardRefusal, hl, touch, stage, ha]

/-- Staleness only grows with time. -/
theorem stale_mono {lim now now' w : Nat} {c : Card} (h : now ≤ now')
    (hs : stale lim now w c = true) : stale lim now' w c = true := by
  simp [stale] at *; omega

/-- A row with a live wait is never stale. -/
theorem stale_live {lim now w : Nat} {c : Card} (hw : 0 < w) : stale lim now w c = false := by
  simp [stale]; omega

/-! ## The plan part of the state -/

/-- A plan body that passes `check` passes the plan check. -/
theorem check_plan {s : State} {e : Event} {c : Fw.Plan.Cmd} (hb : e.body = .plan c)
    (h : check s e = none) : Fw.Plan.check s.plan c = none := by
  unfold check at h
  rw [hb] at h
  split at h
  · cases h
  · exact h

/-- `accept` changes the plan only for a plan body, and then by `Plan.exec`. -/
theorem accept_plan_cases (s : State) (e : Event) : (accept s e).plan = s.plan ∨
    ∃ c, e.body = .plan c ∧ (accept s e).plan = Fw.Plan.exec s.plan c := by
  obtain ⟨k, t, a, b⟩ := e
  cases b with
  | plan c => exact .inr ⟨c, rfl, rfl⟩
  | runFinish r ok => left; simp only [accept]; split <;> rfl
  | _ => left; rfl

/-- `apply` changes the plan only by an accepted plan command. -/
theorem apply_plan_cases (s : State) (e : Event) : (apply s e).plan = s.plan ∨
    ∃ c, e.body = .plan c ∧ Fw.Plan.check s.plan c = none ∧
      (apply s e).plan = Fw.Plan.exec s.plan c := by
  unfold apply step
  split
  · exact .inl rfl
  · split
    · exact .inl rfl
    · rename_i hc
      rcases accept_plan_cases s e with h | ⟨c, hb, h⟩
      · exact .inl h
      · exact .inr ⟨c, hb, check_plan hb hc, h⟩

/-- `apply` keeps the plan invariant (unique task ids, acyclic dependency graph). -/
theorem apply_plan_inv {s : State} (e : Event) (h : Fw.Plan.Inv s.plan) :
    Fw.Plan.Inv (apply s e).plan := by
  rcases apply_plan_cases s e with h1 | ⟨c, _, hc, h1⟩
  · rw [h1]; exact h
  · rw [h1]; exact Fw.Plan.exec_inv h hc

/-- **The console never accepts a dependency cycle**: in every replayed state the task ids are
unique and the dependency graph is acyclic.
-/
theorem project_plan_inv (l : List Event) : Fw.Plan.Inv (project l).plan := by
  suffices ∀ s : State, Fw.Plan.Inv s.plan → Fw.Plan.Inv (l.foldl apply s).plan from
    this _ Fw.Plan.inv_init
  induction l with
  | nil => intro s h; exact h
  | cons e l ih => intro s h; exact ih _ (apply_plan_inv e h)

/-- **A land is never undone over the console reducer**: once a task id holds evidence from a land
event (`task.done`), every event keeps it landed (and so done). Done from define evidence alone is
not monotone: a later define without evidence takes it back (`Fw.Plan.define_removes_unlanded_evidence`).
-/
theorem apply_isLanded {s : State} (e : Event) {x : String}
    (h : Fw.Plan.isLanded s.plan.tasks x = true) :
    Fw.Plan.isLanded (apply s e).plan.tasks x = true := by
  rcases apply_plan_cases s e with h1 | ⟨c, _, hc, h1⟩
  · rw [h1]; exact h
  · rw [h1]; exact Fw.Plan.exec_isLanded hc h

/-- A land is never undone over replay: a task landed after a log stays landed, and so done, after
any extension.
-/
theorem project_isLanded (l₁ l₂ : List Event) {x : String}
    (h : Fw.Plan.isLanded (project l₁).plan.tasks x = true) :
    Fw.Plan.isLanded (project (l₁ ++ l₂)).plan.tasks x = true ∧
      Fw.Plan.isDone (project (l₁ ++ l₂)).plan.tasks x = true := by
  suffices hl : Fw.Plan.isLanded (project (l₁ ++ l₂)).plan.tasks x = true from
    ⟨hl, Fw.Plan.isLanded_isDone hl⟩
  rw [project_append]
  induction l₂ generalizing l₁ with
  | nil => exact h
  | cons e l ih =>
    have := ih (l₁ ++ [e]) (by rw [project_append]; exact apply_isLanded e h)
    rw [project_append] at this
    simpa using this

/-! ## Examples run at build time (the console-mvp table, abridged) -/

#guard may .owner .cardOpen && !may .owner .cardApprove && !may .user .stepPost && !may .hook .cardOpen
#guard may .hook (.plan .claim) && !may .hook (.plan .define) && may .git (.plan .done)
#guard may .hook (.plan .handback) && !may .hook (.plan .integrate) && !may .hook (.plan .park)
#guard may .git (.plan .integrate) && !may .git (.plan .park) && may .lead (.plan .unpark)
#guard !may .owner (.plan .handback) && !may .reviewer (.plan .park) && may .user (.plan .park)
  && !may .owner (.plan .define) && may .script (.plan .milestone)
#guard
  let ev (k : String) (a : Actor) (c : Fw.Plan.Cmd) : Event := ⟨k, 0, a, .plan c⟩
  let s := project [ev "p1" .lead (.define (Fw.Plan.mk "a" [])),
                    ev "p2" .lead (.define (Fw.Plan.mk "b" ["a"]))]
  (step s (ev "p3" .lead (.define (Fw.Plan.mk "a" ["b"])))).2 == .refused "dependency cycle"
  && (step s (ev "p3" .owner (.drop "b"))).2 == .refused "actor owner may not cause task.drop"
  && (step s (ev "p3" .hook (.claim "a" "agent-1" 0))).2 == .accepted false
  && (Fw.Plan.view 0 0 (apply s (ev "p3" .git (.done "a" "abc1234"))).plan).tasks.map (·.state)
       == [.done, .ready]
#guard
  let ev (k : String) (t : Nat) (a : Actor) (b : Body) : Event := ⟨k, t, a, b⟩
  let base := [ev "k1" 1 .owner (.cardOpen "A" "o" false), ev "k2" 2 .lead (.cardApprove "A"),
               ev "k3" 3 .git (.cardBuild "A" "s1" "b")]
  let ready := base ++ [ev "k4" 4 .script (.cardScreen "A" "s1" true),
                        ev "k5" 5 .reviewer (.cardReview "A" "s1" "r" true)]
  let s := project ready
  (s.cards.map stage == [.land_ready])
  && (step (project base) (ev "x" 6 .script (.cardScreen "A" "old" true))).2
       == .refused "stale sha: not the head commit"
  && (step (project base) (ev "x" 6 .reviewer (.cardReview "A" "s1" "b" true))).2
       == .refused "reviewer owns or built this card"
  && (step s (ev "x" 6 .owner (.cardApprove "A"))).2 == .refused "actor owner may not cause card.approve"
  && (step s (ev "k1" 6 .owner (.cardOpen "A" "o" false))).2 == .accepted true
  && ((project (base ++ [ev "l" 9 .git (.cardLanded "A" "s1")])).cards.map (fun c => (c.landed, c.violation))
       == [(true, true)])
  && ((project (ready ++ [ev "q" 6 .lead (.cardLandRequest "A" "s1"), ev "l" 7 .git (.cardLanded "A" "s1")])).cards.map
       (fun c => (c.landed, c.violation)) == [(true, false)])
#guard
  let ev (k : String) (t : Nat) (a : Actor) (b : Body) : Event := ⟨k, t, a, b⟩
  let s := project [ev "k1" 1 .owner (.cardOpen "A" "o" false),
                    ev "k2" 2 .script (.stepPost "S" (some "A") "t" .yes_no none)]
  (step s (ev "x" 3 .user (.stepAnswer "S" "maybe"))).2 == .refused "answer must be yes or no"
  && (step s (ev "x" 3 .user (.stepDone "S"))).2 == .refused "step is waiting, only a started step can be done"
  && (step s (ev "x" 3 .user (.stepAnswer "S" "yes"))).2 == .accepted false

-- the script closes a waiting step for the lead, with a note; a waiting step for the user stays refused
#guard
  let ev (k : String) (t : Nat) (a : Actor) (b : Body) : Event := ⟨k, t, a, b⟩
  let s := project [ev "k1" 1 .script (.stepPost "L" none "t" .action none .lead "body"),
                    ev "k2" 2 .script (.stepPost "U" none "t" .action none)]
  (step s (ev "x" 3 .script (.stepDone "L" (some "resolved automatically")))).2 == .accepted false
  && (step s (ev "y" 3 .script (.stepDone "U" (some "n")))).2 == .refused "step is waiting, only a started step can be done"
  && (step s (ev "z" 3 .user (.stepDone "L"))).2 == .refused "step is waiting, only a started step can be done"
  && ((project [ev "k1" 1 .script (.stepPost "L" none "t" .action none .lead "body"),
                ev "x" 3 .script (.stepDone "L" (some "resolved automatically"))]).steps.map
        (fun x => (x.status, x.answer, x.audience, x.body)))
      == [(.done, some "resolved automatically", .lead, "body")]

end Fw.Console
