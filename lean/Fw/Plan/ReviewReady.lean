/-!
# `plan.reviewReady` and `plan.reviewVerdict`: may a build be reviewed, and may a review accept?

Task `review-flow-v2`. Two pure decisions that the workflows `build-review` and `fable-refusals` used to leave to prose.

* `reviewReady` reads the build report: the `items` (one per deliverable and per prior finding, each with a status and
  evidence), the states of the `runs` the items name, and the `VERDICT` line of `fw land --dry`. It answers `review`
  (spend an Opus review), `dispatch` (the lead must start a run first), `wait` (a named run is still going) or
  `returnToBuilder` (the report is incomplete or wrong). The answers are ranked: a builder fault hides a missing
  dispatch, a missing dispatch hides a wait.
* `verdictOf` reads the severities of a review's findings (`blocker`, `fix-before-land`, `follow-up`) and accepts iff there
  is no blocker. `strictVerdict` is the interim rule until the medium-only refusals are audited: it also refuses on any
  `fix-before-land`. An unknown severity word counts as a blocker.

Coverage of the pinned unit (does the item list name every deliverable and every prior finding?) is not decided here:
it is the reviewer's check. `reviewReady` only checks that the list is non-empty and that each item is well-formed.
-/
namespace Fw.Plan.ReviewReady

/-- What a build report may do next.

The gate answer: review, dispatch a run, wait for a run, or send the report back.
-/
inductive Ready where
  | review | dispatch | wait | returnToBuilder
deriving Repr, DecidableEq

/-- The wire name of a gate answer.

How the answer is spelled in JSON and on the `VERDICT` line.
-/
def Ready.name : Ready → String
  | .review => "review" | .dispatch => "dispatch" | .wait => "wait" | .returnToBuilder => "returnToBuilder"

/-- The status of one report item.

`done` (evidence in the report), `pending` (evidence names a run id), `dispatch` (a run the lead must start; the evidence
is the command), `followUp` (outside the pinned unit), `undelivered` (a unit item not delivered), `unknown` (any other word).
-/
inductive Status where
  | done | pending | dispatch | followUp | undelivered | unknown
deriving Repr, DecidableEq

/-- The status a word names.

`unknown` for a word that is none of the five.
-/
def Status.ofString : String → Status
  | "done" => .done | "pending" => .pending | "dispatch" => .dispatch
  | "followUp" => .followUp | "undelivered" => .undelivered | _ => .unknown

/-- One report item: the deliverable or prior finding it answers, its status word and its evidence text.

What the builder hands back for each unit item.
-/
structure Item where
  id : String
  status : String
  evidence : String
deriving Repr, DecidableEq

/-- A run the report names, with its state (`running`, `complete`, `failed`).

The gate agent reads it by run id with `fw ci state <id>` and replaces the builder's state field.
-/
structure Run where
  id : String
  state : String
deriving Repr, DecidableEq

/-- A token separator: whitespace, `,` or `;`.

The characters that split an evidence text into tokens.
-/
def isSep (c : Char) : Bool := c.isWhitespace || c == ',' || c == ';'

/-- The tokens of an evidence text.

Its non-empty runs between separators.
-/
def tokens (s : String) : List (List Char) := (s.toList.splitOnP isSep).filter (!·.isEmpty)

def isHex (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'f')

/-- The run id a token names: `run:<digits>` gives the digits, `cm:<24 hex>` keeps its `cm:` prefix. -/
def runIdOf : List Char → Option String
  | 'r' :: 'u' :: 'n' :: ':' :: d => if !d.isEmpty && d.all Char.isDigit then some (String.ofList d) else none
  | 'c' :: 'm' :: ':' :: d => if d.length == 24 && d.all isHex then some (String.ofList ('c' :: 'm' :: ':' :: d)) else none
  | _ => none

/-- Is the token `path:line` or `path:line-line`?

A path with a `.`, a colon, then digits with an optional `-` range.
-/
def isFileLine (t : List Char) : Bool :=
  let r := t.reverse
  let suf := r.takeWhile (· != ':')
  match r.dropWhile (· != ':') with
  | ':' :: path =>
    !suf.isEmpty && suf.all (fun c => c.isDigit || c == '-') && suf.getLast?.any Char.isDigit
      && path.any (· == '.')
  | _ => false

/-- Does the evidence cite a file line or a run id?

The test a `done` item must pass.
-/
def hasEvidence (s : String) : Bool := (tokens s).any fun t => isFileLine t || (runIdOf t).isSome

/-- The first run id the evidence names.

The run a `pending` item waits for.
-/
def firstRun (s : String) : Option String := ((tokens s).filterMap runIdOf).head?

/-- The gate answer of one item against the known runs.

`done` needs evidence; `pending` needs a known run that is running (`wait`) or complete (`review`); `dispatch` needs a
non-blank command; `followUp` never blocks; everything else goes back to the builder.
-/
def itemGate (runs : List Run) (i : Item) : Ready :=
  match Status.ofString i.status with
  | .done => if hasEvidence i.evidence then .review else .returnToBuilder
  | .followUp => .review
  | .dispatch => if i.evidence.toList.all Char.isWhitespace then .returnToBuilder else .dispatch
  | .pending =>
    match firstRun i.evidence with
    | none => .returnToBuilder
    | some r =>
      match runs.find? (·.id == r) with
      | none => .returnToBuilder
      | some run => if run.state == "running" then .wait else if run.state == "complete" then .review else .returnToBuilder
  | .undelivered | .unknown => .returnToBuilder

/-- Is the `fw land --dry` line a passing one for this task?

The line is exactly `VERDICT dry <task>`, so a line from another task or a bare prefix fails.
-/
def dryOk (task dry : String) : Bool := dry == "VERDICT dry " ++ task

/-- Is the report itself at fault?

The dry line is not a pass, the report has no item, or an item goes back to the builder.
-/
def fault (task : String) (items : List Item) (runs : List Run) (dry : String) : Bool :=
  !dryOk task dry || items.isEmpty || items.any fun i => itemGate runs i == .returnToBuilder

/-- The gate: `returnToBuilder` on a fault, else `dispatch` if an item needs one, else `wait` if an item waits, else `review`.

Whether a build report earns an Opus review.
-/
def reviewReady (task : String) (items : List Item) (runs : List Run) (dry : String) : Ready :=
  if fault task items runs dry then .returnToBuilder
  else if items.any fun i => itemGate runs i == .dispatch then .dispatch
  else if items.any fun i => itemGate runs i == .wait then .wait
  else .review

/-- The fault test as a statement: the dry line is not a pass, no item is listed, or an item goes back.

The `Prop` form of `fault`.
-/
theorem fault_iff (task items runs dry) :
    fault task items runs dry = true ↔
      (dryOk task dry = false ∨ items = [] ∨ ∃ i ∈ items, itemGate runs i = .returnToBuilder) := by
  simp [fault, List.any_eq_true, List.isEmpty_iff, or_assoc]

/-- Branch `returnToBuilder`: exactly when the dry line is not a pass, no item is listed, or an item goes back.

A faulty report is sent back, whatever else it holds.
-/
theorem reviewReady_returnToBuilder_iff (task items runs dry) :
    reviewReady task items runs dry = .returnToBuilder ↔
      (dryOk task dry = false ∨ items = [] ∨ ∃ i ∈ items, itemGate runs i = .returnToBuilder) := by
  rw [← fault_iff]; unfold reviewReady
  by_cases hf : fault task items runs dry = true <;> by_cases hd : (items.any fun i => itemGate runs i == .dispatch) = true <;>
    by_cases hw : (items.any fun i => itemGate runs i == .wait) = true <;> simp [hf, hd, hw]

/-- Branch `dispatch`: a sound report with an item that needs a dispatched run.

Only a report with no fault asks the lead to dispatch.
-/
theorem reviewReady_dispatch_iff (task items runs dry) :
    reviewReady task items runs dry = .dispatch ↔
      (¬ fault task items runs dry = true ∧ ∃ i ∈ items, itemGate runs i = .dispatch) := by
  have hD : (∃ i ∈ items, itemGate runs i = .dispatch) ↔ (items.any fun i => itemGate runs i == .dispatch) = true := by
    simp [List.any_eq_true]
  unfold reviewReady
  by_cases hf : fault task items runs dry = true <;> by_cases hd : (items.any fun i => itemGate runs i == .dispatch) = true <;>
    by_cases hw : (items.any fun i => itemGate runs i == .wait) = true <;> simp [hf, hd, hw, hD]

/-- Branch `wait`: a sound report, no dispatch needed, an item names a running run.

Only a report with no fault and no missing dispatch waits.
-/
theorem reviewReady_wait_iff (task items runs dry) :
    reviewReady task items runs dry = .wait ↔
      (¬ fault task items runs dry = true ∧ (∀ i ∈ items, itemGate runs i ≠ .dispatch) ∧
        ∃ i ∈ items, itemGate runs i = .wait) := by
  have hD : (∃ i ∈ items, itemGate runs i = .dispatch) ↔ (items.any fun i => itemGate runs i == .dispatch) = true := by
    simp [List.any_eq_true]
  have hW : (∃ i ∈ items, itemGate runs i = .wait) ↔ (items.any fun i => itemGate runs i == .wait) = true := by
    simp [List.any_eq_true]
  unfold reviewReady
  by_cases hf : fault task items runs dry = true <;> by_cases hd : (items.any fun i => itemGate runs i == .dispatch) = true <;>
    by_cases hw : (items.any fun i => itemGate runs i == .wait) = true <;> simp [hf, hd, hw, hD, hW]
  all_goals first | (intro i hi; exact fun e => hd (hD.1 ⟨i, hi, e⟩)) | skip

/-- Branch `review`: the dry line passes, items exist, and every item answers `review`.

A review is spent only when nothing is missing, pending or wrong.
-/
theorem reviewReady_review_iff (task items runs dry) :
    reviewReady task items runs dry = .review ↔
      (dryOk task dry = true ∧ items ≠ [] ∧ ∀ i ∈ items, itemGate runs i = .review) := by
  have hD : (∃ i ∈ items, itemGate runs i = .dispatch) ↔ (items.any fun i => itemGate runs i == .dispatch) = true := by
    simp [List.any_eq_true]
  have hW : (∃ i ∈ items, itemGate runs i = .wait) ↔ (items.any fun i => itemGate runs i == .wait) = true := by
    simp [List.any_eq_true]
  have key : ∀ i ∈ items, (itemGate runs i = .review ↔
      (itemGate runs i ≠ .returnToBuilder ∧ itemGate runs i ≠ .dispatch ∧ itemGate runs i ≠ .wait)) := by
    intro i _; cases itemGate runs i <;> simp
  unfold reviewReady
  by_cases hf : fault task items runs dry = true
  · have := (fault_iff task items runs dry).1 hf
    simp only [hf, ite_true]
    constructor
    · intro h; cases h
    · rintro ⟨d, ne, all⟩
      rcases this with h | h | ⟨i, hi, e⟩
      · simp_all
      · exact absurd h ne
      · rw [all i hi] at e; cases e
  · have hf' := fun h => hf ((fault_iff task items runs dry).2 h)
    simp only [hf]
    by_cases hd : (items.any fun i => itemGate runs i == .dispatch) = true
    · simp only [hd, ite_true]
      constructor
      · intro h; cases h
      · rintro ⟨_, _, all⟩
        obtain ⟨i, hi, e⟩ := hD.2 hd
        rw [all i hi] at e; cases e
    · by_cases hw : (items.any fun i => itemGate runs i == .wait) = true
      · simp only [hd, hw, ite_true]
        constructor
        · intro h; cases h
        · rintro ⟨_, _, all⟩
          obtain ⟨i, hi, e⟩ := hW.2 hw
          rw [all i hi] at e; cases e
      · simp only [hd, hw]
        simp only [fault_iff, not_or, not_exists, not_and] at hf
        obtain ⟨h1, h2, h3⟩ := hf
        refine ⟨fun _ => ⟨by simpa using h1, h2, fun i hi => ?_⟩, fun _ => rfl⟩
        have a := h3 i hi
        have b : itemGate runs i ≠ .dispatch := fun e => hd (hD.1 ⟨i, hi, e⟩)
        have c : itemGate runs i ≠ .wait := fun e => hw (hW.1 ⟨i, hi, e⟩)
        exact (key i hi).2 ⟨a, b, c⟩

/-- Totality: the four answers cover every report.

The gate gives one of the four answers.
-/
theorem reviewReady_total (task items runs dry) :
    reviewReady task items runs dry = .review ∨ reviewReady task items runs dry = .dispatch ∨
    reviewReady task items runs dry = .wait ∨ reviewReady task items runs dry = .returnToBuilder := by
  cases h : reviewReady task items runs dry <;> simp

/-- Without a passing `fw land --dry` line the gate never says `review`.

The dry line is the lone entry point.
-/
theorem no_review_without_dry (task items runs dry) (h : dryOk task dry = false) :
    reviewReady task items runs dry = .returnToBuilder := by
  rw [reviewReady_returnToBuilder_iff]; exact Or.inl h

/-- The dry line passes exactly when it is `VERDICT dry <task>`.

The pass test as a statement.
-/
theorem dryOk_iff (task dry) : dryOk task dry = true ↔ dry = "VERDICT dry " ++ task := by
  simp [dryOk]

/-- A dry line of another task never passes.

A stale line from a different task sends the report back.
-/
theorem dry_other_task_refused (task other items runs) (h : other ≠ task) :
    reviewReady task items runs ("VERDICT dry " ++ other) = .returnToBuilder := by
  apply no_review_without_dry
  cases hb : dryOk task ("VERDICT dry " ++ other)
  · rfl
  · have := (dryOk_iff task _).1 hb
    exact absurd (by simpa using this) h

/-- A review finding's severity.

Three levels: a `blocker` refuses; `fix-before-land` is text the lead applies; `follow-up` is later work.
-/
inductive Sev where
  | blocker | fixBeforeLand | followUp
deriving Repr, DecidableEq

/-- The severity a word names; any other word is a `blocker`.

An unknown word is not trusted to be harmless.
-/
def Sev.ofString : String → Sev
  | "blocker" => .blocker | "fix-before-land" => .fixBeforeLand | "follow-up" => .followUp | _ => .blocker

/-- A review's decision.

`accept` or `refuse`.
-/
inductive Verdict where
  | accept | refuse
deriving Repr, DecidableEq

/-- The wire name of a verdict.

`accept` or `refuse`.
-/
def Verdict.name : Verdict → String
  | .accept => "accept" | .refuse => "refuse"

/-- Accept iff no finding is a blocker.

The rule after the medium-only audit.
-/
def verdictOf (fs : List Sev) : Verdict := if fs.any (· == .blocker) then .refuse else .accept

/-- Must a checker re-check text the lead applies?

An accept (the verdict actually used, `v`) that carries a `fix-before-land` finding. A refuse never needs it.
-/
def recheck (v : Verdict) (fs : List Sev) : Bool := v == .accept && fs.any (· == .fixBeforeLand)

/-- The interim rule until the medium-only audit: also refuse on a `fix-before-land` finding.

Accept iff every finding is a `follow-up`.
-/
def strictVerdict (fs : List Sev) : Verdict := if fs.all (· == .followUp) then .accept else .refuse

/-- Branch `refuse`: some finding is a blocker.

Refusal needs a blocker.
-/
theorem verdictOf_refuse_iff (fs) : verdictOf fs = .refuse ↔ .blocker ∈ fs := by
  unfold verdictOf; split <;> simp_all

/-- Branch `accept`: no finding is a blocker.

Acceptance needs no blocker.
-/
theorem verdictOf_accept_iff (fs) : verdictOf fs = .accept ↔ .blocker ∉ fs := by
  unfold verdictOf; split <;> simp_all

/-- Branch `recheck` under the 3-level rule: no blocker and some `fix-before-land`.

Exactly these accepts need the checker's second look.
-/
theorem recheck_iff (fs) : recheck (verdictOf fs) fs = true ↔ (.blocker ∉ fs ∧ .fixBeforeLand ∈ fs) := by
  unfold recheck; simp [verdictOf_accept_iff]

/-- A refuse never needs a re-check.

Whatever rule gave the verdict.
-/
theorem recheck_refuse (fs) : recheck .refuse fs = false := by
  simp [recheck]

/-- The strict rule accepts exactly the all-`follow-up` lists.

The interim accept condition.
-/
theorem strict_accept_iff (fs) : strictVerdict fs = .accept ↔ ∀ f ∈ fs, f = .followUp := by
  unfold strictVerdict
  have e : fs.all (· == .followUp) = true ↔ ∀ f ∈ fs, f = .followUp := by simp [List.all_eq_true]
  by_cases h : fs.all (· == .followUp) = true
  · simp only [h, ite_true]; exact iff_of_true trivial (e.1 h)
  · simp only [h]; exact iff_of_false (fun x => nomatch x) (fun k => h (e.2 k))

/-- The strict rule is never more lenient than the 3-level rule.

Whatever `strictVerdict` accepts, `verdictOf` accepts.
-/
theorem strict_accept_verdict (fs) (h : strictVerdict fs = .accept) : verdictOf fs = .accept := by
  rw [verdictOf_accept_iff]; intro hb
  have := (strict_accept_iff fs).1 h _ hb
  cases this

/-- Branch `recheck` under the interim rule: never.

`strictVerdict` accepts only all-`follow-up` lists, so an accept carries no `fix-before-land`.
-/
theorem recheck_strict (fs) : recheck (strictVerdict fs) fs = false := by
  unfold recheck
  by_cases hv : strictVerdict fs = .accept
  · have all := (strict_accept_iff fs).1 hv
    have : fs.any (· == .fixBeforeLand) = false := by
      rw [List.any_eq_false]; intro f hf; rw [all f hf]; decide
    simp [this]
  · simp [hv]

-- Goldens: one #guard per branch.
private def it (s e : String) : Item := ⟨"x", s, e⟩
private def passDry := "VERDICT dry t"
#guard reviewReady "t" [it "done" "lean/Fw/X.lean:12"] [] passDry == .review
#guard reviewReady "t" [it "done" "lean/Fw/X.lean:12"] [] "VERDICT scope t" == .returnToBuilder
#guard reviewReady "t" [it "done" "no cite here"] [] passDry == .returnToBuilder
#guard reviewReady "t" [] [] passDry == .returnToBuilder
#guard reviewReady "t" [it "dispatch" "gh workflow run foo"] [] passDry == .dispatch
#guard reviewReady "t" [it "pending" "run:123"] [⟨"123", "running"⟩] passDry == .wait
#guard reviewReady "t" [it "pending" "run:123"] [⟨"123", "complete"⟩] passDry == .review
#guard reviewReady "t" [it "pending" "run:123"] [⟨"123", "failed"⟩] passDry == .returnToBuilder
#guard reviewReady "t" [it "pending" "run:9"] [] passDry == .returnToBuilder
#guard reviewReady "t" [it "pending" "cm:6ade316d0123456789abcdef"] [⟨"cm:6ade316d0123456789abcdef", "running"⟩] passDry == .wait
#guard reviewReady "t" [it "pending" "cm:6ade316d0123456789abcdef"] [⟨"cm:6ade316d0123456789abcdef", "complete"⟩] passDry == .review
#guard reviewReady "t" [it "pending" "cm:6ade316d0123456789abcdef"] [⟨"6ade316d0123456789abcdef", "complete"⟩] passDry == .returnToBuilder
#guard reviewReady "t" [it "done" "cm:6ade316d0123456789abcdef"] [] passDry == .review
#guard reviewReady "t" [it "done" "cm:6ade316d"] [] passDry == .returnToBuilder
#guard reviewReady "t" [it "done" "cm:6ADE316D0123456789ABCDEF"] [] passDry == .returnToBuilder
#guard reviewReady "t" [it "pending" "run:1", it "dispatch" "cmd"] [⟨"1", "running"⟩] passDry == .dispatch
#guard reviewReady "t" [it "followUp" "", it "undelivered" ""] [] passDry == .returnToBuilder
#guard reviewReady "t" [it "followUp" ""] [] passDry == .review
#guard reviewReady "t" [it "done" "lean/Fw/X.lean:12"] [] "VERDICT dry other" == .returnToBuilder
#guard reviewReady "t" [it "done" "lean/Fw/X.lean:12"] [] "VERDICT dry " == .returnToBuilder
#guard verdictOf [.followUp, .fixBeforeLand] == .accept
#guard verdictOf [.followUp, .blocker] == .refuse
#guard recheck (verdictOf [.fixBeforeLand]) [.fixBeforeLand] && !recheck (verdictOf [.followUp]) [.followUp]
  && !recheck (verdictOf [.blocker, .fixBeforeLand]) [.blocker, .fixBeforeLand]
#guard !recheck (strictVerdict [.fixBeforeLand]) [.fixBeforeLand]
#guard strictVerdict [.fixBeforeLand] == .refuse && strictVerdict [] == .accept
#guard Sev.ofString "high" == .blocker

end Fw.Plan.ReviewReady
