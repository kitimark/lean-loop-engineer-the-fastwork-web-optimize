import Fw.Console
/-!
# The console's own events

console-api emits a few events itself, not on behalf of a person: the spool drain posts alert
steps and records agent spawns and stops, and the git reconciler records builds, landings and done
tasks and syncs the plan (task and milestone defines) from main's head.
This module fixes which actor each source writes as and which event type it emits, and proves
that every such pair is allowed by the `MAY` table and that the console never writes as a
person or an agent role (user, lead, owner, reviewer).
-/

namespace Fw.Console.Self
open Fw.Console

/-- A place in console-api that emits an event by itself.

$$\mathrm{Source} = \{\mathrm{alert}, \mathrm{spawn}, \mathrm{stop}, \mathrm{build}, \mathrm{landed}, \mathrm{taskDone}, \mathrm{planDefine}, \mathrm{planMilestone}\}$$
-/
inductive Source where
  | alert | spawn | stop | build | landed | taskDone | planDefine | planMilestone
deriving Repr, DecidableEq

/-- Every source, in a fixed order.

$$\mathrm{sources} = [\mathrm{alert}, \mathrm{spawn}, \mathrm{stop}, \mathrm{build}, \mathrm{landed}, \mathrm{taskDone}, \mathrm{planDefine}, \mathrm{planMilestone}]$$
-/
def sources : List Source := [.alert, .spawn, .stop, .build, .landed, .taskDone, .planDefine, .planMilestone]

/-- The wire name of a source.

$$\operatorname{name}(s) = \begin{cases} \texttt{"alert"} & s = \mathrm{alert} \\ \texttt{"spawn"} & s = \mathrm{spawn} \\ \texttt{"stop"} & s = \mathrm{stop} \\ \texttt{"build"} & s = \mathrm{build} \\ \texttt{"landed"} & s = \mathrm{landed} \\ \texttt{"taskDone"} & s = \mathrm{taskDone} \\ \texttt{"planDefine"} & s = \mathrm{planDefine} \\ \texttt{"planMilestone"} & s = \mathrm{planMilestone} \end{cases}$$
-/
def Source.name : Source → String
  | .alert => "alert" | .spawn => "spawn" | .stop => "stop" | .build => "build"
  | .landed => "landed" | .taskDone => "taskDone" | .planDefine => "planDefine"
  | .planMilestone => "planMilestone"

/-- The source with wire name `n`, if any.

$$\operatorname{ofName}(n) = \text{the first } s \in \mathrm{sources} \text{ with } \operatorname{name}(s) = n, \text{ or } \bot \text{ if there is none}$$
-/
def Source.ofName (n : String) : Option Source := sources.find? (·.name == n)

/-- The actor a source writes as: the drain's alerts and the reconciler's plan sync are the
`script` actor, the drain's spawns and stops the `hook` actor, and the reconciler's git facts the
`git` actor.

$$\operatorname{actor}(s) = \begin{cases} \mathrm{script} & s \in \{\mathrm{alert}, \mathrm{planDefine}, \mathrm{planMilestone}\} \\ \mathrm{hook} & s \in \{\mathrm{spawn}, \mathrm{stop}\} \\ \mathrm{git} & s \in \{\mathrm{build}, \mathrm{landed}, \mathrm{taskDone}\} \end{cases}$$
-/
def actor : Source → Actor
  | .alert | .planDefine | .planMilestone => .script
  | .spawn | .stop => .hook
  | .build | .landed | .taskDone => .git

/-- The event type a source emits.

$$\operatorname{evType}(s) = \begin{cases} \texttt{step.post} & s = \mathrm{alert} \\ \texttt{agent.spawn} & s = \mathrm{spawn} \\ \texttt{agent.stop} & s = \mathrm{stop} \\ \texttt{card.build} & s = \mathrm{build} \\ \texttt{card.landed} & s = \mathrm{landed} \\ \texttt{task.done} & s = \mathrm{taskDone} \\ \texttt{task.define} & s = \mathrm{planDefine} \\ \texttt{milestone.define} & s = \mathrm{planMilestone} \end{cases}$$
-/
def evType : Source → EvType
  | .alert => .stepPost
  | .spawn => .plan .spawn
  | .stop => .plan .stop
  | .build => .cardBuild
  | .landed => .cardLanded
  | .taskDone => .plan .done
  | .planDefine => .plan .define
  | .planMilestone => .plan .milestone

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

$$\forall s \in \mathrm{Source}:\ s \in \mathrm{sources} \land \operatorname{ofName}(\operatorname{name}(s)) = \mathrm{some}(s)$$
-/
theorem ofName_name (s : Source) : s ∈ sources ∧ Source.ofName s.name = some s := by
  cases s <;> decide

/-! ## Examples -/

#guard (actor .alert).name == "script"
#guard (evType .alert).name == "step.post"
#guard (actor .spawn).name == "hook" && (evType .spawn).name == "agent.spawn"
#guard (actor .stop).name == "hook" && (evType .stop).name == "agent.stop"
#guard (actor .taskDone).name == "git" && (evType .taskDone).name == "task.done"
#guard (actor .planDefine).name == "script" && (evType .planDefine).name == "task.define"
#guard (actor .planMilestone).name == "script" && (evType .planMilestone).name == "milestone.define"
#guard Source.ofName "landed" == some .landed
#guard Source.ofName "claim" == none
#guard Source.ofName "nope" == none
#guard sources.all fun s => may (actor s) (evType s)

end Fw.Console.Self
