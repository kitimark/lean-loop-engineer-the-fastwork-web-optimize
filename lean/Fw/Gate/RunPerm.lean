import Lean.Data.Json
import Fw.Gate.Settle

/-! Run-level permutation test of the nav close gap g under `hero.exit:scoped` (task scoped-gap-did); the math is in `research/notes/2026/10-21-scoped-gap-did.md`. -/

namespace Fw.Gate.RunPerm
open Lean

/-- The two kinds of run: the scoped exit and the A/A run (`hero.exit:faithful`, equal to the base). -/
inductive Arm | scoped | faithful deriving DecidableEq, Repr

/-- The `search` of a scoped run's candidate arm. -/
def scopedSearch : String := "?fw=hero.exit:scoped"
/-- The `search` of an A/A run's candidate arm. -/
def faithfulSearch : String := "?fw=hero.exit:faithful"

/-- The arm of a run from the `search`, `hash` and `baseHash` of its artifact, never from run order. -/
def identify (search hash baseHash : String) : Option Arm :=
  if search = scopedSearch ∧ hash ≠ baseHash then some .scoped
  else if search = faithfulSearch ∧ hash = baseHash then some .faithful
  else none

/-- A run whose search is scoped and whose hash differs from the base is scoped. -/
theorem identify_scoped (hash baseHash : String) (h : hash ≠ baseHash) :
    identify scopedSearch hash baseHash = some .scoped := by
  simp [identify, h]

/-- A run whose search is faithful and whose hash equals the base is an A/A run. -/
theorem identify_faithful (hash : String) : identify faithfulSearch hash hash = some .faithful := by
  have : faithfulSearch ≠ scopedSearch := by decide
  simp [identify, this]

/-- A scoped search with the base's hash is no scoped run, and identifies as nothing. -/
theorem identify_scoped_same_hash (hash : String) : identify scopedSearch hash hash = none := by
  have : scopedSearch ≠ faithfulSearch := by decide
  simp [identify, this]

/-- A faithful search with a hash that differs from the base identifies as nothing. -/
theorem identify_faithful_other_hash (hash baseHash : String) (h : hash ≠ baseHash) :
    identify faithfulSearch hash baseHash = none := by
  have : faithfulSearch ≠ scopedSearch := by decide
  simp [identify, this, h]

/-- Any other search identifies as nothing. -/
theorem identify_other_search (search hash baseHash : String) (h1 : search ≠ scopedSearch)
    (h2 : search ≠ faithfulSearch) : identify search hash baseHash = none := by
  simp [identify, h1, h2]

/-- Exactly `n` scoped and `n` faithful runs and no run left unidentified. -/
def balanced (n : Nat) (rs : List (Option Arm)) : Bool :=
  rs.all Option.isSome && rs.count (some .scoped) == n && rs.count (some .faithful) == n

/-- A run that identifies as nothing makes the set unbalanced, whatever the others are. -/
theorem balanced_false_of_none (n : Nat) (rs : List (Option Arm)) (h : none ∈ rs) : balanced n rs = false := by
  have : rs.all Option.isSome = false := by
    simp only [List.all_eq_false, Bool.not_eq_true]
    exact ⟨none, h, rfl⟩
  simp [balanced, this]

/-- One close cell of the probe: width, arm role (0 orig, 1 base, 2 cand) and the gap g in ms. -/
structure Cell where
  width : Nat
  role : Nat
  g : Nat
deriving Repr

/-- The widths of the pre-registered statistic. -/
def widths : List Nat := [390, 640, 641, 1280]

/-- Mean of ln g, none for an empty list. -/
def meanLog (gs : List Nat) : Option Float :=
  if gs.isEmpty then none else some ((gs.foldl (fun s g => s + Float.log g.toFloat) 0.0) / gs.length.toFloat)

/-- At one width: mean ln g of the cand cells minus mean ln g of the orig and base cells pooled. -/
def widthDiff (cs : List Cell) (w : Nat) : Option Float := do
  let c ← meanLog ((cs.filter fun x => x.width == w && x.role == 2).map (·.g))
  let o ← meanLog ((cs.filter fun x => x.width == w && x.role != 2).map (·.g))
  pure (c - o)

/-- The run statistic D: the mean over the four widths of `widthDiff`; none when a width lacks an arm. -/
def runStat (cs : List Cell) : Option Float := do
  let ds ← widths.mapM (widthDiff cs)
  pure (ds.foldl (· + ·) 0.0 / widths.length.toFloat)

/-- A statistic in integer units of 1e-9. -/
def nano (x : Float) : Int := (Float.round (x * 1.0e9)).toInt64.toInt

/-- D in units of 1e-9, the value the permutation uses. -/
def runNano (cs : List Cell) : Option Int := (runStat cs).map nano

/-- The sub-lists of `xs` with `k` elements, in order. -/
def choose {α : Type} : Nat → List α → List (List α)
  | 0, _ => [[]]
  | _ + 1, [] => []
  | k + 1, x :: xs => (choose k xs).map (x :: ·) ++ choose (k + 1) xs

/-- The binomial coefficient `C(n, k)`. -/
def binom : Nat → Nat → Nat
  | _, 0 => 1
  | 0, _ + 1 => 0
  | n + 1, k + 1 => binom n k + binom n (k + 1)

/-- There are `C(n, k)` of them. -/
theorem choose_length {α : Type} : ∀ (k : Nat) (xs : List α), (choose k xs).length = binom xs.length k
  | 0, _ => by simp [choose, binom]
  | _ + 1, [] => by simp [choose, binom]
  | k + 1, x :: xs => by
    simp only [choose, List.length_append, List.length_map, List.length_cons, binom]
    rw [choose_length k xs, choose_length (k + 1) xs]

/-- The empty sub-list is listed for size 0. -/
theorem nil_mem_choose {α : Type} (xs : List α) : ([] : List α) ∈ choose 0 xs := by
  cases xs <;> simp [choose]

/-- Every sub-list of `xs` is listed, as a list of its own length. -/
theorem mem_choose {α : Type} {S xs : List α} (h : S.Sublist xs) : S ∈ choose S.length xs := by
  induction h with
  | slnil => exact nil_mem_choose []
  | @cons S' xs' a _ ih =>
    cases S' with
    | nil => exact nil_mem_choose (a :: xs')
    | cons s ss =>
      rw [List.length_cons] at ih ⊢
      simp only [choose, List.mem_append]
      exact Or.inr ih
  | cons_cons a _ ih =>
    simp only [List.length_cons, choose, List.mem_append, List.mem_map]
    exact Or.inl ⟨_, ih, rfl⟩

/-- Sum of the run values at the indices of `S`. -/
def sumAt (vals : List Int) (S : List Nat) : Int := (S.map fun i => vals.getD i 0).sum

/-- `k (n - k)` times the difference of the group means (scoped minus faithful), `S` the scoped group of `k` among `n` runs. -/
def tScaled (vals : List Int) (k : Nat) (S : List Nat) : Int := vals.length * sumAt vals S - k * vals.sum

/-- `T` orders the labelings as the scoped sum does. -/
theorem tScaled_le_iff (vals : List Int) (k : Nat) (S S' : List Nat) (h : 0 < vals.length) :
    tScaled vals k S ≤ tScaled vals k S' ↔ sumAt vals S ≤ sumAt vals S' := by
  unfold tScaled
  have key : ∀ (N A A' K : Int), 0 < N → (N * A - K ≤ N * A' - K ↔ A ≤ A') := by
    intro N A A' K hN
    constructor
    · intro h1
      exact Int.le_of_mul_le_mul_left (by omega) hN
    · intro h1
      have := Int.mul_le_mul_of_nonneg_left h1 (Int.le_of_lt hN)
      omega
  exact key _ _ _ _ (by omega)

/-- The indices of the runs labelled scoped. -/
def obsSet (labels : List Arm) : List Nat := (List.range labels.length).filter fun i => labels[i]? = some .scoped

/-- Labelings, among all ways to name `|obsSet|` of the runs scoped, whose `T` is at least the observed one. -/
def count (vals : List Int) (labels : List Arm) : Nat :=
  ((choose (obsSet labels).length (List.range labels.length)).filter fun S =>
    tScaled vals (obsSet labels).length (obsSet labels) ≤ tScaled vals (obsSet labels).length S).length

/-- The number of labelings, `C(n, k)`. -/
def total (labels : List Arm) : Nat := binom labels.length (obsSet labels).length

/-- The observed labeling is counted, so p is at least 1 over the number of labelings. -/
theorem count_pos (vals : List Int) (labels : List Arm) : 1 ≤ count vals labels := by
  have hsub : (obsSet labels).Sublist (List.range labels.length) := List.filter_sublist
  have hmem := mem_choose hsub
  unfold count
  apply List.length_pos_iff.mpr
  intro hnil
  have := List.filter_eq_nil_iff.mp hnil _ hmem
  simp at this

/-- The count is at most the number of labelings. -/
theorem count_le_total (vals : List Int) (labels : List Arm) : count vals labels ≤ total labels := by
  unfold count total
  calc _ ≤ (choose (obsSet labels).length (List.range labels.length)).length := List.length_filter_le _ _
    _ = _ := by rw [choose_length]; simp

/-- Five of ten runs scoped: 252 labelings. -/
theorem total_ten_five : binom 10 5 = 252 := by decide

/-- The decision of the pre-registration. -/
inductive Verdict | confirmed | notShown deriving DecidableEq, Repr

/-- `confirmed` iff `count / total < 1/20`, written without division. -/
def verdict (c total : Nat) : Verdict := if 20 * c < total then .confirmed else .notShown

/-- Out of 252 labelings, 12 or fewer at or above the observed `T` confirm the regression. -/
theorem verdict_confirmed (c : Nat) (h : c ≤ 12) : verdict c 252 = .confirmed := by
  unfold verdict
  split <;> first | rfl | (exfalso; omega)

/-- Out of 252 labelings, 13 or more do not. -/
theorem verdict_notShown (c : Nat) (h : 13 ≤ c) : verdict c 252 = .notShown := by
  unfold verdict
  split <;> first | rfl | (exfalso; omega)

/-- The smallest count there is, the observed labeling alone, would confirm: the test can reject at 5 vs 5. -/
theorem verdict_min : verdict 1 252 = .confirmed := verdict_confirmed 1 (by omega)

/-- `t(0.95, 8)`, the one-sided 5 % point of the t distribution with 8 degrees of freedom. -/
def tAlpha : Float := 1.8595
/-- `t(0.80, 8)`, the 80 % point of the same distribution. -/
def tPower : Float := 0.8889

/-- Pooled within-group SD of the values (in log g), the two groups' sums of squares over `na + nb - 2`. -/
def pooledSd (a b : List Float) : Float :=
  let ss := fun (xs : List Float) =>
    let m := xs.foldl (· + ·) 0.0 / xs.length.toFloat
    (xs.map fun x => (x - m) * (x - m)).foldl (· + ·) 0.0
  Float.sqrt ((ss a + ss b) / (a.length + b.length - 2).toFloat)

/-- The smallest effect in log g a one-sided t test at 5 % detects with 80 % power: `(tAlpha + tPower) s sqrt(1/na + 1/nb)`. -/
def mde (a b : List Float) : Float :=
  (tAlpha + tPower) * pooledSd a b * Float.sqrt (1.0 / a.length.toFloat + 1.0 / b.length.toFloat)

/-- A run with its identification and cells, as the TS parser writes it (one JSON line). -/
structure RunRow where
  run : String
  search : String
  hash : String
  baseHash : String
  cells : List Cell

/-- Parse one line of the cells file. -/
def parseRow (line : String) : Except String RunRow := do
  let j ← Json.parse line
  let run ← j.getObjValAs? String "run"
  let search ← j.getObjValAs? String "search"
  let hash ← j.getObjValAs? String "hash"
  let baseHash ← j.getObjValAs? String "baseHash"
  let cs ← j.getObjValAs? (List (List Nat)) "cells"
  let cells ← cs.mapM fun
    | [w, r, g] => pure (Cell.mk w r g)
    | _ => throw s!"run {run}: a cell is not [width, role, g]"
  pure { run, search, hash, baseHash, cells }

/-- The wire name of an arm. -/
def armName : Arm → String
  | .scoped => "scoped"
  | .faithful => "faithful"

/-- The wire name of a verdict. -/
def verdictName : Verdict → String
  | .confirmed => "confirmed"
  | .notShown => "not-shown"

/-- The run values of the permutation (units of 1e-9) split by arm, in file order. -/
def byArm (arms : List Arm) (vals : List Int) (a : Arm) : List Int :=
  ((arms.zip vals).filter fun p => p.1 = a).map (·.2)

/-- The result of a set of runs: per-run lines and the summary line, or the reason the set is refused. -/
def realLines (rows : List RunRow) : Except String (List String) := do
  let arms := rows.map fun r => identify r.search r.hash r.baseHash
  unless balanced 5 arms do
    throw s!"not 5 scoped and 5 faithful: {arms.length} runs, {arms.count (some .scoped)} scoped, {arms.count (some .faithful)} faithful"
  let ds ← rows.mapM fun r => match runNano r.cells with
    | some d => pure d
    | none => throw s!"run {r.run}: a width lacks an arm"
  let armsK := arms.filterMap id
  let per := (rows.zip (armsK.zip ds)).map fun (r, a, d) =>
    (Json.mkObj [("kind", "real-run"), ("run", r.run), ("arm", armName a), ("cells", r.cells.length), ("D", d)]).compress
  let sc := byArm armsK ds .scoped
  let fa := byArm armsK ds .faithful
  let c := count ds armsK
  let tot := total armsK
  let fl := fun (xs : List Int) => xs.map fun d => (Float.ofInt d) / 1.0e9
  let m := mde (fl sc) (fl fa)
  let sum := (Json.mkObj [("kind", "real"), ("runs", rows.length), ("sumScoped", sc.sum), ("sumFaithful", fa.sum),
    ("tScaled", tScaled ds (obsSet armsK).length (obsSet armsK)), ("labelings", tot), ("count", c),
    ("verdict", verdictName (verdict c tot)), ("sdNano", nano (pooledSd (fl sc) (fl fa))), ("mdeNano", nano m),
    ("mdeRatioPpm", (nano (Float.exp m)) / (1000 : Int))]).compress
  pure (per ++ [sum])

/-- Hand-picked cell sets for `runNano`: (name, cells). -/
def statCases : List (String × List Cell) :=
  let mk := fun (c o b : Nat) => widths.flatMap fun w => [Cell.mk w 2 c, Cell.mk w 0 o, Cell.mk w 1 b]
  [ ("equal", mk 100 100 100), ("double", mk 200 100 100), ("pooled", mk 100 100 400),
    ("mixed", [Cell.mk 390 2 200, Cell.mk 390 0 100, Cell.mk 390 1 100, Cell.mk 640 2 100, Cell.mk 640 0 100, Cell.mk 640 1 100,
      Cell.mk 641 2 100, Cell.mk 641 0 100, Cell.mk 641 1 100, Cell.mk 1280 2 400, Cell.mk 1280 0 100, Cell.mk 1280 1 100]),
    ("no-1280", (mk 200 100 100).filter fun x => x.width != 1280),
    ("no-cand-390", (mk 200 100 100).filter fun x => !(x.width == 390 && x.role == 2)) ]

/-- Hand-picked labelings for `count`: (name, scoped runs among ten, values). -/
def permCases : List (String × List Arm × List Int) :=
  let s := Arm.scoped
  let f := Arm.faithful
  [ ("separated-up", [s, s, s, s, s, f, f, f, f, f], [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]),
    ("separated-down", [f, f, f, f, f, s, s, s, s, s], [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]),
    ("equal", [s, f, s, f, s, f, s, f, s, f], [5, 5, 5, 5, 5, 5, 5, 5, 5, 5]),
    ("one-swap", [s, s, s, s, f, s, f, f, f, f], [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]),
    ("three-of-ten", [s, s, s, f, f, f, f, f, f, f], [9, 8, 7, 0, 0, 0, 0, 0, 0, 0]),
    ("count-12", [f, f, f, f, s, s, s, s, f, s], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    ("count-13", [f, f, f, f, s, s, s, s, s, f], [1, 2, 3, 4, 5, 6, 7, 8, 9, 9]),
    ("unequal-groups", [s, s, s, f, f, f, f], [10, 20, 30, 40, 50, 60, 70]) ]

/-- Hand-picked groups for `mde`, in log g: (name, scoped values, faithful values). -/
def mdeCases : List (String × List Float × List Float) :=
  [ ("unit", [1.0, -1.0, 1.0, -1.0, 0.0], [1.0, -1.0, 1.0, -1.0, 0.0]),
    ("spread", [0.1, 0.2, 0.3, 0.4, 0.5], [-0.1, 0.0, 0.1, 0.2, 0.3]) ]

/-- Hand-picked identification triples: (search, hash, baseHash). -/
def identCases : List (String × String × String) :=
  [ (scopedSearch, "a", "b"), (scopedSearch, "a", "a"), (faithfulSearch, "a", "a"), (faithfulSearch, "a", "b"), ("", "a", "a") ]

/-- The golden lines without the real runs. -/
def caseLines (_ : Unit := ()) : List String :=
  identCases.map (fun (s, h, b) => (Json.mkObj [("kind", "ident"), ("search", s), ("hash", h), ("baseHash", b),
    ("arm", match identify s h b with | some a => Json.str (armName a) | none => Json.null)]).compress) ++
  statCases.map (fun (n, cs) => (Json.mkObj [("kind", "stat"), ("name", n),
    ("cells", toJson (cs.map fun c => [c.width, c.role, c.g])),
    ("D", match runNano cs with | some d => toJson d | none => Json.null)]).compress) ++
  permCases.map (fun (n, labels, vals) => (Json.mkObj [("kind", "perm"), ("name", n),
    ("labels", toJson (labels.map armName)), ("vals", toJson vals), ("labelings", total labels), ("count", count vals labels),
    ("verdict", verdictName (verdict (count vals labels) (total labels)))]).compress) ++
  mdeCases.map (fun (n, a, b) => (Json.mkObj [("kind", "mde"), ("name", n), ("a", toJson a), ("b", toJson b),
    ("sdNano", nano (pooledSd a b)), ("mdeNano", nano (mde a b))]).compress)

/-- The golden text for a cells file: the cases, then the real runs. -/
def goldenText (cells : String) : Except String String := do
  let rows ← (cells.splitOn "\n").filter (· ≠ "") |>.mapM parseRow
  let real ← realLines rows
  pure (String.intercalate "" ((caseLines () ++ real).map (· ++ "\n")))

/-- Print the golden text, or with `--check <file>` verify it. `--cells <file>` names the cells file. -/
def run (args : List String) : IO UInt32 := do
  let cellsPath := (Fw.Gate.Settle.argAfter args "--cells").getD "../packages/contracts/golden/gate/run-perm-cells.jsonl"
  match goldenText (← IO.FS.readFile cellsPath) with
  | .error e =>
    IO.eprintln s!"run-perm golden: {e}"
    return 1
  | .ok text =>
    match Fw.Gate.Settle.argAfter args "--check" with
    | some path =>
      let cur ← IO.FS.readBinFile path
      if cur.data == text.toUTF8.data then
        IO.eprintln s!"run-perm golden: {path} is up to date"
        return 0
      IO.eprintln s!"run-perm golden: {path} differs from the generated bytes"
      return 1
    | none =>
      IO.print text
      return 0

end Fw.Gate.RunPerm
