import Fw.Console
/-!
# The console's own events

console-api emits a few events itself, not on behalf of a person: the spool drain posts alert
steps and records task claims, and the git reconciler records builds, landings and done tasks.
This module fixes which actor each source writes as and which event type it emits, and proves
that every such pair is allowed by the `MAY` table and that the console never writes as a
person or an agent role (user, lead, owner, reviewer).
-/

namespace Fw.Console.Self
open Fw.Console

/-- A place in console-api that emits an event by itself.

$$\mathrm{Source} = \{\mathrm{alert}, \mathrm{claim}, \mathrm{build}, \mathrm{landed}, \mathrm{taskDone}\}$$
-/
inductive Source where
  | alert | claim | build | landed | taskDone
deriving Repr, DecidableEq

/-- Every source, in a fixed order.

$$\mathrm{sources} = [\mathrm{alert}, \mathrm{claim}, \mathrm{build}, \mathrm{landed}, \mathrm{taskDone}]$$
-/
def sources : List Source := [.alert, .claim, .build, .landed, .taskDone]

/-- The wire name of a source.

$$\operatorname{name}(s) = \texttt{"alert"}, \texttt{"claim"}, \texttt{"build"}, \texttt{"landed"}, \texttt{"taskDone"} \text{ for } s = \mathrm{alert}, \mathrm{claim}, \mathrm{build}, \mathrm{landed}, \mathrm{taskDone}$$
-/
def Source.name : Source → String
  | .alert => "alert" | .claim => "claim" | .build => "build" | .landed => "landed"
  | .taskDone => "taskDone"

/-- The source with wire name `n`, if any.

$$\operatorname{ofName}(n) = \text{the first } s \in \mathrm{sources} \text{ with } \operatorname{name}(s) = n, \text{ or } \bot \text{ if there is none}$$
-/
def Source.ofName (n : String) : Option Source := sources.find? (·.name == n)

/-- The actor a source writes as: the drain's alerts are the `script` actor, its claims the
`hook` actor, and the reconciler's facts the `git` actor.

$$\operatorname{actor}(s) = \begin{cases} \mathrm{script} & s = \mathrm{alert} \\ \mathrm{hook} & s = \mathrm{claim} \\ \mathrm{git} & s \in \{\mathrm{build}, \mathrm{landed}, \mathrm{taskDone}\} \end{cases}$$
-/
def actor : Source → Actor
  | .alert => .script
  | .claim => .hook
  | .build | .landed | .taskDone => .git

/-- The event type a source emits.

$$\operatorname{evType}(s) = \begin{cases} \texttt{step.post} & s = \mathrm{alert} \\ \texttt{task.claim} & s = \mathrm{claim} \\ \texttt{card.build} & s = \mathrm{build} \\ \texttt{card.landed} & s = \mathrm{landed} \\ \texttt{task.done} & s = \mathrm{taskDone} \end{cases}$$
-/
def evType : Source → EvType
  | .alert => .stepPost
  | .claim => .plan .claim
  | .build => .cardBuild
  | .landed => .cardLanded
  | .taskDone => .plan .done

/-- Every event the console emits by itself is allowed for the actor it writes as.

$$\forall s \in \mathrm{Source}:\ \operatorname{may}(\operatorname{actor}(s), \operatorname{evType}(s)) = \mathrm{true}$$
-/
theorem may_self (s : Source) : may (actor s) (evType s) = true := by
  cases s <;> decide

/-- The console never writes as a person or an agent role.

$$\forall s \in \mathrm{Source}:\ \operatorname{actor}(s) \in \{\mathrm{script}, \mathrm{git}, \mathrm{hook}\}$$
-/
theorem actor_machine (s : Source) : actor s = .script ∨ actor s = .git ∨ actor s = .hook := by
  cases s <;> simp [actor]

/-- Every source is in `sources` and is found again by its wire name.

$$\forall s \in \mathrm{Source}:\ s \in \mathrm{sources} \land \operatorname{ofName}(\operatorname{name}(s)) = s$$
-/
theorem ofName_name (s : Source) : s ∈ sources ∧ Source.ofName s.name = some s := by
  cases s <;> decide

/-! ## Examples -/

#guard (actor .alert).name == "script"
#guard (evType .alert).name == "step.post"
#guard (actor .claim).name == "hook" && (evType .claim).name == "task.claim"
#guard (actor .taskDone).name == "git" && (evType .taskDone).name == "task.done"
#guard Source.ofName "landed" == some .landed
#guard Source.ofName "nope" == none
#guard sources.all fun s => may (actor s) (evType s)

end Fw.Console.Self
