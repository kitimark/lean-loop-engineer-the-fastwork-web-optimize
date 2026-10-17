import Fw.Console
import Fw.Ops.PathCheck
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

/-! ## Land scope: which files a landing may change -/

open Fw.Ops.PathCheck

/-- Paths no landing may ever change (console state, repo internals, settings, the Lean build); written as
exclusion globs, so they win over every include.

$$P = \{\texttt{.fw-console/},\ \texttt{.git/},\ \texttt{.claude/settings*},\ \texttt{lean/.lake/}\}$$
-/
def protectedGlobs : List String := ["!.fw-console/", "!.git/", "!.claude/settings*", "!lean/.lake/"]

/-- Generated outputs that any task may regenerate.

$$S_{gen} = \{\texttt{**/*.gen.json},\ \texttt{packages/contracts/golden/**},\ \texttt{lean/golden/**},\ \texttt{lean/math.lock.json}\}$$
-/
def generated : List String :=
  ["**/*.gen.json", "packages/contracts/golden/**", "lean/golden/**", "lean/math.lock.json"]

/-- The one-line registrations every new module needs.

$$S_{reg} = \{\texttt{lean/Fw.lean},\ \texttt{lean/Fw/Wire.lean},\ \texttt{lean/FwTestMain.lean},\ \texttt{apps/runner/src/fw.ts}\}$$
-/
def registrations : List String :=
  ["lean/Fw.lean", "lean/Fw/Wire.lean", "lean/FwTestMain.lean", "apps/runner/src/fw.ts"]

/-- A name usable in a handoff file name: non-empty, only letters, digits, `-`, `_` and `.`, and not `.` or
`..` (no `/`, no `*`), so a name can never widen the scope.

$$\operatorname{safe}(n) \iff n \ne \varepsilon \land n \notin \{\texttt{.}, \texttt{..}\} \land \forall c \in n:\ c \in [A\text{-}Za\text{-}z0\text{-}9\_.-]$$
-/
def safeName (n : String) : Bool :=
  !n.isEmpty && n != "." && n != ".." &&
    n.toList.all fun c => c.isAlphanum || c == '-' || c == '_' || c == '.'

/-- The handoff globs of the given agent or task names (names that are not plain are dropped).

$$H(N) = [\texttt{docs/team/handoffs/}n\texttt{.md} : n \in N,\ \operatorname{safe}(n)]$$
-/
def handoffs (names : List String) : List String :=
  (names.filter safeName).map fun n => "docs/team/handoffs/" ++ n ++ ".md"

/-- The scope of a landing of a task with write globs `w`, names `N` (task id, owner), and explicit
`--allow` globs `a`.

$$\operatorname{scope}(w, N, a) = w \mathbin{+\!\!+} H(N) \mathbin{+\!\!+} S_{gen} \mathbin{+\!\!+} S_{reg} \mathbin{+\!\!+} a \mathbin{+\!\!+} P$$
-/
def landScope (writes names allow : List String) : List String :=
  writes ++ handoffs names ++ generated ++ registrations ++ allow ++ protectedGlobs

/-- The verdict on a landing.

$$\mathrm{Verdict} = \mathrm{ok} \mid \mathrm{noWrites} \mid \mathrm{outOfScope}(V)$$
-/
inductive Verdict where
  | ok | noWrites | outOfScope (vs : List String)
deriving Repr, DecidableEq

/-- May the changed `paths` land? A task with neither writes nor an explicit `--allow` is refused as
`noWrites`; otherwise the paths outside `landScope` are the violations.

$$\operatorname{verdict}(w, N, a, X) = \begin{cases} \mathrm{noWrites} & w = [\,] \land a = [\,] \\ \mathrm{ok} & \mathrm{violations}(\operatorname{scope}(w,N,a), X) = [\,] \\ \mathrm{outOfScope}(\mathrm{violations}(\operatorname{scope}(w,N,a), X)) & \text{otherwise} \end{cases}$$
-/
def landVerdict (writes names allow paths : List String) : Verdict :=
  if writes.isEmpty && allow.isEmpty then .noWrites
  else match violations (landScope writes names allow) paths with
    | [] => .ok
    | vs => .outOfScope vs

/-- A literal directory glob `d/**` only matches paths that start with `d` (a directory prefix check).

$$\forall d,\ x:\quad d \ne \texttt{**} \land \texttt{*} \notin d \land \mathrm{mp}([d, \texttt{**}], x) \Rightarrow \operatorname{head}(x) = d$$
-/
theorem matchesPath_dir_prefix (d : String) (hd : d ≠ "**") (hs : '*' ∉ d.toList) (x : List String)
    (h : matchesPath [d, "**"] x = true) : x.head? = some d := by
  simp only [matchesPath, List.any_eq_true, List.mem_range] at h
  obtain ⟨k, _, hm⟩ := h
  cases x with
  | nil => simp [globMatch, hd] at hm
  | cons y ys =>
    simp only [List.take_succ_cons, globMatch, hd, Bool.and_eq_true] at hm
    have := (segMatch_lit d.toList y.toList hs).mp hm.1
    simp [String.toList_inj.mp this]

/-- A path matched by no include glob of the scope is reported as a violation: nothing outside every glob lands.

$$\forall G, x:\quad \big(\forall g \in I(G):\ \lnot\mathrm{mp}(g, \mathrm{segs}(x))\big) \Rightarrow x \in \mathrm{violations}(G, [x])$$
-/
theorem outside_every_glob_refused (G : List String) (x : String)
    (h : ∀ g ∈ (parseScope G).incl, matchesPath g (segs x) = false) : x ∈ violations G [x] := by
  rw [mem_violations]
  refine ⟨by simp, ?_⟩
  cases hi : inScope (parseScope G) x
  · rfl
  · obtain ⟨_, _, ⟨g, hg, hm⟩, _⟩ := (inScope_iff _ _).mp hi
    rw [h g hg] at hm; cases hm

/-- An exclusion glob `!g` in the scope refuses every path it matches, whatever else (writes, `--allow`) includes it;
the protected paths of `protectedGlobs` are such exclusions.

$$\forall G, x, g \in G:\quad g_0 = \texttt{!} \land \mathrm{mp}(\mathrm{segs}(g_{1..}), \mathrm{segs}(x)) \Rightarrow x \in \mathrm{violations}(G, [x])$$
-/
theorem excluded_refused (G : List String) (x g : String) (hg : g ∈ G) (hb : g.startsWith "!" = true)
    (hm : matchesPath (segs (g.drop 1).toString) (segs x) = true) : x ∈ violations G [x] := by
  rw [mem_violations]
  refine ⟨by simp, ?_⟩
  refine excl_wins _ x _ ?_ hm
  simp only [parseScope, List.mem_map, List.mem_filter]
  exact ⟨g, ⟨hg, hb⟩, rfl⟩

/-- No writes and no `--allow`: the landing is refused, whatever the paths.

$$\forall N, X:\quad \operatorname{verdict}([\,], N, [\,], X) = \mathrm{noWrites}$$
-/
theorem noWrites_refused (n paths : List String) : landVerdict [] n [] paths = .noWrites := by
  simp [landVerdict]

/-- The verdict is `ok` exactly when the task has writes or an allow and every changed path is in scope.

$$\operatorname{verdict}(w,N,a,X) = \mathrm{ok} \iff (w \ne [\,] \lor a \ne [\,]) \land \mathrm{violations}(\operatorname{scope}(w,N,a), X) = [\,]$$
-/
theorem landVerdict_ok_iff (w n a paths : List String) :
    landVerdict w n a paths = .ok ↔ (w ≠ [] ∨ a ≠ []) ∧ violations (landScope w n a) paths = [] := by
  unfold landVerdict
  cases w with
  | cons x xs => cases hv : violations (landScope (x :: xs) n a) paths <;> simp [hv]
  | nil =>
    cases a with
    | nil => simp
    | cons y ys => cases hv : violations (landScope [] n (y :: ys)) paths <;> simp [hv]

private def tw : List String := ["apps/runner/src/land.ts", "apps/runner/test/land*.ts"]

#guard landVerdict tw ["pa-land"] [] ["apps/runner/src/land.ts", "apps/runner/test/land-x.ts", "docs/team/handoffs/pa-land.md"] == .ok
#guard landVerdict tw ["pa-land"] [] ["apps/runner/src/other.ts"] == .outOfScope ["apps/runner/src/other.ts"]
#guard landVerdict tw ["pa-land"] [] ["docs/team/handoffs/other.md"] == .outOfScope ["docs/team/handoffs/other.md"]
#guard landVerdict tw ["pa-land"] [] ["packages/contracts/golden/ops/a.jsonl", "packages/gate-breakpoints/src/scope.gen.json", "lean/Fw.lean"] == .ok
#guard landVerdict tw ["../x", "a/*"] [] ["docs/team/handoffs/../x.md", "docs/team/handoffs/a/b.md"] ==
  .outOfScope ["docs/team/handoffs/../x.md", "docs/team/handoffs/a/b.md"]
#guard landVerdict [] ["pa-land"] [] ["a"] == .noWrites
#guard landVerdict [] ["pa-land"] ["notes/**"] ["notes/a.md", "x.md"] == .outOfScope ["x.md"]
#guard landVerdict ["**"] ["t"] [] [".git/config", ".fw-console/events.jsonl", "lean/.lake/x", ".claude/settings.json", "a.md"] ==
  .outOfScope [".git/config", ".fw-console/events.jsonl", "lean/.lake/x", ".claude/settings.json"]

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
