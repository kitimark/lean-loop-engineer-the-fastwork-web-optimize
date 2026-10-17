import Fw.Console
/-!
# Land readiness of a card

What a card still needs before `card.land_request` may be accepted, as a list a console card can
show ("approve", "build", "screen", "review", "device"), and the exact refusal the reducer gives a
land request at a sha. `landNeeds c = []` is exactly `ready c` (`landNeeds_nil_iff`), and the
refusal is exactly `cardRefusal` on a `card.land_request` (`landRefusal_none_iff`), so the card
view and the reducer cannot disagree.
-/

namespace Fw.Console.Land
open Fw.Console

/-- One thing a card still needs before it may land.

$$\mathrm{Need} = \{\mathrm{approve}, \mathrm{build}, \mathrm{screen}, \mathrm{review}, \mathrm{device}\}$$
-/
inductive Need where
  | approve | build | screen | review | device
deriving Repr, DecidableEq

/-- The wire name of a need.

$$\operatorname{name}(n) = \texttt{"approve"}, \texttt{"build"}, \texttt{"screen"}, \texttt{"review"}, \texttt{"device"} \text{ for } n = \mathrm{approve}, \mathrm{build}, \mathrm{screen}, \mathrm{review}, \mathrm{device}$$
-/
def Need.name : Need → String
  | .approve => "approve" | .build => "build" | .screen => "screen" | .review => "review"
  | .device => "device"

/-- The missing pieces of card `c`, in the fixed order approve, build, screen, review, device;
screen, review and device count only at the current head.

$$\operatorname{landNeeds}(c) = [\mathrm{approve} \mid \neg c.\mathit{approved}] \mathbin{+\!\!+} [\mathrm{build} \mid c.\mathit{head} = \bot] \mathbin{+\!\!+} [\mathrm{screen} \mid \neg(c.\mathit{head} \ne \bot \land c.\mathit{screenAt} = c.\mathit{head})] \mathbin{+\!\!+} [\mathrm{review} \mid \neg(c.\mathit{head} \ne \bot \land c.\mathit{reviewAt} = c.\mathit{head})] \mathbin{+\!\!+} [\mathrm{device} \mid c.\mathit{needsDevice} \land \neg(c.\mathit{head} \ne \bot \land c.\mathit{deviceAt} = c.\mathit{head})]$$

where $[n \mid P]$ is $[n]$ if $P$ holds and $[\,]$ otherwise.
-/
def landNeeds (c : Card) : List Need :=
  let atHead (x : Option String) : Bool := c.head.isSome && decide (x = c.head)
  (if c.approved then [] else [.approve]) ++ (if c.head.isSome then [] else [.build])
    ++ (if atHead c.screenAt then [] else [.screen]) ++ (if atHead c.reviewAt then [] else [.review])
    ++ (if !c.needsDevice || atHead c.deviceAt then [] else [.device])

/-- A card needs nothing more exactly when it is ready to land.

$$\forall c:\ \operatorname{landNeeds}(c) = [\,] \iff \operatorname{ready}(c)$$
-/
theorem landNeeds_nil_iff (c : Card) : landNeeds c = [] ↔ ready c = true := by
  obtain ⟨id, o, nd, ap, hd, b, sc, rv, rb, dv, lr, ld, vi, la⟩ := c
  cases ap <;> cases nd <;> cases hd <;> simp [landNeeds, ready, and_assoc]

/-- The refusal a `card.land_request` for card `c` at `sha` gets from the reducer
(`none` = it would be accepted).

$$\operatorname{landRefusal}(c, \mathit{sha}) = \operatorname{cardRefusal}(c, \mathrm{cardLandRequest}(c.\mathit{id}, \mathit{sha}))$$
-/
def landRefusal (c : Card) (sha : String) : Option String :=
  cardRefusal c (.cardLandRequest c.id sha)

/-- A land request is accepted exactly when the card is not landed, `sha` is its head, and it
needs nothing more.

$$\forall c,\ \forall \mathit{sha}:\ \operatorname{landRefusal}(c, \mathit{sha}) = \bot \iff \neg c.\mathit{landed} \land c.\mathit{head} = \mathit{sha} \land \operatorname{landNeeds}(c) = [\,]$$
-/
theorem landRefusal_none_iff (c : Card) (sha : String) :
    landRefusal c sha = none ↔ c.landed = false ∧ c.head = some sha ∧ landNeeds c = [] := by
  rw [landNeeds_nil_iff]
  unfold landRefusal cardRefusal
  cases c.landed <;> simp
  by_cases h : c.head = some sha <;> simp [h]

/-! ## Examples -/

private def k0 : Card := { id := "c", owner := "o", needsDevice := false }
private def k1 : Card := { k0 with approved := true, head := some "h", screenAt := some "h" }

#guard landNeeds { k0 with needsDevice := true } == [.approve, .build, .screen, .review, .device]
#guard landNeeds k0 == [.approve, .build, .screen, .review]
#guard landNeeds { k1 with needsDevice := true, reviewAt := some "old", deviceAt := some "h" } == [.review]
#guard landNeeds { k1 with reviewAt := some "h" } == []
#guard landNeeds { k1 with needsDevice := true, reviewAt := some "h" } == [.device]
#guard landRefusal { k1 with reviewAt := some "h" } "h" == none
#guard landRefusal { k1 with reviewAt := some "h" } "g" == some "stale sha: not the head commit"
#guard landRefusal { k0 with head := some "h" } "h" == some "card is not land-ready"
#guard landRefusal { k0 with landed := true } "h" == some "card already landed"
#guard (landNeeds k0).map Need.name == ["approve", "build", "screen", "review"]

end Fw.Console.Land
