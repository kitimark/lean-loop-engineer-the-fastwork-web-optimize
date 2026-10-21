import Fw.Console.Alert
import Fw.Console.ReviewStrips
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

/-- A decision row: the flag, the date, the verdict, the review state and the material (`Fw.Preset.Gen.lookDecisions`). -/
abbrev Row := Fw.Preset.Gen.LookDecision

/-- Whether the visual review of a decision row is still to come. Read from the structured field, not from words. -/
def pending (d : Row) : Bool := d.review == .pending

/-- The words of a decision row, made from its fields. -/
def words (d : Row) : String := d.decision.word ++ (if pending d then ", visual review pending" else "")

/-- A step of the board as the review reads it: its id, its answer, and whether the step is still open (waiting or started). -/
structure Rec where
  id : String
  answer : Option String
  isOpen : Bool
deriving DecidableEq, Repr

/-- The id of the first review step of a flag. -/
def stepId (f : Flag) : String := "review-" ++ f.key

/-- The id of the `k`-th review step of a flag: the first is `stepId`, a later one (posted again after a step was closed
without a decision) is `review-<flag>#<k>`. -/
def stepIdN (f : Flag) (k : Nat) : String := if k = 0 then stepId f else stepId f ++ "#" ++ toString k

/-- Whether a step id belongs to the review steps of a flag. -/
def inFamily (f : Flag) (id : String) : Bool := id == stepId f || (stepId f ++ "#").toList.isPrefixOf id.toList

/-- The audience of a review step: the owner, as for a prompt that needs the owner (`Fw.Console.Alert.audienceOf`). -/
def audience : Audience := .user

/-- The recorded decision of a flag: the first verdict word in the answer of a review step of the flag. -/
def recorded (rs : List Rec) (f : Flag) : Option Verdict :=
  (rs.filterMap fun r => if inFamily f r.id then r.answer.bind Verdict.ofWord else none).head?

/-- The open (waiting or started) review step of a flag, if any. -/
def openStep (rs : List Rec) (f : Flag) : Option Rec := rs.find? fun r => inFamily f r.id && r.isOpen

/-- The step that carries the recorded verdict of a flag. -/
def decidedStep (rs : List Rec) (f : Flag) : Option Rec :=
  rs.find? fun r => inFamily f r.id && (r.answer.bind Verdict.ofWord).isSome

/-- The id for a new review step of a flag: the first of `stepIdN f 0, 1, ...` that is not on the board. -/
def freshId (rs : List Rec) (f : Flag) : String :=
  (((List.range (rs.length + 2)).find? fun k => !(rs.any (·.id == stepIdN f k))).map (stepIdN f)).getD
    (stepIdN f (rs.length + 1))

/-- The list without repeated flags, keeping the first of each. -/
def dedup : List Flag → List Flag
  | [] => []
  | a :: l => a :: (dedup l).erase a

/-- The flags whose review is pending, each once, in row order. -/
def pendingFlags (ds : List Row) : List Flag :=
  dedup ((ds.filter pending).map (·.flag))

/-- One open or decided review. -/
structure Item where
  flag : Flag
  step : String
  date : String
  words : String
  material : Option Fw.Preset.Gen.ReviewMaterial
  state : Option Verdict
deriving Repr

/-- The step of an item: the step with the verdict, else the open step, else the id a new step gets. -/
def stepOf (rs : List Rec) (f : Flag) : String :=
  match decidedStep rs f with
  | some r => r.id
  | none => match openStep rs f with
    | some r => r.id
    | none => freshId rs f

/-- The item of a pending flag, with the first pending row that names it. -/
def itemOf (ds : List Row) (rs : List Rec) (f : Flag) : Item :=
  let row := ds.find? fun d => d.flag == f && pending d
  { flag := f, step := stepOf rs f, date := (row.map (·.date)).getD "", words := (row.map words).getD "",
    material := row.bind (·.material), state := recorded rs f }

/-- The reviews: one item per pending flag. -/
def items (ds : List Row) (rs : List Rec) : List Item := (pendingFlags ds).map (itemOf ds rs)

/-- The items still open. -/
def openItems (ds : List Row) (rs : List Rec) : List Item := (items ds rs).filter (·.state.isNone)

/-- Whether a step is to be posted for a flag: no verdict is recorded and no review step of it is open (none was posted,
or every one was closed without a verdict). -/
def needsPost (rs : List Rec) (f : Flag) : Bool := (recorded rs f).isNone && (openStep rs f).isNone

/-- Whether an answer to the review of `f` is accepted, and why not. -/
def accept (ds : List Row) (rs : List Rec) (f : Flag) (word : String) : Except String Verdict :=
  if !(pendingFlags ds).contains f then .error "no pending review for this flag"
  else if (recorded rs f).isSome then .error "this review is already decided"
  else if (openStep rs f).isNone then .error "the review step was closed without a decision; a new step is posted first"
  else match Verdict.ofWord word with
    | some v => .ok v
    | none => .error "the decision must be keep or reject"

/-- The title of the review step. -/
def title (f : Flag) : String := "Review the look change " ++ f.key

/-- The plain text of the review step. -/
def body (i : Item) : String :=
  Fw.Console.Alert.bodyLines audience
    s!"The look change {i.flag.key} was decided on {i.date} ({i.words})."
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
    f ∈ pendingFlags ds ↔ ∃ d ∈ ds, d.flag = f ∧ pending d = true := by
  simp only [pendingFlags, mem_dedup, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨d, ⟨h1, h2⟩, h3⟩; exact ⟨d, h1, h3, h2⟩
  · rintro ⟨d, h1, h3, h2⟩; exact ⟨d, ⟨h1, h2⟩, h3⟩

/-- The flags with a recorded decision stay decided when the record grows. -/
theorem recorded_append (rs ts : List Rec) (f : Flag) (v : Verdict) (h : recorded rs f = some v) :
    recorded (rs ++ ts) f = some v := by
  unfold recorded at *
  simp [List.filterMap_append, List.head?_append, h]

/-- Nothing recorded, nothing decided. -/
theorem recorded_nil (f : Flag) : recorded [] f = none := rfl

/-- A verdict word names its verdict. -/
theorem word_of_ofWord (w : String) (v : Verdict) (h : Verdict.ofWord w = some v) : w = v.word := by
  cases v <;> (unfold Verdict.ofWord at h; split at h <;> simp_all [Verdict.word])

/-- A decision is recorded only by a review step of the flag whose answer is the verdict word. -/
theorem closed_only_on_decision (rs : List Rec) (f : Flag) (v : Verdict) (h : recorded rs f = some v) :
    ∃ r ∈ rs, inFamily f r.id = true ∧ r.answer = some v.word := by
  unfold recorded at h
  have hm := List.mem_of_mem_head? (Option.mem_def.2 h)
  obtain ⟨r, hr, hv⟩ := List.mem_filterMap.1 hm
  by_cases hf : inFamily f r.id = true
  · simp only [hf, ite_true, Option.bind_eq_some_iff] at hv
    obtain ⟨a, ha, hw⟩ := hv
    exact ⟨r, hr, hf, by rw [ha, word_of_ofWord a v hw]⟩
  · simp [hf] at hv

/-- The items are the pending flags, in order. -/
theorem items_flags (ds : List Row) (rs : List Rec) : (items ds rs).map (·.flag) = pendingFlags ds := by
  simp [items, itemOf, List.map_map, Function.comp_def]

/-- An item exists for a flag exactly when a decision row of the flag is pending. -/
theorem item_iff_pending (ds : List Row) (rs : List Rec) (f : Flag) :
    (∃ i ∈ items ds rs, i.flag = f) ↔ ∃ d ∈ ds, d.flag = f ∧ pending d = true := by
  rw [← mem_pendingFlags, ← items_flags ds rs]; simp

/-- Every pending look decision yields exactly one item. -/
theorem one_item_per_pending (ds : List Row) (rs : List Rec) (f : Flag)
    (h : ∃ d ∈ ds, d.flag = f ∧ pending d = true) :
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

/-- An answer is accepted only for a pending, undecided flag with an open review step and a verdict word. -/
theorem accept_ok (ds : List Row) (rs : List Rec) (f : Flag) (w : String) (v : Verdict)
    (h : accept ds rs f w = .ok v) :
    f ∈ pendingFlags ds ∧ recorded rs f = none ∧ (openStep rs f).isSome = true ∧ Verdict.ofWord w = some v := by
  unfold accept at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  rename_i h1 h2 h3
  cases hw : Verdict.ofWord w with
  | none => simp [hw] at h
  | some u =>
    simp only [hw] at h
    have : u = v := by simpa using h
    subst this
    refine ⟨?_, ?_, ?_, rfl⟩
    · simpa using h1
    · cases hr : recorded rs f <;> simp_all
    · cases ho : openStep rs f <;> simp_all

/-- **An open item with an open step is always accepted for keep and for reject.** -/
theorem open_accepts (ds : List Row) (rs : List Rec) (f : Flag) (hp : f ∈ pendingFlags ds)
    (hr : recorded rs f = none) (ho : (openStep rs f).isSome = true) :
    accept ds rs f "keep" = .ok .keep ∧ accept ds rs f "reject" = .ok .reject := by
  have ho2 : (openStep rs f).isNone = false := by cases h : openStep rs f <;> simp_all
  simp [accept, hp, hr, ho2, Verdict.ofWord]

/-- **A review step closed without a verdict (done, cancelled or answered with no verdict word) refuses an answer.** -/
theorem closed_refused (ds : List Row) (rs : List Rec) (f : Flag) (w : String) (hr : recorded rs f = none)
    (ho : openStep rs f = none) (hp : f ∈ pendingFlags ds) : ∃ e, accept ds rs f w = .error e := by
  simp [accept, hp, hr, ho]

/-- Such an item needs a new step. -/
theorem closed_needs_post (rs : List Rec) (f : Flag) (hr : recorded rs f = none) (ho : openStep rs f = none) :
    needsPost rs f = true := by
  simp [needsPost, hr, ho]

/-- A step is posted again only for an undecided flag with no open step. -/
theorem needsPost_iff (rs : List Rec) (f : Flag) :
    needsPost rs f = true ↔ recorded rs f = none ∧ openStep rs f = none := by
  simp [needsPost]

/-- Every id `stepIdN` makes belongs to the family of the flag. -/
theorem inFamily_stepIdN (f : Flag) (k : Nat) : inFamily f (stepIdN f k) = true := by
  unfold stepIdN inFamily
  by_cases h : k = 0
  · simp [h]
  · simp [h, String.toList_append]

/-- The id of a new step belongs to the family of the flag. -/
theorem inFamily_freshId (rs : List Rec) (f : Flag) : inFamily f (freshId rs f) = true := by
  unfold freshId
  cases List.find? (fun k => !(rs.any (·.id == stepIdN f k))) (List.range (rs.length + 2)) <;>
    simp [inFamily_stepIdN]

/-- **After the new step is posted open, an item whose step was closed without a verdict accepts keep and reject.** -/
theorem repost_accepts (ds : List Row) (rs : List Rec) (f : Flag) (hp : f ∈ pendingFlags ds)
    (hr : recorded rs f = none) (ho : openStep rs f = none) :
    accept ds (rs ++ [⟨freshId rs f, none, true⟩]) f "keep" = .ok .keep ∧
    accept ds (rs ++ [⟨freshId rs f, none, true⟩]) f "reject" = .ok .reject := by
  have hr' : recorded (rs ++ [⟨freshId rs f, none, true⟩]) f = none := by
    unfold recorded at *
    rw [List.head?_eq_none_iff] at hr
    simp [List.filterMap_append, hr]
  have ho' : (openStep (rs ++ [⟨freshId rs f, none, true⟩]) f).isSome = true := by
    unfold openStep at *
    rw [List.find?_append, ho]
    simp [inFamily_freshId]
  exact open_accepts ds _ f hp hr' ho'

/-- Every undecided pending item is either decidable now (keep and reject accepted) or gets a new step first. -/
theorem undecided_actionable (ds : List Row) (rs : List Rec) (f : Flag) (hp : f ∈ pendingFlags ds)
    (hr : recorded rs f = none) :
    (accept ds rs f "keep" = .ok .keep ∧ accept ds rs f "reject" = .ok .reject) ∨ needsPost rs f = true := by
  cases ho : openStep rs f with
  | none => exact .inr (closed_needs_post rs f hr ho)
  | some r => exact .inl (open_accepts ds rs f hp hr (by simp [ho]))

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

private def ex : Row :=
  { flag := ⟨"nav", "e"⟩, date := "d", decision := .kept, review := .pending }
private def exDone : Row := { ex with review := .done }

#guard pending ex
#guard !pending exDone
#guard (items [ex] []).length == 1
#guard (items [exDone] []).length == 0
#guard (openItems [ex] [⟨"review-nav:e", some "keep", false⟩]).length == 0
#guard (openItems [ex] [⟨"review-nav:e", none, true⟩]).length == 1
-- started, then done with no answer: open item, a new step review-nav:e#1 is to be posted
#guard needsPost [⟨"review-nav:e", none, false⟩] ⟨"nav", "e"⟩
#guard freshId [⟨"review-nav:e", none, false⟩] ⟨"nav", "e"⟩ == "review-nav:e#1"
#guard freshId [⟨"review-nav:e", none, false⟩, ⟨"review-nav:e#1", none, false⟩] ⟨"nav", "e"⟩ == "review-nav:e#2"
#guard !needsPost [⟨"review-nav:e", none, false⟩, ⟨"review-nav:e#1", none, true⟩] ⟨"nav", "e"⟩
#guard (recorded [⟨"review-nav:e", none, false⟩, ⟨"review-nav:e#1", some "reject", false⟩] ⟨"nav", "e"⟩) == some .reject
-- a flag whose key is a prefix of another is not confused with it
#guard !inFamily ⟨"nav", "e"⟩ "review-nav:e-x"

end Fw.Console.Review
