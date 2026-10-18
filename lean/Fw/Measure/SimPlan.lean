import Fw.Store.Layout
/-!
# The WebKit Simulator lane's plan: arms, flags, pairing (task `webkit-sim-rewrite`)

`webkit-sim.yml` measures the original page (the read-only snapshot) and the rewrite (`apps/site`, built at the commit
under test) in the iOS Simulator. This module decides, from the dispatch inputs, **which arms run, which query the
rewrite is served with, how a rewrite run is paired with its original run, and when a result counts**. The workflow
only calls it (`fwcore` op `measure.simPlan`) and copies the reply.

* **Arms.** Target `original` runs the arm `v1 … vN`; `rewrite` runs `r1 … rN`; `both` runs both. Job `vK` is the
  original arm of VM `K`, job `rK` the rewrite arm of VM `K`.
* **The query.** The rewrite is served at `/` + `search`, where `search` is built from the preset and the flags exactly as
  `chromium-counts.yml` does (`?preset=<p>`, `?fw=<a:v,...>`, both `?preset=<p>&fw=<...>`); the default configuration is the
  empty query. The original arm never carries a query (`original_search`), so adding flags cannot change it
  (`originals_indep`).
* **Pairing.** In a run with target `both`, every rewrite cell has an original cell of the same VM index, the same
  commit and the same viewport width (`rewrite_paired`): the comparison of original against rewrite is always between
  runs of one build and one breakpoint. The viewport is the Simulator's (430 CSS px wide, MEASURED, run 39053799594).
* **When a result counts.** A rewrite result counts only if its own job and its original partner's job both
  succeeded (`counts`); an original result counts when its own job did (`counts_original`). With every job successful
  all cells count (`counted_all`).
* **Refusals.** `problems` lists everything wrong with a request; a refused request has an empty matrix
  (`plan_nil_of_problems`). Flags and presets are only for arms that serve the rewrite (`Fw.Store.targetFits`).
-/
namespace Fw.Measure.SimPlan
open Fw.Store

/-! ## Targets, arms and cells -/

/-- The targets of the lane.

$$\mathrm{Target} = \{\mathrm{original}, \mathrm{rewrite}, \mathrm{both}\}$$
-/
inductive Target where
  | original
  | rewrite
  | both
deriving DecidableEq, Repr

/-- A target from its input value.

$$\operatorname{ofName}(s) = \begin{cases} \mathrm{original} & s = \texttt{original} \\ \mathrm{rewrite} & s = \texttt{rewrite} \\ \mathrm{both} & s = \texttt{both} \\ \bot & \text{otherwise} \end{cases}$$
-/
def Target.ofName : String → Option Target
  | "original" => some .original
  | "rewrite" => some .rewrite
  | "both" => some .both
  | _ => none

/-- Whether the target runs the original arm.

$$\operatorname{hasO}(t) \iff t \ne \mathrm{rewrite}$$
-/
def Target.hasOriginal : Target → Bool
  | .rewrite => false
  | _ => true

/-- Whether the target runs the rewrite arm.

$$\operatorname{hasR}(t) \iff t \ne \mathrm{original}$$
-/
def Target.hasRewrite : Target → Bool
  | .original => false
  | _ => true

/-- The two arms.

$$\mathrm{Arm} = \{\mathrm{original}, \mathrm{rewrite}\}$$
-/
inductive Arm where
  | original
  | rewrite
deriving DecidableEq, Repr

/-- The wire name of an arm.

$$\operatorname{name}(\mathrm{original}) = \texttt{original},\quad \operatorname{name}(\mathrm{rewrite}) = \texttt{rewrite}$$
-/
def Arm.name : Arm → String
  | .original => "original"
  | .rewrite => "rewrite"

/-- One job of the matrix: the VM name (`v` or `r` and the index), the arm, the VM index (1-based), the commit under
test, the viewport width of the Simulator in CSS px, and the query the page is served with.

$$\mathrm{Cell} = \mathrm{String} \times \mathrm{Arm} \times \mathbb{N} \times \mathrm{String} \times \mathbb{N} \times \mathrm{String}$$
-/
structure Cell where
  vm : String
  arm : Arm
  idx : Nat
  sha : String
  bp : Nat
  search : String
deriving DecidableEq, Repr

/-- The viewport width of the Simulator's Mobile Safari in CSS px (430 x 775 at dpr 3; MEASURED).

$$\mathrm{bp}_{\mathrm{sim}} = 430$$
-/
def simBp : Nat := 430

/-- The original arm of VM `i`: `v<i>`, the snapshot, no query.

$$\operatorname{orig}(\sigma, i) = (\texttt{v}i,\ \mathrm{original},\ i,\ \sigma,\ \mathrm{bp}_{\mathrm{sim}},\ \varepsilon)$$
-/
def origCell (sha : String) (i : Nat) : Cell :=
  { vm := "v" ++ toString i, arm := .original, idx := i, sha := sha, bp := simBp, search := "" }

/-- The rewrite arm of VM `i`: `r<i>`, the build of `apps/site` at the commit, served with the query `q`.

$$\operatorname{rew}(\sigma, q, i) = (\texttt{r}i,\ \mathrm{rewrite},\ i,\ \sigma,\ \mathrm{bp}_{\mathrm{sim}},\ q)$$
-/
def rewCell (sha q : String) (i : Nat) : Cell :=
  { vm := "r" ++ toString i, arm := .rewrite, idx := i, sha := sha, bp := simBp, search := q }

/-- The VM indices 1 to `n`.

$$\operatorname{idxs}(n) = [1, 2, \dots, n]$$
-/
def idxs (n : Nat) : List Nat := (List.range n).map (· + 1)

/-- The matrix: for each VM index in order, its original cell (when the target has the arm), then its rewrite cell.

$$M(t, n, \sigma, q) = \bigoplus_{i=1}^{n} \big([\operatorname{orig}(\sigma, i) \mid \operatorname{hasO}(t)] \mathbin{+\!\!+} [\operatorname{rew}(\sigma, q, i) \mid \operatorname{hasR}(t)]\big)$$
-/
def matrix (t : Target) (n : Nat) (sha q : String) : List Cell :=
  (idxs n).flatMap fun i =>
    (if t.hasOriginal then [origCell sha i] else []) ++ (if t.hasRewrite then [rewCell sha q i] else [])

/-! ## The query -/

/-- The query the rewrite is served with, as `chromium-counts.yml` builds it: the preset when it is not the default,
then the flags.

$$\operatorname{search}(p, F) = \begin{cases} \varepsilon & p = \texttt{original} \land F = \varepsilon \\ \texttt{?fw=}F & p = \texttt{original} \land F \ne \varepsilon \\ \texttt{?preset=}p & p \ne \texttt{original} \land F = \varepsilon \\ \texttt{?preset=}p\texttt{\&fw=}F & \text{otherwise} \end{cases}$$
-/
def searchOf (preset fw : String) : String :=
  let p := if preset == defaultPreset then "" else "?preset=" ++ preset
  if fw.isEmpty then p else if p.isEmpty then "?fw=" ++ fw else p ++ "&fw=" ++ fw

#guard searchOf "original" "" == ""
#guard searchOf "original" "hero.countdown:strip" == "?fw=hero.countdown:strip"
#guard searchOf "strip-demo" "" == "?preset=strip-demo"
#guard searchOf "strip-demo" "a.b:c" == "?preset=strip-demo&fw=a.b:c"

/-- **The default configuration is the empty query.**

$$\operatorname{search}(\texttt{original}, \varepsilon) = \varepsilon$$
-/
theorem searchOf_default : searchOf defaultPreset "" = "" := by
  simp [searchOf]

/-- The flags of an input value `part:variant,part:variant`, `none` when an item is not of that shape; the empty input
has no flags.

$$\operatorname{flags}(\varepsilon) = [\,],\qquad \operatorname{flags}(s) = [\,(a_i, v_i)\,]_i \iff s = a_1\texttt{:}v_1\texttt{,}\dots\texttt{,}a_k\texttt{:}v_k \text{ (each item has exactly one colon)}$$
-/
def parseFlags (s : String) : Option (List (String × String)) :=
  if s.isEmpty then some [] else
    (s.splitOn ",").mapM fun it => match it.splitOn ":" with
      | [a, b] => some (a, b)
      | _ => none

#guard parseFlags "" == some []
#guard parseFlags "a.b:c,d:e" == some [("a.b", "c"), ("d", "e")]
#guard parseFlags "a" == none && parseFlags "a:b:c" == none && parseFlags "a:b," == none

/-- A count input: the decimal numeral of a natural between `lo` and `hi`, written without leading zeros or signs.

$$\operatorname{count}_{[lo,hi]}(s) = \begin{cases} n & s = \operatorname{dec}(n) \land lo \le n \le hi \\ \bot & \text{otherwise} \end{cases}$$
-/
def countOf (lo hi : Nat) (s : String) : Option Nat :=
  match s.toNat? with
  | some n => if toString n == s && lo ≤ n && n ≤ hi then some n else none
  | none => none

#guard countOf 1 3 "2" == some 2 && countOf 1 3 "0" == none && countOf 1 3 "4" == none
#guard countOf 1 3 "02" == none && countOf 1 3 "" == none && countOf 1 3 "+1" == none

/-! ## The request and its problems -/

/-- The dispatch inputs and the commit.

$$\mathrm{Req} = (\mathit{target}, \mathit{vms}, \mathit{sessions}, \mathit{preset}, \mathit{fw}, \mathit{experiment}, \mathit{sha}) \in \mathrm{String}^7$$
-/
structure Req where
  target : String
  vms : String
  sessions : String
  preset : String
  fw : String
  experiment : String
  sha : String

/-- What is wrong with a request (empty = accepted), in this order: the target is not `original`, `rewrite` or `both`;
the experiment is not `determinism` or `quiet`; the experiment `quiet` with a target other than `original`; `vms` is not
1 to 3; `sessions` is not 1 to 4; the preset is not an id; the flags are not `part:variant` items; a part or variant is
not an id; a part appears twice or the parts are not increasing; the target `original` with a preset or flags; the commit is
not 40 hexadecimal digits.

$$\begin{aligned} \operatorname{problems}(r) ={} & [\,\texttt{target}\mid \operatorname{ofName}(r.\mathit{target}) = \bot\,] \mathbin{+\!\!+} [\,\texttt{experiment}\mid r.\mathit{experiment} \notin \{\texttt{determinism}, \texttt{quiet}\}\,] \\ & \mathbin{+\!\!+} [\,\texttt{quiet}\mid r.\mathit{experiment} = \texttt{quiet} \land r.\mathit{target} \ne \texttt{original}\,] \mathbin{+\!\!+} [\,\texttt{vms}\mid \operatorname{count}_{[1,3]}(r.\mathit{vms}) = \bot\,] \mathbin{+\!\!+} [\,\texttt{sessions}\mid \operatorname{count}_{[1,4]}(r.\mathit{sessions}) = \bot\,] \\ & \mathbin{+\!\!+} [\,\texttt{preset}\mid \lnot\operatorname{isId}(r.\mathit{preset})\,] \mathbin{+\!\!+} [\,\texttt{fw shape}\mid \operatorname{flags}(r.\mathit{fw}) = \bot\,] \mathbin{+\!\!+} [\,\texttt{fw ids}\mid \exists (a, v) \in F:\ \lnot\operatorname{isPart}(a) \lor \lnot\operatorname{isId}(v)\,] \\ & \mathbin{+\!\!+} [\,\texttt{fw order}\mid \lnot\operatorname{flagsOk}(F)\,] \mathbin{+\!\!+} [\,\texttt{fits}\mid \lnot\operatorname{fits}(r.\mathit{target}, r.\mathit{preset}, F)\,] \mathbin{+\!\!+} [\,\texttt{sha}\mid \lnot\operatorname{isHex}_{40}(r.\mathit{sha})\,] \end{aligned}$$

with $F = \operatorname{flags}(r.\mathit{fw})$ (empty when the input has the wrong shape) and $[x \mid c]$ is $[x]$ when $c$ holds, else $[\,]$.
-/
def problems (r : Req) : List String :=
  let fw := (parseFlags r.fw).getD []
  (if (Target.ofName r.target).isSome then [] else ["target: not original, rewrite or both"]) ++
  (if r.experiment == "determinism" || r.experiment == "quiet" then [] else ["experiment: not determinism or quiet"]) ++
  (if r.experiment == "quiet" && r.target != "original" then ["experiment quiet needs target original"] else []) ++
  (if (countOf 1 3 r.vms).isSome then [] else ["vms must be 1..3"]) ++
  (if (countOf 1 4 r.sessions).isSome then [] else ["sessions must be 1..4"]) ++
  (if isId r.preset then [] else ["preset: not an id"]) ++
  (if (parseFlags r.fw).isSome then [] else ["fw: expected part:variant,part:variant"]) ++
  (if fw.all (fun p => isPart p.1 && isId p.2) then [] else ["fw: part and variant must be ids"]) ++
  (if flagsOk fw then [] else ["fw: each part once, parts in increasing order"]) ++
  (if targetFits r.target r.preset fw then [] else ["target original takes no preset or flags"]) ++
  (if isHex 40 r.sha then [] else ["sha: not 40 hex digits"])

/-- The plan of a request: its problems, the query of the rewrite arm, and the matrix (empty when refused).

$$\mathrm{Plan} = \mathit{problems} : \mathrm{List\,String} \times \mathit{search} : \mathrm{String} \times \mathit{matrix} : \mathrm{List\,Cell}$$

`problems` lists why the request is refused, `search` is the query of the rewrite arm, and `matrix` holds the cells to run (empty when refused).
-/
structure Plan where
  problems : List String
  search : String
  matrix : List Cell

/-- The plan.

$$\operatorname{plan}(r) = \begin{cases} ([\,],\ q,\ M(t, n, r.\mathit{sha}, q)) & \operatorname{problems}(r) = [\,] \land \operatorname{ofName}(r.\mathit{target}) = t \land \operatorname{count}_{[1,3]}(r.\mathit{vms}) = n \\ (\operatorname{problems}(r),\ q,\ [\,]) & \text{otherwise} \end{cases},\quad q = \operatorname{search}(r.\mathit{preset}, r.\mathit{fw})$$
-/
def plan (r : Req) : Plan :=
  let q := searchOf r.preset r.fw
  match (problems r).isEmpty, Target.ofName r.target, countOf 1 3 r.vms with
  | true, some t, some n => { problems := [], search := q, matrix := matrix t n r.sha q }
  | _, _, _ => { problems := problems r, search := q, matrix := [] }

/-- **A refused request runs nothing.**

$$\operatorname{problems}(r) \ne [\,] \Rightarrow \operatorname{plan}(r).\mathrm{matrix} = [\,]$$
-/
theorem plan_nil_of_problems {r : Req} (h : problems r ≠ []) : (plan r).matrix = [] := by
  unfold plan
  have : (problems r).isEmpty = false := by simpa using h
  simp [this]

/-- **An accepted request plans the matrix of its target and VM count, with the planned query.**

$$\operatorname{problems}(r) = [\,] \Rightarrow \exists t, n:\ \operatorname{ofName}(r.\mathit{target}) = t \land \operatorname{count}_{[1,3]}(r.\mathit{vms}) = n \land \operatorname{plan}(r).\mathrm{matrix} = M(t, n, r.\mathit{sha}, \operatorname{plan}(r).\mathrm{search})$$
-/
theorem plan_matrix {r : Req} (h : problems r = []) :
    ∃ t n, Target.ofName r.target = some t ∧ countOf 1 3 r.vms = some n ∧
      (plan r).matrix = matrix t n r.sha (plan r).search := by
  have hE : (problems r).isEmpty = true := by simp [h]
  cases ht : Target.ofName r.target with
  | none =>
    exfalso
    have hm : "target: not original, rewrite or both" ∈ problems r := by simp [problems, ht]
    rw [h] at hm; simp at hm
  | some t =>
    cases hn : countOf 1 3 r.vms with
    | none =>
      exfalso
      have hm : "vms must be 1..3" ∈ problems r := by simp [problems, hn]
      rw [h] at hm; simp at hm
    | some n =>
      refine ⟨t, n, rfl, rfl, ?_⟩
      simp [plan, hE, ht, hn]

/-! ## The matrix -/

/-- Membership in the matrix.

$$c \in M(t, n, \sigma, q) \iff \exists i \in [1,n]:\ (\operatorname{hasO}(t) \land c = \operatorname{orig}(\sigma, i)) \lor (\operatorname{hasR}(t) \land c = \operatorname{rew}(\sigma, q, i))$$
-/
theorem mem_matrix (t : Target) (n : Nat) (sha q : String) (c : Cell) :
    c ∈ matrix t n sha q ↔ ∃ i ∈ idxs n,
      (t.hasOriginal = true ∧ c = origCell sha i) ∨ (t.hasRewrite = true ∧ c = rewCell sha q i) := by
  unfold matrix
  simp only [List.mem_flatMap, List.mem_append]
  constructor
  · rintro ⟨i, hi, h⟩
    refine ⟨i, hi, ?_⟩
    by_cases ho : t.hasOriginal = true <;> by_cases hr : t.hasRewrite = true <;> simp_all
  · rintro ⟨i, hi, h | h⟩
    · exact ⟨i, hi, Or.inl (by simp [h.1, h.2])⟩
    · exact ⟨i, hi, Or.inr (by simp [h.1, h.2])⟩

/-- A VM index of the matrix is between 1 and `n`.

$$i \in \operatorname{idxs}(n) \iff 1 \le i \le n$$
-/
theorem mem_idxs {n i : Nat} : i ∈ idxs n ↔ 1 ≤ i ∧ i ≤ n := by
  unfold idxs
  simp only [List.mem_map, List.mem_range]
  constructor
  · rintro ⟨j, hj, rfl⟩; omega
  · intro h; exact ⟨i - 1, by omega, by omega⟩

/-- **Every rewrite arm is paired with an original arm of the same build and breakpoint.** When the target runs both
arms, each rewrite cell has an original cell of the same VM index, commit and viewport width.

$$c \in M(\mathrm{both}, n, \sigma, q) \land c.\mathrm{arm} = \mathrm{rewrite} \Rightarrow \exists o \in M(\mathrm{both}, n, \sigma, q):\ o.\mathrm{arm} = \mathrm{original} \land o.\mathrm{idx} = c.\mathrm{idx} \land o.\mathrm{sha} = c.\mathrm{sha} \land o.\mathrm{bp} = c.\mathrm{bp}$$
-/
theorem rewrite_paired {n : Nat} {sha q : String} {c : Cell} (hc : c ∈ matrix .both n sha q) (ha : c.arm = .rewrite) :
    ∃ o ∈ matrix .both n sha q, o.arm = .original ∧ o.idx = c.idx ∧ o.sha = c.sha ∧ o.bp = c.bp := by
  rw [mem_matrix] at hc
  obtain ⟨i, hi, h | h⟩ := hc
  · obtain ⟨-, rfl⟩ := h
    simp [origCell] at ha
  · obtain ⟨-, rfl⟩ := h
    refine ⟨origCell sha i, (mem_matrix _ _ _ _ _).2 ⟨i, hi, Or.inl ⟨rfl, rfl⟩⟩, ?_⟩
    simp [origCell, rewCell]

/-- **The original arm carries no query.** Whatever the flags, an original cell is served at `/`.

$$o \in M(t, n, \sigma, q) \land o.\mathrm{arm} = \mathrm{original} \Rightarrow o.\mathrm{search} = \varepsilon$$
-/
theorem original_search {t : Target} {n : Nat} {sha q : String} {o : Cell} (ho : o ∈ matrix t n sha q)
    (ha : o.arm = .original) : o.search = "" := by
  rw [mem_matrix] at ho
  obtain ⟨i, hi, h | h⟩ := ho
  · obtain ⟨-, rfl⟩ := h; rfl
  · obtain ⟨-, rfl⟩ := h; simp [rewCell] at ha

/-- **The original arm is unchanged by the flags.** The original cells of the matrix are the same list for every query.

$$\operatorname{originals}(M(t, n, \sigma, q)) = \operatorname{originals}(M(t, n, \sigma, q')),\qquad \operatorname{originals}(M) = [\,c \in M \mid c.\mathrm{arm} = \mathrm{original}\,]$$
-/
theorem originals_indep (t : Target) (n : Nat) (sha q q' : String) :
    (matrix t n sha q).filter (fun c => c.arm == .original) = (matrix t n sha q').filter (fun c => c.arm == .original) := by
  unfold matrix
  rw [List.filter_flatMap, List.filter_flatMap]
  congr 1
  funext i
  simp only [List.filter_append]
  by_cases hr : t.hasRewrite = true <;> simp [hr, rewCell]

/-- **Rewrite cells carry the query.** Every rewrite cell is served with the planned query.

$$c \in M(t, n, \sigma, q) \land c.\mathrm{arm} = \mathrm{rewrite} \Rightarrow c.\mathrm{search} = q$$
-/
theorem rewrite_search {t : Target} {n : Nat} {sha q : String} {c : Cell} (hc : c ∈ matrix t n sha q)
    (ha : c.arm = .rewrite) : c.search = q := by
  rw [mem_matrix] at hc
  obtain ⟨i, hi, h | h⟩ := hc
  · obtain ⟨-, rfl⟩ := h; simp [origCell] at ha
  · obtain ⟨-, rfl⟩ := h; rfl

/-- **Size.** The matrix has one cell per VM and arm.

$$|M(t, n, \sigma, q)| = n \cdot ([\operatorname{hasO}(t)] + [\operatorname{hasR}(t)])$$
-/
theorem matrix_length (t : Target) (n : Nat) (sha q : String) :
    (matrix t n sha q).length = n * ((if t.hasOriginal then 1 else 0) + (if t.hasRewrite then 1 else 0)) := by
  unfold matrix
  have h : ∀ l : List Nat, (l.flatMap fun i => (if t.hasOriginal then [origCell sha i] else []) ++
      (if t.hasRewrite then [rewCell sha q i] else [])).length =
      l.length * ((if t.hasOriginal then 1 else 0) + (if t.hasRewrite then 1 else 0)) := by
    intro l
    induction l with
    | nil => simp
    | cons a l ih =>
      simp only [List.flatMap_cons, List.length_append, ih, List.length_cons]
      by_cases ho : t.hasOriginal = true <;> by_cases hr : t.hasRewrite = true <;> simp [ho, hr] <;> omega
  simpa [idxs] using h (idxs n)

/-- A cell's index is the one its VM name is made from, so the partner of a rewrite cell is the original cell of the same index.

$$\operatorname{partner}(c) = \texttt{v}\,c.\mathrm{idx}$$
-/
def partner (c : Cell) : String := "v" ++ toString c.idx

/-! ## When a result counts -/

/-- **A result counts** when its job succeeded (`ok`), and, for a rewrite cell, its original partner's job did too.

$$\operatorname{counts}(c) \iff ok(c.\mathrm{vm}) \land (c.\mathrm{arm} = \mathrm{original} \lor ok(\operatorname{partner}(c)))$$
-/
def counts (ok : String → Bool) (c : Cell) : Bool :=
  ok c.vm && (c.arm == .original || ok (partner c))

/-- The cells whose results count.

$$\operatorname{counted}(ok, M) = [\,c \in M \mid \operatorname{counts}(c)\,]$$
-/
def counted (ok : String → Bool) (cells : List Cell) : List Cell := cells.filter (counts ok)

/-- **An original result counts exactly when its job succeeded.**

$$c.\mathrm{arm} = \mathrm{original} \Rightarrow (\operatorname{counts}(c) \iff ok(c.\mathrm{vm}))$$
-/
theorem counts_original {ok : String → Bool} {c : Cell} (h : c.arm = .original) :
    counts ok c = ok c.vm := by
  simp [counts, h]

/-- **A counted rewrite result has a counted original partner of the same build and breakpoint.** In a run with target
`both`, if a rewrite cell counts then its original cell exists in the matrix, succeeded, and has the same commit and
viewport width.

$$c \in \operatorname{counted}(ok, M(\mathrm{both}, n, \sigma, q)) \land c.\mathrm{arm} = \mathrm{rewrite} \Rightarrow \exists o \in M:\ o.\mathrm{vm} = \operatorname{partner}(c) \land ok(o.\mathrm{vm}) \land ok(c.\mathrm{vm}) \land o.\mathrm{sha} = c.\mathrm{sha} \land o.\mathrm{bp} = c.\mathrm{bp} \land o.\mathrm{arm} = \mathrm{original}$$
-/
theorem counted_rewrite_partner {ok : String → Bool} {n : Nat} {sha q : String} {c : Cell}
    (hc : c ∈ counted ok (matrix .both n sha q)) (ha : c.arm = .rewrite) :
    ∃ o ∈ matrix .both n sha q, o.vm = partner c ∧ ok o.vm = true ∧ ok c.vm = true ∧ o.sha = c.sha ∧ o.bp = c.bp ∧
      o.arm = .original := by
  unfold counted at hc
  rw [List.mem_filter] at hc
  obtain ⟨hm, hk⟩ := hc
  have hk' : ok c.vm = true ∧ ok (partner c) = true := by
    simpa [counts, ha] using hk
  obtain ⟨o, ho, hoa, hoi, hos, hob⟩ := rewrite_paired hm ha
  have hov : o.vm = partner c := by
    rw [mem_matrix] at ho
    obtain ⟨i, hi, h | h⟩ := ho
    · obtain ⟨-, rfl⟩ := h
      simp only [origCell, partner] at hoi ⊢
      rw [hoi]
    · obtain ⟨-, rfl⟩ := h; simp [rewCell] at hoa
  refine ⟨o, ho, hov, ?_, hk'.1, hos, hob, hoa⟩
  rw [hov]; exact hk'.2

/-- **With every job successful, every cell counts.**

$$(\forall v:\ ok(v)) \Rightarrow \operatorname{counted}(ok, M) = M$$
-/
theorem counted_all {ok : String → Bool} (h : ∀ v, ok v = true) (cells : List Cell) :
    counted ok cells = cells := by
  unfold counted
  rw [List.filter_eq_self]
  intro c _
  simp [counts, h]

/-- **A failed original job drops its pair.** If the original job `v` failed, no cell with partner `v` counts as a rewrite
result.

$$ok(\operatorname{partner}(c)) = \mathrm{false} \land c.\mathrm{arm} = \mathrm{rewrite} \Rightarrow \operatorname{counts}(c) = \mathrm{false}$$
-/
theorem counts_false_of_partner {ok : String → Bool} {c : Cell} (h : ok (partner c) = false) (ha : c.arm = .rewrite) :
    counts ok c = false := by
  simp [counts, ha, h]

end Fw.Measure.SimPlan
