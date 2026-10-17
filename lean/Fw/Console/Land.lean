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

$$P = [\texttt{!.fw-console/},\ \texttt{!.git/},\ \texttt{!.claude/settings*},\ \texttt{!lean/.lake/}]$$

(a list, in this order; each entry keeps the leading `!` of an exclusion glob.)
-/
def protectedGlobs : List String := ["!.fw-console/", "!.git/", "!.claude/settings*", "!lean/.lake/"]

/-- Generated outputs that any task may regenerate.

$$S_{gen} = \{\texttt{**/*.gen.json},\ \texttt{packages/contracts/golden/**},\ \texttt{lean/golden/**},\ \texttt{lean/math.lock.json}\}$$
-/
def generated : List String :=
  ["**/*.gen.json", "packages/contracts/golden/**", "lean/golden/**", "lean/math.lock.json"]

/-- The registrations every new module needs: the wire modules, the library root, the test main and the CLI entry point.

$$S_{reg} = \{\texttt{lean/Fw/Wire/**.lean},\ \texttt{lean/Fw/*/Wire.lean},\ \texttt{lean/Fw/Wire.lean},\ \texttt{lean/Fw.lean},\ \texttt{lean/FwTestMain.lean},\ \texttt{apps/runner/src/fw.ts}\}$$
-/
def registrations : List String :=
  ["lean/Fw/Wire/**.lean", "lean/Fw/*/Wire.lean", "lean/Fw/Wire.lean", "lean/Fw.lean", "lean/FwTestMain.lean",
    "apps/runner/src/fw.ts"]

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

/-- The test glob of a written path under `apps|packages/<n>/src/`: the same package's `test/` directory
(`n` a plain name, so it never widens the scope).

$$\operatorname{testGlob}(w) = \begin{cases} p/n/\texttt{test/**} & \mathrm{splitOn}(w,\texttt{/}) = p :: n :: \texttt{src} :: r\ (r \text{ possibly empty}),\ p \in \{\texttt{apps},\texttt{packages}\},\ \operatorname{safe}(n) \\ \bot & \text{otherwise} \end{cases}$$
-/
def testGlob (w : String) : Option String :=
  match w.splitOn "/" with
  | p :: n :: "src" :: _ =>
    if (p == "apps" || p == "packages") && safeName n then some (p ++ "/" ++ n ++ "/test/**") else none
  | _ => none

/-- The test globs of all written paths.

$$T(w) = [\operatorname{testGlob}(x) : x \in w,\ \operatorname{testGlob}(x) \ne \bot]$$
-/
def testGlobs (writes : List String) : List String := writes.filterMap testGlob

/-- A test glob exists exactly for a write `p/n/src/...` with `p` apps or packages and a plain `n`, and it is that
package's `p/n/test/**`; any other write (no `src`, another root, a wildcard in `n`) yields none.

$$\operatorname{testGlob}(w) = \mathrm{some}(g) \iff \exists p, n, r:\ \mathrm{splitOn}(w,\texttt{/}) = p :: n :: \texttt{src} :: r \land p \in \{\texttt{apps},\texttt{packages}\} \land \operatorname{safe}(n) \land g = p/n/\texttt{test/**}$$

(`r` is the list of remaining segments and may be empty: `apps/x/src` also qualifies.)
-/
theorem testGlob_eq_some (w g : String) :
    testGlob w = some g ↔ ∃ p n rest, w.splitOn "/" = p :: n :: "src" :: rest ∧
      (p = "apps" ∨ p = "packages") ∧ safeName n = true ∧ g = p ++ "/" ++ n ++ "/test/**" := by
  unfold testGlob
  constructor
  · intro h
    rcases hs : w.splitOn "/" with _ | ⟨p, _ | ⟨n, _ | ⟨s, rest⟩⟩⟩ <;> rw [hs] at h
    · simp at h
    · simp at h
    · simp at h
    · by_cases hsrc : s = "src"
      · subst hsrc
        by_cases hc : ((p == "apps" || p == "packages") && safeName n) = true
        · simp only [hc, ite_true, Option.some.injEq] at h
          simp only [Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at hc
          exact ⟨p, n, rest, rfl, hc.1, hc.2, h.symm⟩
        · simp only [hc] at h; cases h
      · simp [hsrc] at h
  · rintro ⟨p, n, rest, hs, hp, hn, hg⟩
    rw [hs]
    rcases hp with rfl | rfl <;> simp [hn, hg]

/-! ### Task kinds and their registration sets -/

/-- What a task is, from its id and stream: a port of site part `part` (`port-<part>`), a proof of part `part`
(`proof-<part>`), a measurement task (stream `measure`), or anything else.

$$\mathrm{Kind} = \mathrm{port}(p) \mid \mathrm{proof}(p) \mid \mathrm{measure} \mid \mathrm{other}$$
-/
inductive TaskKind where
  | port (part : String) | proof (part : String) | measure | other
deriving Repr, DecidableEq

/-- The kind of a task from its id and stream; a `port-` or `proof-` id wins over the stream.

$$\operatorname{kind}(i, s) = \begin{cases} \mathrm{port}(i_{5..}) & i = \texttt{port-}\cdots \\ \mathrm{proof}(i_{6..}) & i = \texttt{proof-}\cdots \\ \mathrm{measure} & s = \texttt{measure} \\ \mathrm{other} & \text{otherwise} \end{cases}$$
-/
def taskKind (id stream : String) : TaskKind :=
  if id.startsWith "port-" then .port (id.drop 5).toString
  else if id.startsWith "proof-" then .proof (id.drop 6).toString
  else if stream == "measure" then .measure
  else .other

/-- The Lean module stem of a part name: `hero-exit` becomes `HeroExit`. Only non-empty segments of letters and
digits qualify, so the stem can never widen a glob.

$$\operatorname{pascal}(p) = \begin{cases} \mathrm{cap}(s_1)\cdots\mathrm{cap}(s_k) & p = s_1\texttt{-}\cdots\texttt{-}s_k,\ \forall i:\ s_i \ne \varepsilon \land s_i \in [A\text{-}Za\text{-}z0\text{-}9]^* \\ \bot & \text{otherwise} \end{cases}$$
-/
def pascal (part : String) : Option String :=
  let segs := part.splitOn "-"
  if segs.all (fun s => !s.isEmpty && s.toList.all Char.isAlphanum) then some (String.join (segs.map String.capitalize))
  else none

/-- The Lean files of a part: `lean/Fw/Parts/<Stem>*.lean`.

$$\operatorname{partGlobs}(p) = [\texttt{lean/Fw/Parts/}\operatorname{pascal}(p)\texttt{*.lean}]\ \text{if}\ \operatorname{pascal}(p) \ne \bot\ \text{else}\ [\,]$$
-/
def partGlobs (part : String) : List String :=
  match pascal part with
  | some p => ["lean/Fw/Parts/" ++ p ++ "*.lean"]
  | none => []

/-- The files every site-part port registers itself in.

$$S_{port} = \{\texttt{registry/index.ts},\ \texttt{App.tsx},\ \texttt{gen-shells.mjs},\ \texttt{Gate/Scope.lean},\ \texttt{Parts/Golden.lean},\ \texttt{anchors.json},\ \texttt{scope.gen.json}\}$$
-/
def portRegs : List String :=
  ["apps/site/src/registry/index.ts", "apps/site/src/App.tsx", "apps/site/scripts/gen-shells.mjs",
    "lean/Fw/Gate/Scope.lean", "lean/Fw/Parts/Golden.lean",
    "packages/gate-breakpoints/src/anchors.json", "packages/gate-breakpoints/src/scope.gen.json"]

/-- The registration set of a task kind.

$$\operatorname{reg}(k) = \begin{cases} S_{port} \mathbin{+\!\!+} \operatorname{partGlobs}(p) & k = \mathrm{port}(p) \\ \operatorname{partGlobs}(p) \mathbin{+\!\!+} [\texttt{packages/contracts/golden/engine/}p\texttt{.jsonl}\mid \operatorname{pascal}(p) \ne \bot] & k = \mathrm{proof}(p) \\ [\texttt{packages/measure-*/**},\ \texttt{results/baselines/**}] & k = \mathrm{measure} \\ [\,] & k = \mathrm{other} \end{cases}$$
-/
def kindRegs : TaskKind → List String
  | .port part => portRegs ++ partGlobs part
  | .proof part =>
    partGlobs part ++ (if (pascal part).isSome then ["packages/contracts/golden/engine/" ++ part ++ ".jsonl"] else [])
  | .measure => ["packages/measure-*/**", "results/baselines/**"]
  | .other => []

/-- The scope of a landing of task `t` of stream `s` with write globs `w`, names `N` (task id, owner), and explicit
`--allow` globs `a`: the writes, the test globs, the handoffs, the generated outputs, the always-needed
registrations, the registration set of the task's kind, `--allow`, and last the protected exclusions.

$$\operatorname{scope}(w, N, a, t, s) = w \mathbin{+\!\!+} T(w) \mathbin{+\!\!+} H(N) \mathbin{+\!\!+} S_{gen} \mathbin{+\!\!+} S_{reg} \mathbin{+\!\!+} \operatorname{reg}(\operatorname{kind}(t, s)) \mathbin{+\!\!+} a \mathbin{+\!\!+} P$$
-/
def landScope (writes names allow : List String) (task stream : String := "") : List String :=
  writes ++ testGlobs writes ++ handoffs names ++ generated ++ registrations ++ kindRegs (taskKind task stream) ++ allow ++
    protectedGlobs

/-- Every test glob is in the scope of the landing.

$$\forall g \in T(w):\ g \in \operatorname{scope}(w, N, a, t, s)$$
-/
theorem landScope_mem_tests (writes names allow : List String) (task stream : String) (g : String)
    (h : g ∈ testGlobs writes) : g ∈ landScope writes names allow task stream := by
  unfold landScope
  simp [h]

/-- The protected globs stay last, so no addition (tests, registrations, kind sets, `--allow`) can lift them: the
scope always ends with $P$.

$$\exists X:\ \operatorname{scope}(w,N,a,t,s) = X \mathbin{+\!\!+} P$$
-/
theorem landScope_protected_suffix (writes names allow : List String) (task stream : String) :
    ∃ x, landScope writes names allow task stream = x ++ protectedGlobs :=
  ⟨writes ++ testGlobs writes ++ handoffs names ++ generated ++ registrations ++ kindRegs (taskKind task stream) ++ allow,
    by simp [landScope]⟩

/-- The admitted globs are exactly the task's writes (with their tests), its handoffs, the generated and always-needed
registrations, the registration set of its kind, the explicit `--allow`, and the protected exclusions; nothing else.

$$g \in \operatorname{scope}(w,N,a,t,s) \iff g \in w \cup T(w) \cup H(N) \cup S_{gen} \cup S_{reg} \cup \operatorname{reg}(\operatorname{kind}(t,s)) \cup a \cup P$$
-/
theorem mem_landScope_iff (writes names allow : List String) (task stream g : String) :
    g ∈ landScope writes names allow task stream ↔
      g ∈ writes ∨ g ∈ testGlobs writes ∨ g ∈ handoffs names ∨ g ∈ generated ∨ g ∈ registrations ∨
      g ∈ kindRegs (taskKind task stream) ∨ g ∈ allow ∨ g ∈ protectedGlobs := by
  simp only [landScope, List.mem_append, or_assoc]

/-- The registration set of a kind is in the scope: a port, proof or measurement task needs no hand-written `--allow`
for its own registration files.

$$\forall g \in \operatorname{reg}(\operatorname{kind}(t,s)):\ g \in \operatorname{scope}(w,N,a,t,s)$$
-/
theorem kindRegs_mem_landScope (writes names allow : List String) (task stream g : String)
    (h : g ∈ kindRegs (taskKind task stream)) : g ∈ landScope writes names allow task stream :=
  (mem_landScope_iff _ _ _ _ _ _).mpr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl h))))))

/-- A task of no known kind (not a port, a proof or a measurement) has an empty registration set, so it gains nothing
over the old scope.

$$\operatorname{kind}(t,s) = \mathrm{other} \Rightarrow \operatorname{reg}(\operatorname{kind}(t,s)) = [\,]$$
-/
theorem kindRegs_other (task stream : String) (h : taskKind task stream = .other) :
    kindRegs (taskKind task stream) = [] := by
  rw [h]; rfl

/-- The verdict on a landing.

$$\mathrm{Verdict} = \mathrm{ok} \mid \mathrm{noWrites} \mid \mathrm{outOfScope}(V)$$
-/
inductive Verdict where
  | ok | noWrites | outOfScope (vs : List String)
deriving Repr, DecidableEq

/-- May the changed `paths` land? A task with neither writes nor an explicit `--allow` is refused as
`noWrites`; otherwise the paths outside `landScope` are the violations.

$$\operatorname{verdict}(w, N, a, t, s, X) = \begin{cases} \mathrm{noWrites} & w = [\,] \land a = [\,] \\ \mathrm{ok} & \mathrm{violations}(\operatorname{scope}(w,N,a,t,s), X) = [\,] \\ \mathrm{outOfScope}(\mathrm{violations}(\operatorname{scope}(w,N,a,t,s), X)) & \text{otherwise} \end{cases}$$
-/
def landVerdict (writes names allow paths : List String) (task stream : String := "") : Verdict :=
  if writes.isEmpty && allow.isEmpty then .noWrites
  else match violations (landScope writes names allow task stream) paths with
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

/-- Every protected glob is an exclusion (starts with `!`).

$$\forall g \in P:\ g_0 = \texttt{!}$$
-/
theorem protectedGlobs_excl : ∀ g ∈ protectedGlobs, g.startsWith "!" = true := by decide +kernel

/-- Protected paths stay refused whatever the kind: a path matched by a protected glob is a violation of every scope,
however many registration globs or `--allow` globs would include it.

$$\forall g \in P,\ \forall x:\ \mathrm{mp}(\mathrm{segs}(g_{1..}), \mathrm{segs}(x)) \Rightarrow x \in \mathrm{violations}(\operatorname{scope}(w,N,a,t,s), [x])$$
-/
theorem protected_refused (writes names allow : List String) (task stream : String) (g x : String)
    (hg : g ∈ protectedGlobs) (hm : matchesPath (segs (g.drop 1).toString) (segs x) = true) :
    x ∈ violations (landScope writes names allow task stream) [x] :=
  excluded_refused _ x g
    ((mem_landScope_iff _ _ _ _ _ _).mpr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr hg))))))))
    (protectedGlobs_excl g hg) hm

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

/-! ## The land lock: nothing else commits on main while a land holds its merge open

`fw land` runs `git merge --no-ff --no-commit`, keeps the merge open while the checks run, and only then commits.
Incident `inc-commit-during-land`: another commit on main in that window became the merge commit. The fix is a lock
(`.git/fw-land.lock`) held from the start of the merge to its commit, and a `pre-commit` hook that refuses every
other commit in the locked checkout. This section is the model of that protocol and the decisions the TS glue asks
for (`console.landLock`, `console.landGuard`, `console.landCommit`); the glue only reads facts (is the lock file
there, is its pid alive, is `MERGE_HEAD` there, what is `HEAD`) and runs git.
-/

/-- A commit of the model: its id, its parents, and the task of its `Task:` trailer (if any).

$$\mathrm{Commit} = (\mathit{id},\ \mathit{parents} \in \mathrm{List}\ \mathrm{Id},\ \mathit{task} \in \mathrm{Option}\ \mathrm{Task})$$
-/
structure Commit where
  id : String
  parents : List String
  task : Option String := none
deriving Repr, DecidableEq

/-- The main checkout: its `HEAD`, every commit made so far (newest first), whether the land lock is held, the
open merge's `MERGE_HEAD` (the branch tip) and `HEAD` when the lock was taken ($\mathit{main}_0$).

$$R = (\mathit{head},\ \mathit{log},\ \mathit{locked} \in \mathbb{B},\ \mathit{merge} \in \mathrm{Option}\ \mathrm{Id},\ \mathit{pre})$$
-/
structure Repo where
  head : String
  log : List Commit := []
  locked : Bool := false
  merge : Option String := none
  pre : String := ""
deriving Repr

/-- What can happen in the main checkout: the land takes the lock and opens its merge on branch tip `tip`; someone
else commits (new commit `id`); the land commits its merge as commit `id` with trailer `task`; the land aborts.

$$\mathrm{Ev} = \mathrm{begin}(\mathit{tip}) \mid \mathrm{other}(\mathit{id}) \mid \mathrm{land}(\mathit{id}, \mathit{task}) \mid \mathrm{abort}$$
-/
inductive Event where
  | begin (tip : String) | other (id : String) | land (id task : String) | abort
deriving Repr, DecidableEq

/-- May the land commit its merge now? The lock must be held, `MERGE_HEAD` must still be there (it names the branch
tip), and `HEAD` must still be where the lock was taken. The reply is the branch tip, or the refusal.

$$\operatorname{tip}(L, M, h, p) = \begin{cases} \mathrm{ok}(t) & L \land M = \mathrm{some}(t) \land h = p \\ \mathrm{err}(\text{no lock}) & \lnot L \\ \mathrm{err}(\text{merge state gone}) & L \land M = \bot \\ \mathrm{err}(\text{head moved}) & L \land M \ne \bot \land h \ne p \end{cases}$$
-/
def landTip (locked : Bool) (merge : Option String) (head pre : String) : Except String String :=
  if !locked then .error "no lock"
  else match merge with
    | none => .error "merge state gone"
    | some t => if head == pre then .ok t else .error "head moved"

/-- One step of the main checkout; the second component is the refusal, if any. A commit by someone else is refused
while the lock is held; the land's own commit has parents (`HEAD`, branch tip) and the `Task:` trailer and releases
the lock; an abort only drops the merge and the lock, `HEAD` and the log stay.

$$\mathrm{step}(R, \mathrm{other}(i)) = (R, \mathrm{refused}) \text{ if } R.\mathit{locked}$$
-/
def step (s : Repo) : Event → Repo × Option String
  | .begin tip =>
    if s.locked then (s, some "locked")
    else ({ s with locked := true, merge := some tip, pre := s.head }, none)
  | .other id =>
    if s.locked then (s, some "locked")
    else ({ s with head := id, log := { id := id, parents := [s.head] } :: s.log }, none)
  | .land id task =>
    match landTip s.locked s.merge s.head s.pre with
    | .ok tip =>
      ({ s with head := id, log := { id := id, parents := [s.head, tip], task := some task } :: s.log,
                locked := false, merge := none }, none)
    | .error r => (s, some r)
  | .abort => ({ s with locked := false, merge := none }, none)

/-- Run a list of events from a state.

$$\operatorname{run}(R, [\,]) = R,\quad \operatorname{run}(R, e :: es) = \operatorname{run}(\operatorname{step}(R, e)_1, es)$$
-/
def run (s : Repo) (es : List Event) : Repo := es.foldl (fun r e => (step r e).1) s

/-- Events that neither commit the merge nor drop it: other people's commits (refused while the lock is held) and a
second land trying to take the lock (refused too).

$$\mathrm{safe}(e) \iff e = \mathrm{other}(\cdot) \lor e = \mathrm{begin}(\cdot)$$
-/
def Event.safe : Event → Bool
  | .other _ => true | .begin _ => true | _ => false

/-- A commit attempted by someone else while the lock is held is refused and changes nothing.

$$R.\mathit{locked} \Rightarrow \operatorname{step}(R, \mathrm{other}(i)) = (R, \mathrm{some}(\text{locked}))$$
-/
theorem other_refused_locked (s : Repo) (id : String) (h : s.locked = true) :
    step s (.other id) = (s, some "locked") := by
  simp [step, h]

/-- A second land cannot take the lock while it is held.

$$R.\mathit{locked} \Rightarrow \operatorname{step}(R, \mathrm{begin}(t)) = (R, \mathrm{some}(\text{locked}))$$
-/
theorem begin_refused_locked (s : Repo) (tip : String) (h : s.locked = true) :
    step s (.begin tip) = (s, some "locked") := by
  simp [step, h]

/-- Abort never moves main and never drops a commit: `HEAD` and the log are exactly as before (so `HEAD` is never
below $\mathit{main}_0$).

$$\operatorname{step}(R, \mathrm{abort})_1.\mathit{head} = R.\mathit{head} \land \operatorname{step}(R, \mathrm{abort})_1.\mathit{log} = R.\mathit{log}$$
-/
theorem abort_keeps_main (s : Repo) :
    (step s .abort).1.head = s.head ∧ (step s .abort).1.log = s.log := by
  simp [step]

/-- No step ever drops a commit: every commit of the log stays in it, so a commit that is not part of the merge is
never lost.

$$c \in R.\mathit{log} \Rightarrow c \in \operatorname{step}(R, e)_1.\mathit{log}$$
-/
theorem step_log_mono (s : Repo) (e : Event) (c : Commit) (h : c ∈ s.log) : c ∈ (step s e).1.log := by
  cases e with
  | begin tip => by_cases hl : s.locked <;> simp [step, hl, h]
  | other id => by_cases hl : s.locked <;> simp [step, hl, h]
  | land id task =>
    simp only [step]
    split <;> simp [h]
  | abort => simp [step, h]

/-- Main only moves forward: after a step `HEAD` is the old `HEAD`, or a new commit that has the old `HEAD` as a
parent.

$$\operatorname{step}(R, e)_1.\mathit{head} = R.\mathit{head} \ \lor\ \exists c \in \operatorname{step}(R,e)_1.\mathit{log}:\ c.\mathit{id} = \operatorname{step}(R,e)_1.\mathit{head} \land R.\mathit{head} \in c.\mathit{parents}$$
-/
theorem step_head_forward (s : Repo) (e : Event) :
    (step s e).1.head = s.head ∨
      ∃ c ∈ (step s e).1.log, c.id = (step s e).1.head ∧ s.head ∈ c.parents := by
  cases e with
  | begin tip => by_cases hl : s.locked <;> simp [step, hl]
  | other id => by_cases hl : s.locked <;> simp [step, hl]
  | land id task =>
    simp only [step]
    split
    · right; simp
    · left; rfl
  | abort => left; simp [step]

/-- While the lock is held `HEAD` is where it was when the lock was taken: the lock invariant.

$$I(R) \iff (R.\mathit{locked} \Rightarrow R.\mathit{head} = R.\mathit{pre})$$
-/
def Inv (s : Repo) : Prop := s.locked = true → s.head = s.pre

/-- Every step keeps the lock invariant.

$$I(R) \Rightarrow I(\operatorname{step}(R, e)_1)$$
-/
theorem step_inv (s : Repo) (e : Event) (h : Inv s) : Inv (step s e).1 := by
  unfold Inv at *
  cases e with
  | begin tip => by_cases hl : s.locked <;> simp_all [step]
  | other id => by_cases hl : s.locked <;> simp_all [step]
  | land id task =>
    simp only [step]
    split <;> simp_all
  | abort => simp [step]

/-- Within the lock window the safe events change nothing: other commits are refused, a second lock is refused.

$$R.\mathit{locked} \land (\forall e \in es:\ \mathrm{safe}(e)) \Rightarrow \operatorname{run}(R, es) = R$$
-/
theorem run_safe_locked (es : List Event) : ∀ (s : Repo), s.locked = true → (∀ e ∈ es, e.safe = true) →
    run s es = s := by
  induction es with
  | nil => intro s _ _; rfl
  | cons e es ih =>
    intro s hl hs
    have he : e.safe = true := hs e (by simp)
    have h1 : (step s e).1 = s := by
      cases e with
      | begin tip => simp [step, hl]
      | other id => simp [step, hl]
      | land id task => simp [Event.safe] at he
      | abort => simp [Event.safe] at he
    show run (step s e).1 es = s
    rw [h1]
    exact ih s hl (fun e' he' => hs e' (by simp [he']))

/-- The land's commit has parents exactly ($\mathit{main}_0$, branch tip) and carries the `Task:` trailer, whatever
safe events (other commits, second lands) happen in the window: the new commit is the head of the log, it names the
`HEAD` the lock was taken at and the tip the merge was opened with, and the land is the only commit that moved main.

$$\operatorname{step}(\mathrm{begin}(t))\ \text{from an unlocked}\ R_0,\ \text{then}\ es\ (\text{all safe}),\ \text{then}\ \mathrm{land}(i,k):\quad \operatorname{log}' = (i, [R_0.\mathit{head}, t], \mathrm{some}(k)) :: R_0.\mathit{log} \land \mathit{head}' = i \land \mathit{locked}' = \bot$$
-/
theorem land_commit_exact (s : Repo) (tip id task : String) (es : List Event) (hu : s.locked = false)
    (hs : ∀ e ∈ es, e.safe = true) :
    let s1 := (step s (.begin tip)).1
    let s2 := (step (run s1 es) (.land id task)).1
    s2.log = { id := id, parents := [s.head, tip], task := some task } :: s.log ∧ s2.head = id ∧ s2.locked = false := by
  intro s1 s2
  have h1 : s1 = { s with locked := true, merge := some tip, pre := s.head } := by
    simp [s1, step, hu]
  have hr : run s1 es = s1 := run_safe_locked es s1 (by simp [h1]) hs
  simp only [s2, hr]
  rw [h1]
  simp [step, landTip]

/-- The land does not commit when the merge state is gone or `HEAD` moved; it refuses and leaves main as it is (no
reset).

$$\operatorname{step}(R, \mathrm{land}(i,k)) = (R, \mathrm{some}(r)) \text{ whenever } \lnot R.\mathit{locked} \lor R.\mathit{merge} = \bot \lor R.\mathit{head} \ne R.\mathit{pre}$$
-/
theorem land_refused_leaves_main (s : Repo) (id task : String)
    (h : s.locked = false ∨ s.merge = none ∨ s.head ≠ s.pre) :
    (step s (.land id task)).1 = s ∧ (step s (.land id task)).2 ≠ none := by
  rcases h with h | h | h
  · simp [step, landTip, h]
  · cases hl : s.locked <;> simp [step, landTip, h, hl]
  · cases hl : s.locked <;> cases hm : s.merge <;> simp [step, landTip, h, hl, hm]

/-- What taking the lock needs to know. `free`: no lock file; `busy`: a live process holds it; `stale`: the lock
file names a dead pid (reported to the user, never removed silently).

$$\mathrm{Lock} = \mathrm{free} \mid \mathrm{busy} \mid \mathrm{stale}$$
-/
inductive LockVerdict where
  | free | busy | stale
deriving Repr, DecidableEq

/-- May a land take the lock? Facts: is there a lock file, is its pid alive.

$$\operatorname{lock}(\mathit{held}, \mathit{alive}) = \begin{cases} \mathrm{free} & \lnot\mathit{held} \\ \mathrm{busy} & \mathit{held} \land \mathit{alive} \\ \mathrm{stale} & \mathit{held} \land \lnot\mathit{alive} \end{cases}$$
-/
def lockVerdict (held alive : Bool) : LockVerdict :=
  if !held then .free else if alive then .busy else .stale

/-- The answer of the `pre-commit` hook.

$$\mathrm{Guard} = \mathrm{allow} \mid \mathrm{held} \mid \mathrm{stale}$$
-/
inductive GuardVerdict where
  | allow | held | stale
deriving Repr, DecidableEq

/-- May this commit go through? Facts: a lock file exists (`held`), its pid is alive, the commit is in the locked
checkout (`here`), and the committing process is the land itself (`own`, it carries the lock's token and the land's
pid is alive). A dead lock in this checkout is reported as `stale` (the commit is refused until the user looks).

$$\operatorname{guard}(h, a, c, o) = \begin{cases} \mathrm{allow} & \lnot(h \land c) \lor (a \land o) \\ \mathrm{stale} & h \land c \land \lnot a \\ \mathrm{held} & h \land c \land a \land \lnot o \end{cases}$$
-/
def guardVerdict (held alive here own : Bool) : GuardVerdict :=
  if !(held && here) then .allow else if !alive then .stale else if own then .allow else .held

/-- With the lock held (and its owner alive) in this checkout, a commit that is not the land's own is refused.

$$h \land c \land a \land \lnot o \Rightarrow \operatorname{guard}(h,a,c,o) = \mathrm{held}$$
-/
theorem guard_refuses_other (alive : Bool) (ha : alive = true) : guardVerdict true alive true false = .held := by
  simp [guardVerdict, ha]

/-- Without a lock, or in another checkout, every commit is allowed.

$$\lnot h \lor \lnot c \Rightarrow \operatorname{guard}(h,a,c,o) = \mathrm{allow}$$
-/
theorem guard_allows_unlocked (held alive here own : Bool) (h : held = false ∨ here = false) :
    guardVerdict held alive here own = .allow := by
  rcases h with h | h <;> simp [guardVerdict, h]

/-- The land's own commit goes through.

$$\operatorname{guard}(\top, \top, \top, \top) = \mathrm{allow}$$
-/
theorem guard_allows_own : guardVerdict true true true true = .allow := by
  simp [guardVerdict]

/-- A dead lock in this checkout is never allowed through silently: the commit is refused as `stale`.

$$h \land c \land \lnot a \Rightarrow \operatorname{guard}(h,a,c,o) = \mathrm{stale}$$
-/
theorem guard_reports_stale (own : Bool) : guardVerdict true false true own = .stale := by
  simp [guardVerdict]

/-- The hook and the model agree: in a locked state a non-owner commit is refused by the guard exactly as the model
refuses `other`; the guard allows only the owner or an unlocked checkout.

$$\operatorname{guard}(h,a,c,o) = \mathrm{allow} \iff \lnot(h \land c) \lor (a \land o)$$
-/
theorem guard_allow_iff (held alive here own : Bool) :
    guardVerdict held alive here own = .allow ↔ (held && here) = false ∨ (alive = true ∧ own = true) := by
  cases held <;> cases here <;> cases alive <;> cases own <;> simp [guardVerdict]

/-! ## Which branch to land -/

/-- A candidate branch to land instead of the one given: its name, whether it is ahead of main, whether it contains
the given branch's tip.

$$\mathrm{Cand} = (\mathit{name},\ \mathit{ahead} \in \mathbb{B},\ \mathit{contains} \in \mathbb{B})$$
-/
structure Cand where
  name : String
  ahead : Bool
  contains : Bool
deriving Repr, DecidableEq

/-- A candidate qualifies when it is ahead of main and contains the given branch.

$$q(c) \iff c.\mathit{ahead} \land c.\mathit{contains}$$
-/
def Cand.qualifies (c : Cand) : Bool := c.ahead && c.contains

/-- Which branch to land. `given`: the given branch has something to land. `other n`: it has not, and `n` is the one
candidate ahead of main that contains it (the agent's `ci/<task>` or the branch checked out in its worktree).
`nothing`: no candidate. `ambiguous`: several different candidates; the land refuses.

$$\mathrm{Pick} = \mathrm{given} \mid \mathrm{other}(n) \mid \mathrm{nothing} \mid \mathrm{ambiguous}(N)$$
-/
inductive Pick where
  | given | other (name : String) | nothing | ambiguous (names : List String)
deriving Repr, DecidableEq

/-- The choice, from the given branch's `ahead` fact and the candidates.

$$\operatorname{pick}(a, C) = \begin{cases} \mathrm{given} & a \\ \mathrm{nothing} & \lnot a \land Q = [\,] \\ \mathrm{other}(n) & \lnot a \land Q = n :: r \land \forall x \in r:\ x = n \\ \mathrm{ambiguous}(Q) & \text{otherwise} \end{cases}\quad Q = [c.\mathit{name} : c \in C,\ q(c)]$$
-/
def pick (givenAhead : Bool) (others : List Cand) : Pick :=
  if givenAhead then .given
  else match (others.filter Cand.qualifies).map Cand.name with
    | [] => .nothing
    | n :: rest => if rest.all (· == n) then .other n else .ambiguous (n :: rest)

/-- The given branch is kept exactly when it is ahead of main.

$$\operatorname{pick}(a, C) = \mathrm{given} \iff a$$
-/
theorem pick_given_iff (a : Bool) (cs : List Cand) : pick a cs = .given ↔ a = true := by
  unfold pick
  cases a
  · simp only [Bool.false_eq_true, ↓reduceIte, iff_false]
    split <;> try (split <;> simp)
    simp
  · simp

/-- When the given branch has nothing to land, another branch is chosen exactly when it is the unique candidate ahead
of main that contains the given branch: it qualifies, and every qualifying candidate has its name.

$$\operatorname{pick}(\bot, C) = \mathrm{other}(n) \iff (\exists c \in C:\ q(c) \land c.\mathit{name} = n) \land (\forall c \in C:\ q(c) \Rightarrow c.\mathit{name} = n)$$
-/
theorem pick_other_iff (cs : List Cand) (n : String) :
    pick false cs = .other n ↔
      (∃ c ∈ cs, c.qualifies = true ∧ c.name = n) ∧ (∀ c ∈ cs, c.qualifies = true → c.name = n) := by
  unfold pick
  simp only [Bool.false_eq_true, ↓reduceIte]
  generalize hq : (cs.filter Cand.qualifies).map Cand.name = q
  have hmem : ∀ x, x ∈ q ↔ ∃ c ∈ cs, c.qualifies = true ∧ c.name = x := by
    intro x; subst hq; simp [List.mem_map, List.mem_filter, and_assoc]
  cases q with
  | nil =>
    simp only [reduceCtorEq, false_iff, not_and]
    rintro ⟨c, hc, hq', _⟩
    have := (hmem c.name).mpr ⟨c, hc, hq', rfl⟩
    simp at this
  | cons m rest =>
    constructor
    · intro h
      by_cases hall : rest.all (· == m) = true
      · simp only [hall, ↓reduceIte, Pick.other.injEq] at h
        subst h
        refine ⟨(hmem m).mp (List.mem_cons_self ..), fun c hc hq' => ?_⟩
        have hc' : c.name ∈ m :: rest := (hmem c.name).mpr ⟨c, hc, hq', rfl⟩
        rcases List.mem_cons.mp hc' with h | h
        · exact h
        · simpa using List.all_eq_true.mp hall _ h
      · simp [hall] at h
    · rintro ⟨⟨c, hc, hq', rfl⟩, hu⟩
      have hall : ∀ x ∈ m :: rest, x = c.name := by
        intro x hx
        obtain ⟨c', hc', hq'', rfl⟩ := (hmem x).mp hx
        exact hu c' hc' hq''
      have hm : m = c.name := hall m (List.mem_cons_self ..)
      have hr : rest.all (· == m) = true := by
        refine List.all_eq_true.mpr fun x hx => ?_
        have := hall x (List.mem_cons_of_mem _ hx)
        simp [this, hm]
      simp only [hr, ↓reduceIte, Pick.other.injEq]
      exact hm

private def tw : List String := ["apps/runner/src/land.ts", "apps/runner/test/land*.ts"]

#guard landVerdict tw ["pa-land"] [] ["apps/runner/src/land.ts", "apps/runner/test/land-x.ts", "docs/team/handoffs/pa-land.md"] == .ok
#guard landVerdict tw ["pa-land"] [] ["apps/runner/src/other.ts"] == .outOfScope ["apps/runner/src/other.ts"]
#guard landVerdict tw ["pa-land"] [] ["docs/team/handoffs/other.md"] == .outOfScope ["docs/team/handoffs/other.md"]
#guard landVerdict tw ["pa-land"] [] ["packages/contracts/golden/ops/a.jsonl", "packages/gate-breakpoints/src/scope.gen.json", "lean/Fw.lean"] == .ok
#guard landVerdict tw ["../x", "a/*"] [] ["docs/team/handoffs/../x.md", "docs/team/handoffs/a/b.md"] ==
  .outOfScope ["docs/team/handoffs/../x.md", "docs/team/handoffs/a/b.md"]
#guard landVerdict ["apps/runner/src/land.ts"] ["t"] [] ["apps/runner/test/x.test.ts", "apps/runner/test/sub/y.ts"] == .ok
#guard landVerdict ["packages/gh/src/**"] ["t"] [] ["packages/gh/test/a.ts"] == .ok
#guard landVerdict ["apps/runner/src/land.ts"] ["t"] [] ["apps/console-web/test/x.ts"] == .outOfScope ["apps/console-web/test/x.ts"]
#guard landVerdict ["docs/x.md"] ["t"] [] ["apps/runner/test/x.ts"] == .outOfScope ["apps/runner/test/x.ts"]
#guard testGlob "apps/*/src/a.ts" == none
#guard testGlob "lean/Fw/src/a.ts" == none
#guard testGlob "apps/runner/test/a.ts" == none
#guard testGlobs ["apps/runner/src/a.ts", "packages/c/src/**", "lean/Fw.lean"] == ["apps/runner/test/**", "packages/c/test/**"]
#guard landVerdict ["lean/Fw/X.lean"] ["t"] [] ["lean/Fw/Wire/Console.lean", "lean/Fw/Plan/Wire.lean", "lean/Fw.lean", "lean/FwTestMain.lean"] == .ok
#guard landVerdict ["lean/Fw/X.lean"] ["t"] [] ["lean/Fw/Plan/Other.lean"] == .outOfScope ["lean/Fw/Plan/Other.lean"]
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

/-! ### Kind and protocol examples -/

#guard taskKind "port-platform" "parts" == .port "platform"
#guard taskKind "proof-hero-exit" "lean" == .proof "hero-exit"
#guard taskKind "zone-baselines-webkit" "measure" == .measure
#guard taskKind "land-hardening" "console" == .other
#guard pascal "hero-exit" == some "HeroExit"
#guard pascal "a/b" == none
#guard pascal "" == none
#guard pascal "x--y" == none
#guard landVerdict ["apps/site/src/parts/platform/**"] ["port-platform"] []
  ["apps/site/src/registry/index.ts", "apps/site/src/App.tsx", "apps/site/scripts/gen-shells.mjs", "lean/Fw/Gate/Scope.lean",
    "lean/Fw/Parts/Golden.lean", "lean/Fw/Parts/PlatformSweep.lean", "packages/gate-breakpoints/src/anchors.json",
    "packages/gate-breakpoints/src/scope.gen.json", "apps/site/src/parts/platform/x.tsx"] "port-platform" "parts" == .ok
#guard landVerdict ["apps/site/src/parts/platform/**"] ["port-platform"] [] ["lean/Fw/Parts/HeroExit.lean"] "port-platform" "parts" ==
  .outOfScope ["lean/Fw/Parts/HeroExit.lean"]
#guard landVerdict ["apps/site/src/parts/platform/**"] ["t"] [] ["apps/site/src/App.tsx"] "land-hardening" "console" ==
  .outOfScope ["apps/site/src/App.tsx"]
#guard landVerdict ["research/notes/x.md"] ["zone-baselines-webkit"] []
  ["packages/measure-webkit/src/a.ts", "packages/measure-webkit/test/a.test.ts", "results/baselines/webkit/a.json"] "zone-baselines-webkit" "measure" == .ok
#guard landVerdict ["research/notes/x.md"] ["t"] [] ["results/baselines/a.json"] "t" "console" == .outOfScope ["results/baselines/a.json"]
#guard landVerdict ["lean/Fw/Parts/HiddenPause.lean"] ["proof-hidden-pause"] []
  ["lean/Fw/Parts/HiddenPause.lean", "lean/Fw/Parts/HiddenPauseOpt.lean", "packages/contracts/golden/engine/hidden-pause.jsonl"] "proof-hidden-pause" "lean" == .ok
#guard landVerdict ["a/**"] ["port-x"] [] [".git/config", "lean/.lake/x"] "port-x" "parts" == .outOfScope [".git/config", "lean/.lake/x"]
#guard landVerdict ["a/**"] ["port-x"] ["**"] [".claude/settings.json"] "port-x" "parts" == .outOfScope [".claude/settings.json"]

private def l0 : Repo := { head := "m0" }
#guard (step l0 (.other "x")).1.head == "x"
#guard (step (step l0 (.begin "b")).1 (.other "x")).2 == some "locked"
#guard (run l0 [.begin "b", .other "x", .begin "c"]).head == "m0"
#guard (run l0 [.begin "b", .land "m1" "t"]).log == [{ id := "m1", parents := ["m0", "b"], task := some "t" }]
#guard (step (run l0 [.begin "b", .abort]) (.land "m1" "t")).2 == some "no lock"
#guard (step { l0 with locked := true, pre := "m0" } (.land "m1" "t")).2 == some "merge state gone"
#guard (step { l0 with locked := true, merge := some "b", pre := "mX" } (.land "m1" "t")).2 == some "head moved"
#guard guardVerdict true true true false == .held
#guard guardVerdict true true true true == .allow
#guard guardVerdict true true false false == .allow
#guard guardVerdict true false true true == .stale
#guard guardVerdict false false true false == .allow
#guard lockVerdict false false == .free && lockVerdict true true == .busy && lockVerdict true false == .stale
#guard pick true [] == .given
#guard pick false [] == .nothing
#guard pick false [⟨"ci/t", true, true⟩] == .other "ci/t"
#guard pick false [⟨"ci/t", true, true⟩, ⟨"w", true, true⟩] == .ambiguous ["ci/t", "w"]
#guard pick false [⟨"ci/t", true, true⟩, ⟨"ci/t", true, true⟩] == .other "ci/t"
#guard pick false [⟨"ci/t", true, false⟩, ⟨"w", false, true⟩] == .nothing

end Fw.Console.Land
