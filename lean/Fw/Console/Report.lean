import Fw.Console.Review
import Fw.Console.ReviewFeedback
/-!
# Experiment reports in the Reviews tab

A report is what an experiment hands the owner: a proposal, its arms (the page searches that reproduce them), per-lane metric
rows with one value per arm, per-layer pixel verdicts, a link to the frame strips and a recommendation. The owner answers
approve, hold or reject, with an optional comment that reaches the lead as `review.feedback` on the topic `report:<id>`.

This module decides two things and holds the proofs:
* whether a report is shown: every number carries a tag, MEASURED with the CI run id it came from or INFERRED with its reason;
  a report with one number lacking a tag is refused, with the place and the reason (`refusal`);
* whether an answer is accepted and what it writes (`accept`): the step answer, and the comment as feedback on `report:<id>`.

Accepted limits: a report links to CI artifacts, which expire (GitHub retention); no image is hosted by the console; a report is
never edited (a corrected report is a new id).
-/
namespace Fw.Console.Report
open Fw.Console.Review (Rec)

/-! ## The report -/

/-- Where a number comes from: a CI run (`measured`, the run id) or an argument (`inferred`, its reason). -/
inductive Tag
  | measured (run : String)
  | inferred (why : String)
deriving DecidableEq, Repr

/-- One arm: its name and the search that opens it (`""` or `?fw=...`). -/
structure Arm where
  name   : String
  search : String
deriving DecidableEq, Repr

/-- One number of one arm, as text, with its tag (`none` = untagged). -/
structure Cell where
  arm   : String
  value : String
  tag   : Option Tag
deriving DecidableEq, Repr

/-- One metric of a lane: its name, unit and a cell per arm. -/
structure Row where
  metric : String
  unit   : String
  cells  : List Cell
deriving DecidableEq, Repr

/-- The pixel verdict of one layer (`E`, `Q` or `L`) with its tag. -/
structure LayerVerdict where
  layer   : String
  verdict : String
  tag     : Option Tag
deriving DecidableEq, Repr

/-- One lane (engine and width): its metric rows and its layer verdicts. -/
structure Lane where
  name   : String
  rows   : List Row
  layers : List LayerVerdict
deriving DecidableEq, Repr

/-- The recommendation: one of `adopt`, `hold`, `drop`, and the reason. -/
structure Recommendation where
  word : String
  why  : String
deriving DecidableEq, Repr

/-- A report. `strips` is an optional https link to the frame-strip artifact. -/
structure Report where
  id             : String
  proposal       : String
  title          : String
  arms           : List Arm
  lanes          : List Lane
  strips         : Option String
  recommendation : Recommendation
deriving DecidableEq, Repr

/-! ## What a report is refused for -/

/-- Only white space. -/
def blank (s : String) : Bool := s.toList.all Char.isWhitespace

/-- A CI run id: digits only, at least one. -/
def isRun (s : String) : Bool := !s.isEmpty && s.toList.all Char.isDigit

/-- The characters of a number after an optional leading minus. -/
def unsigned (s : String) : List Char := if s.startsWith "-" then s.toList.drop 1 else s.toList

/-- A decimal number as text: digits with at most one point, a digit first and last. -/
def isNumber (s : String) : Bool :=
  let cs := unsigned s
  (match cs.head?, cs.getLast? with
    | some a, some b => a.isDigit && b.isDigit
    | _, _ => false) &&
  cs.all (fun c => c.isDigit || c == '.') && (cs.filter (· == '.')).length ≤ 1

/-- Why a tag is refused (`none` = accepted). Each branch has its own reason. -/
def tagRefusal : Option Tag → Option String
  | none => some "the number has no MEASURED run id or INFERRED tag"
  | some (.measured run) => if isRun run then none else some "MEASURED needs a CI run id (digits only)"
  | some (.inferred why) => if blank why then some "INFERRED needs its reason" else none

/-- Why a cell is refused: its arm is not one of the report's arms, its value is no number, or its tag is refused. -/
def cellRefusal (arms : List Arm) (c : Cell) : Option String :=
  if !arms.any (·.name == c.arm) then some s!"arm {c.arm} is not an arm of the report"
  else if !isNumber c.value then some s!"arm {c.arm}: {c.value} is not a number"
  else (tagRefusal c.tag).map (s!"arm {c.arm}: " ++ ·)

/-- Why a row is refused: no name, no cell, or one cell refused. -/
def rowRefusal (arms : List Arm) (r : Row) : Option String :=
  (if r.metric.isEmpty then some "a metric has no name"
   else if r.cells.isEmpty then some s!"{r.metric} has no cell"
   else none).orElse fun _ =>
    (r.cells.findSome? (cellRefusal arms)).map (s!"{r.metric}, " ++ ·)

/-- Why a layer verdict is refused: the letter is not E, Q or L, or its tag is refused. -/
def layerRefusal (l : LayerVerdict) : Option String :=
  if !(l.verdict == "E" || l.verdict == "Q" || l.verdict == "L") then some s!"layer {l.layer}: the verdict is E, Q or L"
  else (tagRefusal l.tag).map (s!"layer {l.layer}: " ++ ·)

/-- Why a lane is refused: no name, no row, or a row or layer verdict refused (rows first). -/
def laneRefusal (arms : List Arm) (l : Lane) : Option String :=
  (if l.name.isEmpty then some "a lane has no name"
   else if l.rows.isEmpty then some s!"lane {l.name} has no metric row"
   else none).orElse fun _ =>
    ((l.rows.findSome? (rowRefusal arms)).orElse fun _ => l.layers.findSome? layerRefusal).map (s!"lane {l.name}, " ++ ·)

/-- A report id: lower-case letters, digits and dashes, at most 60 (it is part of a step id and of the topic `report:<id>`). -/
def idOk (s : String) : Bool := !s.isEmpty && s.length ≤ 60 && s.toList.all fun c => c.isLower || c.isDigit || c == '-'

/-- A search of an arm: empty, or a query string. -/
def searchOk (s : String) : Bool := s.isEmpty || s.startsWith "?"

/-- The recommendation words. -/
def recWords : List String := ["adopt", "hold", "drop"]

/-- The checks of a report, in the order of the reasons given. A `none` entry passes. -/
def checks (r : Report) : List (Option String) :=
  [ if idOk r.id then none else some "the id is lower-case letters, digits and dashes (at most 60)",
    if r.proposal.isEmpty then some "the proposal is empty" else none,
    if r.title.isEmpty then some "the title is empty" else none,
    if r.arms.length < 2 then some "a report compares at least two arms" else none,
    if 4 < r.arms.length then some "a report has at most four arms" else none,
    if (r.arms.map (·.name)).any (·.isEmpty) then some "an arm has no name" else none,
    if (r.arms.map (·.name)).eraseDups.length != r.arms.length then some "two arms have one name" else none,
    if r.arms.all (searchOk ·.search) then none else some "an arm search is empty or starts with ?",
    if r.lanes.isEmpty then some "a report has no lane" else none,
    r.lanes.findSome? (laneRefusal r.arms),
    match r.strips with
    | some u => if u.startsWith "https://" && !u.any Char.isWhitespace then none else some "the strips link is an https URL"
    | none => none,
    if recWords.contains r.recommendation.word then none else some "the recommendation is adopt, hold or drop",
    if blank r.recommendation.why then some "the recommendation has no reason" else none ]

/-- Why a report is refused (`none` = shown): the first failing check. -/
def refusal (r : Report) : Option String := (checks r).findSome? id

/-! ## Theorems about the refusal -/

/-- A tag is accepted only as a MEASURED run id or an INFERRED reason. -/
theorem tag_ok_iff (t : Option Tag) : tagRefusal t = none ↔
    (∃ run, t = some (.measured run) ∧ isRun run = true) ∨ (∃ why, t = some (.inferred why) ∧ blank why = false) := by
  cases t with
  | none => simp [tagRefusal]
  | some t => cases t <;> simp [tagRefusal]

/-- No tag: refused. -/
theorem untagged_refused : tagRefusal none ≠ none := by simp [tagRefusal]

/-- MEASURED without a run id (empty, or not digits): refused. -/
theorem measured_without_run_refused (run : String) (h : isRun run = false) : tagRefusal (some (.measured run)) ≠ none := by
  simp [tagRefusal, h]

/-- INFERRED without a reason: refused. -/
theorem inferred_without_why_refused (why : String) (h : blank why = true) : tagRefusal (some (.inferred why)) ≠ none := by
  simp [tagRefusal, h]

/-- MEASURED with a run id: accepted. -/
theorem measured_with_run_ok (run : String) (h : isRun run = true) : tagRefusal (some (.measured run)) = none := by
  simp [tagRefusal, h]

/-- INFERRED with a reason: accepted. -/
theorem inferred_with_why_ok (why : String) (h : blank why = false) : tagRefusal (some (.inferred why)) = none := by
  simp [tagRefusal, h]

/-- A cell of an arm the report does not have is refused. -/
theorem cell_unknown_arm_refused (arms : List Arm) (c : Cell) (h : arms.any (·.name == c.arm) = false) :
    cellRefusal arms c ≠ none := by
  simp [cellRefusal, h]

/-- A cell whose value is no number is refused. -/
theorem cell_not_number_refused (arms : List Arm) (c : Cell) (h : isNumber c.value = false) :
    cellRefusal arms c ≠ none := by
  unfold cellRefusal
  split <;> simp [h]

/-- A cell with a refused tag is refused. -/
theorem cell_tag_refused (arms : List Arm) (c : Cell) (h : tagRefusal c.tag ≠ none) :
    cellRefusal arms c ≠ none := by
  unfold cellRefusal
  split
  · simp
  split
  · simp
  · cases ht : tagRefusal c.tag with
    | none => exact absurd ht h
    | some _ => simp

/-- A cell is accepted only if its arm exists, its value is a number and its tag is accepted. -/
theorem cell_ok (arms : List Arm) (c : Cell) (h : cellRefusal arms c = none) :
    arms.any (·.name == c.arm) = true ∧ isNumber c.value = true ∧ tagRefusal c.tag = none := by
  unfold cellRefusal at h
  split at h
  · cases h
  split at h
  · cases h
  rename_i h1 h2
  refine ⟨by simpa using h1, by simpa using h2, ?_⟩
  cases ht : tagRefusal c.tag with
  | none => rfl
  | some _ => simp [ht] at h

/-- A layer verdict with a refused tag is refused. -/
theorem layer_tag_refused (l : LayerVerdict) (h : tagRefusal l.tag ≠ none) : layerRefusal l ≠ none := by
  unfold layerRefusal
  split
  · simp
  · cases ht : tagRefusal l.tag with
    | none => exact absurd ht h
    | some _ => simp

/-- A layer verdict letter other than E, Q, L is refused. -/
theorem layer_letter_refused (l : LayerVerdict) (h : (l.verdict == "E" || l.verdict == "Q" || l.verdict == "L") = false) :
    layerRefusal l ≠ none := by
  simp [layerRefusal, h]

/-- A layer verdict is accepted only with its letter in E, Q, L and an accepted tag. -/
theorem layer_ok (l : LayerVerdict) (h : layerRefusal l = none) :
    (l.verdict == "E" || l.verdict == "Q" || l.verdict == "L") = true ∧ tagRefusal l.tag = none := by
  unfold layerRefusal at h
  split at h
  · cases h
  rename_i h1
  refine ⟨?_, ?_⟩
  · cases hv : (l.verdict == "E" || l.verdict == "Q" || l.verdict == "L") <;> simp_all
  cases ht : tagRefusal l.tag with
  | none => rfl
  | some _ => simp [ht] at h

private theorem orElse_none {a b : Option String} (h : a.orElse (fun _ => b) = none) : a = none ∧ b = none := by
  cases a <;> simp_all [Option.orElse]

/-- A row is accepted only if each of its cells is. -/
theorem row_ok (arms : List Arm) (r : Row) (h : rowRefusal arms r = none) : ∀ c ∈ r.cells, cellRefusal arms c = none := by
  unfold rowRefusal at h
  have h' := orElse_none (a := if r.metric.isEmpty then some "a metric has no name"
     else if r.cells.isEmpty then some s!"{r.metric} has no cell" else none)
    (b := (r.cells.findSome? (cellRefusal arms)).map (s!"{r.metric}, " ++ ·)) h
  have h2 := h'.2
  simp only [Option.map_eq_none_iff] at h2
  exact List.findSome?_eq_none_iff.mp h2

/-- A lane is accepted only if each of its rows is, and each of its layer verdicts. -/
theorem lane_ok (arms : List Arm) (l : Lane) (h : laneRefusal arms l = none) :
    (∀ r ∈ l.rows, rowRefusal arms r = none) ∧ (∀ v ∈ l.layers, layerRefusal v = none) := by
  unfold laneRefusal at h
  have h' := orElse_none (a := if l.name.isEmpty then some "a lane has no name"
     else if l.rows.isEmpty then some s!"lane {l.name} has no metric row" else none)
    (b := ((l.rows.findSome? (rowRefusal arms)).orElse fun _ => l.layers.findSome? layerRefusal).map (s!"lane {l.name}, " ++ ·)) h
  have h2 := h'.2
  simp only [Option.map_eq_none_iff] at h2
  have h3 := orElse_none h2
  exact ⟨List.findSome?_eq_none_iff.mp h3.1, List.findSome?_eq_none_iff.mp h3.2⟩

/-- A shown report: every number of every row of every lane has an arm of the report, is a number and carries an accepted tag. -/
theorem shown_numbers_tagged (r : Report) (h : refusal r = none) :
    ∀ l ∈ r.lanes, ∀ row ∈ l.rows, ∀ c ∈ row.cells,
      r.arms.any (·.name == c.arm) = true ∧ isNumber c.value = true ∧ tagRefusal c.tag = none := by
  intro l hl row hr c hc
  have hall := List.findSome?_eq_none_iff.mp h
  have hlane : r.lanes.findSome? (laneRefusal r.arms) = none := by
    have := hall (r.lanes.findSome? (laneRefusal r.arms)) (by simp [checks])
    simpa using this
  have h1 := List.findSome?_eq_none_iff.mp hlane l hl
  exact cell_ok _ c (row_ok _ row ((lane_ok _ l h1).1 row hr) c hc)

/-- A shown report: every layer verdict carries an accepted tag and one of the letters E, Q, L. -/
theorem shown_layers_tagged (r : Report) (h : refusal r = none) :
    ∀ l ∈ r.lanes, ∀ v ∈ l.layers,
      (v.verdict == "E" || v.verdict == "Q" || v.verdict == "L") = true ∧ tagRefusal v.tag = none := by
  intro l hl v hv
  have hall := List.findSome?_eq_none_iff.mp h
  have hlane : r.lanes.findSome? (laneRefusal r.arms) = none := by
    have := hall (r.lanes.findSome? (laneRefusal r.arms)) (by simp [checks])
    simpa using this
  have h1 := List.findSome?_eq_none_iff.mp hlane l hl
  exact layer_ok v ((lane_ok _ l h1).2 v hv)

/-- A report with one untagged number is refused. -/
theorem untagged_number_refused (r : Report) (l : Lane) (hl : l ∈ r.lanes) (row : Row) (hr : row ∈ l.rows)
    (c : Cell) (hc : c ∈ row.cells) (ht : c.tag = none) : refusal r ≠ none := by
  intro h
  have := (shown_numbers_tagged r h l hl row hr c hc).2.2
  rw [ht] at this
  exact untagged_refused this

/-- A report with one untagged layer verdict is refused. -/
theorem untagged_layer_refused (r : Report) (l : Lane) (hl : l ∈ r.lanes) (v : LayerVerdict) (hv : v ∈ l.layers)
    (ht : v.tag = none) : refusal r ≠ none := by
  intro h
  have := (shown_layers_tagged r h l hl v hv).2
  rw [ht] at this
  exact untagged_refused this

/-- A report with a MEASURED number without a run id is refused. -/
theorem measured_without_run_report_refused (r : Report) (l : Lane) (hl : l ∈ r.lanes) (row : Row) (hr : row ∈ l.rows)
    (c : Cell) (hc : c ∈ row.cells) (run : String) (ht : c.tag = some (.measured run)) (hn : isRun run = false) :
    refusal r ≠ none := by
  intro h
  have := (shown_numbers_tagged r h l hl row hr c hc).2.2
  rw [ht] at this
  exact measured_without_run_refused run hn this

/-- A report with an INFERRED number without a reason is refused. -/
theorem inferred_without_why_report_refused (r : Report) (l : Lane) (hl : l ∈ r.lanes) (row : Row) (hr : row ∈ l.rows)
    (c : Cell) (hc : c ∈ row.cells) (why : String) (ht : c.tag = some (.inferred why)) (hn : blank why = true) :
    refusal r ≠ none := by
  intro h
  have := (shown_numbers_tagged r h l hl row hr c hc).2.2
  rw [ht] at this
  exact inferred_without_why_refused why hn this

/-- A report with a value that is no number is refused. -/
theorem not_a_number_report_refused (r : Report) (l : Lane) (hl : l ∈ r.lanes) (row : Row) (hr : row ∈ l.rows)
    (c : Cell) (hc : c ∈ row.cells) (hn : isNumber c.value = false) : refusal r ≠ none := by
  intro h
  have := (shown_numbers_tagged r h l hl row hr c hc).2.1
  rw [hn] at this
  cases this

/-- A shown report compares at least two arms. -/
theorem shown_has_two_arms (r : Report) (h : refusal r = none) : 2 ≤ r.arms.length := by
  have hall := List.findSome?_eq_none_iff.mp h
  have := hall (if r.arms.length < 2 then some "a report compares at least two arms" else none) (by simp [checks])
  by_cases hl : r.arms.length < 2
  · simp [hl] at this
  · omega

/-- A shown report recommends adopt, hold or drop. -/
theorem shown_recommendation (r : Report) (h : refusal r = none) : r.recommendation.word ∈ recWords := by
  have hall := List.findSome?_eq_none_iff.mp h
  have := hall (if recWords.contains r.recommendation.word then none else some "the recommendation is adopt, hold or drop")
    (by simp [checks])
  by_cases hl : recWords.contains r.recommendation.word = true
  · simpa using hl
  · simp at this
    exact this

/-- A shown report has a usable id. -/
theorem shown_id (r : Report) (h : refusal r = none) : idOk r.id = true := by
  have hall := List.findSome?_eq_none_iff.mp h
  have := hall (if idOk r.id then none else some "the id is lower-case letters, digits and dashes (at most 60)")
    (by simp [checks])
  by_cases hl : idOk r.id = true
  · exact hl
  · simp [hl] at this

/-! ## The answer -/

/-- The owner's answer to a report. -/
inductive Answer | approve | hold | reject
deriving DecidableEq, Repr

/-- The word of an answer (the step option and the request body). -/
def Answer.word : Answer → String
  | .approve => "approve"
  | .hold => "hold"
  | .reject => "reject"

/-- The answer a word names. -/
def Answer.ofWord : String → Option Answer
  | "approve" => some .approve
  | "hold" => some .hold
  | "reject" => some .reject
  | _ => none

/-- The three words, in the order of the step options. -/
def options : List String := [Answer.approve.word, Answer.hold.word, Answer.reject.word]

/-- A word names an answer exactly when it is the answer's word. -/
theorem ofWord_word (a : Answer) : Answer.ofWord a.word = some a := by cases a <;> rfl

/-- The step of a report. -/
def stepId (id : String) : String := "report-" ++ id

/-- The feedback topic of a report (the `flag` of `review.feedback`). -/
def topic (id : String) : String := "report:" ++ id

/-- The feedback topic of a report is `report:` followed by its id. -/
theorem topic_prefix (id : String) : topic id = "report:" ++ id := rfl

/-- Where a report stands on the board. -/
inductive State
  | unposted
  | open
  | decided (a : Answer)
  | closed
deriving DecidableEq, Repr

/-- The state of a report from the board steps: no step (unposted); a step with an answer word (decided); an open step; a step
closed without an answer (closed). -/
def stateOf (rs : List Rec) (id : String) : State :=
  match rs.find? (·.id == stepId id) with
  | none => .unposted
  | some r => match r.answer.bind Answer.ofWord with
    | some a => .decided a
    | none => if r.isOpen then .open else .closed

/-- The state word shown to the page. -/
def State.word : State → String
  | .unposted => "unposted"
  | .open => "open"
  | .decided a => a.word
  | .closed => "closed"

/-- Whether the step of a report is still to be posted. -/
def needsPost (rs : List Rec) (id : String) : Bool := stateOf rs id == .unposted

/-- What an accepted answer writes: the step answer and, for a comment, the feedback `(topic, text)`. -/
structure Plan where
  step     : String
  answer   : Answer
  feedback : Option (String × String)
deriving DecidableEq, Repr

/-- Whether an answer to the report `id` is accepted, and why not. A blank comment writes no feedback; a longer comment than the
feedback cap is refused. -/
def accept (rs : List Rec) (id word comment : String) : Except String Plan :=
  match stateOf rs id with
  | .unposted => .error "this report is not posted"
  | .decided _ => .error "this report is already answered"
  | .closed => .error "the report step was closed without an answer; post the report again under a new id"
  | .open => match Answer.ofWord word with
    | none => .error "the answer must be approve, hold or reject"
    | some a =>
      if blank comment then .ok { step := stepId id, answer := a, feedback := none }
      else match Fw.Console.ReviewFeedback.textRefusal comment with
        | some e => .error e
        | none => .ok { step := stepId id, answer := a, feedback := some (topic id, comment) }

/-- An answer is refused unless the step is open. -/
theorem accept_needs_open (rs : List Rec) (id word comment : String) (p : Plan) (h : accept rs id word comment = .ok p) :
    stateOf rs id = .open := by
  unfold accept at h
  cases hs : stateOf rs id <;> simp_all

/-- An answered report is refused (the first answer stays). -/
theorem decided_refused (rs : List Rec) (id word comment : String) (a : Answer) (h : stateOf rs id = .decided a) :
    ∃ e, accept rs id word comment = .error e := by
  simp [accept, h]

/-- An unposted report is refused. -/
theorem unposted_refused (rs : List Rec) (id word comment : String) (h : stateOf rs id = .unposted) :
    ∃ e, accept rs id word comment = .error e := by
  simp [accept, h]

/-- A step closed without an answer is refused. -/
theorem closed_refused (rs : List Rec) (id word comment : String) (h : stateOf rs id = .closed) :
    ∃ e, accept rs id word comment = .error e := by
  simp [accept, h]

/-- A word that is not approve, hold or reject is refused. -/
theorem unknown_word_refused (rs : List Rec) (id word comment : String) (h : stateOf rs id = .open)
    (hw : Answer.ofWord word = none) : ∃ e, accept rs id word comment = .error e := by
  simp [accept, h, hw]

/-- An open report accepts each of the three words, with no comment. -/
theorem open_accepts (rs : List Rec) (id : String) (a : Answer) (h : stateOf rs id = .open) :
    accept rs id a.word "" = .ok { step := stepId id, answer := a, feedback := none } := by
  have hb : blank "" = true := by decide
  simp [accept, h, ofWord_word, hb]

/-- A comment on an open report is written as feedback on `report:<id>`, with the comment as it is. -/
theorem comment_is_feedback (rs : List Rec) (id word comment : String) (p : Plan)
    (h : accept rs id word comment = .ok p) (hc : blank comment = false) :
    p.feedback = some (topic id, comment) := by
  unfold accept at h
  cases hs : stateOf rs id <;> simp [hs] at h
  cases hw : Answer.ofWord word <;> simp [hw, hc] at h
  cases hr : Fw.Console.ReviewFeedback.textRefusal comment <;> simp [hr] at h
  subst h
  rfl

/-- A blank comment writes no feedback. -/
theorem blank_comment_no_feedback (rs : List Rec) (id word comment : String) (p : Plan)
    (h : accept rs id word comment = .ok p) (hc : blank comment = true) : p.feedback = none := by
  unfold accept at h
  cases hs : stateOf rs id <;> simp [hs] at h
  cases hw : Answer.ofWord word <;> simp [hw, hc] at h
  subst h
  rfl

/-- A comment the feedback thread would refuse (too long) refuses the answer too, so no answer is recorded without its comment. -/
theorem long_comment_refused (rs : List Rec) (id word comment : String) (e : String) (h : stateOf rs id = .open)
    (hw : (Answer.ofWord word).isSome = true) (hc : blank comment = false)
    (hr : Fw.Console.ReviewFeedback.textRefusal comment = some e) : accept rs id word comment = .error e := by
  cases hw' : Answer.ofWord word with
  | none => simp [hw'] at hw
  | some a => simp [accept, h, hw', hc, hr]

/-- The step an accepted answer writes to is the report's own step. -/
theorem accept_step (rs : List Rec) (id word comment : String) (p : Plan) (h : accept rs id word comment = .ok p) :
    p.step = stepId id := by
  unfold accept at h
  cases hs : stateOf rs id <;> simp [hs] at h
  cases hw : Answer.ofWord word <;> simp [hw] at h
  split at h
  · cases h; rfl
  · cases hr : Fw.Console.ReviewFeedback.textRefusal comment <;> simp [hr] at h
    subst h; rfl

/-- A decided report stays decided when more steps are appended to the board. -/
theorem decided_stays (rs ts : List Rec) (id : String) (a : Answer) (h : stateOf rs id = .decided a) :
    stateOf (rs ++ ts) id = .decided a := by
  unfold stateOf at h ⊢
  cases hf : rs.find? (·.id == stepId id) with
  | none => simp [hf] at h
  | some r => simp [List.find?_append, hf] at h ⊢; exact h

/-! ## The item the page shows -/

/-- The title of the report step. -/
def title (r : Report) : String := "Review the report " ++ r.id

/-- The plain text of the report step. -/
def body (r : Report) : String :=
  Fw.Console.Alert.bodyLines Fw.Console.Review.audience
    s!"The experiment report {r.id} on {r.proposal} is ready: {r.title}."
    s!"Nothing is blocked. The recommendation is {r.recommendation.word}: {r.recommendation.why}"
    "Open the Reports section of the Reviews tab, read the arms side by side, then answer approve, hold or reject (a comment reaches the lead)."
    s!"report {r.id}; step {stepId r.id}; feedback topic {topic r.id}"

end Fw.Console.Report
