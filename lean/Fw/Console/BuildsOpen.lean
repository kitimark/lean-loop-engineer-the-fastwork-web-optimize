namespace Fw.Console.BuildsOpen

structure PartFact where
  id : String
  variants : List String
  impls : List String
  requires : List (String × List String)
  conflicts : List (String × List String)
  layers : List String := []

structure PresetFact where
  name : String
  base : Option String
  fw : List (String × String)

def maxLen : Nat := 2000

def okChar (c : Char) : Bool :=
  c.isAlphanum || c == '.' || c == ':' || c == ',' || c == '-' || c == '_' || c == '@' || c == '=' || c == '&'

def body (s : String) : String := if s.startsWith "?" then (s.drop 1).toString else s

def splitParam (seg : String) : String × String :=
  match seg.splitOn "=" with
  | [] => ("", "")
  | k :: rest => (k, "=".intercalate rest)

def params (b : String) : List (String × String) :=
  ((b.splitOn "&").filter (· != "")).map splitParam

def valuesOf (k : String) (ps : List (String × String)) : List String :=
  (ps.filter (·.1 == k)).map (·.2)

def fwEntries (ps : List (String × String)) : List String :=
  ((valuesOf "fw" ps).flatMap (·.splitOn ",")).filter (· != "")

def fwlEntries (ps : List (String × String)) : List String :=
  ((valuesOf "fwl" ps).flatMap (·.splitOn ",")).filter (· != "")

def layerOpts : List String := ["c", "s", "cs"]

def splitLayer (e : String) : Option (String × String) :=
  match e.splitOn ":" with
  | [l, o] => if l != "" && layerOpts.contains o then some (l, o) else none
  | _ => none

def splitEntry (e : String) : Option (String × String × Option String) :=
  match e.splitOn ":" with
  | [id, rest] =>
    if id == "" || id.contains '@' then none else
    match rest.splitOn "@" with
    | [v] => if v == "" then none else some (id, v, none)
    | [v, i] => if v == "" || i == "" then none else some (id, v, some i)
    | _ => none
  | _ => none

structure St where
  errs : List String
  sel : List (String × String)

def setSel (sel : List (String × String)) (id v : String) : List (String × String) :=
  if sel.any (·.1 == id) then sel.map (fun e => if e.1 == id then (id, v) else e) else sel ++ [(id, v)]

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

def mergeInto (base own : List (String × String)) : List (String × String) :=
  own.foldl (fun a e =>
    if a.any (·.1 == e.1) then a.map (fun x => if x.1 == e.1 then (e.1, e.2) else x) else a ++ [e]) base

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

def initSel (parts : List PartFact) : List (String × String) :=
  parts.map fun p => (p.id, p.variants.headD "faithful")

def selected (sel : List (String × String)) : List String := sel.map fun e => e.1 ++ ":" ++ e.2

def keyOf (sel : List (String × String)) (p : PartFact) : String := p.id ++ ":" ++ ((sel.lookup p.id).getD "")

def partErrors (sel : List (String × String)) (p : PartFact) : List String :=
  (((p.requires.lookup (keyOf sel p)).getD []).filter (fun n => !(selected sel).contains n)).map
    (fun n => keyOf sel p ++ " requires " ++ n) ++
  (((p.conflicts.lookup (keyOf sel p)).getD []).filter (fun b => (selected sel).contains b)).map
    (fun b => keyOf sel p ++ " conflicts with " ++ b)

def ruleErrors (parts : List PartFact) (sel : List (String × String)) : List String :=
  parts.flatMap (partErrors sel)

def applyPreset (parts : List PartFact) (name : String) (st : St) (ents : List (String × String)) : St :=
  ents.foldl (fun s e =>
    let ps := e.2.splitOn "@"
    applyOne parts s e.1 (ps.headD "") ps[1]? s!"preset \"{name}\"") st

def applyFwEntry (parts : List PartFact) (st : St) (e : String) : St :=
  match splitEntry e with
  | none => { st with errs := st.errs ++ [s!"?fw=: cannot parse \"{e}\" (expected part:variant)"] }
  | some (id, v, i) => applyOne parts st id v i "?fw="

def finish (parts : List PartFact) (st : St) : List String :=
  if st.errs.isEmpty then ruleErrors parts st.sel else st.errs

def stage1 (parts : List PartFact) (presets : List PresetFact) (names : List String) : St :=
  let st0 : St := { errs := if names.length > 1 then ["only one ?preset= is allowed"] else [], sel := initSel parts }
  match names.head? with
  | none => st0
  | some name =>
    let r := presetEntries presets name [] st0.errs (presets.length + 2)
    applyPreset parts name { st0 with errs := r.2 } r.1

def errorsOf (parts : List PartFact) (presets : List PresetFact) (names fw : List String) : List String :=
  finish parts (fw.foldl (applyFwEntry parts) (stage1 parts presets names))

def layerErrors (parts : List PartFact) (fwl : List String) : List String :=
  fwl.zipIdx.flatMap fun (e, i) =>
    match splitLayer e with
    | none => [s!"?fwl=: cannot parse \"{e}\" (expected layer:c, layer:s or layer:cs)"]
    | some (l, _) =>
      (if parts.any (·.layers.contains l) then [] else [s!"?fwl=: unknown layer \"{l}\""]) ++
      (if (fwl.take i).any (fun x => (splitLayer x).map (·.1) == some l) then [s!"?fwl=: layer \"{l}\" is listed twice"]
       else [])

def searchErrors (parts : List PartFact) (presets : List PresetFact) (ps : List (String × String)) : List String :=
  errorsOf parts presets (valuesOf "preset" ps) (fwEntries ps) ++ layerErrors parts (fwlEntries ps)

inductive Verdict where
  | ok (canonical : String)
  | refused (reasons : List String)
deriving Repr, DecidableEq

def lengthReason : String := "search is longer than 2000 characters"

def charsetReason : String := "search has a character outside A-Z a-z 0-9 . : , - _ @ = & (after one leading ?)"

def canonical (preset : Option String) (fw : List String) (fwl : List String := []) : String :=
  let ps := (match preset with | some n => ["preset=" ++ n] | none => []) ++
    (if fw.isEmpty then [] else ["fw=" ++ ",".intercalate fw]) ++
    (if fwl.isEmpty then [] else ["fwl=" ++ ",".intercalate fwl])
  if ps.isEmpty then "" else "?" ++ "&".intercalate ps

def verdictOf (names fw fwl : List String) : List String → Verdict
  | [] => .ok (canonical names.head? fw fwl)
  | es => .refused es

def validate (parts : List PartFact) (presets : List PresetFact) (search : String) : Verdict :=
  if search.length > maxLen then .refused [lengthReason]
  else if !((body search).toList.all okChar) then .refused [charsetReason]
  else
    let ps := params (body search)
    verdictOf (valuesOf "preset" ps) (fwEntries ps) (fwlEntries ps) (searchErrors parts presets ps)

theorem validate_long (parts presets) (s : String) (h : s.length > maxLen) :
    validate parts presets s = .refused [lengthReason] := by
  simp [validate, h]

theorem validate_charset (parts presets) (s : String) (hl : ¬ s.length > maxLen)
    (h : (body s).toList.all okChar = false) :
    validate parts presets s = .refused [charsetReason] := by
  simp [validate, hl, h]

theorem verdictOf_ok (names fw fwl) : verdictOf names fw fwl [] = .ok (canonical names.head? fw fwl) := rfl

theorem verdictOf_refused (names fw fwl) (es : List String) (h : es ≠ []) : verdictOf names fw fwl es = .refused es := by
  cases es with
  | nil => exact absurd rfl h
  | cons a t => rfl

theorem okChar_percent : okChar '%' = false := by decide

theorem okChar_plus : okChar '+' = false := by decide

theorem validate_percent (parts presets) (s : String) (hl : ¬ s.length > maxLen) (hm : '%' ∈ (body s).toList) :
    validate parts presets s = .refused [charsetReason] :=
  validate_charset parts presets s hl (by
    cases h : (body s).toList.all okChar
    · rfl
    · have := List.all_eq_true.1 h '%' hm
      simp [okChar_percent] at this)

theorem validate_plus (parts presets) (s : String) (hl : ¬ s.length > maxLen) (hm : '+' ∈ (body s).toList) :
    validate parts presets s = .refused [charsetReason] :=
  validate_charset parts presets s hl (by
    cases h : (body s).toList.all okChar
    · rfl
    · have := List.all_eq_true.1 h '+' hm
      simp [okChar_plus] at this)

theorem validate_ok (parts presets) (s : String) (hl : ¬ s.length > maxLen)
    (hc : (body s).toList.all okChar = true) (h : searchErrors parts presets (params (body s)) = []) :
    validate parts presets s =
      .ok (canonical (valuesOf "preset" (params (body s))).head? (fwEntries (params (body s))) (fwlEntries (params (body s)))) := by
  simp [validate, hl, hc, h, verdictOf]

theorem validate_refused (parts presets) (s : String) (hl : ¬ s.length > maxLen)
    (hc : (body s).toList.all okChar = true) (es : List String) (hne : es ≠ [])
    (h : searchErrors parts presets (params (body s)) = es) :
    validate parts presets s = .refused es := by
  simp [validate, hl, hc, h, verdictOf_refused _ _ _ _ hne]

theorem layerErrors_unparsable (parts) (fwl : List String) (e : String) (he : e ∈ fwl) (hs : splitLayer e = none) :
    layerErrors parts fwl ≠ [] := by
  obtain ⟨i, hi⟩ := List.mem_iff_getElem.1 he
  obtain ⟨hlt, rfl⟩ := hi
  intro h
  have hm : (fwl[i], i) ∈ fwl.zipIdx := List.mem_zipIdx_iff_getElem?.2 (by simp [hlt])
  have := List.flatMap_eq_nil_iff.1 h _ hm
  simp [hs] at this

theorem layerErrors_unknown (parts) (fwl : List String) (e l o : String) (he : e ∈ fwl)
    (hs : splitLayer e = some (l, o)) (hu : parts.any (·.layers.contains l) = false) : layerErrors parts fwl ≠ [] := by
  obtain ⟨i, hi⟩ := List.mem_iff_getElem.1 he
  obtain ⟨hlt, rfl⟩ := hi
  intro h
  have hm : (fwl[i], i) ∈ fwl.zipIdx := List.mem_zipIdx_iff_getElem?.2 (by simp [hlt])
  have := List.flatMap_eq_nil_iff.1 h _ hm
  simp only [hs, hu, Bool.false_eq_true, ↓reduceIte, List.cons_append, reduceCtorEq] at this

theorem layerErrors_twice (parts) (fwl : List String) (i j : Nat) (hij : i < j) (hj : j < fwl.length) (l : String)
    (hi : (splitLayer (fwl[i]'(by omega))).map (·.1) = some l) (hl : (splitLayer fwl[j]).map (·.1) = some l) :
    layerErrors parts fwl ≠ [] := by
  intro h
  have hm : (fwl[j], j) ∈ fwl.zipIdx := List.mem_zipIdx_iff_getElem?.2 (by simp [hj])
  have := List.flatMap_eq_nil_iff.1 h _ hm
  obtain ⟨o, ho⟩ : ∃ o, splitLayer fwl[j] = some (l, o) := by
    cases hs : splitLayer fwl[j] with
    | none => simp [hs] at hl
    | some p => simp [hs] at hl; exact ⟨p.2, by rw [← hl]⟩
  have hany : (fwl.take j).any (fun x => (splitLayer x).map (·.1) == some l) = true := by
    rw [List.any_eq_true]
    exact ⟨fwl[i], List.mem_iff_getElem.2 ⟨i, by simp; omega, by simp⟩, by simp [hi]⟩
  simp [ho, hany] at this

#guard validate [] [] "" == .ok ""
#guard validate [] [] "?" == .ok ""
#guard validate [] [] "?a%20b" == .refused [charsetReason]
#guard validate [{ id := "hero", variants := ["faithful"], impls := [], requires := [], conflicts := [], layers := ["hero_copy"] }] []
    "?fwl=hero_copy:c" == .ok "?fwl=hero_copy:c"
#guard validate [{ id := "hero", variants := ["faithful"], impls := [], requires := [], conflicts := [], layers := ["hero_copy"] }] []
    "?fwl=hero_copy:cs,hero_copy:s" == .refused ["?fwl=: layer \"hero_copy\" is listed twice"]
#guard validate [] [] "?fwl=hero_copy:c" == .refused ["?fwl=: unknown layer \"hero_copy\""]
#guard validate [] [] "?fwl=hero_copy:x" == .refused ["?fwl=: cannot parse \"hero_copy:x\" (expected layer:c, layer:s or layer:cs)"]
#guard canonical none ["a:b"] ["l:c"] == "?fw=a:b&fwl=l:c" && canonical (some "p") [] ["l:s"] == "?preset=p&fwl=l:s"

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

theorem foldl_len {α} (g : St → α → St) (hm : ∀ s a, s.errs.length ≤ (g s a).errs.length) (l : List α) (st : St) :
    st.errs.length ≤ (l.foldl g st).errs.length := by
  induction l generalizing st with
  | nil => simp
  | cons b l ih => exact Nat.le_trans (hm st b) (ih (g st b))

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

theorem errorsOf_of_stage (parts : List PartFact) (fw : List String) (st1 : St) (h : 0 < st1.errs.length) :
    finish parts (fw.foldl (applyFwEntry parts) st1) ≠ [] :=
  finish_pos _ _ (Nat.lt_of_lt_of_le h (foldl_len _ (fun s a => applyFwEntry_len parts s a) fw st1))

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

theorem errorsOf_two_presets (parts presets) (names fw : List String) (h : 1 < names.length) :
    errorsOf parts presets names fw ≠ [] :=
  errorsOf_of_stage _ _ _ (stage1_two parts presets names h)

theorem errorsOf_unknown_part (parts presets names fw) (e id v : String) (i : Option String) (he : e ∈ fw)
    (hs : splitEntry e = some (id, v, i)) (hf : parts.find? (·.id == id) = none) :
    errorsOf parts presets names fw ≠ [] := by
  unfold errorsOf
  apply finish_pos
  exact foldl_pos _ (fun s a => applyFwEntry_len parts s a) e fw _ he (fun s => by
    unfold applyFwEntry; rw [hs]; exact applyOne_unknown_part _ _ _ _ _ _ hf)

theorem errorsOf_unknown_variant (parts presets names fw) (e id v : String) (i : Option String) (he : e ∈ fw)
    (hs : splitEntry e = some (id, v, i)) (p : PartFact) (hp : parts.find? (·.id == id) = some p)
    (hv : p.variants.contains v = false) : errorsOf parts presets names fw ≠ [] := by
  unfold errorsOf
  apply finish_pos
  exact foldl_pos _ (fun s a => applyFwEntry_len parts s a) e fw _ he (fun s => by
    unfold applyFwEntry; rw [hs]; exact applyOne_unknown_variant _ _ _ _ _ _ p hp hv)

theorem errorsOf_unparsable (parts presets names fw) (e : String) (he : e ∈ fw) (hs : splitEntry e = none) :
    errorsOf parts presets names fw ≠ [] := by
  unfold errorsOf
  apply finish_pos
  exact foldl_pos _ (fun s a => applyFwEntry_len parts s a) e fw _ he (fun s => by
    unfold applyFwEntry; rw [hs]; simp)

theorem ruleErrors_requires (parts) (sel : List (String × String)) (p : PartFact) (hp : p ∈ parts) (n : String)
    (hn : n ∈ ((p.requires.lookup (p.id ++ ":" ++ ((sel.lookup p.id).getD ""))).getD []))
    (hmiss : (selected sel).contains n = false) : ruleErrors parts sel ≠ [] := by
  unfold ruleErrors
  intro h
  have h1 := List.flatMap_eq_nil_iff.1 h p hp
  have h2 := List.map_eq_nil_iff.1 (List.append_eq_nil_iff.1 h1).1
  have h3 := List.filter_eq_nil_iff.1 h2 n hn
  exact absurd h3 (by simpa using hmiss)

theorem ruleErrors_conflicts (parts) (sel : List (String × String)) (p : PartFact) (hp : p ∈ parts) (b : String)
    (hb : b ∈ ((p.conflicts.lookup (p.id ++ ":" ++ ((sel.lookup p.id).getD ""))).getD []))
    (hhit : (selected sel).contains b = true) : ruleErrors parts sel ≠ [] := by
  unfold ruleErrors
  intro h
  have h1 := List.flatMap_eq_nil_iff.1 h p hp
  have h2 := List.map_eq_nil_iff.1 (List.append_eq_nil_iff.1 h1).2
  have h3 := List.filter_eq_nil_iff.1 h2 b hb
  exact h3 (by simpa using hhit)

theorem ruleErrors_nil_requires (parts) (sel : List (String × String)) (h : ruleErrors parts sel = [])
    (p : PartFact) (hp : p ∈ parts) (n : String)
    (hn : n ∈ ((p.requires.lookup (p.id ++ ":" ++ ((sel.lookup p.id).getD ""))).getD [])) :
    (selected sel).contains n = true := by
  by_cases hc : (selected sel).contains n = true
  · exact hc
  · have hf : (selected sel).contains n = false := by simpa using hc
    exact absurd h (ruleErrors_requires parts sel p hp n hn hf)

theorem ruleErrors_nil_conflicts (parts) (sel : List (String × String)) (h : ruleErrors parts sel = [])
    (p : PartFact) (hp : p ∈ parts) (b : String)
    (hb : b ∈ ((p.conflicts.lookup (p.id ++ ":" ++ ((sel.lookup p.id).getD ""))).getD [])) :
    (selected sel).contains b = false := by
  by_cases hc : (selected sel).contains b = true
  · exact absurd h (ruleErrors_conflicts parts sel p hp b hb hc)
  · simpa using hc

theorem canonical_none : canonical none [] = "" := rfl

def mainSlot : String := "open-main"

structure PvFact where
  id : String
  slot : String
  sha : String
  serving : Bool

inductive Act where
  | reuse (id : String)
  | wait (id : String)
  | rebuild (id : String)
  | start
deriving Repr, DecidableEq

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

theorem decide_reuse (pvs : List PvFact) (slot sha : String) (p : PvFact)
    (h : pvs.find? (fun p => p.serving && p.sha == sha) = some p) : decide pvs slot sha = .reuse p.id := by
  simp [decide, h]

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

theorem decide_wait (pvs : List PvFact) (slot sha : String) (p : PvFact)
    (h0 : pvs.find? (fun p => p.serving && p.sha == sha) = none)
    (h : pvs.find? (fun p => !p.serving && p.sha == sha) = some p) : decide pvs slot sha = .wait p.id := by
  simp [decide, h0, h]

theorem decide_rebuild (pvs : List PvFact) (slot sha : String) (p : PvFact)
    (h0 : pvs.find? (fun p => p.serving && p.sha == sha) = none)
    (h1 : pvs.find? (fun p => !p.serving && p.sha == sha) = none)
    (h : pvs.find? (·.slot == slot) = some p) : decide pvs slot sha = .rebuild p.id := by
  simp [decide, h0, h1, h]

theorem decide_start (pvs : List PvFact) (slot sha : String)
    (h0 : pvs.find? (fun p => p.serving && p.sha == sha) = none)
    (h1 : pvs.find? (fun p => !p.serving && p.sha == sha) = none)
    (h : pvs.find? (·.slot == slot) = none) : decide pvs slot sha = .start := by
  simp [decide, h0, h1, h]

theorem decide_nil (slot sha : String) : decide [] slot sha = .start := rfl

inductive Arm where
  | rewrite
  | compare
deriving Repr, DecidableEq

def path (id : String) (arm : Arm) (search : String) : String :=
  match arm with
  | .rewrite => "/preview/" ++ id ++ "/r/" ++ search
  | .compare => "/preview/" ++ id ++ "/compare" ++ search

def linkHost (lan : Bool) (lanAddr : Option String) : String :=
  match lan, lanAddr with
  | true, some a => a
  | _, _ => "127.0.0.1"

def fullUrl (lan : Bool) (lanAddr : Option String) (port : Nat) (p : String) : String :=
  "http://" ++ linkHost lan lanAddr ++ ":" ++ toString port ++ p

theorem linkHost_lan (a : String) : linkHost true (some a) = a := rfl
theorem linkHost_lan_unknown : linkHost true none = "127.0.0.1" := rfl
theorem linkHost_off (o : Option String) : linkHost false o = "127.0.0.1" := by simp [linkHost]
theorem fullUrl_eq (lan : Bool) (a : Option String) (port : Nat) (p : String) :
    fullUrl lan a port p = "http://" ++ linkHost lan a ++ ":" ++ toString port ++ p := rfl
theorem path_rewrite (id s : String) : path id .rewrite s = "/preview/" ++ id ++ "/r/" ++ s := rfl
theorem path_compare (id s : String) : path id .compare s = "/preview/" ++ id ++ "/compare" ++ s := rfl

inductive Open where
  | refused (reasons : List String)
  | go (act : Act) (canonical slot sha : String)
deriving Repr, DecidableEq

def openSearch (parts : List PartFact) (presets : List PresetFact) (pvs : List PvFact) (main search : String) : Open :=
  match validate parts presets search with
  | .refused rs => .refused rs
  | .ok c => .go (decide pvs mainSlot main) c mainSlot main

def openRow (pvs : List PvFact) (slot sha search : String) : Open :=
  .go (decide pvs slot sha) search slot sha

theorem openSearch_refused (parts presets pvs main search rs)
    (h : validate parts presets search = .refused rs) : openSearch parts presets pvs main search = .refused rs := by
  simp [openSearch, h]

theorem openSearch_ok (parts presets pvs main search c)
    (h : validate parts presets search = .ok c) :
    openSearch parts presets pvs main search = .go (decide pvs mainSlot main) c mainSlot main := by
  simp [openSearch, h]

theorem openSearch_go_valid (parts presets pvs main search act c slot sha)
    (h : openSearch parts presets pvs main search = .go act c slot sha) :
    validate parts presets search = .ok c := by
  unfold openSearch at h
  split at h
  · cases h
  · rename_i c' hc
    cases h
    exact hc

theorem openSearch_reuse (parts presets pvs main search c p)
    (hv : validate parts presets search = .ok c)
    (h : pvs.find? (fun p => p.serving && p.sha == main) = some p) :
    openSearch parts presets pvs main search = .go (.reuse p.id) c mainSlot main := by
  rw [openSearch_ok _ _ _ _ _ _ hv, decide_reuse _ _ _ _ h]

theorem openRow_reuse (pvs slot sha search p) (h : pvs.find? (fun p => p.serving && p.sha == sha) = some p) :
    openRow pvs slot sha search = .go (.reuse p.id) search slot sha := by
  simp [openRow, decide_reuse _ _ _ _ h]

end Fw.Console.BuildsOpen
