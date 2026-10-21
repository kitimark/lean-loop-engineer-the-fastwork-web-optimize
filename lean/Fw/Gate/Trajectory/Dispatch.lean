import Fw.Gate.Trajectory
/-!
# Trajectory dispatch scope: which width subsets a dispatch may run

A dispatch is marked verdict (its run is stored and judged) or diagnostic. `outcome` gives no verdict to a run short of
a lane width, so a verdict dispatch walks all four widths and only a diagnostic one may walk a subset.
`apps/runner/src/run-pick.ts` is the TS twin, checked against `packages/contracts/golden/gate/trajectory-dispatch.jsonl`.

```
cd lean && lake env lean --run scripts/TrajectoryDispatchGolden.lean           # write the file
cd lean && lake env lean --run scripts/TrajectoryDispatchGolden.lean --check   # fail if it is stale
```
-/
namespace Fw.Gate.Trajectory.Dispatch
open Lean Fw.Gate.Trajectory

/-- What a run is for: a verdict run is stored and judged, a diagnostic run is read by hand. -/
inductive Mark where
  | verdict
  | diagnostic
  deriving DecidableEq, Repr

/-- Why a dispatch is refused. -/
inductive Why where
  | emptyWidths
  | badInput
  | scopedVerdict
  deriving DecidableEq, Repr

/-- The decision on a dispatch: run these widths, or refuse. -/
inductive Decision where
  | accepted (ws : List Nat)
  | refused (why : Why)
  deriving DecidableEq, Repr

/-- The decision on a mark and the widths a dispatch walks: none is empty, a width outside the lane is bad, a verdict run
short of a lane width is scoped. -/
def dispatch (m : Mark) (ws : List Nat) : Decision :=
  if ws.isEmpty then .refused .emptyWidths
  else if !ws.all allowedWidths.contains then .refused .badInput
  else match m with
    | .diagnostic => .accepted ws
    | .verdict => if allowedWidths.all ws.contains then .accepted ws else .refused .scopedVerdict

/-- The decision on a mark and the `widths` input: an empty input is all four widths, a refused one is bad. -/
def dispatchIn (m : Mark) (s : String) : Decision :=
  match pickWidths s with
  | .refused => .refused .badInput
  | .list ws => dispatch m ws

/-- The legs an engine runs for a dispatch; none when it is refused. -/
def dispatchLegs (e : Engine) (m : Mark) (s : String) : Option (List (List Nat)) :=
  match dispatchIn m s with
  | .accepted ws => some (legs e ws)
  | .refused _ => none

-- The decision, whole -----------------------------------------------------------------------------------------------

/-- A dispatch is accepted, whole, exactly when it is nonempty, inside the lane, and (verdict only) complete. -/
theorem dispatch_accepted_iff (m : Mark) (ws xs : List Nat) :
    dispatch m ws = .accepted xs ↔
      xs = ws ∧ ws ≠ [] ∧ (∀ w ∈ ws, w ∈ allowedWidths) ∧ (m = .verdict → ∀ w ∈ allowedWidths, w ∈ ws) := by
  unfold dispatch
  by_cases h1 : ws = []
  · subst h1; simp
  have h1' : ws.isEmpty = false := by simpa using h1
  by_cases h2 : ∀ w ∈ ws, w ∈ allowedWidths
  · have h2' : ws.all allowedWidths.contains = true := by simpa using h2
    cases m
    · by_cases h3 : ∀ w ∈ allowedWidths, w ∈ ws
      · have h3' : allowedWidths.all ws.contains = true := by simpa using h3
        simp [h1', h2', h3', h1, eq_comm]
        rintro rfl; exact ⟨h2, h3⟩
      · have h3' : allowedWidths.all ws.contains = false := by simpa using h3
        simp [h1', h2', h3', h1, h3]
    · simp [h1', h2', h1, eq_comm]
      rintro rfl; exact h2
  · have h2' : ws.all allowedWidths.contains = false := by simpa using h2
    simp [h1', h2', h1, h2]

-- Refusals -----------------------------------------------------------------------------------------------------------

/-- Branch empty: no width at all is refused, for either mark. -/
theorem dispatch_empty (m : Mark) : dispatch m [] = .refused .emptyWidths := by
  simp [dispatch]

/-- Branch outside the lane: a width the lane does not run is refused, for either mark. -/
theorem dispatch_bad (m : Mark) (ws : List Nat) (hne : ws ≠ []) (h : ¬ ∀ w ∈ ws, w ∈ allowedWidths) :
    dispatch m ws = .refused .badInput := by
  have h1 : ws.isEmpty = false := by simpa using hne
  have h2 : ws.all allowedWidths.contains = false := by simpa using h
  simp [dispatch, h1, h2]

/-- Branch scoped verdict: a verdict run short of a lane width is refused. -/
theorem dispatch_verdict_scoped (ws : List Nat) (hne : ws ≠ []) (hin : ∀ w ∈ ws, w ∈ allowedWidths)
    (w : Nat) (hw : w ∈ allowedWidths) (hm : w ∉ ws) : dispatch .verdict ws = .refused .scopedVerdict := by
  have h1 : ws.isEmpty = false := by simpa using hne
  have h2 : ws.all allowedWidths.contains = true := by simpa using hin
  have h3 : allowedWidths.all ws.contains = false := by
    rw [List.all_eq_false]; exact ⟨w, hw, by simpa using hm⟩
  simp [dispatch, h1, h2, h3]

/-- Branch diagnostic: a nonempty subset of the lane widths is accepted, whole. -/
theorem dispatch_diagnostic (ws : List Nat) (hne : ws ≠ []) (hin : ∀ w ∈ ws, w ∈ allowedWidths) :
    dispatch .diagnostic ws = .accepted ws :=
  (dispatch_accepted_iff _ _ _).2 ⟨rfl, hne, hin, fun h => by cases h⟩

/-- Branch complete verdict: all four widths are accepted. -/
theorem dispatch_verdict_all : dispatch .verdict allowedWidths = .accepted allowedWidths := by decide

/-- An empty `widths` input is all four widths, for either mark. -/
theorem dispatchIn_default (m : Mark) : dispatchIn m "" = .accepted allowedWidths := by
  cases m <;> decide

-- Verdict runs -------------------------------------------------------------------------------------------------------

/-- An accepted verdict dispatch walks every lane width. -/
theorem verdict_all_widths (ws xs : List Nat) (h : dispatch .verdict ws = .accepted xs) :
    ∀ w ∈ allowedWidths, w ∈ xs := by
  obtain ⟨rfl, _, _, hv⟩ := (dispatch_accepted_iff _ _ _).1 h
  exact hv rfl

/-- The `widths` input of an accepted verdict dispatch also walks every lane width. -/
theorem verdict_in_all_widths (s : String) (xs : List Nat) (h : dispatchIn .verdict s = .accepted xs) :
    ∀ w ∈ allowedWidths, w ∈ xs := by
  unfold dispatchIn at h
  split at h
  · simp at h
  · exact verdict_all_widths _ _ h

/-- A run of an accepted verdict dispatch never lacks a width: `outcome` does not give `unjudged .widths` for it. -/
theorem verdict_outcome_judged (ws : List Nat) (s : Stored) (h : dispatch .verdict ws = .accepted s.widths)
    (hc : covers s.engine s.walk = true) : outcome s ≠ .unjudged .widths := by
  have hall : allowedWidths.all s.widths.contains = true := by
    simpa using verdict_all_widths ws s.widths h
  simp only [outcome, hc, hall, Bool.not_true, Bool.false_eq_true, ite_false, ne_eq]
  split <;> try simp
  split <;> simp

-- Diagnostic runs ----------------------------------------------------------------------------------------------------

/-- An accepted dispatch of either mark walks at least one width, in the lane. -/
theorem accepted_nonempty (m : Mark) (ws xs : List Nat) (h : dispatch m ws = .accepted xs) :
    xs ≠ [] ∧ ∀ w ∈ xs, w ∈ allowedWidths := by
  obtain ⟨rfl, hne, hin, _⟩ := (dispatch_accepted_iff _ _ _).1 h
  exact ⟨hne, hin⟩

/-- A diagnostic dispatch walks at least one width and every engine has a leg for it. -/
theorem diagnostic_nonempty (ws xs : List Nat) (h : dispatch .diagnostic ws = .accepted xs) (e : Engine) :
    xs ≠ [] ∧ legs e xs ≠ [] := by
  obtain ⟨hne, hin⟩ := accepted_nonempty _ _ _ h
  refine ⟨hne, fun hl => ?_⟩
  obtain ⟨w, hw⟩ := List.exists_mem_of_ne_nil _ hne
  have := (legs_mem e xs w).2 ⟨hw, hin w hw⟩
  rw [hl] at this
  simp at this

/-- A diagnostic run short of a lane width has no verdict, so it is never judged. -/
theorem diagnostic_unjudged (s : Stored) (hc : covers s.engine s.walk = true) (w : Nat) (hw : w ∈ allowedWidths)
    (hm : w ∉ s.widths) : outcome s = .unjudged .widths :=
  outcome_widths s hc w hw hm

-- Legs ---------------------------------------------------------------------------------------------------------------

/-- The legs of an accepted dispatch walk exactly its widths. -/
theorem dispatch_legs_mem (m : Mark) (ws xs : List Nat) (h : dispatch m ws = .accepted xs) (e : Engine) (w : Nat) :
    w ∈ (legs e xs).flatten ↔ w ∈ xs := by
  obtain ⟨_, hin⟩ := accepted_nonempty m ws xs h
  rw [legs_mem]
  exact ⟨fun h => h.1, fun h => ⟨h, hin w h⟩⟩

/-- All four widths: the legs are the leg table, so a verdict dispatch uses every slot. -/
theorem dispatchLegs_verdict_default (e : Engine) : dispatchLegs e .verdict "" = some (legTable e) := by
  cases e <;> decide

/-- Cutting the widths never adds a leg. -/
theorem legs_length_le (e : Engine) (ws : List Nat) : (legs e ws).length ≤ (legTable e).length := by
  unfold legs
  exact Nat.le_trans (List.length_filter_le _ _) (by simp)

/-- Two lists are the legs of the macOS table cut: a pair keeps its nonempty members. -/
theorem pair_filter_length (a b : List Nat) :
    ([a, b].filter fun l => !l.isEmpty).length = 1 ↔ (a = [] ∧ b ≠ []) ∨ (a ≠ [] ∧ b = []) := by
  cases a <;> cases b <;> simp

/-- A cut of a pair of widths is empty exactly when none of the pair is picked. -/
theorem cut_eq_nil (p q : Nat) (ws : List Nat) :
    [p, q].filter ws.contains = [] ↔ p ∉ ws ∧ q ∉ ws := by
  simp [List.filter_eq_nil_iff]

/-- The macOS legs of a nonempty subset of the lane widths: one when the widths fall within 390 and 641 or within 640
and 1280, else two. -/
theorem one_leg_iff (ws : List Nat) (hne : ws ≠ []) (hin : ∀ w ∈ ws, w ∈ allowedWidths) :
    (legs .macWebkit ws).length = 1 ↔ ((∀ w ∈ ws, w = 390 ∨ w = 641) ∨ (∀ w ∈ ws, w = 640 ∨ w = 1280)) := by
  have hmem : ∀ w ∈ ws, w = 390 ∨ w = 640 ∨ w = 641 ∨ w = 1280 := fun w hw => by
    have := hin w hw; simp [allowedWidths] at this; omega
  obtain ⟨w0, hw0⟩ := List.exists_mem_of_ne_nil _ hne
  have hlegs : legs .macWebkit ws = [[390, 641].filter ws.contains, [640, 1280].filter ws.contains].filter
      fun l => !l.isEmpty := rfl
  rw [hlegs, pair_filter_length]
  simp only [ne_eq, cut_eq_nil]
  constructor
  · rintro (⟨⟨h1, h2⟩, _⟩ | ⟨_, ⟨h1, h2⟩⟩)
    · right
      intro w hw
      rcases hmem w hw with rfl | rfl | rfl | rfl
      · exact absurd hw h1
      · exact Or.inl rfl
      · exact absurd hw h2
      · exact Or.inr rfl
    · left
      intro w hw
      rcases hmem w hw with rfl | rfl | rfl | rfl
      · exact Or.inl rfl
      · exact absurd hw h1
      · exact Or.inr rfl
      · exact absurd hw h2
  · rintro (h | h)
    · right
      refine ⟨fun ⟨h1, h2⟩ => ?_, ?_, ?_⟩
      · rcases h w0 hw0 with rfl | rfl
        · exact h1 hw0
        · exact h2 hw0
      · intro hh; rcases h 640 hh with h' | h' <;> omega
      · intro hh; rcases h 1280 hh with h' | h' <;> omega
    · left
      refine ⟨⟨?_, ?_⟩, fun ⟨h1, h2⟩ => ?_⟩
      · intro hh; rcases h 390 hh with h' | h' <;> omega
      · intro hh; rcases h 641 hh with h' | h' <;> omega
      · rcases h w0 hw0 with rfl | rfl
        · exact h1 hw0
        · exact h2 hw0

-- The golden ---------------------------------------------------------------------------------------------------------

/-- The word of a mark in the golden. -/
def Mark.word : Mark → String
  | .verdict => "verdict"
  | .diagnostic => "diagnostic"

/-- The word of a refusal in the golden. -/
def Why.word : Why → String
  | .emptyWidths => "emptyWidths"
  | .badInput => "badInput"
  | .scopedVerdict => "scopedVerdict"

/-- The engines of the golden, in the order of the dispatch. -/
def engines : List Engine := [.chromium, .linuxWebkit, .macWebkit]

/-- The widths as JSON. -/
def widthsJson (ws : List Nat) : Json := Json.arr (ws.map fun w => toJson w).toArray

/-- A decision as JSON fields: its verdict word, the refusal or null, the widths or null. -/
def Decision.fields : Decision → List (String × Json)
  | .accepted ws => [("decision", "accepted"), ("why", Json.null), ("widths", widthsJson ws)]
  | .refused w => [("decision", "refused"), ("why", w.word), ("widths", Json.null)]

/-- The legs of an accepted decision per engine, or null. -/
def legsJson : Decision → Json
  | .accepted ws => Json.mkObj (engines.map fun e => (e.word, Json.arr ((legs e ws).map widthsJson).toArray))
  | .refused _ => Json.null

/-- A golden line for a dispatch on a `widths` input. -/
def inLine (m : Mark) (s : String) : Json :=
  let d := dispatchIn m s
  Json.mkObj ([("kind", Json.str "in"), ("mark", Json.str m.word), ("input", Json.str s)] ++ d.fields ++ [("legs", legsJson d)])

/-- A golden line for a dispatch on a list of widths. -/
def listLine (m : Mark) (ws : List Nat) : Json :=
  let d := dispatch m ws
  Json.mkObj ([("kind", Json.str "list"), ("mark", Json.str m.word), ("in", widthsJson ws)] ++ d.fields ++ [("legs", legsJson d)])

/-- A golden line for an `engines` input. -/
def enginesLine (s : String) : Json :=
  Json.mkObj [("kind", "engines"), ("input", s),
    ("engines", match enginesOf s with
      | none => Json.null
      | some es => Json.arr (es.map fun e => Json.str e.word).toArray)]

/-- The nonempty subsets of the lane widths, each in lane order. -/
def subsets : List (List Nat) := (allowedWidths.foldr (fun w acc => acc ++ acc.map (w :: ·)) [[]]).filter (· ≠ [])

/-- A subset as a `widths` input. -/
def commaOf (ws : List Nat) : String := ",".intercalate (ws.map toString)

/-- The `widths` inputs of the golden: empty, every subset, and the refused ones. -/
def inputs : List String :=
  [""] ++ subsets.map commaOf ++ ["1280,390", "390,500", "390,390", "390,,640", "390,wide", ",", "0", "-390", "0390", "390,", " 390"]

/-- The lists of widths of the golden: empty, outside the lane, repeated, complete, and every subset. -/
def lists : List (List Nat) := [[], [500], [390, 500], [390, 390], allowedWidths] ++ subsets

/-- The golden lines. -/
def lines : List Json :=
  ([Mark.verdict, .diagnostic].flatMap fun m => inputs.map (inLine m) ++ lists.map (listLine m)) ++
    ["both", "chromium", "playwright-webkit", "firefox", ""].map enginesLine

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/gate/trajectory-dispatch.jsonl"

/-- The golden file text. -/
def goldenText : String := String.join (lines.map fun l => l.compress ++ "\n")

/-- Write, or with `--check` verify, the golden file; exit 1 when it is stale. -/
def run (args : List String) : IO UInt32 := do
  if !args.contains "--check" then
    IO.FS.writeFile goldenPath goldenText
    IO.println s!"trajectory-dispatch golden: {lines.length} lines written"
    return 0
  let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
  if cur != goldenText then
    IO.println s!"trajectory-dispatch golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/TrajectoryDispatchGolden.lean)"
    return 1
  IO.println s!"trajectory-dispatch golden: {lines.length} lines, up to date"
  return 0

end Fw.Gate.Trajectory.Dispatch
