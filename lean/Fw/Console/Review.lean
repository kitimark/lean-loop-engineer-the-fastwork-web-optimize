import Fw.Console.Alert
import Fw.Preset.Gen
/-!
# Pending user reviews of kept look changes

A kept look change whose visual review is pending becomes one user step; only a recorded keep or reject closes it.
-/
namespace Fw.Console.Review
open Fw.Preset

/-- The user's answer to a review. -/
inductive Verdict | keep | reject
deriving DecidableEq, Repr

/-- The word of an answer (the step option and the URL body). -/
def Verdict.word : Verdict → String
  | .keep => "keep"
  | .reject => "reject"

/-- The verdict a word names. -/
def Verdict.ofWord : String → Option Verdict
  | "keep" => some .keep
  | "reject" => some .reject
  | _ => none

/-- The words of a decision row that mark its visual review as pending. -/
def marker : String := "pending user visual review"

/-- Whether the words of a decision row leave the visual review pending. -/
def pending (words : String) : Bool := 1 < (words.splitOn marker).length

/-- A decision row: the flag, the date and the words of the user's decision (`Fw.Preset.Gen.lookDecisions`). -/
abbrev Row := Flag × String × String

/-- A step of the board as the review reads it: its id and its answer. -/
structure Rec where
  id : String
  answer : Option String
deriving DecidableEq, Repr

/-- The id of the board step that carries the review of a flag. -/
def stepId (f : Flag) : String := "review-" ++ f.key

/-- The audience of a review step: the owner, as for a prompt that needs the owner (`Fw.Console.Alert.audienceOf`). -/
def audience : Audience := .user

/-- The recorded decision of a flag: the verdict word in the answer of its step. -/
def recorded (rs : List Rec) (f : Flag) : Option Verdict :=
  match rs.find? (·.id == stepId f) with
  | some r => r.answer.bind Verdict.ofWord
  | none => none

/-- The list without repeated flags, keeping the first of each. -/
def dedup : List Flag → List Flag
  | [] => []
  | a :: l => a :: (dedup l).erase a

/-- The flags whose review is pending, each once, in row order. -/
def pendingFlags (ds : List Row) : List Flag :=
  dedup ((ds.filter fun d => pending d.2.2).map (·.1))

/-- One open or decided review. -/
structure Item where
  flag : Flag
  step : String
  date : String
  words : String
  state : Option Verdict
deriving Repr

/-- The item of a pending flag, with the first pending row that names it. -/
def itemOf (ds : List Row) (rs : List Rec) (f : Flag) : Item :=
  let row := ds.find? fun d => d.1 == f && pending d.2.2
  { flag := f, step := stepId f, date := (row.map (·.2.1)).getD "", words := (row.map (·.2.2)).getD "",
    state := recorded rs f }

/-- The reviews: one item per pending flag. -/
def items (ds : List Row) (rs : List Rec) : List Item := (pendingFlags ds).map (itemOf ds rs)

/-- The items still open. -/
def openItems (ds : List Row) (rs : List Rec) : List Item := (items ds rs).filter (·.state.isNone)

/-- Whether the step of a flag is still to be posted. -/
def needsPost (rs : List Rec) (f : Flag) : Bool := !(rs.any (·.id == stepId f))

/-- Whether an answer to the review of `f` is accepted, and why not. -/
def accept (ds : List Row) (rs : List Rec) (f : Flag) (word : String) : Except String Verdict :=
  if !(pendingFlags ds).contains f then .error "no pending review for this flag"
  else if (recorded rs f).isSome then .error "this review is already decided"
  else match Verdict.ofWord word with
    | some v => .ok v
    | none => .error "the decision must be keep or reject"

/-- The title of the review step. -/
def title (f : Flag) : String := "Review the look change " ++ f.key

/-- The plain text of the review step. -/
def body (i : Item) : String :=
  Fw.Console.Alert.bodyLines audience
    s!"The look change {i.flag.key} was kept on {i.date} ({i.words})."
    "Nothing is blocked. Compose marks the variant \"look change, review pending\" until you decide."
    "Open the review page, look at the frame strips, then press Keep or Reject in the console."
    s!"flag {i.flag.key}; step {i.step}"

/-- Dedup keeps exactly the flags of the list. -/
theorem mem_dedup (l : List Flag) (x : Flag) : x ∈ dedup l ↔ x ∈ l := by
  induction l with
  | nil => simp [dedup]
  | cons a l ih =>
    by_cases h : x = a
    · subst h; simp [dedup]
    · simp [dedup, h, List.mem_erase_of_ne h, ih]

/-- Dedup has no repeated flag. -/
theorem nodup_dedup (l : List Flag) : (dedup l).Nodup := by
  induction l with
  | nil => simp [dedup]
  | cons a l ih =>
    simp only [dedup, List.nodup_cons]
    exact ⟨fun h => ((ih.mem_erase_iff).1 h).1 rfl, ih.erase a⟩

/-- A flag is pending when a decision row of it is pending. -/
theorem mem_pendingFlags (ds : List Row) (f : Flag) :
    f ∈ pendingFlags ds ↔ ∃ d ∈ ds, d.1 = f ∧ pending d.2.2 = true := by
  simp only [pendingFlags, mem_dedup, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨d, ⟨h1, h2⟩, h3⟩; exact ⟨d, h1, h3, h2⟩
  · rintro ⟨d, h1, h3, h2⟩; exact ⟨d, ⟨h1, h2⟩, h3⟩

/-- The flags with a recorded decision stay decided when the record grows. -/
theorem recorded_append (rs ts : List Rec) (f : Flag) (v : Verdict) (h : recorded rs f = some v) :
    recorded (rs ++ ts) f = some v := by
  unfold recorded at *
  cases hf : rs.find? (·.id == stepId f) with
  | none => simp [hf] at h
  | some r =>
    rw [List.find?_append, hf]
    simpa [hf] using h

/-- Nothing recorded, nothing decided. -/
theorem recorded_nil (f : Flag) : recorded [] f = none := rfl

/-- A decision is recorded only by a step of the flag whose answer is the verdict word. -/
theorem closed_only_on_decision (rs : List Rec) (f : Flag) (v : Verdict) (h : recorded rs f = some v) :
    ∃ r ∈ rs, r.id = stepId f ∧ r.answer = some v.word := by
  unfold recorded at h
  cases hf : rs.find? (·.id == stepId f) with
  | none => simp [hf] at h
  | some r =>
    simp only [hf, Option.bind_eq_some_iff] at h
    obtain ⟨a, ha, hv⟩ := h
    refine ⟨r, List.mem_of_find?_eq_some hf, ?_, ?_⟩
    · simpa using List.find?_some hf
    · have : a = v.word := by
        cases v <;> (unfold Verdict.ofWord at hv; split at hv <;> simp_all [Verdict.word])
      rw [← this]; exact ha

/-- The items are the pending flags, in order. -/
theorem items_flags (ds : List Row) (rs : List Rec) : (items ds rs).map (·.flag) = pendingFlags ds := by
  simp [items, itemOf, List.map_map, Function.comp_def]

/-- An item exists for a flag exactly when a decision row of the flag is pending. -/
theorem item_iff_pending (ds : List Row) (rs : List Rec) (f : Flag) :
    (∃ i ∈ items ds rs, i.flag = f) ↔ ∃ d ∈ ds, d.1 = f ∧ pending d.2.2 = true := by
  rw [← mem_pendingFlags, ← items_flags ds rs]; simp

/-- Every pending look decision yields exactly one item. -/
theorem one_item_per_pending (ds : List Row) (rs : List Rec) (f : Flag) (h : ∃ d ∈ ds, d.1 = f ∧ pending d.2.2 = true) :
    ((items ds rs).filter fun i => i.flag == f).length = 1 := by
  have hm : f ∈ pendingFlags ds := (mem_pendingFlags ds f).2 h
  have hn : (pendingFlags ds).Nodup := nodup_dedup _
  have e : ((items ds rs).filter fun i => i.flag == f).length = ((items ds rs).map (·.flag)).count f := by
    rw [List.count_eq_countP, List.countP_map, List.countP_eq_length_filter]
    rfl
  rw [e, items_flags]
  exact hn.count_of_mem hm

/-- An item is open exactly when no decision is recorded for its flag. -/
theorem item_state (ds : List Row) (rs : List Rec) (i : Item) (h : i ∈ items ds rs) : i.state = recorded rs i.flag := by
  simp only [items, List.mem_map] at h
  obtain ⟨f, _, rfl⟩ := h
  rfl

/-- A decided item never reopens when the record grows. -/
theorem decided_stays (ds : List Row) (rs ts : List Rec) (i : Item) (v : Verdict)
    (h : i ∈ items ds rs) (hs : i.state = some v) :
    ∃ j ∈ items ds (rs ++ ts), j.flag = i.flag ∧ j.state = some v := by
  refine ⟨itemOf ds (rs ++ ts) i.flag, ?_, rfl, ?_⟩
  · simp only [items, List.mem_map]
    refine ⟨i.flag, ?_, rfl⟩
    rw [← items_flags ds rs]; exact List.mem_map.2 ⟨i, h, rfl⟩
  · rw [item_state ds rs i h] at hs
    exact recorded_append rs ts i.flag v hs

/-- An answer is accepted only for a pending, undecided flag and a verdict word. -/
theorem accept_ok (ds : List Row) (rs : List Rec) (f : Flag) (w : String) (v : Verdict)
    (h : accept ds rs f w = .ok v) :
    f ∈ pendingFlags ds ∧ recorded rs f = none ∧ Verdict.ofWord w = some v := by
  unfold accept at h
  split at h
  · simp at h
  split at h
  · simp at h
  rename_i h1 h2
  cases hw : Verdict.ofWord w with
  | none => simp [hw] at h
  | some u =>
    simp only [hw] at h
    have : u = v := by simpa using h
    subst this
    refine ⟨?_, ?_, rfl⟩
    · simpa using h1
    · cases hr : recorded rs f <;> simp_all

/-- The audience of a review is the audience of a prompt that needs the owner. -/
theorem audience_is_owner (a : String) : audience = Fw.Console.Alert.audienceOf .needsInput a := rfl

/-- A decided item is not open. -/
theorem decided_not_open (ds : List Row) (rs : List Rec) (i : Item) (v : Verdict)
    (hs : i.state = some v) : i ∉ openItems ds rs := by
  simp [openItems, hs]

/-- An item with no recorded decision is open. -/
theorem undecided_open (ds : List Row) (rs : List Rec) (i : Item) (h : i ∈ items ds rs) (hs : i.state = none) :
    i ∈ openItems ds rs := by
  simp [openItems, h, hs]

#guard pending "accepted, pending user visual review"
#guard !pending "kept after visual review"
#guard (items [(⟨"nav", "e"⟩, "d", "pending user visual review")] []).length == 1
#guard (openItems [(⟨"nav", "e"⟩, "d", "pending user visual review")]
  [⟨"review-nav:e", some "keep"⟩]).length == 0
#guard (openItems [(⟨"nav", "e"⟩, "d", "pending user visual review")] [⟨"review-nav:e", none⟩]).length == 1

end Fw.Console.Review
