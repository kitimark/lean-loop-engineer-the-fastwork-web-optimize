/-!
# Builds tab: open a preview at a chosen search

Two pure decisions. `validate` says whether a pasted URL search is one the site accepts, and gives its canonical form or the
reasons. It is the rule of `apps/site/src/registry/resolve.ts` (`?preset=` then `?fw=part:variant[@impl]`, one preset, `extends`,
`requires`, `conflicts`) over registry facts the I/O glue reads, behind a charset allowlist that runs first. `decide` says
what an Open click does: reuse a serving preview of the commit, wait for a building one, rebuild the slot, or start.
The wire ops are `console.buildsSearch` and `console.buildsOpen`.
-/
namespace Fw.Console.BuildsOpen

/-! ## Registry facts -/

/-- One part of the site registry (`part.json`): variants in file order (the head is the default), impls, rules. -/
structure PartFact where
  id : String
  variants : List String
  impls : List String
  requires : List (String × List String)
  conflicts : List (String × List String)

/-- One preset file: its name, optional `extends`, and its own `fw` entries (`part` to `variant` or `variant@impl`). -/
structure PresetFact where
  name : String
  base : Option String
  fw : List (String × String)

/-! ## Charset and syntax -/

/-- The longest search the console takes. -/
def maxLen : Nat := 2000

/-- A search character: ASCII letter or digit, or one of `. : , - _ @ = &`. No `%`, `+`, `#`, space or quote. -/
def okChar (c : Char) : Bool :=
  c.isAlphanum || c == '.' || c == ':' || c == ',' || c == '-' || c == '_' || c == '@' || c == '=' || c == '&'

/-- The search without one leading `?`. -/
def body (s : String) : String := if s.startsWith "?" then (s.drop 1).toString else s

/-- A parameter `k=v` (the value is everything after the first `=`; no `=` gives an empty value). -/
def splitParam (seg : String) : String × String :=
  match seg.splitOn "=" with
  | [] => ("", "")
  | k :: rest => (k, "=".intercalate rest)

/-- The parameters of a search body, in order; empty segments are skipped (as `URLSearchParams` does). -/
def params (b : String) : List (String × String) :=
  ((b.splitOn "&").filter (· != "")).map splitParam

/-- The values of every parameter named `k`. -/
def valuesOf (k : String) (ps : List (String × String)) : List String :=
  (ps.filter (·.1 == k)).map (·.2)

/-- The `?fw=` entries: every `fw` value split at `,`, empty entries dropped. -/
def fwEntries (ps : List (String × String)) : List String :=
  ((valuesOf "fw" ps).flatMap (·.splitOn ",")).filter (· != "")

/-- `part:variant` or `part:variant@impl`; the part has no `@`, no piece is empty (the site's `splitEntry`). -/
def splitEntry (e : String) : Option (String × String × Option String) :=
  match e.splitOn ":" with
  | [id, rest] =>
    if id == "" || id.contains '@' then none else
    match rest.splitOn "@" with
    | [v] => if v == "" then none else some (id, v, none)
    | [v, i] => if v == "" || i == "" then none else some (id, v, some i)
    | _ => none
  | _ => none

/-! ## Resolution (the site's `resolve`) -/

/-- The errors so far (in the order the site reports them) and the chosen variant of each part. -/
structure St where
  errs : List String
  sel : List (String × String)

/-- Set the chosen variant of a part. -/
def setSel (sel : List (String × String)) (id v : String) : List (String × String) :=
  if sel.any (·.1 == id) then sel.map (fun e => if e.1 == id then (id, v) else e) else sel ++ [(id, v)]

/-- Choose `variant` (and `impl`) for part `id`, or add an error; `src` names where the entry came from. -/
def applyOne (parts : List PartFact) (st : St) (id variant : String) (impl : Option String) (src : String) : St :=
  match parts.find? (·.id == id) with
  | none => { st with errs := st.errs ++ [s!"{src}: unknown part \"{id}\""] }
  | some p =>
    if !(p.variants.contains variant) then
      { st with errs := st.errs ++ [s!"{src}: part \"{id}\" has no variant \"{variant}\""] }
    else
      let st1 := { st with sel := setSel st.sel id variant }
      match impl with
      | none => st1
      | some i =>
        if p.impls.contains i then st1
        else { st1 with errs := st1.errs ++ [s!"{src}: part \"{id}\" has no impl \"{i}\""] }

/-- Own entries over base entries; a key already present keeps its place. -/
def mergeInto (base own : List (String × String)) : List (String × String) :=
  own.foldl (fun a e =>
    if a.any (·.1 == e.1) then a.map (fun x => if x.1 == e.1 then (e.1, e.2) else x) else a ++ [e]) base

/-- The entries of a preset with its `extends` chain resolved (base first), and the errors found on the way. `fuel` bounds the chain. -/
def presetEntries (presets : List PresetFact) (name : String) (seen errs : List String) :
    Nat → (List (String × String)) × List String
  | 0 => ([], errs)
  | n + 1 =>
    match presets.find? (·.name == name) with
    | none => ([], errs ++ [s!"unknown preset \"{name}\""])
    | some p =>
      if seen.contains name then ([], errs ++ [s!"preset cycle: {" -> ".intercalate (seen ++ [name])}"])
      else
        match p.base with
        | some bn =>
          let r := presetEntries presets bn (seen ++ [name]) errs n
          (mergeInto r.1 p.fw, r.2)
        | none => (mergeInto [] p.fw, errs)

/-- The chosen variant of every part before any request: the head variant. -/
def initSel (parts : List PartFact) : List (String × String) :=
  parts.map fun p => (p.id, p.variants.headD "faithful")

/-- The `part:variant` strings the selection holds. -/
def selected (sel : List (String × String)) : List String := sel.map fun e => e.1 ++ ":" ++ e.2

/-- The key `part:variant` of a part in the selection. -/
def keyOf (sel : List (String × String)) (p : PartFact) : String := p.id ++ ":" ++ ((sel.lookup p.id).getD "")

/-- The violated `requires` (first) and `conflicts` of one part in the selection. -/
def partErrors (sel : List (String × String)) (p : PartFact) : List String :=
  (((p.requires.lookup (keyOf sel p)).getD []).filter (fun n => !(selected sel).contains n)).map
    (fun n => keyOf sel p ++ " requires " ++ n) ++
  (((p.conflicts.lookup (keyOf sel p)).getD []).filter (fun b => (selected sel).contains b)).map
    (fun b => keyOf sel p ++ " conflicts with " ++ b)

/-- Violated `requires` and `conflicts` of the selection, part by part. -/
def ruleErrors (parts : List PartFact) (sel : List (String × String)) : List String :=
  parts.flatMap (partErrors sel)

/-- Apply the entries of preset `name`. -/
def applyPreset (parts : List PartFact) (name : String) (st : St) (ents : List (String × String)) : St :=
  ents.foldl (fun s e =>
    let ps := e.2.splitOn "@"
    applyOne parts s e.1 (ps.headD "") ps[1]? s!"preset \"{name}\"") st

/-- Apply one `?fw=` entry. -/
def applyFwEntry (parts : List PartFact) (st : St) (e : String) : St :=
  match splitEntry e with
  | none => { st with errs := st.errs ++ [s!"?fw=: cannot parse \"{e}\" (expected part:variant)"] }
  | some (id, v, i) => applyOne parts st id v i "?fw="

/-- Errors if any, else the violated rules. -/
def finish (parts : List PartFact) (st : St) : List String :=
  if st.errs.isEmpty then ruleErrors parts st.sel else st.errs

/-- The state after the `?preset=` values: one preset applies; a second `?preset=` is an error. -/
def stage1 (parts : List PartFact) (presets : List PresetFact) (names : List String) : St :=
  let st0 : St := { errs := if names.length > 1 then ["only one ?preset= is allowed"] else [], sel := initSel parts }
  match names.head? with
  | none => st0
  | some name =>
    let r := presetEntries presets name [] st0.errs (presets.length + 2)
    applyPreset parts name { st0 with errs := r.2 } r.1

/-- Every error of a request: the preset values (each `?preset=`, in order) and the `?fw=` entries. -/
def errorsOf (parts : List PartFact) (presets : List PresetFact) (names fw : List String) : List String :=
  finish parts (fw.foldl (applyFwEntry parts) (stage1 parts presets names))

/-! ## The verdict -/

/-- The accepted search in canonical form, or the reasons. -/
inductive Verdict where
  | ok (canonical : String)
  | refused (reasons : List String)
deriving Repr, DecidableEq

/-- The reason for a search that is too long. -/
def lengthReason : String := "search is longer than 2000 characters"

/-- The reason for a search with a character outside the allowlist. -/
def charsetReason : String := "search has a character outside A-Z a-z 0-9 . : , - _ @ = & (after one leading ?)"

/-- The canonical search: the preset first, then one `fw` list; empty when neither is given. -/
def canonical (preset : Option String) (fw : List String) : String :=
  let ps := (match preset with | some n => ["preset=" ++ n] | none => []) ++
    (if fw.isEmpty then [] else ["fw=" ++ ",".intercalate fw])
  if ps.isEmpty then "" else "?" ++ "&".intercalate ps

/-- The verdict for the errors of a request: no error accepts it. -/
def verdictOf (names fw : List String) : List String → Verdict
  | [] => .ok (canonical names.head? fw)
  | es => .refused es

/-- Accept a search: length, then charset, then the site's rules. -/
def validate (parts : List PartFact) (presets : List PresetFact) (search : String) : Verdict :=
  if search.length > maxLen then .refused [lengthReason]
  else if !((body search).toList.all okChar) then .refused [charsetReason]
  else
    let ps := params (body search)
    verdictOf (valuesOf "preset" ps) (fwEntries ps) (errorsOf parts presets (valuesOf "preset" ps) (fwEntries ps))

/-! ### Theorems: the verdict, one per branch -/

/-- Too long: refused, before anything else is read. -/
theorem validate_long (parts presets) (s : String) (h : s.length > maxLen) :
    validate parts presets s = .refused [lengthReason] := by
  simp [validate, h]

/-- A bad character: refused with the charset reason, before any parsing. -/
theorem validate_charset (parts presets) (s : String) (hl : ¬ s.length > maxLen)
    (h : (body s).toList.all okChar = false) :
    validate parts presets s = .refused [charsetReason] := by
  simp [validate, hl, h]

/-- No error: the canonical search. -/
theorem verdictOf_ok (names fw) : verdictOf names fw [] = .ok (canonical names.head? fw) := rfl

/-- Errors: refused with exactly those. -/
theorem verdictOf_refused (names fw) (es : List String) (h : es ≠ []) : verdictOf names fw es = .refused es := by
  cases es with
  | nil => exact absurd rfl h
  | cons a t => rfl

/-- Past the charset, accepted exactly when the site's rules report no error; the answer is the canonical search. -/
theorem validate_ok (parts presets) (s : String) (hl : ¬ s.length > maxLen)
    (hc : (body s).toList.all okChar = true)
    (h : errorsOf parts presets (valuesOf "preset" (params (body s))) (fwEntries (params (body s))) = []) :
    validate parts presets s = .ok (canonical (valuesOf "preset" (params (body s))).head? (fwEntries (params (body s)))) := by
  simp [validate, hl, hc, h, verdictOf]

/-- Past the charset, refused with exactly the errors the site's rules report. -/
theorem validate_refused (parts presets) (s : String) (hl : ¬ s.length > maxLen)
    (hc : (body s).toList.all okChar = true) (es : List String) (hne : es ≠ [])
    (h : errorsOf parts presets (valuesOf "preset" (params (body s))) (fwEntries (params (body s))) = es) :
    validate parts presets s = .refused es := by
  simp [validate, hl, hc, h, verdictOf_refused _ _ _ hne]

#guard validate [] [] "" == .ok ""
#guard validate [] [] "?" == .ok ""
#guard validate [] [] "?a%20b" == .refused [charsetReason]

/-! ### Theorems: the site's rules -/

theorem applyOne_len (parts) (st : St) (id v : String) (i : Option String) (src : String) :
    st.errs.length ≤ (applyOne parts st id v i src).errs.length := by
  unfold applyOne
  split
  · simp
  · split
    · simp
    · split
      · simp
      · split <;> simp

theorem applyOne_unknown_part (parts) (st : St) (id v : String) (i : Option String) (src : String)
    (h : parts.find? (·.id == id) = none) : 0 < (applyOne parts st id v i src).errs.length := by
  unfold applyOne; simp [h]

theorem applyOne_unknown_variant (parts) (st : St) (id v : String) (i : Option String) (src : String)
    (p : PartFact) (hp : parts.find? (·.id == id) = some p) (hv : p.variants.contains v = false) :
    0 < (applyOne parts st id v i src).errs.length := by
  unfold applyOne
  have hv' : v ∉ p.variants := by simpa using hv
  simp [hp, hv']

theorem applyOne_unknown_impl (parts) (st : St) (id v i : String) (src : String)
    (p : PartFact) (hp : parts.find? (·.id == id) = some p) (hv : p.variants.contains v = true)
    (hi : p.impls.contains i = false) : 0 < (applyOne parts st id v (some i) src).errs.length := by
  unfold applyOne
  have hv' : v ∈ p.variants := by simpa using hv
  have hi' : i ∉ p.impls := by simpa using hi
  simp [hp, hv', hi']

/-- Folding keeps errors. -/
theorem foldl_len {α} (g : St → α → St) (hm : ∀ s a, s.errs.length ≤ (g s a).errs.length) (l : List α) (st : St) :
    st.errs.length ≤ (l.foldl g st).errs.length := by
  induction l generalizing st with
  | nil => simp
  | cons b l ih => exact Nat.le_trans (hm st b) (ih (g st b))

/-- One member of the list that always adds an error leaves at least one. -/
theorem foldl_pos {α} (g : St → α → St) (hm : ∀ s a, s.errs.length ≤ (g s a).errs.length) (a0 : α) (l : List α)
    (st : St) (h : a0 ∈ l) (hp : ∀ s, 0 < (g s a0).errs.length) : 0 < (l.foldl g st).errs.length := by
  induction l generalizing st with
  | nil => cases h
  | cons b l ih =>
    simp only [List.foldl_cons]
    rcases List.mem_cons.1 h with rfl | h'
    · exact Nat.lt_of_lt_of_le (hp st) (foldl_len g hm l _)
    · exact ih _ h'

theorem applyFwEntry_len (parts) (st : St) (e : String) : st.errs.length ≤ (applyFwEntry parts st e).errs.length := by
  unfold applyFwEntry
  split
  · simp
  · exact applyOne_len ..

theorem applyPreset_len (parts) (name : String) (st : St) (ents) :
    st.errs.length ≤ (applyPreset parts name st ents).errs.length := by
  unfold applyPreset
  exact foldl_len _ (fun s e => applyOne_len ..) ents st

theorem finish_pos (parts) (st : St) (h : 0 < st.errs.length) : finish parts st ≠ [] := by
  unfold finish
  cases hs : st.errs with
  | nil => simp [hs] at h
  | cons a t => simp

theorem finish_clean (parts) (st : St) (h : st.errs = []) : finish parts st = ruleErrors parts st.sel := by
  unfold finish; simp [h]

/-- The request errors are never empty once the preset stage left an error. -/
theorem errorsOf_of_stage (parts : List PartFact) (fw : List String) (st1 : St) (h : 0 < st1.errs.length) :
    finish parts (fw.foldl (applyFwEntry parts) st1) ≠ [] :=
  finish_pos _ _ (Nat.lt_of_lt_of_le h (foldl_len _ (fun s a => applyFwEntry_len parts s a) fw st1))

/-- The preset walk only adds errors. -/
theorem presetEntries_len (presets) (name : String) (seen errs : List String) (n : Nat) :
    errs.length ≤ (presetEntries presets name seen errs n).2.length := by
  induction n generalizing name seen with
  | zero => simp [presetEntries]
  | succ n ih =>
    unfold presetEntries
    split
    · simp
    · split
      · simp
      · split
        · rename_i bn _
          exact ih bn (seen ++ [name])
        · simp

theorem stage1_two (parts presets) (names : List String) (h : 1 < names.length) :
    0 < (stage1 parts presets names).errs.length := by
  unfold stage1
  have hl : ((if names.length > 1 then ["only one ?preset= is allowed"] else []) : List String).length = 1 := by
    simp [h]
  cases hh : names.head? with
  | none => simp [hl]
  | some name =>
    simp only []
    refine Nat.lt_of_lt_of_le ?_ (applyPreset_len _ _ _ _)
    exact Nat.lt_of_lt_of_le (by simp [hl]) (presetEntries_len presets name [] _ _)

/-- Two `?preset=` values: refused. -/
theorem errorsOf_two_presets (parts presets) (names fw : List String) (h : 1 < names.length) :
    errorsOf parts presets names fw ≠ [] :=
  errorsOf_of_stage _ _ _ (stage1_two parts presets names h)

/-- An unknown part in `?fw=`: refused. -/
theorem errorsOf_unknown_part (parts presets names fw) (e id v : String) (i : Option String) (he : e ∈ fw)
    (hs : splitEntry e = some (id, v, i)) (hf : parts.find? (·.id == id) = none) :
    errorsOf parts presets names fw ≠ [] := by
  unfold errorsOf
  apply finish_pos
  exact foldl_pos _ (fun s a => applyFwEntry_len parts s a) e fw _ he (fun s => by
    unfold applyFwEntry; rw [hs]; exact applyOne_unknown_part _ _ _ _ _ _ hf)

/-- An unknown variant in `?fw=`: refused. -/
theorem errorsOf_unknown_variant (parts presets names fw) (e id v : String) (i : Option String) (he : e ∈ fw)
    (hs : splitEntry e = some (id, v, i)) (p : PartFact) (hp : parts.find? (·.id == id) = some p)
    (hv : p.variants.contains v = false) : errorsOf parts presets names fw ≠ [] := by
  unfold errorsOf
  apply finish_pos
  exact foldl_pos _ (fun s a => applyFwEntry_len parts s a) e fw _ he (fun s => by
    unfold applyFwEntry; rw [hs]; exact applyOne_unknown_variant _ _ _ _ _ _ p hp hv)

/-- An entry that does not parse: refused. -/
theorem errorsOf_unparsable (parts presets names fw) (e : String) (he : e ∈ fw) (hs : splitEntry e = none) :
    errorsOf parts presets names fw ≠ [] := by
  unfold errorsOf
  apply finish_pos
  exact foldl_pos _ (fun s a => applyFwEntry_len parts s a) e fw _ he (fun s => by
    unfold applyFwEntry; rw [hs]; simp)

/-- A violated `requires`: refused. -/
theorem ruleErrors_requires (parts) (sel : List (String × String)) (p : PartFact) (hp : p ∈ parts) (n : String)
    (hn : n ∈ ((p.requires.lookup (p.id ++ ":" ++ ((sel.lookup p.id).getD ""))).getD []))
    (hmiss : (selected sel).contains n = false) : ruleErrors parts sel ≠ [] := by
  unfold ruleErrors
  intro h
  have h1 := List.flatMap_eq_nil_iff.1 h p hp
  have h2 := List.map_eq_nil_iff.1 (List.append_eq_nil_iff.1 h1).1
  have h3 := List.filter_eq_nil_iff.1 h2 n hn
  exact absurd h3 (by simpa using hmiss)

/-- A violated `conflicts`: refused. -/
theorem ruleErrors_conflicts (parts) (sel : List (String × String)) (p : PartFact) (hp : p ∈ parts) (b : String)
    (hb : b ∈ ((p.conflicts.lookup (p.id ++ ":" ++ ((sel.lookup p.id).getD ""))).getD []))
    (hhit : (selected sel).contains b = true) : ruleErrors parts sel ≠ [] := by
  unfold ruleErrors
  intro h
  have h1 := List.flatMap_eq_nil_iff.1 h p hp
  have h2 := List.map_eq_nil_iff.1 (List.append_eq_nil_iff.1 h1).2
  have h3 := List.filter_eq_nil_iff.1 h2 b hb
  exact h3 (by simpa using hhit)

/-- No rule error: every `requires` of every part holds in the selection. -/
theorem ruleErrors_nil_requires (parts) (sel : List (String × String)) (h : ruleErrors parts sel = [])
    (p : PartFact) (hp : p ∈ parts) (n : String)
    (hn : n ∈ ((p.requires.lookup (p.id ++ ":" ++ ((sel.lookup p.id).getD ""))).getD [])) :
    (selected sel).contains n = true := by
  by_cases hc : (selected sel).contains n = true
  · exact hc
  · have hf : (selected sel).contains n = false := by simpa using hc
    exact absurd h (ruleErrors_requires parts sel p hp n hn hf)

/-- No rule error: no `conflicts` of any part holds in the selection. -/
theorem ruleErrors_nil_conflicts (parts) (sel : List (String × String)) (h : ruleErrors parts sel = [])
    (p : PartFact) (hp : p ∈ parts) (b : String)
    (hb : b ∈ ((p.conflicts.lookup (p.id ++ ":" ++ ((sel.lookup p.id).getD ""))).getD [])) :
    (selected sel).contains b = false := by
  by_cases hc : (selected sel).contains b = true
  · exact absurd h (ruleErrors_conflicts parts sel p hp b hb hc)
  · simpa using hc

/-- `canonical` of nothing is the empty search. -/
theorem canonical_none : canonical none [] = "" := rfl

/-! ## Open: start or reuse -/

/-- The preview slot a pasted search opens in: the main build. -/
def mainSlot : String := "open-main"

/-- A preview of the console's table: its slot, commit and whether it serves. -/
structure PvFact where
  id : String
  slot : String
  sha : String
  serving : Bool

/-- What an Open click does. -/
inductive Act where
  | reuse (id : String)
  | wait (id : String)
  | rebuild (id : String)
  | start
deriving Repr, DecidableEq

/-- Reuse a serving preview of the commit; else wait for a building one; else rebuild the slot's older preview; else start. -/
def decide (pvs : List PvFact) (slot sha : String) : Act :=
  match pvs.find? (fun p => p.serving && p.sha == sha) with
  | some p => .reuse p.id
  | none =>
    match pvs.find? (fun p => !p.serving && p.sha == sha) with
    | some p => .wait p.id
    | none =>
      match pvs.find? (·.slot == slot) with
      | some p => .rebuild p.id
      | none => .start

/-- A serving preview of the commit: reuse it. -/
theorem decide_reuse (pvs : List PvFact) (slot sha : String) (p : PvFact)
    (h : pvs.find? (fun p => p.serving && p.sha == sha) = some p) : decide pvs slot sha = .reuse p.id := by
  simp [decide, h]

/-- Reuse names a serving preview of this commit. -/
theorem decide_reuse_sound (pvs : List PvFact) (slot sha id : String) (h : decide pvs slot sha = .reuse id) :
    ∃ p ∈ pvs, p.id = id ∧ p.serving = true ∧ p.sha = sha := by
  unfold decide at h
  split at h
  · rename_i p hp
    cases h
    have := List.find?_some hp
    have hm := List.mem_of_find?_eq_some hp
    simp at this
    exact ⟨p, hm, rfl, this.1, this.2⟩
  · split at h <;> (try split at h) <;> cases h

/-- No serving preview of the commit, a building one: wait for it. -/
theorem decide_wait (pvs : List PvFact) (slot sha : String) (p : PvFact)
    (h0 : pvs.find? (fun p => p.serving && p.sha == sha) = none)
    (h : pvs.find? (fun p => !p.serving && p.sha == sha) = some p) : decide pvs slot sha = .wait p.id := by
  simp [decide, h0, h]

/-- No preview of the commit, an older one in the slot: rebuild. -/
theorem decide_rebuild (pvs : List PvFact) (slot sha : String) (p : PvFact)
    (h0 : pvs.find? (fun p => p.serving && p.sha == sha) = none)
    (h1 : pvs.find? (fun p => !p.serving && p.sha == sha) = none)
    (h : pvs.find? (·.slot == slot) = some p) : decide pvs slot sha = .rebuild p.id := by
  simp [decide, h0, h1, h]

/-- No preview of the commit and none in the slot: start. -/
theorem decide_start (pvs : List PvFact) (slot sha : String)
    (h0 : pvs.find? (fun p => p.serving && p.sha == sha) = none)
    (h1 : pvs.find? (fun p => !p.serving && p.sha == sha) = none)
    (h : pvs.find? (·.slot == slot) = none) : decide pvs slot sha = .start := by
  simp [decide, h0, h1, h]

/-- No preview at all: start. -/
theorem decide_nil (slot sha : String) : decide [] slot sha = .start := rfl

/-! ## Links -/

/-- Which arm an Open click shows. -/
inductive Arm where
  | rewrite
  | compare
deriving Repr, DecidableEq

/-- The path on the preview port: the rewrite arm at the search, or the compare view at it. -/
def path (id : String) (arm : Arm) (search : String) : String :=
  match arm with
  | .rewrite => "/preview/" ++ id ++ "/r/" ++ search
  | .compare => "/preview/" ++ id ++ "/compare" ++ search

/-- The host of a link to copy: the LAN address when LAN is on and the console knows it, else loopback. -/
def linkHost (lan : Bool) (lanAddr : Option String) : String :=
  match lan, lanAddr with
  | true, some a => a
  | _, _ => "127.0.0.1"

/-- The full link: scheme, host, preview port, path. It holds nothing else: no token, no cookie, no fragment. -/
def fullUrl (lan : Bool) (lanAddr : Option String) (port : Nat) (p : String) : String :=
  "http://" ++ linkHost lan lanAddr ++ ":" ++ toString port ++ p

theorem linkHost_lan (a : String) : linkHost true (some a) = a := rfl
theorem linkHost_lan_unknown : linkHost true none = "127.0.0.1" := rfl
theorem linkHost_off (o : Option String) : linkHost false o = "127.0.0.1" := by simp [linkHost]
theorem fullUrl_eq (lan : Bool) (a : Option String) (port : Nat) (p : String) :
    fullUrl lan a port p = "http://" ++ linkHost lan a ++ ":" ++ toString port ++ p := rfl
theorem path_rewrite (id s : String) : path id .rewrite s = "/preview/" ++ id ++ "/r/" ++ s := rfl
theorem path_compare (id s : String) : path id .compare s = "/preview/" ++ id ++ "/compare" ++ s := rfl

/-! ## The open decision -/

/-- What `console.buildsOpen` answers. -/
inductive Open where
  | refused (reasons : List String)
  | go (act : Act) (canonical slot sha : String)
deriving Repr, DecidableEq

/-- A pasted search opens the main build: refused unless valid; else reuse or start in the main slot at the main commit. -/
def openSearch (parts : List PartFact) (presets : List PresetFact) (pvs : List PvFact) (main search : String) : Open :=
  match validate parts presets search with
  | .refused rs => .refused rs
  | .ok c => .go (decide pvs mainSlot main) c mainSlot main

/-- A Builds row opens its own slot and commit at the row's search (decided by `console.builds`, never by the client). -/
def openRow (pvs : List PvFact) (slot sha search : String) : Open :=
  .go (decide pvs slot sha) search slot sha

/-- A refused search never opens or starts anything. -/
theorem openSearch_refused (parts presets pvs main search rs)
    (h : validate parts presets search = .refused rs) : openSearch parts presets pvs main search = .refused rs := by
  simp [openSearch, h]

/-- A valid search opens the main build at its canonical form. -/
theorem openSearch_ok (parts presets pvs main search c)
    (h : validate parts presets search = .ok c) :
    openSearch parts presets pvs main search = .go (decide pvs mainSlot main) c mainSlot main := by
  simp [openSearch, h]

/-- An open that goes ahead names a valid search: `go` only follows `ok`. -/
theorem openSearch_go_valid (parts presets pvs main search act c slot sha)
    (h : openSearch parts presets pvs main search = .go act c slot sha) :
    validate parts presets search = .ok c := by
  unfold openSearch at h
  split at h
  · cases h
  · rename_i c' hc
    cases h
    exact hc

/-- A pasted search reuses a serving preview of main's commit when there is one. -/
theorem openSearch_reuse (parts presets pvs main search c p)
    (hv : validate parts presets search = .ok c)
    (h : pvs.find? (fun p => p.serving && p.sha == main) = some p) :
    openSearch parts presets pvs main search = .go (.reuse p.id) c mainSlot main := by
  rw [openSearch_ok _ _ _ _ _ _ hv, decide_reuse _ _ _ _ h]

/-- A row reuses a serving preview of its commit when there is one. -/
theorem openRow_reuse (pvs slot sha search p) (h : pvs.find? (fun p => p.serving && p.sha == sha) = some p) :
    openRow pvs slot sha search = .go (.reuse p.id) search slot sha := by
  simp [openRow, decide_reuse _ _ _ _ h]

end Fw.Console.BuildsOpen
