import Lean.Data.Json

namespace Fw.Gate.TransitionList

open Lean

structure TL where
  props : List String
  durs : List String
  timings : List String
  delays : List String
  behaviors : List String
  deriving DecidableEq, Repr

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

def expand (p : String) : List String := (table.lookup p).getD [p]

def isShort (p : String) : Bool := (table.lookup p).isSome

def hasShort (t : TL) : Bool := t.props.any isShort

def filled (t : TL) : Bool := !t.durs.isEmpty && !t.timings.isEmpty && !t.delays.isEmpty && !t.behaviors.isEmpty

def at' (l : List String) (i : Nat) : String := l.getD (i % l.length) ""

def normalize (t : TL) : TL :=
  if hasShort t && filled t then
    let es := t.props.zipIdx
    { props := es.flatMap fun (p, _) => expand p
      durs := es.flatMap fun (p, i) => (expand p).map fun _ => at' t.durs i
      timings := es.flatMap fun (p, i) => (expand p).map fun _ => at' t.timings i
      delays := es.flatMap fun (p, i) => (expand p).map fun _ => at' t.delays i
      behaviors := es.flatMap fun (p, i) => (expand p).map fun _ => at' t.behaviors i }
  else t

theorem normalize_of_not_hasShort (t : TL) (h : hasShort t = false) : normalize t = t := by
  simp [normalize, h]

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

def earnFaithful : TL :=
  { props := ["max-width", "opacity", "padding-inline"], durs := ["0.68s", "0.32s", "0.68s"]
    timings := ["cubic-bezier(0.33, 0, 0.2, 1)", "cubic-bezier(0.33, 0, 0.2, 1)", "cubic-bezier(0.33, 0, 0.2, 1)"]
    delays := ["0s", "0.12s", "0s"], behaviors := ["normal", "normal", "normal"] }

def earnLogical : TL :=
  { props := ["max-width", "opacity", "padding-inline-start", "padding-inline-end"]
    durs := ["0.68s", "0.32s", "0.68s", "0.68s"]
    timings := ["cubic-bezier(0.33, 0, 0.2, 1)", "cubic-bezier(0.33, 0, 0.2, 1)", "cubic-bezier(0.33, 0, 0.2, 1)",
      "cubic-bezier(0.33, 0, 0.2, 1)"]
    delays := ["0s", "0.12s", "0s", "0s"], behaviors := ["normal", "normal", "normal", "normal"] }

theorem earn_equal : normalize earnFaithful = normalize earnLogical ∧ earnFaithful ≠ earnLogical := by decide

theorem earnLogical_fixed : normalize earnLogical = earnLogical := by decide

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

def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, t) =>
    (Json.mkObj [("name", n), ("request", tlJson t), ("response", tlJson (normalize t))]).compress ++ "\n")

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "gate" / "transition-list.jsonl"

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
