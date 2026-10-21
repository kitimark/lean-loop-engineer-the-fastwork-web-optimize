import Lean.Data.Json
/-!
# Does a cited CI run carry the flag it is cited for (op `gate.runCite`)
-/
namespace Fw.Gate.RunCite
open Lean

/-- The `key=value` pairs of a URL search such as `?preset=v2-proved&fw=a:b,c:d`. -/
def params (search : String) : List (String × String) :=
  let body := match search.toList with
    | '?' :: rest => String.ofList rest
    | _ => search
  (body.splitOn "&").filterMap fun p =>
    match p.splitOn "=" with
    | [] | [""] => none
    | [k] => some (k, "")
    | k :: rest => some (k, "=".intercalate rest)

/-- The flag entries (`part:variant`, maybe `@impl`) of a search's `fw` parameters. -/
def fwOf (search : String) : List String :=
  (params search).flatMap fun (k, v) => if k == "fw" then (v.splitOn ",").filter (· != "") else []

/-- The preset names of a search's `preset` parameters. -/
def presetOf (search : String) : List String :=
  (params search).filterMap fun (k, v) => if k == "preset" && v != "" then some v else none

/-- What a run's own artifacts say: the search of every arm (`""` = no query), or why there is nothing to read. -/
inductive Facts where
  | arms (searches : List String)
  | missing (why : String)
  deriving DecidableEq, Repr

/-- The verdict on one citation of a run for a flag. -/
inductive Verdict where
  | match
  | mismatch (carried : List String)
  | unknown (why : String)
  deriving DecidableEq, Repr

/-- Every flag entry any arm carried, first occurrence first. -/
def carried (as : List String) : List String := (as.flatMap fwOf).eraseDups

/-- Every preset any arm carried, first occurrence first. -/
def presets (as : List String) : List String := (as.flatMap presetOf).eraseDups

/-- The `part:variant` of a flag entry, without its `@impl`. -/
def variantOf (entry : String) : String := (entry.splitOn "@").headD entry

/-- A carried entry stands for the cited flag: equal, or equal once the entry's `@impl` is dropped. -/
def covers (entry flag : String) : Bool := entry == flag || variantOf entry == flag

/-- Why a run with no arm is unknown. -/
def noArm : String := "the run's artifacts record no arm"

/-- Why a run that carried presets but not the flag is unknown. -/
def presetWhy (ps : List String) : String :=
  s!"the run carried preset {", ".intercalate ps}, and its artifacts do not list the preset's flags"

/-- The verdict on citing a run with facts `f` for `flag`. -/
def verdict : Facts → String → Verdict
  | .missing why, _ => .unknown why
  | .arms as, flag =>
    if as.isEmpty then .unknown noArm
    else if (carried as).any (covers · flag) then .match
    else if (presets as).isEmpty then .mismatch (carried as)
    else .unknown (presetWhy (presets as))

theorem mem_carried (as : List String) (e : String) : e ∈ carried as ↔ ∃ s ∈ as, e ∈ fwOf s := by
  simp [carried, List.mem_eraseDups, List.mem_flatMap]

theorem any_carried (as : List String) (flag : String) :
    (carried as).any (covers · flag) = true ↔ ∃ s ∈ as, ∃ e ∈ fwOf s, covers e flag = true := by
  simp only [List.any_eq_true, mem_carried]
  constructor
  · rintro ⟨e, ⟨s, hs, he⟩, hc⟩; exact ⟨s, hs, e, he, hc⟩
  · rintro ⟨s, hs, e, he, hc⟩; exact ⟨e, ⟨s, hs, he⟩, hc⟩

theorem presets_nil_iff (as : List String) : presets as = [] ↔ ∀ s ∈ as, presetOf s = [] := by
  constructor
  · intro h s hs
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro p hp
    have : p ∈ presets as := by simp [presets, List.mem_eraseDups, List.mem_flatMap]; exact ⟨s, hs, hp⟩
    simp [h] at this
  · intro h
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro p hp
    simp only [presets, List.mem_eraseDups, List.mem_flatMap] at hp
    obtain ⟨s, hs, hp⟩ := hp
    simp [h s hs] at hp

theorem verdict_missing (why flag : String) : verdict (.missing why) flag = .unknown why := rfl

theorem verdict_no_arm (flag : String) : verdict (.arms []) flag = .unknown noArm := rfl

theorem verdict_match_iff (as : List String) (flag : String) :
    verdict (.arms as) flag = .match ↔ ∃ s ∈ as, ∃ e ∈ fwOf s, covers e flag = true := by
  rw [← any_carried]
  cases as with
  | nil => simp [verdict, carried]
  | cons a t =>
    simp only [verdict, List.isEmpty_cons, Bool.false_eq_true, ite_false]
    split <;> rename_i h
    · simp [h]
    · split <;> simp [h]

theorem verdict_mismatch_iff (as : List String) (flag : String) (c : List String) :
    verdict (.arms as) flag = .mismatch c ↔
      as ≠ [] ∧ (∀ s ∈ as, ∀ e ∈ fwOf s, covers e flag = false) ∧ (∀ s ∈ as, presetOf s = []) ∧
        c = carried as := by
  have hany : (carried as).any (covers · flag) = false ↔ ∀ s ∈ as, ∀ e ∈ fwOf s, covers e flag = false := by
    rw [← Bool.not_eq_true, any_carried]
    simp
  rw [← hany, ← presets_nil_iff]
  cases as with
  | nil => simp [verdict]
  | cons a t =>
    simp only [verdict, List.isEmpty_cons, Bool.false_eq_true, ite_false, ne_eq, reduceCtorEq,
      not_false_eq_true, true_and]
    split <;> rename_i h
    · simp [h]
    · simp only [Bool.not_eq_true] at h
      split <;> rename_i hp
      · simp only [List.isEmpty_iff] at hp
        simp [h, hp, eq_comm]
      · simp only [List.isEmpty_iff] at hp
        simp [h, hp]

theorem verdict_preset (as : List String) (flag : String) (hne : as ≠ [])
    (hno : ∀ s ∈ as, ∀ e ∈ fwOf s, covers e flag = false) (hp : presets as ≠ []) :
    verdict (.arms as) flag = .unknown (presetWhy (presets as)) := by
  have hany : (carried as).any (covers · flag) = false := by
    rw [← Bool.not_eq_true, any_carried]
    intro ⟨s, hs, e, he, hc⟩
    simp [hno s hs e he] at hc
  cases as with
  | nil => exact absurd rfl hne
  | cons a t =>
    have : (presets (a :: t)).isEmpty = false := by
      cases h : presets (a :: t) with
      | nil => exact absurd h hp
      | cons _ _ => rfl
    simp [verdict, hany, this]

theorem mismatch_lists_every_flag (as : List String) (flag : String) (c : List String)
    (h : verdict (.arms as) flag = .mismatch c) : ∀ s ∈ as, ∀ e ∈ fwOf s, e ∈ c := by
  obtain ⟨-, -, -, rfl⟩ := (verdict_mismatch_iff as flag c).mp h
  intro s hs e he
  exact (mem_carried as e).mpr ⟨s, hs, he⟩

theorem covers_iff (entry flag : String) : covers entry flag = true ↔ entry = flag ∨ variantOf entry = flag := by
  simp [covers]

/-- What a citation says its run carried: the row's flag, no flag at all (an A/A run), or the named sibling flag. -/
inductive Role where
  | row
  | aa
  | sibling (flag : String)
  deriving DecidableEq, Repr

/-- Every flag entry and every `preset=<name>` any arm carried. -/
def applied (as : List String) : List String := carried as ++ (presets as).map ("preset=" ++ ·)

/-- The verdict on citing a run with facts `f` as an A/A run. -/
def aaVerdict : Facts → Verdict
  | .missing why => .unknown why
  | .arms as =>
    if as.isEmpty then .unknown noArm
    else if (applied as).isEmpty then .match
    else .mismatch (applied as)

/-- The verdict on citing a run with facts `f` from a row about `flag`, by the citation's role. -/
def judge (f : Facts) (flag : String) : Role → Verdict
  | .row => verdict f flag
  | .aa => aaVerdict f
  | .sibling s => verdict f s

theorem judge_row (f : Facts) (flag : String) : judge f flag .row = verdict f flag := rfl

theorem judge_aa (f : Facts) (flag : String) : judge f flag .aa = aaVerdict f := rfl

theorem judge_sibling (f : Facts) (flag s : String) : judge f flag (.sibling s) = verdict f s := rfl

theorem carried_nil_iff (as : List String) : carried as = [] ↔ ∀ s ∈ as, fwOf s = [] := by
  constructor
  · intro h s hs
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro e he
    have := (mem_carried as e).mpr ⟨s, hs, he⟩
    simp [h] at this
  · intro h
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro e he
    obtain ⟨s, hs, he⟩ := (mem_carried as e).mp he
    simp [h s hs] at he

theorem applied_nil_iff (as : List String) : applied as = [] ↔ ∀ s ∈ as, fwOf s = [] ∧ presetOf s = [] := by
  simp only [applied, List.append_eq_nil_iff, List.map_eq_nil_iff, carried_nil_iff, presets_nil_iff]
  constructor
  · rintro ⟨h1, h2⟩ s hs; exact ⟨h1 s hs, h2 s hs⟩
  · intro h; exact ⟨fun s hs => (h s hs).1, fun s hs => (h s hs).2⟩

theorem aa_missing (why : String) : aaVerdict (.missing why) = .unknown why := rfl

theorem aa_no_arm : aaVerdict (.arms []) = .unknown noArm := rfl

theorem aa_match_iff (as : List String) :
    aaVerdict (.arms as) = .match ↔ as ≠ [] ∧ ∀ s ∈ as, fwOf s = [] ∧ presetOf s = [] := by
  rw [← applied_nil_iff]
  cases as with
  | nil => simp [aaVerdict]
  | cons a t =>
    simp only [aaVerdict, List.isEmpty_cons, Bool.false_eq_true, ite_false, ne_eq, reduceCtorEq,
      not_false_eq_true, true_and]
    split <;> rename_i h <;> simp only [List.isEmpty_iff] at h <;> simp [h]

theorem aa_mismatch_iff (as : List String) (c : List String) :
    aaVerdict (.arms as) = .mismatch c ↔ as ≠ [] ∧ applied as ≠ [] ∧ c = applied as := by
  cases as with
  | nil => simp [aaVerdict]
  | cons a t =>
    simp only [aaVerdict, List.isEmpty_cons, Bool.false_eq_true, ite_false, ne_eq, reduceCtorEq,
      not_false_eq_true, true_and]
    split <;> rename_i h <;> simp only [List.isEmpty_iff] at h <;> simp [h, eq_comm]

theorem aa_ignores_flag (f : Facts) (flag flag' : String) : judge f flag .aa = judge f flag' .aa := rfl

theorem sibling_ignores_flag (f : Facts) (flag flag' s : String) :
    judge f flag (.sibling s) = judge f flag' (.sibling s) := rfl

/-- A citation: the run id, the flag of the row or note that cites it, and what it says the run carried. -/
structure Cite where
  run : String
  flag : String
  role : Role
  deriving DecidableEq, Repr

/-- Why a run the caller gave no facts for is unknown. -/
def notFetched : String := "no facts for this run were given"

/-- The facts of `run` in `runs` (the first entry wins). -/
def lookup (runs : List (String × Facts)) (run : String) : Facts :=
  match runs.find? (·.1 == run) with
  | some (_, f) => f
  | none => .missing notFetched

/-- The verdict on each citation, in order. -/
def check (runs : List (String × Facts)) (cs : List Cite) : List Verdict :=
  cs.map fun c => judge (lookup runs c.run) c.flag c.role

theorem check_length (runs : List (String × Facts)) (cs : List Cite) : (check runs cs).length = cs.length := by
  simp [check]

theorem check_unfetched (cs : List Cite) : ∀ v ∈ check [] cs, v = .unknown notFetched := by
  intro v hv
  simp only [check, List.mem_map] at hv
  obtain ⟨⟨run, flag, role⟩, -, rfl⟩ := hv
  cases role <;> rfl

#guard fwOf "?fw=morph.tween:waapi-scoped" == ["morph.tween:waapi-scoped"]
#guard fwOf "?preset=v2-proved&fw=a.b:c,d:e@plain" == ["a.b:c", "d:e@plain"]
#guard fwOf "" == []
#guard presetOf "?preset=v2-proved&fw=a:b" == ["v2-proved"]
#guard verdict (.arms ["", "", "?fw=morph.tween:waapi-scoped"]) "morph.tween:waapi" ==
  .mismatch ["morph.tween:waapi-scoped"]
#guard verdict (.arms ["", "", "?fw=morph.tween:waapi-scoped"]) "morph.tween:waapi-scoped" == .match
#guard verdict (.arms ["", "?fw=hero.exit:faithful", "?fw=hero.exit:faithful"]) "morph.tween:waapi" ==
  .mismatch ["hero.exit:faithful"]
#guard verdict (.arms ["", ""]) "nav:earn-no-transition" == .mismatch []
#guard verdict (.arms ["?fw=hero.countdown:one-chain@plain"]) "hero.countdown:one-chain" == .match
#guard verdict (.arms ["?fw=hero.countdown:one-chain@plain"]) "hero.countdown:one-chain@mui" ==
  .mismatch ["hero.countdown:one-chain@plain"]
#guard verdict (.arms ["", "?preset=v2-proved"]) "engine.scroll:batched" == .unknown (presetWhy ["v2-proved"])
#guard verdict (.arms ["?preset=v2-proved&fw=morph.tween:waapi"]) "morph.tween:waapi" == .match
#guard verdict (.arms []) "a:b" == .unknown noArm
#guard verdict (.missing "expired") "a:b" == .unknown "expired"
#guard aaVerdict (.arms ["", ""]) == .match
#guard aaVerdict (.arms ["", "?fw=a:b"]) == .mismatch ["a:b"]
#guard aaVerdict (.arms ["?preset=v2-proved"]) == .mismatch ["preset=v2-proved"]
#guard judge (.arms ["", "", "?fw=morph.tween:waapi-scoped"]) "morph.tween:waapi" (.sibling "morph.tween:waapi-scoped")
  == .match
#guard check [("1", .arms ["?fw=a:b"])] [⟨"1", "a:b", .row⟩, ⟨"2", "a:b", .row⟩, ⟨"1", "a:b", .aa⟩] ==
  [.match, .unknown notFetched, .mismatch ["a:b"]]

/-! ## Run ids and role markers in a ledger row's evidence -/

/-- A word character of a JavaScript regular expression `\b`. -/
def isWord (c : Char) : Bool := c.isAlphanum || c == '_'

/-- Each maximal run of word characters in `cs`, with the text after it; `w` is the word read so far, reversed. -/
def words : List Char → List Char → List (String × List Char)
  | [], w => if w.isEmpty then [] else [(String.ofList w.reverse, [])]
  | c :: cs, w =>
    if isWord c then words cs (c :: w)
    else if w.isEmpty then words cs []
    else (String.ofList w.reverse, c :: cs) :: words cs []

/-- A run id: a word of 10 to 12 digits. -/
def isRunId (t : String) : Bool := 10 ≤ t.length && t.length ≤ 12 && t.all Char.isDigit

/-- A flag `part:variant`: the part a letter then letters, digits or dots; the variant letters, digits or `_@-`. -/
def isFlag (t : String) : Bool :=
  match t.splitOn ":" with
  | [p, v] =>
    match p.toList with
    | c :: cs => c.isAlpha && cs.all (fun c => c.isAlphanum || c == '.') && v != "" &&
        v.toList.all (fun c => c.isAlphanum || ['_', '@', '-'].contains c)
    | [] => false
  | _ => false

/-- The role a marker right after a run id gives: ` (A/A)` an A/A run, ` (<part:variant>)` a sibling; else `.row`. -/
def markOf : List Char → Role
  | ' ' :: '(' :: tl =>
    let inner := tl.takeWhile (· != ')')
    if inner.length < tl.length then
      let t := String.ofList inner
      if t == "A/A" then .aa else if isFlag t then .sibling t else .row
    else .row
  | _ => .row

/-- Every run id in `ev`, in order, with the role of the marker after it. -/
def mentions (ev : String) : List (String × Role) :=
  (words ev.toList []).filterMap fun (t, rest) => if isRunId t then some (t, markOf rest) else none

/-- The marked roles of `run` among mentions `ms`, first occurrence first. -/
def marks (ms : List (String × Role)) (run : String) : List Role :=
  ((ms.filter (·.1 == run)).map (·.2)).filter (· != .row) |>.eraseDups

/-- The citations of `run` in a row about `flag` whose marked roles of `run` are `rs`. -/
def citesFor (flag run : String) : List Role → List Cite
  | [] => [⟨run, flag, .row⟩]
  | r :: rs => (r :: rs).map (⟨run, flag, ·⟩)

/-- The citations of evidence `ev` in a row about `flag`: one per marked role of a run, or the row's flag if none. -/
def citesOf (flag ev : String) : List Cite :=
  let ms := mentions ev
  (ms.map (·.1)).eraseDups.flatMap fun run => citesFor flag run (marks ms run)

theorem mem_marks (ms : List (String × Role)) (run : String) (r : Role) :
    r ∈ marks ms run ↔ (run, r) ∈ ms ∧ r ≠ .row := by
  simp only [marks, List.mem_eraseDups, List.mem_filter, List.mem_map, bne_iff_ne, ne_eq, beq_iff_eq]
  constructor
  · rintro ⟨⟨⟨run', r'⟩, ⟨hm, rfl⟩, rfl⟩, hr⟩; exact ⟨hm, hr⟩
  · rintro ⟨hm, hr⟩; exact ⟨⟨(run, r), ⟨hm, rfl⟩, rfl⟩, hr⟩

theorem mem_citesFor (flag run : String) (rs : List Role) (c : Cite) :
    c ∈ citesFor flag run rs ↔ c.run = run ∧ c.flag = flag ∧ (rs = [] ∧ c.role = .row ∨ c.role ∈ rs) := by
  obtain ⟨run', flag', role'⟩ := c
  cases rs with
  | nil => simp [citesFor, eq_comm]
  | cons r rs =>
    simp only [citesFor, List.mem_map, Cite.mk.injEq, reduceCtorEq, false_and, false_or]
    constructor
    · rintro ⟨x, hx, rfl, rfl, rfl⟩; exact ⟨rfl, rfl, hx⟩
    · rintro ⟨rfl, rfl, hx⟩; exact ⟨role', hx, rfl, rfl, rfl⟩

theorem mem_citesOf (flag ev : String) (c : Cite) :
    c ∈ citesOf flag ev ↔ c.flag = flag ∧ (∃ r, (c.run, r) ∈ mentions ev) ∧
      (marks (mentions ev) c.run = [] ∧ c.role = .row ∨ c.role ∈ marks (mentions ev) c.run) := by
  simp only [citesOf, List.mem_flatMap, List.mem_eraseDups, List.mem_map, mem_citesFor]
  constructor
  · rintro ⟨run, ⟨⟨run', r⟩, hm, rfl⟩, rfl, hf, h⟩; exact ⟨hf, ⟨r, hm⟩, h⟩
  · rintro ⟨hf, ⟨r, hm⟩, h⟩; exact ⟨c.run, ⟨(c.run, r), hm, rfl⟩, rfl, hf, h⟩

theorem cite_marked (flag ev run : String) (r : Role) (hr : r ≠ .row) :
    ⟨run, flag, r⟩ ∈ citesOf flag ev ↔ (run, r) ∈ mentions ev := by
  rw [mem_citesOf]
  simp only [true_and, hr, and_false, false_or, mem_marks, ne_eq, not_false_eq_true, and_true]
  exact ⟨fun h => h.2, fun h => ⟨⟨r, h⟩, h⟩⟩

theorem cite_row (flag ev run : String) :
    ⟨run, flag, .row⟩ ∈ citesOf flag ev ↔ (∃ r, (run, r) ∈ mentions ev) ∧ marks (mentions ev) run = [] := by
  rw [mem_citesOf]
  simp only [true_and, and_true, mem_marks, ne_eq, not_true_eq_false, and_false, or_false]

/-- A findings-ledger row: its id, its `flag` if any, and its evidence text. -/
structure Row where
  id : String
  flag : Option String
  evidence : String
  deriving DecidableEq, Repr

/-- The run ids of evidence `ev` that no marker in it follows, first occurrence first. -/
def unmarked (ev : String) : List String :=
  let ms := mentions ev
  ((ms.map (·.1)).eraseDups).filter fun run => marks ms run == []

/-- The citations of a row: by its `flag`, else only its marked runs, cited with flag `""`. -/
def rowCites (r : Row) : List Cite :=
  match r.flag with
  | some f => citesOf f r.evidence
  | none => (citesOf "" r.evidence).filter (·.role != .row)

/-- The rows with no flag and some unmarked run id, with those ids: reported, not checked. -/
def unflagged (rs : List Row) : List (String × List String) :=
  rs.filterMap fun r =>
    let runs := unmarked r.evidence
    if r.flag.isNone && !runs.isEmpty then some (r.id, runs) else none

theorem mem_unmarked (ev run : String) :
    run ∈ unmarked ev ↔ (∃ r, (run, r) ∈ mentions ev) ∧ marks (mentions ev) run = [] := by
  simp only [unmarked, List.mem_filter, List.mem_eraseDups, List.mem_map, beq_iff_eq]
  constructor
  · rintro ⟨⟨⟨run', r⟩, hm, rfl⟩, h⟩; exact ⟨⟨r, hm⟩, h⟩
  · rintro ⟨⟨r, hm⟩, h⟩; exact ⟨⟨(run, r), hm, rfl⟩, h⟩

theorem row_flag (r : Row) (f : String) (h : r.flag = some f) : rowCites r = citesOf f r.evidence := by
  simp [rowCites, h]

theorem row_no_flag (r : Row) (h : r.flag = none) (c : Cite) :
    c ∈ rowCites r ↔ c.flag = "" ∧ (c.run, c.role) ∈ mentions r.evidence ∧ c.role ≠ .row := by
  obtain ⟨run, flag, role⟩ := c
  simp only [rowCites, h, List.mem_filter, bne_iff_ne, ne_eq]
  constructor
  · rintro ⟨hc, hr⟩
    obtain ⟨rfl⟩ := ((mem_citesOf _ _ _).mp hc).1
    exact ⟨rfl, (cite_marked _ _ _ _ hr).mp hc, hr⟩
  · rintro ⟨rfl, hm, hr⟩
    exact ⟨(cite_marked _ _ _ _ hr).mpr hm, hr⟩

theorem row_no_flag_covers (r : Row) (h : r.flag = none) (run : String) (role : Role)
    (hm : (run, role) ∈ mentions r.evidence) : (∃ c ∈ rowCites r, c.run = run) ∨ run ∈ unmarked r.evidence := by
  cases hk : marks (mentions r.evidence) run with
  | nil => exact .inr ((mem_unmarked _ _).mpr ⟨⟨role, hm⟩, hk⟩)
  | cons k ks =>
    have hk' : k ∈ marks (mentions r.evidence) run := hk ▸ List.mem_cons_self
    obtain ⟨hmk, hne⟩ := (mem_marks _ _ _).mp hk'
    exact .inl ⟨⟨run, "", k⟩, (row_no_flag r h _).mpr ⟨rfl, hmk, hne⟩, rfl⟩

theorem mem_unflagged (rs : List Row) (r : Row) (hr : r ∈ rs) (hf : r.flag = none) (run : String)
    (hm : run ∈ unmarked r.evidence) : ∃ runs, (r.id, runs) ∈ unflagged rs ∧ run ∈ runs := by
  refine ⟨unmarked r.evidence, ?_, hm⟩
  have hne : (unmarked r.evidence).isEmpty = false := by
    cases h : unmarked r.evidence with
    | nil => simp [h] at hm
    | cons _ _ => rfl
  simp only [unflagged, List.mem_filterMap]
  exact ⟨r, hr, by simp [hf, hne]⟩

#guard mentions "A/A 39466378530, runs 39457767229 (morph.tween:waapi-scoped) and 39464322751 (A/A)" ==
  [("39466378530", .row), ("39457767229", .sibling "morph.tween:waapi-scoped"), ("39464322751", .aa)]
#guard mentions "39463486725 (flag), 39471466367 (6 runs below), 39471466367(A/A), x39466378530, 123456789" ==
  [("39463486725", .row), ("39471466367", .row), ("39471466367", .row)]
#guard mentions "39466378530 (A/A" == [("39466378530", .row)]
#guard mentions "39466378530 (hero.exit:faithful A/A)" == [("39466378530", .row)]
#guard citesOf "a:b" "39466378530 (A/A) here; again 39466378530 and 39400000000, 39400000000 (c:d)" ==
  [⟨"39466378530", "a:b", .aa⟩, ⟨"39400000000", "a:b", .sibling "c:d"⟩]
#guard citesOf "a:b" "39400000000 (A/A), 39400000000 (c:d)" ==
  [⟨"39400000000", "a:b", .aa⟩, ⟨"39400000000", "a:b", .sibling "c:d"⟩]
#guard unflagged [⟨"r1", none, "runs 39400000000"⟩, ⟨"r2", some "a:b", "39400000000"⟩, ⟨"r3", none, "none"⟩] ==
  [("r1", ["39400000000"])]
#guard unflagged [⟨"r", none, "39400000000 (a:b), 39400000001 (A/A)"⟩] == []
#guard unflagged [⟨"r", none, "39400000000 (a:b), 39400000001 and 39400000000"⟩] == [("r", ["39400000001"])]
#guard rowCites ⟨"r", none, "39400000000 (a:b), 39400000001, 39400000002 (A/A)"⟩ ==
  [⟨"39400000000", "", .sibling "a:b"⟩, ⟨"39400000002", "", .aa⟩]
#guard rowCites ⟨"r", some "c:d", "39400000000 (a:b), 39400000001"⟩ ==
  [⟨"39400000000", "c:d", .sibling "a:b"⟩, ⟨"39400000001", "c:d", .row⟩]

/-! ## Wire codec of `gate.runCite` -/

/-- Decode one run: `{run, arms: [search]}` or `{run, missing: why}`. -/
def factsOfJson (j : Json) : Except String (String × Facts) := do
  let run ← j.getObjValAs? String "run"
  match j.getObjValAs? (Array String) "arms" with
  | .ok as => pure (run, .arms as.toList)
  | .error _ =>
    match j.getObjValAs? String "missing" with
    | .ok w => pure (run, .missing w)
    | .error _ => throw s!"run {run}: neither arms nor missing"

/-- Decode a role: no `role` or `"row"`, `"aa"`, or `"sibling"` with its `sibling` flag. -/
def roleOfJson (j : Json) : Except String Role :=
  match j.getObjValAs? String "role" with
  | .error _ | .ok "row" => pure .row
  | .ok "aa" => pure .aa
  | .ok "sibling" =>
    match j.getObjValAs? String "sibling" with
    | .ok s => pure (.sibling s)
    | .error _ => throw "role sibling without a sibling flag"
  | .ok r => throw s!"unknown role {r}"

/-- Decode one citation `{run, flag, role?, sibling?}`. -/
def citeOfJson (j : Json) : Except String Cite := do
  pure ⟨← j.getObjValAs? String "run", ← j.getObjValAs? String "flag", ← roleOfJson j⟩

/-- Decode one row `{id, flag?, evidence}`; a `flag` that is not a string counts as none. -/
def rowOfJson (j : Json) : Except String Row := do
  pure ⟨← j.getObjValAs? String "id", (j.getObjValAs? String "flag").toOption, ← j.getObjValAs? String "evidence"⟩

/-- The role fields of a citation's reply; none for `.row`. -/
def roleFields : Role → List (String × Json)
  | .row => []
  | .aa => [("role", "aa")]
  | .sibling s => [("role", "sibling"), ("sibling", .str s)]

/-- The verdict fields of a reply. -/
def verdictFields : Verdict → List (String × Json)
  | .match => [("verdict", "match")]
  | .mismatch cs => [("verdict", "mismatch"), ("carried", .arr (cs.toArray.map .str))]
  | .unknown w => [("verdict", "unknown"), ("why", .str w)]

/-- Encode one verdict next to its citation and `extra` fields. -/
def verdictJson (extra : List (String × Json)) (c : Cite) (v : Verdict) : Json :=
  Json.mkObj (extra ++ [("run", .str c.run), ("flag", .str c.flag)] ++ roleFields c.role ++ verdictFields v)

/-- An optional array field: absent is `none`. -/
def optArr (req : Json) (k : String) : Except String (Option (Array Json)) :=
  match req.getObjVal? k with
  | .error _ => pure none
  | .ok _ => some <$> req.getObjValAs? (Array Json) k

/-- `gate.runCite`: `{runs, cites?, rows?}` to `{verdicts, unflagged?}` (`unflagged` when `rows` is given). -/
def reply (req : Json) : Except String (List (String × Json)) := do
  let runs ← (← req.getObjValAs? (Array Json) "runs").toList.mapM factsOfJson
  let cj ← optArr req "cites"
  let rj ← optArr req "rows"
  if cj.isNone && rj.isNone then throw "neither cites nor rows"
  let cs ← (cj.getD #[]).toList.mapM citeOfJson
  let rs ← (rj.getD #[]).toList.mapM rowOfJson
  let fromCites := (cs.zip (check runs cs)).map fun (c, v) => verdictJson [] c v
  let fromRows := rs.flatMap fun r =>
    let rc := rowCites r
    (rc.zip (check runs rc)).map fun (c, v) => verdictJson [("row", .str r.id)] c v
  let uf := (unflagged rs).map fun (id, ns) => Json.mkObj [("row", .str id), ("runs", .arr (ns.toArray.map .str))]
  pure ([("verdicts", .arr (fromCites ++ fromRows).toArray)] ++
    if rj.isSome then [("unflagged", .arr uf.toArray)] else [])

private def replyText (s : String) : String :=
  match Json.parse s >>= reply with
  | .ok r => (Json.mkObj r).compress
  | .error e => e

#guard replyText "{\"runs\":[{\"run\":\"7\",\"arms\":[\"\",\"?fw=a:b\"]}],\"cites\":[{\"run\":\"7\",\"flag\":\"a:c\"}]}" ==
  "{\"verdicts\":[{\"carried\":[\"a:b\"],\"flag\":\"a:c\",\"run\":\"7\",\"verdict\":\"mismatch\"}]}"
#guard replyText "{\"runs\":[{\"run\":\"7\"}],\"cites\":[]}" == "run 7: neither arms nor missing"
#guard replyText "{\"runs\":[]}" == "neither cites nor rows"
#guard replyText "{\"runs\":[],\"cites\":[{\"run\":\"7\",\"flag\":\"a:c\",\"role\":\"bb\"}]}" == "unknown role bb"

/-! ## Golden vectors -/

/-- Request text of a golden case. -/
private def req (runs cites : String) : String := s!"\{\"op\":\"gate.runCite\",\"runs\":[{runs}],\"cites\":[{cites}]}"

/-- Request text of a golden case over ledger rows. -/
private def reqRows (runs rows : String) : String := s!"\{\"op\":\"gate.runCite\",\"runs\":[{runs}],\"rows\":[{rows}]}"

/-- The golden cases `(name, request)`; the first holds the facts of run 39457767229 at one width. -/
def cases : List (String × String) := [
  ("incident 2026-10-21: run 39457767229 carried morph.tween:waapi-scoped, cited for morph.tween:waapi",
    req "{\"run\":\"39457767229\",\"arms\":[\"\",\"\",\"?fw=morph.tween:waapi-scoped\"]}"
      "{\"run\":\"39457767229\",\"flag\":\"morph.tween:waapi\"},{\"run\":\"39457767229\",\"flag\":\"morph.tween:waapi-scoped\"}"),
  ("a run that carried another flag: a citation for a flag it did not carry is a mismatch",
    req "{\"run\":\"1\",\"arms\":[\"\",\"\",\"?fw=hero.exit:faithful\"]}"
      "{\"run\":\"1\",\"flag\":\"morph.tween:waapi\"},{\"run\":\"1\",\"flag\":\"hero.exit:faithful\"}"),
  ("a run with no query on any arm carried nothing",
    req "{\"run\":\"2\",\"arms\":[\"\",\"\"]}" "{\"run\":\"2\",\"flag\":\"nav:earn-no-transition\"}"),
  ("an @impl entry stands for its variant; an @impl citation needs that impl",
    req "{\"run\":\"3\",\"arms\":[\"?fw=hero.countdown:one-chain@plain\"]}"
      "{\"run\":\"3\",\"flag\":\"hero.countdown:one-chain\"},{\"run\":\"3\",\"flag\":\"hero.countdown:one-chain@plain\"},{\"run\":\"3\",\"flag\":\"hero.countdown:one-chain@mui\"}"),
  ("several flags in one fw parameter, next to a preset",
    req "{\"run\":\"4\",\"arms\":[\"?preset=v2-proved&fw=hero.countdown:strip,morph.countdown:strip\"]}"
      "{\"run\":\"4\",\"flag\":\"morph.countdown:strip\"},{\"run\":\"4\",\"flag\":\"engine.scroll:batched\"}"),
  ("a preset run: a flag outside its fw parameter is unknown",
    req "{\"run\":\"5\",\"arms\":[\"\",\"?preset=v2-proved\"]}" "{\"run\":\"5\",\"flag\":\"engine.scroll:batched\"}"),
  ("expired or not a gate run: unknown with the reason given",
    req "{\"run\":\"6\",\"missing\":\"no gate artifact\"}" "{\"run\":\"6\",\"flag\":\"a:b\"}"),
  ("no facts for the run; no arm in the artifacts",
    req "{\"run\":\"8\",\"arms\":[]}" "{\"run\":\"9\",\"flag\":\"a:b\"},{\"run\":\"8\",\"flag\":\"a:b\"}"),
  ("a prefix of a carried flag is not that flag",
    req "{\"run\":\"10\",\"arms\":[\"?fw=morph.tween:waapi\"]}" "{\"run\":\"10\",\"flag\":\"morph.tween:waapi-\"},{\"run\":\"10\",\"flag\":\"morph.tween:waap\"}"),
  ("a run without facts: refused", "{\"op\":\"gate.runCite\",\"runs\":[{\"run\":\"11\"}],\"cites\":[]}"),
  ("neither cites nor rows: refused", "{\"op\":\"gate.runCite\",\"runs\":[]}"),
  ("role aa: a run with no fw and no preset on any arm matches",
    req "{\"run\":\"12\",\"arms\":[\"\",\"\",\"\"]}" "{\"run\":\"12\",\"flag\":\"morph.tween:waapi\",\"role\":\"aa\"}"),
  ("role aa: a run that carried a flag or a preset is a mismatch listing them",
    req "{\"run\":\"13\",\"arms\":[\"\",\"?fw=morph.tween:waapi-scoped\"]},{\"run\":\"14\",\"arms\":[\"\",\"?preset=v2-proved\"]}"
      "{\"run\":\"13\",\"flag\":\"morph.tween:waapi\",\"role\":\"aa\"},{\"run\":\"14\",\"flag\":\"a:b\",\"role\":\"aa\"}"),
  ("role aa: no arm or no artifact is unknown",
    req "{\"run\":\"15\",\"arms\":[]},{\"run\":\"16\",\"missing\":\"no gate artifact\"}"
      "{\"run\":\"15\",\"flag\":\"a:b\",\"role\":\"aa\"},{\"run\":\"16\",\"flag\":\"a:b\",\"role\":\"aa\"}"),
  ("role sibling: judged against the sibling, not the row's flag",
    req "{\"run\":\"39457767229\",\"arms\":[\"\",\"\",\"?fw=morph.tween:waapi-scoped\"]}"
      "{\"run\":\"39457767229\",\"flag\":\"morph.tween:waapi\",\"role\":\"sibling\",\"sibling\":\"morph.tween:waapi-scoped\"},{\"run\":\"39457767229\",\"flag\":\"morph.tween:waapi-scoped\",\"role\":\"sibling\",\"sibling\":\"morph.tween:waapi\"}"),
  ("a sibling role without its flag: refused",
    req "" "{\"run\":\"1\",\"flag\":\"a:b\",\"role\":\"sibling\"}"),
  ("ledger rows: ' (A/A)' and ' (part:variant)' right after a run id set its role; a marked run is not cited for the row's flag",
    reqRows "{\"run\":\"39466378530\",\"arms\":[\"\",\"\",\"\"]},{\"run\":\"39457767229\",\"arms\":[\"\",\"\",\"?fw=morph.tween:waapi-scoped\"]},{\"run\":\"39449092483\",\"arms\":[\"\",\"\",\"?fw=morph.tween:waapi\"]}"
      "{\"id\":\"morph.tween.waapi.falsified\",\"flag\":\"morph.tween:waapi\",\"evidence\":\"fixed driver, 39466378530 (A/A); waapi runs 39449092483 and waapi-scoped runs 39457767229 (morph.tween:waapi-scoped); again 39457767229, 39466378530\"}"),
  ("ledger rows: prose that is not a marker leaves the row's flag",
    reqRows "{\"run\":\"39466378530\",\"arms\":[\"\",\"\",\"\"]},{\"run\":\"39464294630\",\"arms\":[\"\",\"\"]}"
      "{\"id\":\"r\",\"flag\":\"nav:earn-no-transition\",\"evidence\":\"A/A 39466378530; 39464294630 and 39464322751 (A/A); 39400000001 (hero.exit:faithful A/A); 39400000002(A/A); 39400000003 (flag); 394000000 and x39400000004\"}"),
  ("ledger rows: a row with no flag checks its marked runs and reports its unmarked ones; a row without run ids is neither",
    reqRows "{\"run\":\"39452631146\",\"arms\":[\"\",\"\",\"?fw=hero.exit:scoped\"]},{\"run\":\"39456741492\",\"arms\":[\"\",\"\",\"?fw=hero.exit:faithful\"]}"
      "{\"id\":\"hero.exit.scoped.inline\",\"evidence\":\"runs 39448209903, 39452631146 (hero.exit:scoped), 39456741492 (A/A)\"},{\"id\":\"n\",\"flag\":3,\"evidence\":\"39400000000\"},{\"id\":\"none\",\"evidence\":\"no run\"}"),
  ("ledger rows: a row with no flag whose every run is marked is checked in full and not reported",
    reqRows "{\"run\":\"39448209903\",\"arms\":[\"\",\"\",\"?fw=hero.exit:scoped\"]},{\"run\":\"39462188464\",\"arms\":[\"\",\"\",\"\"]}"
      "{\"id\":\"hero.exit.scoped.inline\",\"evidence\":\"runs 39448209903 (hero.exit:scoped), 39462188464 (A/A)\"}")]

/-- One golden line `{name, request, response}`; `response` is the reply `fwcore` gives without its `id`. -/
def line (c : String × String) : Json :=
  let request := (Json.parse c.2).toOption.getD (Json.mkObj [("unparsable", .str c.2)])
  let response := match reply request with
    | .ok r => Json.mkObj r
    | .error e => Json.mkObj [("error", .str e)]
  Json.mkObj [("name", .str c.1), ("request", request), ("response", response)]

/-- Where the golden lives, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/gate/run-cite.jsonl"

/-- Write, or with `--check` verify, the golden file; exit 1 when the checked-in file is stale. -/
def run (args : List String) : IO UInt32 := do
  let text := String.join (cases.map fun c => (line c).compress ++ "\n")
  if !args.contains "--check" then
    IO.FS.writeFile goldenPath text
    IO.println s!"run-cite golden: {cases.length} lines written"
    return 0
  let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
  if cur != text then
    IO.println s!"run-cite golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/RunCiteGolden.lean)"
    return 1
  IO.println s!"run-cite golden: {cases.length} lines, up to date"
  return 0

end Fw.Gate.RunCite
