import Fw.Oracle.Calibrate
import Fw.Oracle.Send
import Fw.Oracle.Questions
import Fw.Oracle.Labels
/-!
# Fw.Oracle.Replay: the offline replay of the Jev trial (sets D1 and D2), its sample and its score

A replay set is a file of labeled rows from our own history (task `jev-datasets`). This module decides everything
`fw oracle send` and the scorer need from it:

- `sets`: the registered sets, each with its question and the row keys that fill the question's state fields
  (`sets_fields`); a row's state (`rowState`) is its texts cut into lines of at most `lineWidth` characters
  (`textLines`, `chunk_le`, `chunk_flatten`: no character is lost) with local run ids (`wf_…`) replaced by `wf_<id>`
  (`scrubWf`, `scrubWf_clean`), and every state built this way passes the field check of the send gate
  (`rowState_declared`).
- The sample of a sampled set (`pick`): per option, the first `minHoldout` held-out rows and the first `max 1 k`
  calibration rows labeled with it, in hash order (`sampleHeld_mem`, `sampleHeld_length`, `sampleCal_mem`; at most
  90 rows for D2, `d2_pick_le`). `minHoldout q k` is the least number of held-out hits that can pass the holdout
  test (`minHoldout_least`), and certifying an option needs at least that many held-out rows labeled with it
  (`certify_needs_holdout`), so no smaller stratified sample can certify an option. Rows whose finding or location
  names a grade are left out (`leaks`).
- The score of one arm: the confusion matrix, per option the rows chosen, labeled and right (`right_le_chosen`,
  `right_le_labeled`), cost from the published prices (`armPrice`, `dollars`) and latency (`meanQ`, `medianN`).
-/
namespace Fw.Oracle

/-! ## Lines of a state -/

/-- **Cut a list into pieces of at most `n`** (no cut when `n = 0`). -/
def chunk {α : Type} (n : Nat) (l : List α) : List (List α) :=
  if _h : 0 < n ∧ l ≠ [] then l.take n :: chunk n (l.drop n)
  else if l = [] then [] else [l]
termination_by l.length
decreasing_by
  obtain ⟨hn, hl⟩ := _h
  have : 0 < l.length := List.length_pos_iff.mpr hl
  simp only [List.length_drop]
  omega

/-- **No element is lost**: the pieces put back together are the list. -/
theorem chunk_flatten {α : Type} (n : Nat) (l : List α) : (chunk n l).flatten = l := by
  induction l using (measure List.length).wf.induction with
  | h l ih =>
    rw [chunk]
    split
    · rename_i h
      simp only [List.flatten_cons]
      have hl : 0 < l.length := List.length_pos_iff.mpr h.2
      rw [ih (l.drop n) (by show (l.drop n).length < l.length; simp only [List.length_drop]; omega),
        List.take_append_drop]
    · split
      · rename_i h; simp [h]
      · simp

/-- **Every piece has at most `n` elements** (for `n > 0`). -/
theorem chunk_le {α : Type} (n : Nat) (hn : 0 < n) (l : List α) : ∀ c ∈ chunk n l, c.length ≤ n := by
  induction l using (measure List.length).wf.induction with
  | h l ih =>
    rw [chunk]
    split
    · rename_i h
      intro c hc
      simp only [List.mem_cons] at hc
      rcases hc with rfl | hc
      · exact List.length_take_le _ _
      · have hl : 0 < l.length := List.length_pos_iff.mpr h.2
        exact ih (l.drop n) (by show (l.drop n).length < l.length; simp only [List.length_drop]; omega) c hc
    · rename_i h
      split
      · simp
      · rename_i hl
        exact absurd ⟨hn, hl⟩ h

/-- The most characters a state line of a replay row has (under the send gate's 500, so a redaction that lengthens a
line stays under it). -/
def lineWidth : Nat := 400

/-- **The lines of a text**: its newline-separated lines, each cut into pieces of at most `lineWidth` characters;
empty lines are dropped. -/
def textLines (s : String) : List String :=
  (s.splitOn "\n").flatMap fun ln => (chunk lineWidth ln.toList).map String.ofList

/-- **Every line of a text is at most `lineWidth` characters.** -/
theorem textLines_le (s : String) : ∀ x ∈ textLines s, x.length ≤ lineWidth := by
  intro x hx
  simp only [textLines, List.mem_flatMap, List.mem_map] at hx
  obtain ⟨ln, _, c, hc, rfl⟩ := hx
  rw [String.length_ofList]
  exact chunk_le lineWidth (by decide) _ c hc

#guard textLines "a\nb" == ["a", "b"]
#guard textLines "" == []
#guard (textLines (String.ofList (List.replicate 900 'x'))).map String.length == [400, 400, 100]

/-! ## Local run ids -/

/-- A character of a local run id after `wf_`: a digit, `a` to `f`, or `-`. -/
def isIdChar (c : Char) : Bool := c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'f')) || c == '-'

/-- What a local run id becomes. -/
def wfMark : List Char := "wf_<id>".toList

/-- A text starts with a local run id: `wf_` and an id character. -/
def startsId : List Char → Bool
  | 'w' :: 'f' :: '_' :: d :: _ => isIdChar d
  | _ => false

theorem length_dropWhile_le {α : Type} (p : α → Bool) (l : List α) : (l.dropWhile p).length ≤ l.length := by
  induction l with
  | nil => simp
  | cons x xs ih => simp only [List.dropWhile_cons]; split <;> simp; omega

/-- **Replace local run ids**: every `wf_` followed by id characters becomes `wf_<id>`. -/
def scrubWf : List Char → List Char
  | [] => []
  | c :: rest =>
    if startsId (c :: rest) then wfMark ++ scrubWf ((rest.drop 2).dropWhile isIdChar)
    else c :: scrubWf rest
termination_by l => l.length
decreasing_by
  all_goals simp_wf
  have := length_dropWhile_le isIdChar (rest.drop 2)
  simp at this
  omega

/-- A text holds no local run id: no `wf_` is followed by an id character. -/
def noWfId : List Char → Bool
  | [] => true
  | c :: rest => !startsId (c :: rest) && noWfId rest

theorem startsId_w {c : Char} {r : List Char} (h : startsId (c :: r) = true) : c = 'w' := by
  unfold startsId at h
  split at h <;> simp_all

/-- Scrubbing keeps the first character. -/
theorem scrubWf_head (c : Char) (r : List Char) : ∃ t, scrubWf (c :: r) = c :: t := by
  rw [scrubWf]
  split
  · rename_i h
    rw [startsId_w h]
    exact ⟨_, rfl⟩
  · exact ⟨_, rfl⟩

/-- Scrubbing passes a character other than `w` through. -/
theorem scrubWf_cons {c : Char} (hc : c ≠ 'w') (r : List Char) : scrubWf (c :: r) = c :: scrubWf r := by
  have hs : startsId (c :: r) = false := by
    cases h : startsId (c :: r)
    · rfl
    · exact absurd (startsId_w h) hc
  rw [scrubWf]
  simp [hs]

/-- A run id in front of a scrubbed text was already in front of the text. -/
theorem startsId_scrub (c : Char) (rest : List Char) (h : startsId (c :: scrubWf rest) = true) :
    startsId (c :: rest) = true := by
  have hw := startsId_w h
  subst hw
  match rest, h with
  | [], h => simp [scrubWf, startsId] at h
  | x :: xs, h =>
    obtain ⟨t, ht⟩ := scrubWf_head x xs
    rw [ht] at h
    by_cases hx : x = 'f'
    · subst hx
      rw [scrubWf_cons (by decide)] at ht
      simp only [List.cons.injEq, true_and] at ht
      subst ht
      match xs, h with
      | [], h => simp [scrubWf, startsId] at h
      | y :: ys, h =>
        obtain ⟨u, hu⟩ := scrubWf_head y ys
        rw [hu] at h
        by_cases hy : y = '_'
        · subst hy
          rw [scrubWf_cons (by decide)] at hu
          simp only [List.cons.injEq, true_and] at hu
          subst hu
          match ys, h with
          | [], h => simp [scrubWf, startsId] at h
          | z :: zs, h =>
            obtain ⟨v, hv⟩ := scrubWf_head z zs
            rw [hv] at h
            simpa [startsId] using h
        · simp [startsId, hy] at h
    · simp [startsId, hx] at h

/-- **A scrubbed text holds no local run id.** -/
theorem scrubWf_clean (l : List Char) : noWfId (scrubWf l) = true := by
  induction l using (measure List.length).wf.induction with
  | h l ih =>
    match l with
    | [] => simp [scrubWf, noWfId]
    | c :: rest =>
      rw [scrubWf]
      split
      · have hd := length_dropWhile_le isIdChar (rest.drop 2)
        have hc := ih ((rest.drop 2).dropWhile isIdChar)
          (by show _ < (c :: rest).length; simp only [List.length_cons, List.length_drop] at hd ⊢; omega)
        simp [wfMark, noWfId, startsId, isIdChar, hc]
      · rename_i hs
        have hc := ih rest (by show rest.length < (c :: rest).length; simp)
        simp only [noWfId, hc, Bool.and_true, Bool.not_eq_eq_eq_not, Bool.not_true]
        cases h : startsId (c :: scrubWf rest)
        · rfl
        · exact absurd (startsId_scrub c rest h) hs

#guard String.ofList (scrubWf "see wf_30bab1a1-3ee-1 and worktree-wf_2a4f5755-f50-1/x".toList) ==
  "see wf_<id> and worktree-wf_<id>/x"
#guard String.ofList (scrubWf "wf_trial stays".toList) == "wf_trial stays"
#guard noWfId (scrubWf "wwf_abc wf_ wf_1".toList)

/-! ## The sets -/

/-- A registered replay set: its name, its file under the datasets directory, its question, the row key that fills
each state field, and whether it is sent in full or as the stratified sample. -/
structure ReplaySet where
  name : String
  file : String
  question : Question
  fields : List (String × String)
  sampled : Bool

/-- **D1**: the incident ledger, every labeled row. -/
def d1 : ReplaySet :=
  { name := "d1", file := "d1.jsonl", question := incidentClass, sampled := false,
    fields := [("title", "title"), ("symptom", "symptom"), ("cause", "cause")] }

/-- **D2**: the review findings, the stratified sample. The finding text is the row's `what`, the task text its
`taskText`. -/
def d2 : ReplaySet :=
  { name := "d2", file := "d2.jsonl", question := findingSeverity, sampled := true,
    fields := [("finding", "what"), ("where", "where"), ("task", "taskText"), ("unit", "unit"),
      ("limits", "limits")] }

/-- The registered replay sets. -/
def sets : List ReplaySet := [d1, d2]

/-- The registered set with this name, if any. -/
def replaySet (x : String) : Option ReplaySet := sets.find? (·.name == x)

/-- **Each set fills exactly its question's fields, in order.** -/
theorem sets_fields : ∀ r ∈ sets, r.fields.map Prod.fst = r.question.fields := by
  simp only [sets, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq]
  exact ⟨rfl, rfl⟩

/-- **The D2 options are the three grade words and the no-match option** (D1's classes are D1 labels:
`incidentClass_labels`). -/
theorem d2_labels : d2.question.spec.keys = Labels.exactWords ++ [noGrade] := by decide

/-- The state of one row: each field's text (the row's value at its key, empty when absent) with local run ids
replaced (`scrubWf`) and cut into lines (`textLines`). -/
def rowState (r : ReplaySet) (row : List (String × String)) : State :=
  r.fields.map fun (f, k) => (f, textLines (String.ofList (scrubWf ((row.lookup k).getD "").toList)))

/-- **A row's state names exactly the set's question fields**, so the send gate never refuses it as undeclared. -/
theorem rowState_declared (r : ReplaySet) (hr : r ∈ sets) (row : List (String × String)) :
    declared r.question (rowState r row) = true := by
  have hf := sets_fields r hr
  simp only [declared, rowState, List.all_eq_true, List.mem_map, Prod.exists]
  rintro p ⟨f, key, hm, rfl⟩
  rw [← hf]
  exact List.contains_iff_mem.mpr (List.mem_map.mpr ⟨(f, key), hm, rfl⟩)

/-- **No state line of a row is longer than `lineWidth`.** -/
theorem rowState_lines (r : ReplaySet) (row : List (String × String)) :
    ∀ p ∈ rowState r row, ∀ x ∈ p.2, x.length ≤ lineWidth := by
  intro p hp x hx
  simp only [rowState, List.mem_map] at hp
  obtain ⟨_, _, rfl⟩ := hp
  exact textLines_le _ x hx

/-- A text names a grade: one of the three grade words anywhere, or a grade word of the old vocabulary as its first
word (`Labels.wordGrade`). A D2 row whose finding or location names a grade is left out of the sample, since its
answer would be read off the text. -/
def namesGrade (text : String) : Bool :=
  let l := Labels.lowerTrim text
  Labels.exactWords.any (fun w => Labels.hasInfix w.toList l) || (Labels.wordGrade (Labels.headWord l)).isSome

#guard namesGrade "Blocker: the proof is missing" && namesGrade "a FOLLOW-UP item" && namesGrade "High risk"
#guard !namesGrade "the proof is missing" && !namesGrade "highlight the row"

/-- The row keys whose text decides `namesGrade` (D2's finding and location). -/
def leakKeys : List String := ["what", "where"]

/-- A row leaks its label when a leak key's text names a grade. -/
def leaks (row : List (String × String)) : Bool := leakKeys.any fun k => namesGrade ((row.lookup k).getD "")

#guard leaks [("what", "minor: typo"), ("where", "x")] && !leaks [("what", "typo"), ("taskText", "follow-up")]

/-! ## The least sample that can certify -/

/-- **More right answers among fewer rows still pass**: if `h` hits of `n` rows pass the Wilson test at a rate
`0 ≤ q < 1`, then `h` hits of `h` rows pass it too (the bound only rises when misses are removed). -/
theorem wilsonOk_hits (z q : Rat) (h n : Nat) (hz : 0 ≤ z) (hq : 0 ≤ q) (hh : 0 < h) (hn : h ≤ n)
    (hw : wilsonOk z q h n = true) : wilsonOk z q h h = true := by
  simp only [wilsonOk, Bool.and_eq_true, decide_eq_true_eq] at hw ⊢
  obtain ⟨⟨⟨_, hq1⟩, ha⟩, hw⟩ := hw
  have H0 : (0 : Rat) < h := by exact_mod_cast hh
  have hHN : (h : Rat) ≤ n := by exact_mod_cast hn
  have h1q : (0 : Rat) ≤ 1 - q := by grind
  have hqH : q * h ≤ q * n := Rat.mul_le_mul_of_nonneg_left hHN hq
  have hA : 0 ≤ (h : Rat) - q * n := by grind
  have hAB : (h : Rat) - q * n ≤ h - q * h := by grind
  have hsq1 : ((h : Rat) - q * n) * (h - q * n) ≤ (h - q * n) * (h - q * h) :=
    Rat.mul_le_mul_of_nonneg_left hAB hA
  have hsq2 : ((h : Rat) - q * n) * (h - q * h) ≤ (h - q * h) * (h - q * h) :=
    Rat.mul_le_mul_of_nonneg_right hAB (by grind)
  have hzz : (0 : Rat) ≤ z * z * q * (1 - q) :=
    Rat.mul_nonneg (Rat.mul_nonneg (Rat.mul_nonneg hz hz) hq) h1q
  have hl : z * z * q * (1 - q) * h ≤ z * z * q * (1 - q) * n := Rat.mul_le_mul_of_nonneg_left hHN hzz
  have hqh : q * (h : Rat) ≤ h := by
    have := Rat.mul_nonneg h1q (Rat.le_of_lt H0)
    grind
  refine ⟨⟨⟨hh, hq1⟩, hqh⟩, ?_⟩
  have e1 : z * z * (h : Rat) * q * (1 - q) = z * z * q * (1 - q) * h := by grind
  have e2 : z * z * (n : Rat) * q * (1 - q) = z * z * q * (1 - q) * n := by grind
  grind

/-- The first `i`, from `start` on and within `fuel` steps, where `p` holds (`start + fuel` when none does). -/
def firstFrom (p : Nat → Bool) (start : Nat) : Nat → Nat
  | 0 => start
  | fuel + 1 => if p start then start else firstFrom p (start + 1) fuel

theorem firstFrom_le (p : Nat → Bool) (h : Nat) (hp : p h = true) :
    ∀ (fuel start : Nat), start ≤ h → firstFrom p start fuel ≤ h := by
  intro fuel
  induction fuel with
  | zero => intro start hs; exact hs
  | succ f ih =>
    intro start hs
    simp only [firstFrom]
    split
    · exact hs
    · rename_i hps
      have : start ≠ h := fun e => hps (e ▸ hp)
      exact ih (start + 1) (by omega)

theorem firstFrom_least (p : Nat → Bool) :
    ∀ (fuel start j : Nat), start ≤ j → j < firstFrom p start fuel → p j = false := by
  intro fuel
  induction fuel with
  | zero => intro start j hs hj; simp only [firstFrom] at hj; omega
  | succ f ih =>
    intro start j hs hj
    simp only [firstFrom] at hj
    split at hj
    · omega
    · rename_i hps
      by_cases e : j = start
      · subst e; simpa using hps
      · exact ih (start + 1) j (by omega) hj

/-- **The least number of held-out rows that can certify an option**: the least `h ≥ max 1 k` such that `h` right of
`h` passes the Wilson test at rate `q` (searched up to 10000). -/
def minHoldout (q : Rat) (k : Nat) : Nat := firstFrom (fun h => wilsonOk wilsonZ q h h) (max 1 k) 10000

#guard minHoldout (9 / 10) 5 == 25
#guard minHoldout (8 / 10) 5 == 11
#guard minHoldout (1 / 2) 5 == 5

/-- **No smaller number passes**: below `minHoldout q k`, `h` right of `h` fails the Wilson test. -/
theorem minHoldout_least (q : Rat) (k h : Nat) (hk : max 1 k ≤ h) (hlt : h < minHoldout q k) :
    wilsonOk wilsonZ q h h = false :=
  firstFrom_least (fun x => wilsonOk wilsonZ q x x) 10000 (max 1 k) h hk hlt

/-- **Certifying an option needs at least `minHoldout q k` held-out rows labeled with it** (for `0 ≤ q`): whatever
the answers, a certified table entry for `o` means the holdout part holds that many rows whose label is `o`. So a
sample with fewer held-out rows of an option can never certify it. -/
theorem certify_needs_holdout (s : Spec) (q : Rat) (k : Nat) (rs : List IdRow) (o : Advice) (τ : Rat) (hq : 0 ≤ q)
    (h : (certify s q k rs).lookup o = some τ) :
    minHoldout q k ≤ ((holdPart rs).filter (·.label == o)).length := by
  have hok := (certify_entry s q k rs o τ h).2.2
  simp only [holdOk, okOpt, Bool.and_eq_true, decide_eq_true_eq] at hok
  obtain ⟨⟨hk, _⟩, hw⟩ := hok
  have hle := hitsAs_le s τ (holdPart rs) o
  have hadv := hitsAs_le_advisedAs s τ (holdPart rs) o
  have hhh := wilsonOk_hits wilsonZ q _ _ (by unfold wilsonZ; grind) hq (by omega) hadv hw
  have := firstFrom_le (fun x => wilsonOk wilsonZ q x x) _ hhh 10000 (max 1 k) hk
  exact Nat.le_trans this hle

/-! ## The stratified sample -/

/-- Rows `(id, label)` in hash order: by FNV-1a of `s:` and the id (another order than the split's own hash). -/
def byHash (rows : List (String × String)) : List (String × String) :=
  rows.mergeSort fun a b => Labels.fnv1a ("s:" ++ a.1) ≤ Labels.fnv1a ("s:" ++ b.1)

/-- The held-out rows of one option in the sample: the first `minHoldout q k` held-out rows labeled `o`. -/
def sampleHeld (q : Rat) (k : Nat) (rows : List (String × String)) (o : String) : List (String × String) :=
  (byHash (rows.filter fun r => r.2 == o && heldOut r.1)).take (minHoldout q k)

/-- The calibration rows of one option in the sample: the first `max 1 k` calibration rows labeled `o`. -/
def sampleCal (k : Nat) (rows : List (String × String)) (o : String) : List (String × String) :=
  (byHash (rows.filter fun r => r.2 == o && !heldOut r.1)).take (max 1 k)

/-- **The sample of a sampled set**: per option, its held-out rows then its calibration rows. -/
def sample (q : Rat) (k : Nat) (opts : List String) (rows : List (String × String)) : List (String × String) :=
  opts.flatMap fun o => sampleHeld q k rows o ++ sampleCal k rows o

/-- **The held-out sample of an option is held out, labeled with it, and taken from the rows.** -/
theorem sampleHeld_mem (q : Rat) (k : Nat) (rows : List (String × String)) (o : String) :
    ∀ r ∈ sampleHeld q k rows o, r ∈ rows ∧ r.2 = o ∧ heldOut r.1 = true := by
  intro r hr
  simp only [sampleHeld, byHash] at hr
  have := List.mem_of_mem_take hr
  simp only [List.mem_mergeSort, List.mem_filter, Bool.and_eq_true, beq_iff_eq] at this
  exact ⟨this.1, this.2.1, this.2.2⟩

/-- **The sample holds `minHoldout q k` held-out rows of an option whenever the set has that many.** -/
theorem sampleHeld_length (q : Rat) (k : Nat) (rows : List (String × String)) (o : String)
    (h : minHoldout q k ≤ (rows.filter fun r => r.2 == o && heldOut r.1).length) :
    (sampleHeld q k rows o).length = minHoldout q k := by
  simp only [sampleHeld, byHash, List.length_take, List.length_mergeSort]
  omega

/-- **The calibration sample of an option is not held out.** -/
theorem sampleCal_mem (k : Nat) (rows : List (String × String)) (o : String) :
    ∀ r ∈ sampleCal k rows o, r ∈ rows ∧ r.2 = o ∧ heldOut r.1 = false := by
  intro r hr
  simp only [sampleCal, byHash] at hr
  have := List.mem_of_mem_take hr
  simp only [List.mem_mergeSort, List.mem_filter, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_eq_eq_not,
    Bool.not_true] at this
  exact ⟨this.1, this.2.1, this.2.2⟩

/-- **At most `minHoldout q k + max 1 k` rows per option.** -/
theorem sample_length (q : Rat) (k : Nat) (opts : List String) (rows : List (String × String)) :
    (sample q k opts rows).length ≤ opts.length * (minHoldout q k + max 1 k) := by
  induction opts with
  | nil => simp [sample]
  | cons o os ih =>
    simp only [sample, List.flatMap_cons, List.length_append, List.length_cons] at ih ⊢
    have h1 : (sampleHeld q k rows o).length ≤ minHoldout q k := by
      simp only [sampleHeld, List.length_take]; omega
    have h2 : (sampleCal k rows o).length ≤ max 1 k := by
      simp only [sampleCal, List.length_take]; omega
    rw [Nat.succ_mul]
    omega

/-- The option name of an advice (the labels of the replay sets are option names). -/
def optionName : Advice → String
  | .pick o => o
  | .yes => "yes"
  | .no => "no"
  | .level i => toString i

/-- The labeled rows `(id, label)` of rows `(id, label, leaks)` that may be sampled: those that do not leak. -/
def unleaked (rows : List (String × String × Bool)) : List (String × String) :=
  rows.filterMap fun (i, l, lk) => if lk then none else some (i, l)

/-- **The rows a set sends**: every labeled row when the set is not sampled, else the sample over the advisable
options of its question, leaking rows left out. Rows are `(id, label, leaks)`. -/
def pick (r : ReplaySet) (rows : List (String × String × Bool)) : List (String × String) :=
  if r.sampled then
    sample r.question.target r.question.perOption (r.question.spec.advisable.map optionName) (unleaked rows)
  else rows.map fun (i, l, _) => (i, l)

/-- **The D2 sample has at most `minHoldout (9/10) 5 + 5` rows per grade** (25 + 5, so 90 for the three grades). -/
theorem d2_pick_le (rows : List (String × String × Bool)) :
    (pick d2 rows).length ≤ 3 * (minHoldout (9 / 10) 5 + 5) :=
  sample_length (9 / 10) 5 (d2.question.spec.advisable.map optionName) (unleaked rows)

#guard 3 * (minHoldout (9 / 10) 5 + 5) == 90

/-! ## The score of one arm -/

/-- One scored row: its label and the option the arm picked (`none`: the request failed). -/
abbrev Scored := String × Option String

/-- The rows the arm answered with `o`. -/
def chosenN (rs : List Scored) (o : String) : Nat := (rs.filter fun r => r.2 == some o).length

/-- The rows labeled `o`. -/
def labeledN (rs : List Scored) (o : String) : Nat := (rs.filter fun r => r.1 == o).length

/-- The rows labeled `o` that the arm answered with `o`. -/
def rightN (rs : List Scored) (o : String) : Nat := (rs.filter fun r => r.2 == some o && r.1 == o).length

/-- The rows the arm answered correctly, any option. -/
def rightAll (rs : List Scored) : Nat := (rs.filter fun r => r.2 == some r.1).length

/-- The rows the arm answered at all. -/
def answeredN (rs : List Scored) : Nat := (rs.filter fun r => r.2.isSome).length

theorem filter_and_le {α : Type} (p q : α → Bool) (l : List α) :
    (l.filter fun x => p x && q x).length ≤ (l.filter p).length := by
  induction l with
  | nil => simp
  | cons x xs ih =>
    simp only [List.filter_cons]
    by_cases hp : p x <;> by_cases hq : q x <;> simp [hp, hq] <;> omega

/-- **Right answers are among the answers of that option.** -/
theorem right_le_chosen (rs : List Scored) (o : String) : rightN rs o ≤ chosenN rs o :=
  filter_and_le _ _ rs

/-- **Right answers are among the rows of that label.** -/
theorem right_le_labeled (rs : List Scored) (o : String) : rightN rs o ≤ labeledN rs o := by
  have : rightN rs o = (rs.filter fun r => r.1 == o && r.2 == some o).length := by
    unfold rightN
    congr 1
    apply List.filter_congr
    intro x _
    exact Bool.and_comm _ _
  rw [this]
  exact filter_and_le _ _ rs

/-- `a / b`, none when `b = 0` (precision, recall and accuracy of an empty column). -/
def ratio (a b : Nat) : Option Rat := if b = 0 then none else some ((a : Rat) / b)

/-- The confusion row of label `l`: per option how many rows labeled `l` were answered with it, then the failures. -/
def confusionRow (rs : List Scored) (opts : List String) (l : String) : List Nat :=
  opts.map (fun o => (rs.filter fun r => r.1 == l && r.2 == some o).length) ++
    [(rs.filter fun r => r.1 == l && r.2.isNone).length]

#guard rightN [("a", some "a"), ("a", some "b"), ("b", some "a"), ("b", none)] "a" == 1
#guard chosenN [("a", some "a"), ("a", some "b"), ("b", some "a"), ("b", none)] "a" == 2
#guard labeledN [("a", some "a"), ("a", some "b"), ("b", some "a"), ("b", none)] "b" == 2
#guard rightAll [("a", some "a"), ("a", some "b"), ("b", some "b"), ("b", none)] == 2
#guard confusionRow [("a", some "a"), ("a", some "b"), ("b", some "a"), ("b", none)] ["a", "b"] "b" == [1, 0, 1]
#guard ratio 1 0 == none && ratio 1 4 == some (1 / 4)

/-- A price per million tokens, input and output, in US dollars. -/
structure Price where
  input : Rat
  output : Rat
deriving Repr, DecidableEq

/-- **The published prices** (CONFIRMED, read 2026-10-22): Jev 0.042 per million input tokens, output free
(docs.typesafe.ai/models.md); Claude Haiku 5.5 0.10 and 0.50, Claude Sonnet 5.5 2 and 10 (docs.claude.com pricing,
prompts up to 100k tokens). -/
def armPrice : String → Option Price
  | "jev" => some { input := 42 / 1000, output := 0 }
  | "haiku" => some { input := 1 / 10, output := 1 / 2 }
  | "sonnet" => some { input := 2, output := 10 }
  | _ => none

/-- The dollars of a token count at a price. -/
def dollars (p : Price) (inTok outTok : Nat) : Rat := ((inTok : Rat) * p.input + (outTok : Rat) * p.output) / 1000000

#guard dollars { input := 42 / 1000, output := 0 } 1000000 500 == 42 / 1000
#guard (armPrice "sonnet").map (dollars · 1000 100) == some (3 / 1000)
#guard armPrice "gpt" == none

/-- The mean of some durations, none when there are none. -/
def meanQ (xs : List Nat) : Option Rat := ratio xs.sum xs.length

/-- The median of some durations (the lower middle of the sorted list), none when there are none. -/
def medianN (xs : List Nat) : Option Nat := (xs.mergeSort (· ≤ ·))[(xs.length - 1) / 2]?

#guard meanQ [1, 2, 6] == some 3 && meanQ [] == none
#guard medianN [5, 1, 3] == some 3 && medianN [4, 1, 3, 2] == some 2 && medianN [] == none

end Fw.Oracle
