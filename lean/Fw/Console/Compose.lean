import Fw.Console.BuildsOpen
import Fw.Parts.Contract
import Fw.Preset.Gen
/-!
# Compose tab: pick one variant per part, get a preview search

The user picks a variant for each part like Lego bricks and gets the search of that combination. Four pure decisions, over
facts the I/O glue reads (`part.json`, the presets, the findings ledger's identity columns):

* `classOf`: the class of a variant. `original` (the faithful default), `refuted` (a ledger row that matches it is refuted),
  `proved` (a member of the `v2-proved` preset: equal look, proved), `lookChange` (the part file records a look change, accepted
  pending review), `measured` (a ledger row matches, but it is not admitted), `unrated` (no ledger row measured it).
* `rowsFor`: which ledger rows speak of a variant. The ledger is the one source of the explanations; this says which rows.
* `entries` and `search`: the canonical search of a combination, in page order, default variants left out.
* `decide`: whether a combination gets a link. It is refused with reasons when a pick names no registered variant, picks a
  refuted variant, or breaks a `requires` or `conflicts` rule of the site (`Fw.Console.BuildsOpen.validate`, the proved mirror
  of `apps/site/src/registry/resolve.ts`). Coupled groups (`Fw.Parts.Contract`) never refuse; they add a note, because proofs of
  independent parts do not compose over a coupled group.

The wire op is `console.compose`. The goldens are `packages/contracts/golden/console/console.compose.jsonl`.
-/
namespace Fw.Console.Compose
open Fw.Console.BuildsOpen

/-! ## Facts -/

/-- One registered variant: its name, its `kind` (`faithful`, `optimized`, ...) and the `limit` text of its provenance (empty when none). -/
structure VariantFact where
  name : String
  kind : String
  limit : String
deriving Repr, DecidableEq

/-- One part of the site registry: its page region (`slot`), variants in file order (the head is the default), impls and rules. -/
structure PartInfo where
  id : String
  slot : String
  variants : List VariantFact
  impls : List String
  requires : List (String × List String)
  conflicts : List (String × List String)
deriving Repr

/-- The part as `BuildsOpen` reads it. -/
def PartInfo.fact (p : PartInfo) : PartFact :=
  { id := p.id, variants := p.variants.map (·.name), impls := p.impls, requires := p.requires, conflicts := p.conflicts }

/-- The identity columns of one findings-ledger row, and its optional `flag` (`part:variant`). -/
structure LRow where
  part : String
  candidate : String
  status : String
  flag : Option String
deriving Repr, DecidableEq

/-- The regions of the page, in page order (`apps/site/src/App.tsx` render order; engine and morph parts have no box of their own). -/
def regions : List String := ["nav", "hero", "people", "pain", "commission", "platform", "morph", "overlays", "engine"]

/-- Position of a region in the page; an unknown region goes last. -/
def regionIdx (r : String) : Nat := (regions.findIdx? (· == r)).getD regions.length

/-- The parts in page order: by region, then by part id. -/
def ordered (parts : List PartInfo) : List PartInfo :=
  parts.mergeSort fun a b => regionIdx a.slot < regionIdx b.slot || (regionIdx a.slot == regionIdx b.slot && a.id ≤ b.id)

/-- The default variant of a part: the head of its variants. -/
def defaultOf (p : PartInfo) : String := (p.variants.head?.map (·.name)).getD "faithful"

/-- The part registers a variant of this name. -/
def hasVariant (p : PartInfo) (v : String) : Bool := p.variants.any (·.name == v)

/-! ## Which ledger rows speak of a variant -/

/-- A name character: ASCII letter or digit, `.`, `-` or `_`. -/
def nameChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == '-' || c == '_'

/-- Words of a text: maximal runs of name characters and `:`, with trailing `:` and `.` dropped, none empty. -/
def tokens (s : String) : List String :=
  let rec go : List Char → List Char → List (List Char) → List (List Char)
    | [], cur, acc => cur.reverse :: acc
    | c :: cs, cur, acc => if nameChar c || c == ':' then go cs (c :: cur) acc else go cs [] (cur.reverse :: acc)
  let trim (l : List Char) : List Char := (l.reverse.dropWhile (fun c => c == ':' || c == '.')).reverse
  ((go s.toList [] []).reverse.map trim).filter (· != []) |>.map String.ofList

/-- The part ids a ledger `part` text names: the text before its first `(`, and a parenthesis that opens with `+`. -/
def rowParts (s : String) : List String :=
  match s.splitOn "(" with
  | [] => []
  | h :: rest => tokens h ++ (rest.filter (fun r => (r.dropWhile (· == ' ')).startsWith "+")).flatMap tokens

/-- The ledger rows that carry a variant's proof, from the preset generator's link table, and the one extra row that speaks of
`hero.countdown:hidden-pause` (the row of its `morph.countdown` twin). -/
def explicitKeys (part variant : String) : List (String × String) :=
  ((Fw.Preset.Gen.linkTable.filter (fun l => l.1.part == part && l.1.variant == variant)).flatMap (·.2)) ++
  (if part == "hero.countdown" && variant == "hidden-pause" then
    [("hero.countdown / morph.countdown", "hidden-skip: skip face writes while the clock is not visible; the spring keeps integrating")]
   else [])

/-- A candidate text puts the variant in backticks. -/
def quoted (cand variant : String) : Bool := (cand.splitOn ("`" ++ variant ++ "`")).length > 1

/-- Whether a ledger row speaks of variant `v` of part `p`. A row with a `flag` speaks of exactly that flag. Any other row speaks of
it when the row names the part and the candidate text either has `part:variant` as a word, starts with the variant name, puts the
variant in backticks, or is a row the link table (or its one extra) names for the variant. -/
def matchRow (p : PartInfo) (v : String) (r : LRow) : Bool :=
  match r.flag with
  | some f => f == p.id ++ ":" ++ v
  | none =>
    (rowParts r.part).contains p.id &&
      ((tokens r.candidate).contains (p.id ++ ":" ++ v) || (tokens r.candidate).head? == some v ||
        quoted r.candidate v || (explicitKeys p.id v).contains (r.part, r.candidate))

/-- The indices of the ledger rows that speak of variant `v` of part `p`, in ledger order. -/
def rowsFor (rows : List LRow) (p : PartInfo) (v : String) : List Nat :=
  (rows.zipIdx.filter (fun e => matchRow p v e.1)).map (·.2)

/-- The indices of the rows that name part `p` and speak of none of its variants. -/
def otherRows (rows : List LRow) (p : PartInfo) : List Nat :=
  (rows.zipIdx.filter (fun e => (rowParts e.1.part).contains p.id && !(p.variants.any (fun v => matchRow p v.name e.1)))).map (·.2)

/-! ## Classes -/

/-- The class of a variant. -/
inductive Cls where
  | original | proved | lookChange | measured | refuted | unrated
deriving Repr, DecidableEq

/-- The wire name of a class. -/
def Cls.name : Cls → String
  | .original => "original" | .proved => "proved" | .lookChange => "look-change"
  | .measured => "measured" | .refuted => "refuted" | .unrated => "unrated"

/-- The one-line reason a class shows on the card. -/
def Cls.why : Cls → String
  | .original => "the faithful page: the original look and behaviour"
  | .proved => "same look as the original, proved, and part of v2-proved"
  | .lookChange => "the look changes; accepted, pending your review"
  | .measured => "measured, not admitted: the proof or the measurement is not complete"
  | .refuted => "refused: a finding refuted it"
  | .unrated => "no finding has measured it yet"

/-- A part file records a look change in the variant's `limit` text. -/
def lookChange (limit : String) : Bool := limit.startsWith "look change"

/-- The class of variant `v` given its kind, whether it is in `v2-proved`, and the rows that speak of it. A refuting row wins over
every membership; then the faithful variant, `v2-proved`, a recorded look change, any row with a verdict; else unrated. -/
def classOf (v : VariantFact) (inProved : Bool) (rows : List LRow) : Cls :=
  if v.kind == "faithful" then .original
  else if rows.any (·.status == "refuted") then .refuted
  else if inProved then .proved
  else if lookChange v.limit then .lookChange
  else if rows.any (·.status != "not-tried") then .measured
  else .unrated

theorem classOf_original (v rows p) (h : v.kind = "faithful") : classOf v p rows = .original := by
  simp [classOf, h]

theorem classOf_refuted (v inProved rows) (hk : v.kind ≠ "faithful") (h : rows.any (·.status == "refuted") = true) :
    classOf v inProved rows = .refuted := by
  simp [classOf, hk, h]

theorem classOf_proved (v rows) (hk : v.kind ≠ "faithful") (h : rows.any (·.status == "refuted") = false) :
    classOf v true rows = .proved := by
  simp [classOf, hk, h]

theorem classOf_lookChange (v rows) (hk : v.kind ≠ "faithful") (h : rows.any (·.status == "refuted") = false)
    (hl : lookChange v.limit = true) : classOf v false rows = .lookChange := by
  simp [classOf, hk, h, hl]

theorem classOf_measured (v rows) (hk : v.kind ≠ "faithful") (h : rows.any (·.status == "refuted") = false)
    (hl : lookChange v.limit = false) (hm : rows.any (·.status != "not-tried") = true) :
    classOf v false rows = .measured := by
  simp [classOf, hk, h, hl, hm]

theorem classOf_unrated (v rows) (hk : v.kind ≠ "faithful") (h : rows.any (·.status == "refuted") = false)
    (hl : lookChange v.limit = false) (hm : rows.any (·.status != "not-tried") = false) :
    classOf v false rows = .unrated := by
  simp [classOf, hk, h, hl, hm]

/-- The (part, variant) pairs of the `v2-proved` preset, `@impl` dropped; empty when the preset is not registered. -/
def provedFlags (presets : List PresetFact) : List (String × String) :=
  (presetEntries presets "v2-proved" [] [] (presets.length + 2)).1.map fun e => (e.1, (e.2.splitOn "@").headD "")

/-- One variant of the table. -/
structure VarOut where
  name : String
  kind : String
  isDefault : Bool
  cls : Cls
  rows : List Nat
  refusal : Option String
deriving Repr

/-- One part of the table. -/
structure PartOut where
  id : String
  slot : String
  group : String
  pageLevel : Bool
  variants : List VarOut
  other : List Nat
deriving Repr

/-- The first 80 characters of a text. -/
def clip (s : String) : String := String.ofList (s.toList.take 80)

/-- The refusal text of a refuted variant: the first refuting row it matches. -/
def refusalOf (rows : List LRow) (idx : List Nat) : Option String :=
  (idx.filterMap fun i => rows[i]?).find? (·.status == "refuted") |>.map fun r => "refuted by the finding \"" ++ clip r.candidate ++ "\""

/-- The coupled group of a part in the part contract (`solo` when the contract has no row). -/
def groupOf (id : String) : String := ((Fw.Parts.Contract.parts.find? (·.id == id)).map (·.group.name)).getD "solo"

/-- The part is page-level in the part contract. -/
def pageLevelOf (id : String) : Bool := ((Fw.Parts.Contract.parts.find? (·.id == id)).map Fw.Parts.Contract.pageLevel).getD false

/-- One part's card: every variant with its class and rows. -/
def partOut (rows : List LRow) (proved : List (String × String)) (p : PartInfo) : PartOut :=
  { id := p.id, slot := p.slot, group := groupOf p.id, pageLevel := pageLevelOf p.id, other := otherRows rows p
    variants := p.variants.map fun v =>
      let idx := rowsFor rows p v.name
      let rs := idx.filterMap fun i => rows[i]?
      let c := classOf v (proved.contains (p.id, v.name)) rs
      { name := v.name, kind := v.kind, isDefault := v.name == defaultOf p, cls := c, rows := idx,
        refusal := if c == .refuted then refusalOf rows idx else none } }

/-- The table: every part in page order. -/
def table (parts : List PartInfo) (rows : List LRow) (presets : List PresetFact) : List PartOut :=
  (ordered parts).map (partOut rows (provedFlags presets))

/-! ## The combination and its canonical search -/

/-- The variant a combination gives to part `p`: its last pick that names a registered variant, else the default. -/
def choice (picks : List (String × String)) (p : PartInfo) : String :=
  match (picks.filter fun e => e.1 == p.id && hasVariant p e.2).getLast? with
  | some e => e.2
  | none => defaultOf p

/-- The non-default choices, in the order of `parts`. -/
def entries (parts : List PartInfo) (picks : List (String × String)) : List (String × String) :=
  parts.filterMap fun p => if choice picks p == defaultOf p then none else some (p.id, choice picks p)

/-- The search of a list of entries: empty for none, else `?fw=part:variant,...`. -/
def render (es : List (String × String)) : String := canonical none (es.map fun e => e.1 ++ ":" ++ e.2)

/-- The canonical search of a combination: its non-default choices in page order. -/
def search (parts : List PartInfo) (picks : List (String × String)) : String := render (entries (ordered parts) picks)

/-- The same combination (every part gets the same variant) gives the same entries, in any pick order or with repeated picks. -/
theorem entries_congr (a b : List (String × String)) :
    ∀ (parts : List PartInfo), (∀ p ∈ parts, choice a p = choice b p) → entries parts a = entries parts b := by
  intro parts
  induction parts with
  | nil => intro _; rfl
  | cons q qs ih =>
    intro h
    have hq := h q (List.mem_cons_self ..)
    have hqs := ih (fun p hp => h p (List.mem_cons_of_mem _ hp))
    simp only [entries, List.filterMap_cons] at hqs ⊢
    rw [hq, hqs]

/-- The same combination gives the same canonical search. -/
theorem search_congr (parts : List PartInfo) (a b : List (String × String)) (h : ∀ p ∈ parts, choice a p = choice b p) :
    search parts a = search parts b := by
  unfold search
  rw [entries_congr a b (ordered parts)]
  intro p hp
  exact h p ((List.mergeSort_perm _ _).subset hp)

/-- A part left at its default adds no entry. -/
theorem entries_cons_default (q : PartInfo) (qs picks) (hc : choice picks q = defaultOf q) :
    entries (q :: qs) picks = entries qs picks := by
  simp [entries, hc]

/-- A part off its default adds its entry in front. -/
theorem entries_cons_pick (q : PartInfo) (qs picks) (hc : ¬ choice picks q = defaultOf q) :
    entries (q :: qs) picks = (q.id, choice picks q) :: entries qs picks := by
  simp [entries, hc]

/-- A part id that no part in the list has is not in the entries. -/
theorem entries_lookup_none (picks : List (String × String)) (k : String) :
    ∀ (parts : List PartInfo), (∀ r ∈ parts, r.id ≠ k) → (entries parts picks).lookup k = none := by
  intro parts
  induction parts with
  | nil => intro _; rfl
  | cons q qs ih =>
    intro h
    have hq : q.id ≠ k := h q (List.mem_cons_self ..)
    have hqs := ih (fun r hr => h r (List.mem_cons_of_mem _ hr))
    by_cases hc : choice picks q = defaultOf q
    · rw [entries_cons_default q qs picks hc]; exact hqs
    · have hk : (k == q.id) = false := beq_eq_false_iff_ne.2 (Ne.symm hq)
      rw [entries_cons_pick q qs picks hc]
      simp [List.lookup, hk, hqs]

/-- Looking a part up in the entries gives its choice (the default when it is left out), when part ids are distinct: the
entries determine the combination. -/
theorem entries_lookup (picks : List (String × String)) :
    ∀ (parts : List PartInfo), (parts.map (·.id)).Nodup → ∀ p ∈ parts,
      ((entries parts picks).lookup p.id).getD (defaultOf p) = choice picks p := by
  intro parts
  induction parts with
  | nil => intro _ p hp; cases hp
  | cons q qs ih =>
    intro hnd p hp
    have hnd' : q.id ∉ qs.map (·.id) ∧ (qs.map (·.id)).Nodup := List.nodup_cons.1 (by simpa using hnd)
    have hnq : ∀ r ∈ qs, r.id ≠ q.id := fun r hr h => hnd'.1 (List.mem_map.2 ⟨r, hr, h⟩)
    rcases List.mem_cons.1 hp with rfl | hp'
    · by_cases hc : choice picks p = defaultOf p
      · rw [entries_cons_default p qs picks hc, entries_lookup_none picks p.id qs hnq]
        simp [hc]
      · rw [entries_cons_pick p qs picks hc]
        simp [List.lookup]
    · have hne : q.id ≠ p.id := fun h => hnq p hp' h.symm
      have := ih hnd'.2 p hp'
      by_cases hc : choice picks q = defaultOf q
      · rw [entries_cons_default q qs picks hc]; exact this
      · have hk : (p.id == q.id) = false := beq_eq_false_iff_ne.2 (Ne.symm hne)
        rw [entries_cons_pick q qs picks hc]
        simp [List.lookup, hk, this]

/-- Two combinations with the same entries give every part the same variant: the canonical search names one combination
(the render of entries into text is deterministic; that the text parses back to the entries is checked by the goldens). -/
theorem entries_inj (parts : List PartInfo) (hnd : (parts.map (·.id)).Nodup) (a b : List (String × String))
    (h : entries parts a = entries parts b) : ∀ p ∈ parts, choice a p = choice b p := by
  intro p hp
  rw [← entries_lookup a parts hnd p hp, ← entries_lookup b parts hnd p hp, h]

/-! ## The decision -/

/-- A pick that names no registered part or variant. -/
def pickReasons (parts : List PartInfo) (picks : List (String × String)) : List String :=
  picks.flatMap fun e =>
    match parts.find? (·.id == e.1) with
    | none => ["unknown part \"" ++ e.1 ++ "\""]
    | some p => if hasVariant p e.2 then [] else ["part \"" ++ e.1 ++ "\" has no variant \"" ++ e.2 ++ "\""]

/-- The picks of the combination that are refuted variants. -/
def refutedReasons (tbl : List PartOut) (es : List (String × String)) : List String :=
  es.flatMap fun e =>
    match (tbl.find? (·.id == e.1)).bind (fun po => po.variants.find? (·.name == e.2)) with
    | some vo => if vo.cls == .refuted then [e.1 ++ ":" ++ e.2 ++ " is " ++ (vo.refusal.getD "refuted")] else []
    | none => []

/-- The reasons the site's own rules refuse a search (none when it is accepted). -/
def ruleReasons (parts : List PartInfo) (c : String) : List String :=
  match validate (parts.map (·.fact)) [] c with
  | .ok _ => []
  | .refused rs => rs

/-- Notes on a combination: a coupled group or a page-level part with other non-default choices. Never a refusal. -/
def notes (es : List (String × String)) : List String :=
  let keys (l : List (String × String)) := ", ".intercalate (l.map fun e => e.1 ++ ":" ++ e.2)
  (["g1", "g2", "g3", "g4", "g5"].filterMap fun g =>
    let m := es.filter fun e => groupOf e.1 == g
    if m.length ≥ 2 then
      some (s!"coupled group {g}: {keys m} change parts that read each other, so their separate proofs do not compose; only a combined whole-page run covers this mix")
    else none) ++
  (let pl := es.filter fun e => pageLevelOf e.1
   if !pl.isEmpty && es.length ≥ 2 then
     [s!"page-level part {keys pl} acts on every part, so it is only covered by a whole-page run together with the other choices"]
   else [])

/-- The answer for a combination: a link only when allowed, else the reasons. -/
structure Decision where
  link : Option String
  reasons : List String
  notes : List String
deriving Repr

/-- Decide a combination. The link is the canonical search, and only when no pick is unknown, none is refuted, and the site's
rules accept the search. -/
def decide (parts : List PartInfo) (rows : List LRow) (presets : List PresetFact) (picks : List (String × String)) : Decision :=
  let es := entries (ordered parts) picks
  let c := render es
  let rs := pickReasons parts picks ++ refutedReasons (table parts rows presets) es ++ ruleReasons parts c
  { link := if rs.isEmpty then some c else none, reasons := rs, notes := if rs.isEmpty then notes es else [] }

/-- A link is the canonical search of the combination, and the reasons are empty. -/
theorem decide_link (parts rows presets picks) (c : String) (h : (decide parts rows presets picks).link = some c) :
    c = search parts picks ∧ (decide parts rows presets picks).reasons = [] := by
  unfold decide at h ⊢
  simp only [] at h ⊢
  split at h
  · rename_i hr
    simp at h
    exact ⟨h.symm, by simpa using hr⟩
  · simp at h

/-- A refused combination never yields a link. -/
theorem refused_no_link (parts rows presets picks) (h : (decide parts rows presets picks).reasons ≠ []) :
    (decide parts rows presets picks).link = none := by
  unfold decide at h ⊢
  simp only [] at h ⊢
  split
  · rename_i hr
    exact absurd (by simpa using hr) h
  · rfl

/-- An allowed combination has reasons empty, so a link exists exactly then. -/
theorem link_iff (parts rows presets picks) :
    (decide parts rows presets picks).link.isSome = ((decide parts rows presets picks).reasons.isEmpty) := by
  unfold decide
  simp only []
  split <;> simp_all

/-- A refused search always carries a reason. -/
theorem validate_refused_ne (parts presets) (s : String) (rs : List String)
    (h : validate parts presets s = .refused rs) : rs ≠ [] := by
  unfold validate at h
  split at h
  · simp at h; subst h; simp
  · split at h
    · simp at h; subst h; simp
    · dsimp only at h
      generalize hE : errorsOf parts presets (valuesOf "preset" (params (body s))) (fwEntries (params (body s))) = es at h
      cases es with
      | nil => cases h
      | cons a t =>
        rw [verdictOf_refused _ _ _ (List.cons_ne_nil a t)] at h
        cases h
        exact List.cons_ne_nil a t

/-- The site's rules accept the search of every allowed combination: it resolves without error in the grammar of
`resolve.ts` (`Fw.Console.BuildsOpen.validate` is its proved mirror). -/
theorem link_resolves (parts rows presets picks) (c : String) (h : (decide parts rows presets picks).link = some c) :
    ∃ c', validate (parts.map (·.fact)) [] c = .ok c' := by
  obtain ⟨hc, hr⟩ := decide_link parts rows presets picks c h
  unfold decide at hr
  simp only [] at hr
  have h3 : ruleReasons parts (render (entries (ordered parts) picks)) = [] := by
    have := List.append_eq_nil_iff.1 hr
    exact this.2
  subst hc
  unfold search
  unfold ruleReasons at h3
  cases hv : validate (parts.map (·.fact)) [] (render (entries (ordered parts) picks)) with
  | ok c' => exact ⟨c', rfl⟩
  | refused rs =>
    rw [hv] at h3
    exact absurd h3 (validate_refused_ne _ _ _ _ hv)

/-- An allowed combination picks no refuted variant. -/
theorem link_no_refuted (parts rows presets picks) (h : (decide parts rows presets picks).link.isSome = true) :
    refutedReasons (table parts rows presets) (entries (ordered parts) picks) = [] := by
  have h2 := (link_iff parts rows presets picks).symm ▸ h
  unfold decide at h2
  simp only [List.isEmpty_iff, List.append_eq_nil_iff] at h2
  exact h2.1.2

/-- An allowed combination has every pick on a registered part and variant. -/
theorem link_known_picks (parts rows presets picks) (h : (decide parts rows presets picks).link.isSome = true) :
    pickReasons parts picks = [] := by
  have h2 := (link_iff parts rows presets picks).symm ▸ h
  unfold decide at h2
  simp only [List.isEmpty_iff, List.append_eq_nil_iff] at h2
  exact h2.1.1

/-- Page order lists the same parts, once each. -/
theorem ordered_nodup (parts : List PartInfo) (h : (parts.map (fun p : PartInfo => p.id)).Nodup) : ((ordered parts).map (fun p : PartInfo => p.id)).Nodup :=
  ((List.mergeSort_perm _ _).symm.map (fun p : PartInfo => p.id)).nodup_iff.1 h

/-- Two combinations that give the same entries in page order give every part the same variant. -/
theorem search_entries_inj (parts : List PartInfo) (h : (parts.map (·.id)).Nodup) (a b : List (String × String))
    (he : entries (ordered parts) a = entries (ordered parts) b) : ∀ p ∈ parts, choice a p = choice b p := by
  intro p hp
  exact entries_inj (ordered parts) (ordered_nodup parts h) a b he p ((List.mergeSort_perm _ _).symm.subset hp)

end Fw.Console.Compose
