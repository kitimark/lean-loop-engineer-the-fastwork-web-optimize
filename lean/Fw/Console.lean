import Fw.Plan.Core
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

/-- Who caused an event (stamped by console-api, never by the sender).

$$\mathrm{Actor} = \{\mathrm{user}, \mathrm{lead}, \mathrm{owner}, \mathrm{reviewer}, \mathrm{script}, \mathrm{git}, \mathrm{hook}\}$$
-/
inductive Actor where
  | user | lead | owner | reviewer | script | git | hook
deriving Repr, DecidableEq

/-- The wire name of an actor.

$$\operatorname{name}(a) = \text{the constructor name of } a \text{ as a string, e.g. } \operatorname{name}(\mathrm{owner}) = \texttt{"owner"}$$
-/
def Actor.name : Actor → String
  | .user => "user" | .lead => "lead" | .owner => "owner" | .reviewer => "reviewer"
  | .script => "script" | .git => "git" | .hook => "hook"

/-- The kind of a step (what the user is asked to do).

$$\mathrm{StepKind} = \{\mathrm{action}, \mathrm{yes\_no}, \mathrm{choice}, \mathrm{text}\}$$
-/
inductive StepKind where
  | action | yes_no | choice | text
deriving Repr, DecidableEq

/-- The kind of a run.

$$\mathrm{RunKind} = \{\mathrm{screen}, \mathrm{gate}, \mathrm{run}, \mathrm{device}\}$$
-/
inductive RunKind where
  | screen | gate | run | device
deriving Repr, DecidableEq

/-- The status of a step.

$$\mathrm{StepStatus} = \{\mathrm{waiting}, \mathrm{started}, \mathrm{answered}, \mathrm{done}, \mathrm{cancelled}\}$$
-/
inductive StepStatus where
  | waiting | started | answered | done | cancelled
deriving Repr, DecidableEq

/-- The wire name of a step status.

$$\operatorname{name}(x) = \text{the constructor name of } x \text{ as a string, e.g. } \operatorname{name}(\mathrm{started}) = \texttt{"started"}$$
-/
def StepStatus.name : StepStatus → String
  | .waiting => "waiting" | .started => "started" | .answered => "answered" | .done => "done"
  | .cancelled => "cancelled"

/-- A step is open while it is waiting or started.

$$\operatorname{isOpen}(x) = \mathrm{true} \iff x \in \{\mathrm{waiting}, \mathrm{started}\}$$
-/
def StepStatus.isOpen : StepStatus → Bool
  | .waiting | .started => true
  | _ => false

/-- The status of a run.

$$\mathrm{RunStatus} = \{\mathrm{running}, \mathrm{passed}, \mathrm{failed}\}$$
-/
inductive RunStatus where
  | running | passed | failed
deriving Repr, DecidableEq

/-- A card (one experiment row) and the evidence on it, each piece keyed by the commit it is about.

$$c = (\mathit{id}, \mathit{owner}, \mathit{needsDevice}, \mathit{approved}, \mathit{head}_\bot, \mathit{builders}, \mathit{screenAt}_\bot, \mathit{reviewAt}_\bot, \mathit{reviewedBy}_\bot, \mathit{deviceAt}_\bot, \mathit{landReq}_\bot, \mathit{landed}, \mathit{violation}, \mathit{lastAt})$$
-/
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

/-- A step: a question or action put to the user, optionally about a card.

$$s = (\mathit{id}, \mathit{card}_\bot, \mathit{title}, \mathit{kind}, \mathit{options}_\bot, \mathit{status}, \mathit{answer}_\bot, \mathit{postedAt}, \mathit{lastAt})$$
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
deriving Repr, DecidableEq

/-- A run (screen, gate, run or device job) on a card.

$$r = (\mathit{id}, \mathit{card}, \mathit{kind}, \mathit{status}, \mathit{startedAt})$$
-/
structure Run where
  id        : String
  card      : String
  kind      : RunKind
  status    : RunStatus := .running
  startedAt : Nat
deriving Repr, DecidableEq

/-- Event bodies (one per command type of the contract).

$$\begin{aligned} \mathrm{Body} = {} & \mathrm{cardOpen}(\mathit{card}, \mathit{owner}, \mathit{needsDevice}) \mid \mathrm{cardApprove}(\mathit{card}) \mid \mathrm{cardBuild}(\mathit{card}, \mathit{sha}, \mathit{agent}) \mid \mathrm{cardScreen}(\mathit{card}, \mathit{sha}, \mathit{pass}) \\ & \mid \mathrm{cardReview}(\mathit{card}, \mathit{sha}, \mathit{signedBy}, \mathit{accept}) \mid \mathrm{cardSwipe}(\mathit{card}, \mathit{sha}, \mathit{better}) \mid \mathrm{cardLandRequest}(\mathit{card}, \mathit{sha}) \mid \mathrm{cardLanded}(\mathit{card}, \mathit{sha}) \\ & \mid \mathrm{stepPost}(\mathit{step}, \mathit{card}_\bot, \mathit{title}, \mathit{kind}, \mathit{options}_\bot) \mid \mathrm{stepStart}(\mathit{step}) \mid \mathrm{stepAnswer}(\mathit{step}, \mathit{answer}) \mid \mathrm{stepDone}(\mathit{step}) \mid \mathrm{stepCancel}(\mathit{step}) \\ & \mid \mathrm{runStart}(\mathit{run}, \mathit{card}, \mathit{kind}) \mid \mathrm{runFinish}(\mathit{run}, \mathit{ok}) \mid \mathrm{plan}(c),\ c \in \mathrm{Plan.Cmd} \end{aligned}$$
-/
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
                    (options : Option (List String))
  | stepStart       (step : String)
  | stepAnswer      (step answer : String)
  | stepDone        (step : String)
  | stepCancel      (step : String)
  | runStart        (run card : String) (kind : RunKind)
  | runFinish       (run : String) (ok : Bool)
  | plan            (c : Fw.Plan.Cmd)
deriving Repr, DecidableEq

/-- The 15 card/step/run event types and the 5 plan command types (the `type` field on the wire).

$$\mathrm{EvType} = \{\texttt{card.open}, \texttt{card.approve}, \texttt{card.build}, \texttt{card.screen}, \texttt{card.review}, \texttt{card.swipe}, \texttt{card.land\_request}, \texttt{card.landed}, \texttt{step.post}, \texttt{step.start}, \texttt{step.answer}, \texttt{step.done}, \texttt{step.cancel}, \texttt{run.start}, \texttt{run.finish}\} \cup \{\mathrm{plan}(\tau) : \tau \in \mathrm{Plan.CmdType}\}$$
-/
inductive EvType where
  | cardOpen | cardApprove | cardBuild | cardScreen | cardReview | cardSwipe | cardLandRequest
  | cardLanded | stepPost | stepStart | stepAnswer | stepDone | stepCancel | runStart | runFinish
  | plan (t : Fw.Plan.CmdType)
deriving Repr, DecidableEq

/-- The wire name of an event type.

$$\operatorname{name}(\mathrm{cardOpen}) = \texttt{"card.open"},\ \dots,\ \operatorname{name}(\mathrm{cardLandRequest}) = \texttt{"card.land\_request"},\ \dots,\ \operatorname{name}(\mathrm{runFinish}) = \texttt{"run.finish"},\ \operatorname{name}(\mathrm{plan}(\tau)) = \operatorname{Plan.name}(\tau)$$
-/
def EvType.name : EvType → String
  | .cardOpen => "card.open" | .cardApprove => "card.approve" | .cardBuild => "card.build"
  | .cardScreen => "card.screen" | .cardReview => "card.review" | .cardSwipe => "card.swipe"
  | .cardLandRequest => "card.land_request" | .cardLanded => "card.landed"
  | .stepPost => "step.post" | .stepStart => "step.start" | .stepAnswer => "step.answer"
  | .stepDone => "step.done" | .stepCancel => "step.cancel" | .runStart => "run.start"
  | .runFinish => "run.finish" | .plan t => t.name

/-- The type of a body.

$$\operatorname{type}(\mathrm{cardOpen}(\dots)) = \mathrm{cardOpen},\ \dots,\ \operatorname{type}(\mathrm{runFinish}(\dots)) = \mathrm{runFinish},\ \operatorname{type}(\mathrm{plan}(c)) = \mathrm{plan}(\operatorname{Plan.type}(c))$$
-/
def Body.type : Body → EvType
  | .cardOpen .. => .cardOpen | .cardApprove .. => .cardApprove | .cardBuild .. => .cardBuild
  | .cardScreen .. => .cardScreen | .cardReview .. => .cardReview | .cardSwipe .. => .cardSwipe
  | .cardLandRequest .. => .cardLandRequest | .cardLanded .. => .cardLanded
  | .stepPost .. => .stepPost | .stepStart .. => .stepStart | .stepAnswer .. => .stepAnswer
  | .stepDone .. => .stepDone | .stepCancel .. => .stepCancel | .runStart .. => .runStart
  | .runFinish .. => .runFinish | .plan c => .plan c.type

/-- An event: an idempotency key, the stamp time (ms, by console-api), the actor and the body.

$$e = (\mathit{key}(e), \mathit{ts}(e), \mathit{actor}(e), \mathit{body}(e)) \in \mathrm{String} \times \mathbb{N} \times \mathrm{Actor} \times \mathrm{Body}$$
-/
structure Event where
  key   : String
  ts    : Nat
  actor : Actor
  body  : Body
deriving Repr, DecidableEq

/-- The console state: the accepted keys (newest first), the cards, steps and runs (each in
creation order), and the plan (the work graph, `Fw.Plan.State`).

$$\sigma = (S, \mathit{cards}, \mathit{steps}, \mathit{runs}, \mathit{plan}), \qquad \sigma_0 = ([\,], [\,], [\,], [\,], \pi_0)$$
-/
structure State where
  seen  : List String := []
  cards : List Card := []
  steps : List Step := []
  runs  : List Run := []
  plan  : Fw.Plan.State := {}
deriving Repr, DecidableEq

/-- The authority table (`MAY`): the actors allowed to cause each event type.

$$\begin{aligned} &\mathrm{MAY}(\texttt{card.open}) = \{\mathrm{owner}, \mathrm{lead}, \mathrm{user}\}, && \mathrm{MAY}(\texttt{card.approve}) = \{\mathrm{lead}, \mathrm{user}\}, \\ &\mathrm{MAY}(\texttt{card.build}) = \{\mathrm{git}\}, && \mathrm{MAY}(\texttt{card.screen}) = \{\mathrm{script}\}, \\ &\mathrm{MAY}(\texttt{card.review}) = \{\mathrm{reviewer}\}, && \mathrm{MAY}(\texttt{card.swipe}) = \{\mathrm{script}\}, \\ &\mathrm{MAY}(\texttt{card.land\_request}) = \{\mathrm{lead}, \mathrm{user}\}, && \mathrm{MAY}(\texttt{card.landed}) = \{\mathrm{git}\}, \\ &\mathrm{MAY}(\texttt{step.post}) = \{\mathrm{script}, \mathrm{owner}, \mathrm{lead}\}, && \mathrm{MAY}(\texttt{step.start}) = \{\mathrm{user}\}, \\ &\mathrm{MAY}(\texttt{step.answer}) = \{\mathrm{user}\}, && \mathrm{MAY}(\texttt{step.done}) = \{\mathrm{user}, \mathrm{owner}, \mathrm{script}\}, \\ &\mathrm{MAY}(\texttt{step.cancel}) = \{\mathrm{script}, \mathrm{user}, \mathrm{lead}\}, && \mathrm{MAY}(\texttt{run.start}) = \{\mathrm{script}, \mathrm{owner}, \mathrm{lead}\}, \\ &\mathrm{MAY}(\texttt{run.finish}) = \{\mathrm{script}\}, \\ &\mathrm{MAY}(\texttt{task.define}) = \mathrm{MAY}(\texttt{task.drop}) = \mathrm{MAY}(\texttt{milestone.define}) = \{\mathrm{lead}, \mathrm{user}, \mathrm{script}\}, \\ &\mathrm{MAY}(\texttt{task.claim}) = \{\mathrm{hook}, \mathrm{script}, \mathrm{lead}\}, && \mathrm{MAY}(\texttt{task.done}) = \{\mathrm{git}, \mathrm{lead}, \mathrm{user}\} \end{aligned}$$

Edge: the actor $\mathrm{hook}$ may cause only $\texttt{task.claim}$ (an agent start observed by a hook).
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
  | .stepDone => [.user, .owner, .script]
  | .stepCancel => [.script, .user, .lead]
  | .runStart => [.script, .owner, .lead]
  | .runFinish => [.script]
  | .plan .define | .plan .drop | .plan .milestone => [.lead, .user, .script]
  | .plan .claim => [.hook, .script, .lead]
  | .plan .done => [.git, .lead, .user]

/-- An actor may cause an event type iff it is in the table.

$$\operatorname{may}(a, \tau) = \mathrm{true} \iff a \in \mathrm{MAY}(\tau)$$
-/
def may (a : Actor) (t : EvType) : Bool := (mayList t).contains a

/-- A card is ready to land: approved, built, and screened, reviewed and (if it needs the device)
swiped, all at its current head.

$$\operatorname{ready}(c) \iff \mathit{approved} \ \land\ \mathit{head} \ne \bot \ \land\ \mathit{screenAt} = \mathit{head} \ \land\ \mathit{reviewAt} = \mathit{head} \ \land\ (\neg\mathit{needsDevice} \lor \mathit{deviceAt} = \mathit{head})$$
-/
def ready (c : Card) : Bool :=
  c.approved && c.head.isSome && decide (c.screenAt = c.head) && decide (c.reviewAt = c.head)
    && (!c.needsDevice || decide (c.deviceAt = c.head))

/-- Record activity at time `t` (the last-event time never moves back).

$$\operatorname{touch}_t(c) = c[\mathit{lastAt} := \max(\mathit{lastAt}, t)]$$
-/
def touch (t : Nat) (c : Card) : Card := { c with lastAt := max c.lastAt t }

/-- Why a card event is refused on card `c` (`none` = acceptable). First match wins; with
$L = \texttt{"card already landed"}$ and $\Sigma = \texttt{"stale sha: not the head commit"}$:

$$\operatorname{cardRefusal}(c, b) = \begin{cases}
L \text{ if } \mathit{landed};\ \texttt{"already approved"} \text{ if } \mathit{approved};\ \bot & b = \mathrm{cardApprove} \\
L \text{ if } \mathit{landed};\ \bot & b = \mathrm{cardBuild} \text{ or } \mathrm{cardLanded} \\
L \text{ if } \mathit{landed};\ \Sigma \text{ if } \mathit{head} \ne \mathit{sha};\ \bot \text{ if } \mathit{pass};\ \texttt{"failed screen does not advance the card"} & b = \mathrm{cardScreen}(\cdot, \mathit{sha}, \mathit{pass}) \\
L \text{ if } \mathit{landed};\ \Sigma \text{ if } \mathit{head} \ne \mathit{sha};\ \texttt{"reviewer owns or built this card"} \text{ if } r = \mathit{owner} \lor r \in \mathit{builders};\ \bot \text{ if } \mathit{ok};\ \texttt{"rejected review does not advance the card"} & b = \mathrm{cardReview}(\cdot, \mathit{sha}, r, \mathit{ok}) \\
L \text{ if } \mathit{landed};\ \Sigma \text{ if } \mathit{head} \ne \mathit{sha};\ \bot \text{ if } \mathit{better};\ \texttt{"not better: device evidence not recorded"} & b = \mathrm{cardSwipe}(\cdot, \mathit{sha}, \mathit{better}) \\
L \text{ if } \mathit{landed};\ \Sigma \text{ if } \mathit{head} \ne \mathit{sha};\ \bot \text{ if } \operatorname{ready}(c);\ \texttt{"card is not land-ready"} & b = \mathrm{cardLandRequest}(\cdot, \mathit{sha}) \\
\bot & \text{any other body}
\end{cases}$$
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

/-- The card transition at time `t`: a refused body leaves the card unchanged; otherwise

$$\operatorname{cardStep}_t(b, c) = \begin{cases}
c & \operatorname{cardRefusal}(c, b) \ne \bot \\
\operatorname{touch}_t(c[\mathit{approved} := \mathrm{true}]) & b = \mathrm{cardApprove} \\
\operatorname{touch}_t(c[\mathit{head} := \mathit{sha},\ \mathit{builders} := a :: \mathit{builders},\ \mathit{screenAt}, \mathit{reviewAt}, \mathit{reviewedBy}, \mathit{deviceAt}, \mathit{landReq} := \bot]) & b = \mathrm{cardBuild}(\cdot, \mathit{sha}, a) \\
\operatorname{touch}_t(c[\mathit{screenAt} := \mathit{sha}]) & b = \mathrm{cardScreen}(\cdot, \mathit{sha}, \cdot) \\
\operatorname{touch}_t(c[\mathit{reviewAt} := \mathit{sha},\ \mathit{reviewedBy} := r]) & b = \mathrm{cardReview}(\cdot, \mathit{sha}, r, \cdot) \\
\operatorname{touch}_t(c[\mathit{deviceAt} := \mathit{sha}]) & b = \mathrm{cardSwipe}(\cdot, \mathit{sha}, \cdot) \\
\operatorname{touch}_t(c[\mathit{landReq} := \mathit{sha}]) & b = \mathrm{cardLandRequest}(\cdot, \mathit{sha}) \\
\operatorname{touch}_t(c[\mathit{landed} := \mathrm{true},\ \mathit{violation} := \neg(\mathit{landReq} = \mathit{sha} \land \operatorname{ready}(c))]) & b = \mathrm{cardLanded}(\cdot, \mathit{sha}) \\
c & \text{otherwise}
\end{cases}$$
-/
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

/-- The card a card body acts on through `cardStep` (none for `cardOpen`, steps and runs).

$$\operatorname{cardOf}(b) = \begin{cases} \mathit{card} & b \in \{\mathrm{cardApprove}, \mathrm{cardBuild}, \mathrm{cardScreen}, \mathrm{cardReview}, \mathrm{cardSwipe}, \mathrm{cardLandRequest}, \mathrm{cardLanded}\}(\mathit{card}, \dots) \\ \bot & \text{otherwise} \end{cases}$$
-/
def cardOf : Body → Option String
  | .cardApprove c | .cardBuild c _ _ | .cardScreen c _ _ | .cardReview c _ _ _ | .cardSwipe c _ _
  | .cardLandRequest c _ | .cardLanded c _ => some c
  | _ => none

/-- Apply `f` to every card with the given id.

$$\operatorname{mapCards}(\mathit{id}, f, cs) = \big[\, \textbf{if } c.\mathit{id} = \mathit{id} \textbf{ then } f(c) \textbf{ else } c \ :\ c \in cs \,\big]$$
-/
def mapCards (id : String) (f : Card → Card) (cs : List Card) : List Card :=
  cs.map fun c => if c.id = id then f c else c

/-- Apply `f` to every step with the given id, and record activity at `t` on it.

$$\operatorname{mapSteps}_t(\mathit{id}, f, ss) = \big[\, \textbf{if } s.\mathit{id} = \mathit{id} \textbf{ then } f(s)[\mathit{lastAt} := \max(s.\mathit{lastAt}, t)] \textbf{ else } s \ :\ s \in ss \,\big]$$
-/
def mapSteps (t : Nat) (id : String) (f : Step → Step) (ss : List Step) : List Step :=
  ss.map fun s => if s.id = id then { f s with lastAt := max s.lastAt t } else s

/-- Why a step event is refused on the step `st` it names (`none` = acceptable); first match wins.

$$\operatorname{stepRefusal}(st, b) = \begin{cases}
\bot \text{ if } \mathit{status} = \mathrm{waiting};\ \texttt{"step is } \mathit{status} \texttt{, not waiting"} & b = \mathrm{stepStart} \\
\bot \text{ if } \operatorname{isOpen}(\mathit{status});\ \texttt{"step already } \mathit{status} \texttt{"} & b = \mathrm{stepCancel} \\
\bot \text{ if } \mathit{status} = \mathrm{started};\ \texttt{"step is } \mathit{status} \texttt{, only a started step can be done"} & b = \mathrm{stepDone} \\
\texttt{"step already } \mathit{status} \texttt{"} \text{ if } \neg\operatorname{isOpen};\ \texttt{"an action step is finished with step.done, not an answer"} \text{ if } \mathit{kind} = \mathrm{action}; & \\
\quad \texttt{"answer must be yes or no"} \text{ if } \mathit{kind} = \mathrm{yes\_no} \land a \notin \{\texttt{yes}, \texttt{no}\}; & \\
\quad \texttt{"answer is not one of the options"} \text{ if } \mathit{kind} = \mathrm{choice} \land a \notin \mathit{options} \ (\bot \text{ counts as } [\,]);\ \bot & b = \mathrm{stepAnswer}(\cdot, a) \\
\bot & \text{any other body}
\end{cases}$$
-/
def stepRefusal (st : Step) : Body → Option String
  | .stepStart _ =>
    if st.status = .waiting then none else some s!"step is {st.status.name}, not waiting"
  | .stepCancel _ => if st.status.isOpen then none else some s!"step already {st.status.name}"
  | .stepDone _ =>
    if st.status = .started then none
    else some s!"step is {st.status.name}, only a started step can be done"
  | .stepAnswer _ a =>
    if !st.status.isOpen then some s!"step already {st.status.name}"
    else if st.kind = .action then some "an action step is finished with step.done, not an answer"
    else if st.kind = .yes_no && a != "yes" && a != "no" then some "answer must be yes or no"
    else if st.kind = .choice && !((st.options.getD []).contains a) then
      some "answer is not one of the options"
    else none
  | _ => none

/-- Why an event is refused in state `σ` (`none` = accepted). First match wins; "the step", "the
run" and "the card" are the first ones in their list with that id.

$$\operatorname{check}(\sigma, e) = \begin{cases}
\texttt{"actor } \mathit{a} \texttt{ may not cause } \tau \texttt{"} & \neg\operatorname{may}(a, \tau),\ a = \mathit{actor}(e),\ \tau = \operatorname{type}(\mathit{body}(e)) \\
\texttt{"card exists"} \text{ if } \exists c:\ c.\mathit{id} = \mathit{id};\ \bot & b = \mathrm{cardOpen}(\mathit{id}, \dots) \\
\texttt{"step exists"} \text{ if } \exists s:\ s.\mathit{id} = \mathit{id};\ \texttt{"no such card"} \text{ if } \mathit{card} \ne \bot \text{ is unknown};\ \texttt{"choice step needs at least 2 options"} \text{ if } \mathit{kind} = \mathrm{choice} \land |\mathit{options}| < 2;\ \bot & b = \mathrm{stepPost}(\mathit{id}, \mathit{card}, \cdot, \mathit{kind}, \mathit{options}) \\
\texttt{"no such step"} \text{ if unknown};\ \operatorname{stepRefusal}(st, b) & b \in \{\mathrm{stepStart}, \mathrm{stepAnswer}, \mathrm{stepDone}, \mathrm{stepCancel}\} \\
\texttt{"no such card"} \text{ if unknown};\ \texttt{"run exists"} \text{ if } \exists r:\ r.\mathit{id} = \mathit{run};\ \bot & b = \mathrm{runStart}(\mathit{run}, \mathit{card}, \cdot) \\
\texttt{"no such run"} \text{ if unknown};\ \bot \text{ if } r.\mathit{status} = \mathrm{running};\ \texttt{"run already finished"} & b = \mathrm{runFinish}(\mathit{run}, \cdot) \\
\operatorname{Plan.check}(\sigma.\mathit{plan}, c) & b = \mathrm{plan}(c) \\
\texttt{"no such card"} \text{ if unknown};\ \operatorname{cardRefusal}(c, b) & \operatorname{cardOf}(b) = \mathit{id}
\end{cases}$$

Edge: an absent option list counts as having 0 options.
-/
def check (s : State) (e : Event) : Option String :=
  if !may e.actor e.body.type then some s!"actor {e.actor.name} may not cause {e.body.type.name}" else
  match e.body with
  | .cardOpen id _ _ => if s.cards.any (·.id == id) then some "card exists" else none
  | .stepPost id card _ kind opts =>
    if s.steps.any (·.id == id) then some "step exists"
    else if (match card with | some c => !(s.cards.any (·.id == c)) | none => false) then some "no such card"
    else if kind = .choice && (opts.getD []).length < 2 then some "choice step needs at least 2 options"
    else none
  | .stepStart id | .stepAnswer id _ | .stepDone id | .stepCancel id =>
    match s.steps.find? (·.id == id) with
    | none => some "no such step"
    | some st => stepRefusal st e.body
  | .runStart r card _ =>
    if !(s.cards.any (·.id == card)) then some "no such card"
    else if s.runs.any (·.id == r) then some "run exists" else none
  | .runFinish r _ =>
    match s.runs.find? (·.id == r) with
    | none => some "no such run"
    | some run => if run.status = .running then none else some "run already finished"
  | .plan c => Fw.Plan.check s.plan c
  | b => match cardOf b with
    | none => none
    | some id => match s.cards.find? (·.id == id) with
      | none => some "no such card"
      | some c => cardRefusal c b

/-- The effect of an accepted event on cards, steps and runs (the seen list is handled by `apply`).
With $t = \mathit{ts}(e)$:

$$\operatorname{accept}(\sigma, e) = \begin{cases}
\sigma[\mathit{cards} \mathrel{{+}{+}}= [(\mathit{id}, o, d, \text{defaults}, \mathit{lastAt} := t)]] & \mathrm{cardOpen}(\mathit{id}, o, d) \\
\sigma[\mathit{steps} \mathrel{{+}{+}}= [(\mathit{id}, \mathit{card}, \mathit{title}, \mathit{kind}, \mathit{options}, \mathrm{waiting}, \bot, t, t)]] & \mathrm{stepPost} \\
\sigma[\mathit{steps} := \operatorname{mapSteps}_t(\mathit{id}, \mathit{status} := \mathrm{started})] & \mathrm{stepStart}(\mathit{id}) \\
\sigma[\mathit{steps} := \operatorname{mapSteps}_t(\mathit{id}, \mathit{status} := \mathrm{answered},\ \mathit{answer} := a)] & \mathrm{stepAnswer}(\mathit{id}, a) \\
\sigma[\mathit{steps} := \operatorname{mapSteps}_t(\mathit{id}, \mathit{status} := \mathrm{done})] & \mathrm{stepDone}(\mathit{id}) \\
\sigma[\mathit{steps} := \operatorname{mapSteps}_t(\mathit{id}, \mathit{status} := \mathrm{cancelled})] & \mathrm{stepCancel}(\mathit{id}) \\
\sigma[\mathit{cards} := \operatorname{mapCards}(\mathit{card}, \operatorname{touch}_t),\ \mathit{runs} \mathrel{{+}{+}}= [(\mathit{run}, \mathit{card}, k, \mathrm{running}, t)]] & \mathrm{runStart}(\mathit{run}, \mathit{card}, k) \\
\sigma[\mathit{cards} := \operatorname{mapCards}(r.\mathit{card}, \operatorname{touch}_t),\ \mathit{runs} := \text{every run } \mathit{run} \text{ gets } \mathit{status} := (\mathrm{passed} \text{ if } \mathit{ok} \text{ else } \mathrm{failed})] & \mathrm{runFinish}(\mathit{run}, \mathit{ok}),\ r \text{ the first run } \mathit{run} \\
\sigma[\mathit{plan} := \operatorname{Plan.exec}(\sigma.\mathit{plan}, c)] & \mathrm{plan}(c) \\
\sigma[\mathit{cards} := \operatorname{mapCards}(\mathit{id}, \operatorname{cardStep}_t(b, \cdot))] & \operatorname{cardOf}(b) = \mathit{id} \\
\sigma & \text{otherwise (an unknown run)}
\end{cases}$$
-/
def accept (s : State) (e : Event) : State :=
  let t := e.ts
  match e.body with
  | .cardOpen id owner dev =>
    { s with cards := s.cards ++ [{ id, owner, needsDevice := dev, lastAt := t }] }
  | .stepPost id card title kind opts =>
    { s with steps := s.steps ++ [{ id, card, title, kind, options := opts, postedAt := t, lastAt := t }] }
  | .stepStart id => { s with steps := mapSteps t id (fun x => { x with status := .started }) s.steps }
  | .stepAnswer id a =>
    { s with steps := mapSteps t id (fun x => { x with status := .answered, answer := some a }) s.steps }
  | .stepDone id => { s with steps := mapSteps t id (fun x => { x with status := .done }) s.steps }
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
  | .plan c => { s with plan := Fw.Plan.exec s.plan c }
  | b => match cardOf b with
    | some id => { s with cards := mapCards id (cardStep t b) s.cards }
    | none => s

/-- What the reducer did with an event: accepted (possibly as a duplicate of a seen key) or
refused with a reason.

$$\mathrm{Outcome} = \mathrm{accepted}(\mathit{duplicate} \in \{\mathrm{true}, \mathrm{false}\}) \mid \mathrm{refused}(\mathit{reason})$$
-/
inductive Outcome where
  | accepted (duplicate : Bool)
  | refused (reason : String)
deriving Repr, DecidableEq

/-- The reducer step: a seen key is a no-op duplicate; a refused event leaves the state untouched
(its key is **not** marked seen); an accepted event is applied and its key put first in the seen
list.

$$\operatorname{step}(\sigma, e) = \begin{cases} (\sigma,\ \mathrm{accepted}(\mathrm{true})) & \mathit{key}(e) \in S \\ (\sigma,\ \mathrm{refused}(w)) & \text{else if } \operatorname{check}(\sigma, e) = w \\ \big(\operatorname{accept}(\sigma, e)[S := \mathit{key}(e) :: S],\ \mathrm{accepted}(\mathrm{false})\big) & \text{otherwise} \end{cases}$$
-/
def step (s : State) (e : Event) : State × Outcome :=
  if s.seen.contains e.key then (s, .accepted true)
  else match check s e with
    | some w => (s, .refused w)
    | none   => ({ accept s e with seen := e.key :: s.seen }, .accepted false)

/-- The state after one event.

$$\operatorname{apply}(\sigma, e) = \operatorname{step}(\sigma, e)_1$$
-/
def apply (s : State) (e : Event) : State := (step s e).1

/-- Replay: the state of a log is the left fold of `apply` from the empty state.

$$\operatorname{project}([e_1, \dots, e_n]) = \operatorname{apply}(\cdots \operatorname{apply}(\operatorname{apply}(\sigma_0, e_1), e_2) \cdots, e_n)$$
-/
def project (log : List Event) : State := log.foldl apply {}

/-- The stage of a card.

$$\mathrm{Stage} = \{\mathrm{question}, \mathrm{build}, \mathrm{screen}, \mathrm{review}, \mathrm{device}, \mathrm{land\_ready}, \mathrm{land}\}$$
-/
inductive Stage where
  | question | build | screen | review | device | land_ready | land
deriving Repr, DecidableEq

/-- The stage of a card is computed, never written (first match wins).

$$\operatorname{stage}(c) = \begin{cases} \mathrm{land} & \mathit{landed} \\ \mathrm{question} & \neg\mathit{approved} \\ \mathrm{build} & \mathit{head} = \bot \\ \mathrm{screen} & \mathit{screenAt} \ne \mathit{head} \\ \mathrm{review} & \mathit{reviewAt} \ne \mathit{head} \\ \mathrm{device} & \mathit{needsDevice} \land \mathit{deviceAt} \ne \mathit{head} \\ \mathrm{land\_ready} & \text{otherwise} \end{cases}$$
-/
def stage (c : Card) : Stage :=
  if c.landed then .land
  else if !c.approved then .question
  else if c.head.isNone then .build
  else if c.screenAt != c.head then .screen
  else if c.reviewAt != c.head then .review
  else if c.needsDevice && c.deviceAt != c.head then .device
  else .land_ready

/-- Stale: no live wait on the row, and no event for at least `lim` ms.

$$\operatorname{stale}(\mathit{lim}, \mathit{now}, w, c) = \mathrm{true} \iff w = 0 \ \land\ \mathit{lim} \le \mathit{now} \mathbin{\dot-} c.\mathit{lastAt}$$
-/
def stale (lim now liveWaits : Nat) (c : Card) : Bool :=
  liveWaits == 0 && decide (lim ≤ now - c.lastAt)

/-! ## Theorems -/

/-- A seen key is a no-op, reported as a duplicate.

$$\forall \sigma, e:\quad \mathit{key}(e) \in S \;\Rightarrow\; \operatorname{step}(\sigma, e) = (\sigma,\ \mathrm{accepted}(\mathrm{true}))$$
-/
theorem step_seen {s : State} {e : Event} (h : e.key ∈ s.seen) : step s e = (s, .accepted true) := by
  simp [step, h]

/-- A refused event changes nothing at all (not even the seen list).

$$\forall \sigma, e, w:\quad \operatorname{step}(\sigma, e)_2 = \mathrm{refused}(w) \;\Rightarrow\; \operatorname{step}(\sigma, e)_1 = \sigma$$
-/
theorem refused_keeps {s : State} {e : Event} {w : String} (h : (step s e).2 = .refused w) :
    (step s e).1 = s := by
  revert h
  unfold step
  split
  · intro _; rfl
  · split
    · intro _; rfl
    · intro h; simp at h

/-- A refusal from `check` leaves the state unchanged.

$$\forall \sigma, e, w:\quad \operatorname{check}(\sigma, e) = w \;\Rightarrow\; \operatorname{apply}(\sigma, e) = \sigma$$
-/
theorem reject_keeps {s : State} {e : Event} {why : String} (h : check s e = some why) :
    apply s e = s := by
  unfold apply step; split
  · rfl
  · simp [h]

/-- Idempotency: applying the same event twice equals applying it once (states only; for the
reported outcome see `step_twice`).

$$\forall \sigma, e:\quad \operatorname{apply}(\operatorname{apply}(\sigma, e), e) = \operatorname{apply}(\sigma, e)$$
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

$$\forall \sigma, e:\quad \operatorname{step}\big(\operatorname{apply}(\sigma, e), e\big)_2 = \mathrm{accepted}(\mathrm{true}) \ \lor\ \operatorname{step}\big(\operatorname{apply}(\sigma, e), e\big)_2 = \operatorname{step}(\sigma, e)_2$$
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

/-- Only actors in the `MAY` table get a fresh event accepted.

$$\forall \sigma, e:\quad \operatorname{step}(\sigma, e)_2 = \mathrm{accepted}(\mathrm{false}) \;\Rightarrow\; \operatorname{may}(\mathit{actor}(e), \operatorname{type}(\mathit{body}(e))) = \mathrm{true}$$
-/
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

/-- An actor outside the `MAY` table is refused with the table's reason.

$$\forall \sigma, e:\quad \operatorname{may}(\mathit{actor}(e), \operatorname{type}(\mathit{body}(e))) = \mathrm{false} \;\Rightarrow\; \operatorname{check}(\sigma, e) = \texttt{"actor } \operatorname{name}(\mathit{actor}(e)) \texttt{ may not cause } \operatorname{name}(\operatorname{type}(\mathit{body}(e))) \texttt{"}$$
-/
theorem unauthorized_rejected {s : State} {e : Event} (h : may e.actor e.body.type = false) :
    check s e = some s!"actor {e.actor.name} may not cause {e.body.type.name}" := by
  simp [check, h]

/-- Only the user answers or starts steps: an answer or start from anyone else changes nothing.

$$\forall \sigma, e:\quad \mathit{body}(e) \in \{\mathrm{stepAnswer}, \mathrm{stepStart}\}(\dots) \ \land\ \mathit{actor}(e) \ne \mathrm{user} \;\Rightarrow\; \operatorname{apply}(\sigma, e) = \sigma$$
-/
theorem only_user_answers {s : State} {e : Event}
    (hb : (∃ id a, e.body = .stepAnswer id a) ∨ (∃ id, e.body = .stepStart id))
    (ha : e.actor ≠ .user) : apply s e = s := by
  have : may e.actor e.body.type = false := by
    rcases hb with ⟨id, a, hb⟩ | ⟨id, hb⟩ <;>
      (rw [hb]; cases h : e.actor <;> simp_all [may, mayList, Body.type])
  exact reject_keeps (unauthorized_rejected this)

/-- A git `card.landed` fact for a known card that has not landed is never refused.

$$\forall \sigma, e, \mathit{id}, \mathit{sha}, c:\quad \mathit{body}(e) = \mathrm{cardLanded}(\mathit{id}, \mathit{sha}) \ \land\ \mathit{actor}(e) = \mathrm{git} \ \land\ c \text{ is the first card with id } \mathit{id} \ \land\ \neg c.\mathit{landed} \;\Rightarrow\; \operatorname{check}(\sigma, e) = \bot$$
-/
theorem landed_fact_accepted {s : State} {e : Event} {id sha : String} {c : Card}
    (hb : e.body = .cardLanded id sha) (ha : e.actor = .git)
    (hc : s.cards.find? (·.id == id) = some c) (hl : c.landed = false) :
    check s e = none := by
  simp [check, hb, ha, may, mayList, Body.type, cardOf, hc, cardRefusal, hl]

/-- Snapshot plus tail equals the full replay.

$$\forall L_1, L_2:\quad \operatorname{project}(L_1 \mathbin{+\!\!+} L_2) = \operatorname{foldl}\big(\operatorname{apply},\ \operatorname{project}(L_1),\ L_2\big)$$
-/
theorem project_append (l₁ l₂ : List Event) : project (l₁ ++ l₂) = l₂.foldl apply (project l₁) := by
  simp [project, List.foldl_append]

/-! ### Card invariant -/

/-- The card invariant: a landing without a violation was ready; a pending land request is held
only by a ready card; the recorded reviewer neither owns the card nor built on it.

$$\operatorname{CardInv}(c) \iff \big(\mathit{landed} \land \neg\mathit{violation} \Rightarrow \operatorname{ready}(c)\big) \ \land\ \big(\mathit{landReq} \ne \bot \land \neg\mathit{landed} \Rightarrow \operatorname{ready}(c)\big) \ \land\ \big(\forall r:\ \mathit{reviewedBy} = r \Rightarrow r \ne \mathit{owner} \land r \notin \mathit{builders}\big)$$
-/
def CardInv (c : Card) : Prop :=
  (c.landed = true → c.violation = false → ready c = true) ∧
  (c.landReq.isSome = true → c.landed = false → ready c = true) ∧
  (∀ r, c.reviewedBy = some r → r ≠ c.owner ∧ r ∉ c.builders)

/-- The state invariant: every card satisfies `CardInv`.

$$\operatorname{Inv}(\sigma) \iff \forall c \in \mathit{cards}:\ \operatorname{CardInv}(c)$$
-/
def Inv (s : State) : Prop := ∀ c ∈ s.cards, CardInv c

/-- Touching a card keeps its invariant.

$$\forall t, c:\quad \operatorname{CardInv}(c) \;\Rightarrow\; \operatorname{CardInv}(\operatorname{touch}_t(c))$$
-/
theorem touch_inv (t : Nat) (c : Card) (h : CardInv c) : CardInv (touch t c) := h

/-- Every card transition keeps the card invariant.

$$\forall t, b, c:\quad \operatorname{CardInv}(c) \;\Rightarrow\; \operatorname{CardInv}(\operatorname{cardStep}_t(b, c))$$
-/
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

/-- Mapping an invariant-keeping function over the cards keeps the state invariant.

$$\forall \mathit{id}, f, cs:\quad (\forall c:\ \operatorname{CardInv}(c) \Rightarrow \operatorname{CardInv}(f(c))) \ \land\ (\forall c \in cs:\ \operatorname{CardInv}(c)) \;\Rightarrow\; \forall c \in \operatorname{mapCards}(\mathit{id}, f, cs):\ \operatorname{CardInv}(c)$$
-/
theorem mapCards_inv {id : String} {f : Card → Card} {cs : List Card}
    (hf : ∀ c, CardInv c → CardInv (f c)) (h : ∀ c ∈ cs, CardInv c) :
    ∀ c ∈ mapCards id f cs, CardInv c := by
  intro c hc
  simp only [mapCards, List.mem_map] at hc
  obtain ⟨c0, hc0, rfl⟩ := hc
  split
  · exact hf c0 (h c0 hc0)
  · exact h c0 hc0

/-- The empty state satisfies the invariant.

$$\operatorname{Inv}(\sigma_0)$$
-/
theorem inv_init : Inv {} := by simp [Inv]

/-- `accept` keeps the invariant.

$$\forall \sigma, e:\quad \operatorname{Inv}(\sigma) \;\Rightarrow\; \operatorname{Inv}(\operatorname{accept}(\sigma, e))$$
-/
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

/-- `apply` keeps the invariant.

$$\forall \sigma, e:\quad \operatorname{Inv}(\sigma) \;\Rightarrow\; \operatorname{Inv}(\operatorname{apply}(\sigma, e))$$
-/
theorem apply_inv {s : State} (e : Event) (h : Inv s) : Inv (apply s e) := by
  unfold apply step
  split
  · exact h
  · split
    · exact h
    · exact accept_inv e h

/-- Every replayed state satisfies the invariant.

$$\forall L:\quad \operatorname{Inv}(\operatorname{project}(L))$$
-/
theorem project_inv (l : List Event) : Inv (project l) := by
  suffices ∀ s, Inv s → Inv (l.foldl apply s) from this _ inv_init
  induction l with
  | nil => intro s h; exact h
  | cons e l ih => intro s h; exact ih _ (apply_inv e h)

/-- **Land only when ready.** A landing without a violation had all its evidence at the landed
commit.

$$\forall L,\ \forall c \in \operatorname{project}(L).\mathit{cards}:\quad \mathit{landed} \land \neg\mathit{violation} \;\Rightarrow\; \mathit{approved} \land \mathit{head} \ne \bot \land \mathit{screenAt} = \mathit{head} \land \mathit{reviewAt} = \mathit{head} \land (\neg\mathit{needsDevice} \lor \mathit{deviceAt} = \mathit{head})$$
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

/-- An accepted land request is only ever held by a ready card.

$$\forall L,\ \forall c \in \operatorname{project}(L).\mathit{cards}:\quad \mathit{landReq} \ne \bot \land \neg\mathit{landed} \;\Rightarrow\; \operatorname{ready}(c)$$
-/
theorem landReq_ready (l : List Event) (c : Card) (hc : c ∈ (project l).cards)
    (hr : c.landReq.isSome = true) (hl : c.landed = false) : ready c = true :=
  (project_inv l c hc).2.1 hr hl

/-- Reviews are independent: the recorded reviewer neither owns the card nor built on it.

$$\forall L,\ \forall c \in \operatorname{project}(L).\mathit{cards},\ \forall r:\quad \mathit{reviewedBy} = r \;\Rightarrow\; r \ne \mathit{owner} \land r \notin \mathit{builders}$$
-/
theorem review_independent (l : List Event) (c : Card) (hc : c ∈ (project l).cards) (r : String)
    (hr : c.reviewedBy = some r) : r ≠ c.owner ∧ r ∉ c.builders :=
  (project_inv l c hc).2.2 r hr

/-- A new build sends an approved, unlanded card back to `screen`.

$$\forall t \in \mathbb{N},\ \forall \mathit{id}, \mathit{sha}, a, c:\quad \neg c.\mathit{landed} \ \land\ c.\mathit{approved} \;\Rightarrow\; \operatorname{stage}\big(\operatorname{cardStep}_t(\mathrm{cardBuild}(\mathit{id}, \mathit{sha}, a), c)\big) = \mathrm{screen}$$
-/
theorem built_resets (t : Nat) (id sha a : String) (c : Card)
    (hl : c.landed = false) (ha : c.approved = true) :
    stage (cardStep t (.cardBuild id sha a) c) = .screen := by
  simp [cardStep, cardRefusal, hl, touch, stage, ha]

/-- Staleness only grows with time.

$$\forall \mathit{lim}, \mathit{now}, \mathit{now}', w \in \mathbb{N},\ \forall c:\quad \mathit{now} \le \mathit{now}' \ \land\ \operatorname{stale}(\mathit{lim}, \mathit{now}, w, c) \;\Rightarrow\; \operatorname{stale}(\mathit{lim}, \mathit{now}', w, c)$$
-/
theorem stale_mono {lim now now' w : Nat} {c : Card} (h : now ≤ now')
    (hs : stale lim now w c = true) : stale lim now' w c = true := by
  simp [stale] at *; omega

/-- A row with a live wait is never stale.

$$\forall \mathit{lim}, \mathit{now}, w \in \mathbb{N},\ \forall c:\quad 0 < w \;\Rightarrow\; \operatorname{stale}(\mathit{lim}, \mathit{now}, w, c) = \mathrm{false}$$
-/
theorem stale_live {lim now w : Nat} {c : Card} (hw : 0 < w) : stale lim now w c = false := by
  simp [stale]; omega

/-! ## The plan part of the state -/

/-- A plan body that passes `check` passes the plan check.

$$\forall \sigma, e, c:\quad \mathit{body}(e) = \mathrm{plan}(c) \land \operatorname{check}(\sigma, e) = \bot \Rightarrow \operatorname{Plan.check}(\sigma.\mathit{plan}, c) = \bot$$
-/
theorem check_plan {s : State} {e : Event} {c : Fw.Plan.Cmd} (hb : e.body = .plan c)
    (h : check s e = none) : Fw.Plan.check s.plan c = none := by
  unfold check at h
  rw [hb] at h
  split at h
  · cases h
  · exact h

/-- `accept` changes the plan only for a plan body, and then by `Plan.exec`.

$$\forall \sigma, e:\quad \operatorname{accept}(\sigma, e).\mathit{plan} = \sigma.\mathit{plan} \lor \exists c:\ \mathit{body}(e) = \mathrm{plan}(c) \land \operatorname{accept}(\sigma, e).\mathit{plan} = \operatorname{Plan.exec}(\sigma.\mathit{plan}, c)$$
-/
theorem accept_plan_cases (s : State) (e : Event) : (accept s e).plan = s.plan ∨
    ∃ c, e.body = .plan c ∧ (accept s e).plan = Fw.Plan.exec s.plan c := by
  obtain ⟨k, t, a, b⟩ := e
  cases b with
  | plan c => exact .inr ⟨c, rfl, rfl⟩
  | runFinish r ok => left; simp only [accept]; split <;> rfl
  | _ => left; rfl

/-- `apply` changes the plan only by an accepted plan command.

$$\forall \sigma, e:\quad \operatorname{apply}(\sigma, e).\mathit{plan} = \sigma.\mathit{plan} \lor \exists c:\ \mathit{body}(e) = \mathrm{plan}(c) \land \operatorname{Plan.check}(\sigma.\mathit{plan}, c) = \bot \land \operatorname{apply}(\sigma, e).\mathit{plan} = \operatorname{Plan.exec}(\sigma.\mathit{plan}, c)$$
-/
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

/-- `apply` keeps the plan invariant (unique task ids, acyclic dependency graph).

$$\forall \sigma, e:\quad \operatorname{Plan.Inv}(\sigma.\mathit{plan}) \Rightarrow \operatorname{Plan.Inv}(\operatorname{apply}(\sigma, e).\mathit{plan})$$
-/
theorem apply_plan_inv {s : State} (e : Event) (h : Fw.Plan.Inv s.plan) :
    Fw.Plan.Inv (apply s e).plan := by
  rcases apply_plan_cases s e with h1 | ⟨c, _, hc, h1⟩
  · rw [h1]; exact h
  · rw [h1]; exact Fw.Plan.exec_inv h hc

/-- **The console never accepts a dependency cycle**: in every replayed state the task ids are
unique and the dependency graph is acyclic.

$$\forall L:\quad \operatorname{Nodup}(\operatorname{ids}(\operatorname{project}(L).\mathit{plan}.\mathit{tasks})) \land \operatorname{Acyclic}(\operatorname{project}(L).\mathit{plan}.\mathit{tasks})$$
-/
theorem project_plan_inv (l : List Event) : Fw.Plan.Inv (project l).plan := by
  suffices ∀ s : State, Fw.Plan.Inv s.plan → Fw.Plan.Inv (l.foldl apply s).plan from
    this _ Fw.Plan.inv_init
  induction l with
  | nil => intro s h; exact h
  | cons e l ih => intro s h; exact ih _ (apply_plan_inv e h)

/-- **Done is monotone over the console reducer**: once a task id is done it stays done.

$$\forall \sigma, e, x:\quad \operatorname{isDone}(\sigma.\mathit{plan}.\mathit{tasks}, x) \Rightarrow \operatorname{isDone}(\operatorname{apply}(\sigma, e).\mathit{plan}.\mathit{tasks}, x)$$
-/
theorem apply_isDone {s : State} (e : Event) {x : String}
    (h : Fw.Plan.isDone s.plan.tasks x = true) : Fw.Plan.isDone (apply s e).plan.tasks x = true := by
  rcases apply_plan_cases s e with h1 | ⟨c, _, hc, h1⟩
  · rw [h1]; exact h
  · rw [h1]; exact Fw.Plan.exec_isDone hc h

/-- Done is monotone over replay: a task done after a log stays done after any extension.

$$\forall L_1, L_2, x:\quad \operatorname{isDone}(\operatorname{project}(L_1).\mathit{plan}.\mathit{tasks}, x) \Rightarrow \operatorname{isDone}(\operatorname{project}(L_1 \mathbin{+\!\!+} L_2).\mathit{plan}.\mathit{tasks}, x)$$
-/
theorem project_isDone (l₁ l₂ : List Event) {x : String}
    (h : Fw.Plan.isDone (project l₁).plan.tasks x = true) :
    Fw.Plan.isDone (project (l₁ ++ l₂)).plan.tasks x = true := by
  rw [project_append]
  induction l₂ generalizing l₁ with
  | nil => exact h
  | cons e l ih =>
    have := ih (l₁ ++ [e]) (by rw [project_append]; exact apply_isDone e h)
    rw [project_append] at this
    simpa using this

/-! ## Examples run at build time (the console-mvp table, abridged) -/

#guard may .owner .cardOpen && !may .owner .cardApprove && !may .user .stepPost && !may .hook .cardOpen
#guard may .hook (.plan .claim) && !may .hook (.plan .define) && may .git (.plan .done)
  && !may .owner (.plan .define) && may .script (.plan .milestone)
#guard
  let ev (k : String) (a : Actor) (c : Fw.Plan.Cmd) : Event := ⟨k, 0, a, .plan c⟩
  let s := project [ev "p1" .lead (.define (Fw.Plan.mk "a" [])),
                    ev "p2" .lead (.define (Fw.Plan.mk "b" ["a"]))]
  (step s (ev "p3" .lead (.define (Fw.Plan.mk "a" ["b"])))).2 == .refused "dependency cycle"
  && (step s (ev "p3" .owner (.drop "b"))).2 == .refused "actor owner may not cause task.drop"
  && (step s (ev "p3" .hook (.claim "a" "agent-1"))).2 == .accepted false
  && (Fw.Plan.view (apply s (ev "p3" .git (.done "a" "abc1234"))).plan).tasks.map (·.state)
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

end Fw.Console
