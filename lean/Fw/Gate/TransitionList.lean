import Lean.Data.Json

/-!
# Computed transition lists with their shorthands expanded

The breakpoint gate compares the five computed `transition-*` lists of a node. A rewrite may list a logical longhand
pair (`padding-inline-start, padding-inline-end`) where the original lists the shorthand (`padding-inline`): both
start the same transitions, because a transition on a shorthand property transitions every longhand it sets
(css-transitions-1 §3, "If a property is a shorthand, it is expanded to its longhands"; the list of transitioned
properties is then the expansion, each longhand taking the entry's duration, timing function, delay and behavior).
This module expands the listed shorthands in `transition-property`, repeats each entry's other four values for its
longhands, and leaves any list without a listed shorthand untouched, so every other comparison is as strict as before.

The five lists are parallel: entry `i` of `transition-property` takes entry `i mod n` of each other list of length
`n` (css-transitions-1 §3.1: lists repeat to the length of `transition-property`). Longhand names follow
css-logical-1 §4.3 and css-box-4 (`padding`, `margin`, `inset` physical order top, right, bottom, left).
-/

namespace Fw.Gate.TransitionList

open Lean

/-- The five computed `transition-*` lists of a node, each as the comma-separated entries `getComputedStyle` returns.

One node's transitions. -/
structure TL where
  props : List String
  durs : List String
  timings : List String
  delays : List String
  behaviors : List String
  deriving DecidableEq, Repr

/-- The allowlist of shorthand properties and their longhands, in expansion order.

Which names expand. -/
def table : List (String × List String) :=
  [("padding-inline", ["padding-inline-start", "padding-inline-end"]),
   ("padding-block", ["padding-block-start", "padding-block-end"]),
   ("margin-inline", ["margin-inline-start", "margin-inline-end"]),
   ("margin-block", ["margin-block-start", "margin-block-end"]),
   ("inset-inline", ["inset-inline-start", "inset-inline-end"]),
   ("inset-block", ["inset-block-start", "inset-block-end"]),
   ("padding", ["padding-top", "padding-right", "padding-bottom", "padding-left"]),
   ("margin", ["margin-top", "margin-right", "margin-bottom", "margin-left"]),
   ("inset", ["top", "right", "bottom", "left"])]

/-- The longhands of one property name; a name outside the table stays as it is.

Expansion of one entry. -/
def expand (p : String) : List String := (table.lookup p).getD [p]

/-- Whether the name is a listed shorthand.

Table membership. -/
def isShort (p : String) : Bool := (table.lookup p).isSome

/-- Whether some entry of `transition-property` is a listed shorthand.

The gate for expansion. -/
def hasShort (t : TL) : Bool := t.props.any isShort

/-- Whether every one of the other four lists has an entry to repeat.

Expansion needs it. -/
def filled (t : TL) : Bool := !t.durs.isEmpty && !t.timings.isEmpty && !t.delays.isEmpty && !t.behaviors.isEmpty

/-- Entry `i mod n` of a list of length `n` (the empty list gives the empty string).

List repetition. -/
def at' (l : List String) (i : Nat) : String := l.getD (i % l.length) ""

/-- The lists with every listed shorthand expanded; the other four lists repeat per entry. A list with no listed
shorthand (or with an empty companion list) is returned as it is.

The normal form compared by the gate. -/
def normalize (t : TL) : TL :=
  if hasShort t && filled t then
    let es := t.props.zipIdx
    { props := es.flatMap fun (p, _) => expand p
      durs := es.flatMap fun (p, i) => (expand p).map fun _ => at' t.durs i
      timings := es.flatMap fun (p, i) => (expand p).map fun _ => at' t.timings i
      delays := es.flatMap fun (p, i) => (expand p).map fun _ => at' t.delays i
      behaviors := es.flatMap fun (p, i) => (expand p).map fun _ => at' t.behaviors i }
  else t

/-- A list with no listed shorthand is unchanged.

Every comparison without a shorthand is as strict as before. -/
theorem normalize_of_not_hasShort (t : TL) (h : hasShort t = false) : normalize t = t := by
  simp [normalize, h]

/-- No longhand of the table is itself a table name.

Why one pass reaches the normal form. -/
theorem longhands_not_short : ∀ e ∈ table, ∀ l ∈ e.2, isShort l = false := by decide

private theorem mem_of_lookup (tb : List (String × List String)) (p : String) (ls : List String)
    (h : tb.lookup p = some ls) : (p, ls) ∈ tb := by
  induction tb with
  | nil => simp [List.lookup] at h
  | cons e tl ih =>
    obtain ⟨k, v⟩ := e
    simp only [List.lookup] at h
    by_cases hk : p == k
    · simp [hk] at h
      have : p = k := by simpa using hk
      subst this; subst h; simp
    · simp [hk] at h
      exact List.mem_cons_of_mem _ (ih h)

private theorem expand_not_short (p l : String) (h : l ∈ expand p) : isShort l = false := by
  unfold expand at h
  cases hp : table.lookup p with
  | none =>
    simp [hp] at h
    subst h
    simp [isShort, hp]
  | some ls =>
    simp [hp] at h
    exact longhands_not_short _ (mem_of_lookup table p ls hp) l h

/-- Normalization is idempotent.

A normalized list needs no second pass. -/
theorem normalize_idem (t : TL) : normalize (normalize t) = normalize t := by
  by_cases h : (hasShort t && filled t) = true
  · have hn : hasShort (normalize t) = false := by
      simp only [normalize, h, ite_true]
      simp only [hasShort, List.any_eq_false]
      intro l hl
      simp only [List.mem_flatMap] at hl
      obtain ⟨⟨p, i⟩, _, hl⟩ := hl
      simpa using expand_not_short p l hl
    exact normalize_of_not_hasShort _ hn
  · simp [normalize, h]

/-- Table rows, as the golden names them.

The two earn lists in the original (shorthand) and the rewrite (logical longhands), base state. -/
def earnFaithful : TL :=
  { props := ["max-width", "opacity", "padding-inline"], durs := ["0.68s", "0.32s", "0.68s"]
    timings := ["cubic-bezier(0.33, 0, 0.2, 1)", "cubic-bezier(0.33, 0, 0.2, 1)", "cubic-bezier(0.33, 0, 0.2, 1)"]
    delays := ["0s", "0.12s", "0s"], behaviors := ["normal", "normal", "normal"] }

/-- The rewrite's list for the same state (`nav:earn-logical`, nav.module.css).

The logical longhand spelling. -/
def earnLogical : TL :=
  { props := ["max-width", "opacity", "padding-inline-start", "padding-inline-end"]
    durs := ["0.68s", "0.32s", "0.68s", "0.68s"]
    timings := ["cubic-bezier(0.33, 0, 0.2, 1)", "cubic-bezier(0.33, 0, 0.2, 1)", "cubic-bezier(0.33, 0, 0.2, 1)",
      "cubic-bezier(0.33, 0, 0.2, 1)"]
    delays := ["0s", "0.12s", "0s", "0s"], behaviors := ["normal", "normal", "normal", "normal"] }

/-- The faithful and the logical earn lists normalize to the same list, and they differ before.

What the gate needs to judge the variant equal while still comparing the lists.
-/
theorem earn_equal : normalize earnFaithful = normalize earnLogical ∧ earnFaithful ≠ earnLogical := by decide

/-- The logical list is already in normal form.

Only the original side changes. -/
theorem earnLogical_fixed : normalize earnLogical = earnLogical := by decide

/-- Golden cases: name and list.

The vectors the TS twin replays. -/
def cases : List (String × TL) :=
  [("earn-faithful", earnFaithful), ("earn-logical", earnLogical),
   ("single-longhand", ⟨["opacity"], ["0.2s"], ["ease"], ["0s"], ["normal"]⟩),
   ("shorter-lists-repeat", ⟨["margin-block", "color", "inset-inline"], ["1s", "2s"], ["ease"], ["0s"], ["normal"]⟩),
   ("physical-padding", ⟨["padding"], ["1s"], ["linear"], ["0.1s"], ["normal"]⟩),
   ("inset-and-margin", ⟨["inset", "margin-inline"], ["1s", "2s"], ["ease", "linear"], ["0s", "1s"], ["normal", "allow-discrete"]⟩),
   ("unknown-name-stays", ⟨["all", "padding-inline-x"], ["1s"], ["ease"], ["0s"], ["normal"]⟩),
   ("empty-companion", ⟨["padding-inline"], [], ["ease"], ["0s"], ["normal"]⟩)]

private def listJ (l : List String) : Json := Json.arr (l.map Json.str).toArray

private def tlJson (t : TL) : Json :=
  Json.mkObj [("props", listJ t.props), ("durs", listJ t.durs), ("timings", listJ t.timings),
    ("delays", listJ t.delays), ("behaviors", listJ t.behaviors)]

/-- The golden text, one JSON line per case.

The golden file's contents. -/
def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, t) =>
    (Json.mkObj [("name", n), ("request", tlJson t), ("response", tlJson (normalize t))]).compress ++ "\n")

/-- The golden file, relative to `lean/`.

Where the vectors live. -/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "gate" / "transition-list.jsonl"

/-- Writes the golden file, or compares it with the generated text and returns `fail ∈ {0, 1}`.

Keeps the JavaScript twin's vectors in step with the rule. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / goldenPath
  if write then
    IO.FS.writeFile p goldenText
    IO.println s!"transition-list golden: {cases.length} cases, written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"transition-list golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/TransitionListGolden.lean)"
    return 1
  IO.println s!"transition-list golden: {cases.length} cases, up to date"
  return 0

#guard (cases.map (·.1)).Nodup
#guard cases.all fun (_, t) => normalize (normalize t) == normalize t
#guard (normalize ⟨["opacity"], ["0.2s"], ["ease"], ["0s"], ["normal"]⟩).props == ["opacity"]

end Fw.Gate.TransitionList
