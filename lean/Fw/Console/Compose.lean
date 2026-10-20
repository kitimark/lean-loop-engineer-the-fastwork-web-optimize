import Fw.Console.BuildsOpen
import Fw.Parts.Contract
import Fw.Preset.Gen
/-!
# Compose tab: pick one variant per part, get a preview search

The user picks a variant for each part like Lego bricks and gets the search of that combination. Four pure decisions, over
facts the I/O glue reads (`part.json`, the presets, the findings ledger's identity columns):

* `classOf`: the class of a variant. `original` (the faithful default), `refuted` (a ledger row that matches it is refuted),
  `proved` (a member of the `v2-proved` preset: equal look, proved), `lookChange` (the part file records a look change, accepted
  pending review), `ledgerProved` (every matching ledger row is `proved`, but the gate has not admitted the variant to `v2-proved`), `measured` (a ledger
  row matches, but it is not admitted and not every row is `proved`), `unrated` (no ledger row measured it).
  A row whose `supersededBy` names a later row's `id` counts for no class; `supersedeErrors` refuses a name with no row.
* `rowsFor`: which ledger rows speak of a variant. The ledger is the one source of the explanations; this says which rows.
  `varRows` adds the rows that supersede one of them, by identity.
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

/-- The identity columns of one findings-ledger row: its optional `flag` (`part:variant`), its optional `id`, and the optional
`supersededBy`, the `id` of the later row that fixed or replaced it. -/
structure LRow where
  part : String
  candidate : String
  status : String
  flag : Option String
  id : Option String := none
  supersededBy : Option String := none
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

/-- The ledger rows that carry a variant's proof, from the preset generator's link table, and the extra rows the ledger has no `flag`
for yet: the row of the `morph.countdown` twin of `hero.countdown:hidden-pause`, the two rows of `morph.columns:hidden-pause`
(its own, and the `engine.scene` one), and the `engine.scene` row of `morph.countdown:hidden-pause`. -/
def explicitKeys (part variant : String) : List (String × String) :=
  ((Fw.Preset.Gen.linkTable.filter (fun l => l.1.part == part && l.1.variant == variant)).flatMap (·.2)) ++
  (if part == "hero.countdown" && variant == "hidden-pause" then
    [("hero.countdown / morph.countdown", "hidden-skip: skip face writes while the clock is not visible; the spring keeps integrating")]
   else []) ++
  (if part == "morph.columns" && variant == "hidden-pause" then
    [("morph.columns", "columns as a still picture while the menu is closed (g0.0h keep-phase = hidden-pause of the marquee)"),
     ("engine.scene", "hidden pause of compositor marquees (morph.columns at m <= 0.08, scene off-screen), HiddenPause.lean")]
   else []) ++
  (if part == "morph.countdown" && variant == "hidden-pause" then
    [("engine.scene", "morph.countdown hidden: keep the spring integrating, skip the 16 face writes per digit (HiddenPause skipWrites)")]
   else [])

/-- A candidate text puts the variant in backticks. -/
def quoted (cand variant : String) : Bool := (cand.splitOn ("`" ++ variant ++ "`")).length > 1

/-- Whether a ledger row speaks of variant `v` of part `p`. A row with a `flag` speaks of exactly that flag. Any other row speaks of
it by one of four rules. Rules 1 to 3 need the row's `part` text to name the part: (1) the candidate has `part:variant` as a word,
(2) the candidate starts with the variant name, (3) the candidate puts the variant in backticks. Rule 4 needs no part name: the
row is one the link table (or `explicitKeys`' extras) names for the variant, by its exact `part` and `candidate` text. -/
def matchRow (p : PartInfo) (v : String) (r : LRow) : Bool :=
  match r.flag with
  | some f => f == p.id ++ ":" ++ v
  | none =>
    ((rowParts r.part).contains p.id &&
      ((tokens r.candidate).contains (p.id ++ ":" ++ v) || (tokens r.candidate).head? == some v || quoted r.candidate v)) ||
    (explicitKeys p.id v).contains (r.part, r.candidate)

/-- The indices of the ledger rows that speak of variant `v` of part `p`, in ledger order. -/
def rowsFor (rows : List LRow) (p : PartInfo) (v : String) : List Nat :=
  (rows.zipIdx.filter (fun e => matchRow p v e.1)).map (·.2)

/-! ## Superseded rows

A row whose `supersededBy` names a later row's `id` no longer counts for a class; the later row does, and it joins the
variant's rows by that identity, whether or not its text matches the variant. -/

/-- No later row has fixed or replaced the row. -/
def LRow.live (r : LRow) : Bool := r.supersededBy.isNone

/-- The rows that count for a class: the live ones. -/
def live (rows : List LRow) : List LRow := rows.filter (·.live)

/-- The index of the first row whose `id` is `s`. -/
def idxOf (rows : List LRow) (s : String) : Option Nat := rows.findIdx? (·.id == some s)

/-- The index of the row that supersedes row `i`. -/
def nextOf (rows : List LRow) (i : Nat) : Option Nat := (rows[i]?.bind (·.supersededBy)).bind (idxOf rows)

/-- The rows that supersede row `i`, transitively, at most `fuel` of them. -/
def successors (rows : List LRow) : Nat → Nat → List Nat
  | 0, _ => []
  | fuel + 1, i =>
    match nextOf rows i with
    | some j => j :: successors rows fuel j
    | none => []

/-- The rows that supersede a row speaking of variant `v` of part `p`, transitively, and do not speak of it by `matchRow`. -/
def extraRows (rows : List LRow) (p : PartInfo) (v : String) : List Nat :=
  let m := rowsFor rows p v
  ((m.flatMap (successors rows rows.length)).filter (!m.contains ·)).eraseDups

/-- The rows of variant `v` of part `p`: those that speak of it, then those that supersede one of them. -/
def varRows (rows : List LRow) (p : PartInfo) (v : String) : List Nat := rowsFor rows p v ++ extraRows rows p v

/-- A row with no `supersededBy` has no successor. -/
theorem nextOf_none (rows : List LRow) (i : Nat) (h : ∀ r ∈ rows, r.supersededBy = none) : nextOf rows i = none := by
  unfold nextOf
  cases hr : rows[i]? with
  | none => rfl
  | some r => simp [h r (List.mem_of_getElem? hr)]

/-- With no `supersededBy` in the ledger, no row joins a variant by identity. -/
theorem extraRows_no_superseded (rows : List LRow) (p : PartInfo) (v : String) (h : ∀ r ∈ rows, r.supersededBy = none) :
    extraRows rows p v = [] := by
  have hs : successors rows rows.length = fun _ => [] := by
    funext i
    cases rows.length with
    | zero => rfl
    | succ n => simp [successors, nextOf_none rows i h]
  have hn : ∀ l : List Nat, l.flatMap (fun _ => ([] : List Nat)) = [] := fun l => by
    induction l <;> simp_all [List.flatMap_cons]
  simp only [extraRows, hs, hn]
  rfl

/-- With no `supersededBy` in the ledger, a variant's rows are the rows that speak of it. -/
theorem varRows_no_superseded (rows : List LRow) (p : PartInfo) (v : String) (h : ∀ r ∈ rows, r.supersededBy = none) :
    varRows rows p v = rowsFor rows p v := by
  simp [varRows, extraRows_no_superseded rows p v h]

/-- The row that supersedes a row of the variant is among the variant's rows. -/
theorem varRows_superseding (rows : List LRow) (p : PartInfo) (v : String) (i j : Nat) (hi : i ∈ rowsFor rows p v)
    (hj : nextOf rows i = some j) : j ∈ varRows rows p v := by
  unfold varRows extraRows
  by_cases hm : (rowsFor rows p v).contains j = true
  · exact List.mem_append_left _ (by simpa using hm)
  · apply List.mem_append_right
    rw [List.mem_eraseDups, List.mem_filter]
    refine ⟨List.mem_flatMap.2 ⟨i, hi, ?_⟩, by simpa using hm⟩
    have hlt : i < rows.length := by
      unfold nextOf at hj
      cases hr : rows[i]? with
      | none => simp [hr] at hj
      | some r => exact (List.getElem?_eq_some_iff.1 hr).1
    obtain ⟨n, hn⟩ : ∃ n, rows.length = n + 1 := ⟨rows.length - 1, by omega⟩
    rw [hn]
    simp [successors, hj]

/-- The indices of the rows that name part `p` and are none of its variants' rows. -/
def otherRows (rows : List LRow) (p : PartInfo) : List Nat :=
  (rows.zipIdx.filter (fun e => (rowParts e.1.part).contains p.id &&
    !(p.variants.any (fun v => matchRow p v.name e.1 || (extraRows rows p v.name).contains e.2)))).map (·.2)

/-! ## Classes -/

/-- The class of a variant. -/
inductive Cls where
  | original | proved | lookChange | ledgerProved | measured | refuted | unrated
deriving Repr, DecidableEq

/-- The wire name of a class. -/
def Cls.name : Cls → String
  | .original => "original" | .proved => "proved" | .lookChange => "look-change"
  | .ledgerProved => "ledger-proved" | .measured => "measured" | .refuted => "refuted" | .unrated => "unrated"

/-- The one-line reason a class shows on the card. -/
def Cls.why : Cls → String
  | .original => "the faithful page: the original look and behaviour"
  | .proved => "same look as the original, proved, and part of v2-proved"
  | .lookChange => "the look changes; accepted, pending your review"
  | .ledgerProved => "proved in the ledger, not yet admitted to v2-proved by the gate"
  | .measured => "not in v2-proved yet (the gate has not admitted it)"
  | .refuted => "refused: a finding refuted it"
  | .unrated => "no finding has measured it yet"

/-- A part file records a look change in the variant's `limit` text. -/
def lookChange (limit : String) : Bool := limit.startsWith "look change"

/-- The class of variant `v` given its kind, whether it is in `v2-proved`, and the rows that count. A refuting row wins over
every membership; then the faithful variant, `v2-proved`, a recorded look change, any row with a verdict; else unrated. -/
def classBy (v : VariantFact) (inProved : Bool) (rows : List LRow) : Cls :=
  if v.kind == "faithful" then .original
  else if rows.any (·.status == "refuted") then .refuted
  else if inProved then .proved
  else if lookChange v.limit then .lookChange
  else if !rows.isEmpty && rows.all (·.status == "proved") then .ledgerProved
  else if rows.any (·.status != "not-tried") then .measured
  else .unrated

/-- The class of variant `v` from its rows: `classBy` over the live ones. A superseded row neither refutes nor counts. -/
def classOf (v : VariantFact) (inProved : Bool) (rows : List LRow) : Cls := classBy v inProved (live rows)

theorem classOf_original (v rows p) (h : v.kind = "faithful") : classOf v p rows = .original := by
  simp [classOf, classBy, h]

theorem classOf_refuted (v inProved rows) (hk : v.kind ≠ "faithful") (h : (live rows).any (·.status == "refuted") = true) :
    classOf v inProved rows = .refuted := by
  simp [classOf, classBy, hk, h]

theorem classOf_proved (v rows) (hk : v.kind ≠ "faithful") (h : (live rows).any (·.status == "refuted") = false) :
    classOf v true rows = .proved := by
  simp [classOf, classBy, hk, h]

theorem classOf_lookChange (v rows) (hk : v.kind ≠ "faithful") (h : (live rows).any (·.status == "refuted") = false)
    (hl : lookChange v.limit = true) : classOf v false rows = .lookChange := by
  simp [classOf, classBy, hk, h, hl]

theorem classOf_ledgerProved (v rows) (hk : v.kind ≠ "faithful") (h : (live rows).any (·.status == "refuted") = false)
    (hl : lookChange v.limit = false) (hne : (live rows).isEmpty = false) (hp : (live rows).all (·.status == "proved") = true) :
    classOf v false rows = .ledgerProved := by
  simp [classOf, classBy, hk, h, hl, hne, hp]

theorem classOf_measured (v rows) (hk : v.kind ≠ "faithful") (h : (live rows).any (·.status == "refuted") = false)
    (hl : lookChange v.limit = false) (hnp : (!(live rows).isEmpty && (live rows).all (·.status == "proved")) = false)
    (hm : (live rows).any (·.status != "not-tried") = true) : classOf v false rows = .measured := by
  simp [classOf, classBy, hk, h, hl, hnp, hm]

theorem classOf_unrated (v rows) (hk : v.kind ≠ "faithful") (h : (live rows).any (·.status == "refuted") = false)
    (hl : lookChange v.limit = false) (hm : (live rows).any (·.status != "not-tried") = false) :
    classOf v false rows = .unrated := by
  unfold classOf
  generalize live rows = rs at h hm ⊢
  simp [classBy, hk, h, hl, hm]
  intro hne
  obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil rs hne
  refine ⟨x, hx, ?_⟩
  have hall := List.all_eq_true.1 (by simpa using hm : rs.all (fun x => !(x.status != "not-tried")) = true) x hx
  intro hp
  simp [hp] at hall

/-- A superseded row changes no class: the class is the one of the other rows. -/
theorem classOf_superseded_cons (v inProved) (r : LRow) (rows) (h : r.supersededBy.isSome = true) :
    classOf v inProved (r :: rows) = classOf v inProved rows := by
  have : r.live = false := by simpa [LRow.live, Option.isNone_iff_eq_none, Option.isSome_iff_ne_none] using h
  simp [classOf, live, this]

/-- **A superseded refuted row never refutes**: when every refuted row has a `supersededBy`, the class is not `refuted`. -/
theorem classOf_superseded_never_refutes (v inProved rows)
    (h : ∀ r ∈ rows, r.status = "refuted" → r.supersededBy.isSome = true) : classOf v inProved rows ≠ .refuted := by
  have hl : (live rows).any (·.status == "refuted") = false := by
    rw [List.any_eq_false]
    intro r hr hs
    have hm := List.mem_filter.1 hr
    have := h r hm.1 (by simpa using hs)
    simp [LRow.live, Option.isNone_iff_eq_none, Option.isSome_iff_ne_none] at hm this
    exact this hm.2
  intro hc
  unfold classOf classBy at hc
  rw [hl] at hc
  simp only [Bool.false_eq_true, ↓reduceIte] at hc
  split at hc <;> (try split at hc) <;> (try split at hc) <;> (try split at hc) <;> (try split at hc) <;> cases hc

/-- **The superseding row's class applies**: a refuted row and the row its `supersededBy` names give the class of that row
alone. -/
theorem classOf_superseding (v inProved) (old new : LRow) (s : String) (ho : old.supersededBy = some s)
    (_hn : new.id = some s) : classOf v inProved [old, new] = classOf v inProved [new] :=
  classOf_superseded_cons v inProved old [new] (by simp [ho])

/-- **With no `supersededBy`, the class is unchanged**: `classOf` is `classBy` over every row that speaks of the variant. -/
theorem classOf_no_superseded (v inProved rows) (h : ∀ r ∈ rows, r.supersededBy = none) :
    classOf v inProved rows = classBy v inProved rows := by
  have : live rows = rows := List.filter_eq_self.2 fun r hr => by simp [LRow.live, h r hr]
  simp [classOf, this]

/-- The (part, variant) pairs of the `v2-proved` preset, `@impl` dropped; empty when the preset is not registered. -/
def provedFlags (presets : List PresetFact) : List (String × String) :=
  (presetEntries presets "v2-proved" [] [] (presets.length + 2)).1.map fun e => (e.1, (e.2.splitOn "@").headD "")

/-- The impl the site gives a part when no `@impl` is named (`DEFAULT_IMPL` in `apps/site/src/registry/resolve.ts`). -/
def defaultImpl : String := "mui"

/-- The reasons a preset cannot be a one-click combination: an entry `variant@impl` with an impl other than the default. The
composer has no impl pick, so its link would open the default impl, not the preset's. -/
def implReasons (presets : List PresetFact) (name : String) : List String :=
  (presetEntries presets name [] [] (presets.length + 2)).1.filterMap fun e =>
    match e.2.splitOn "@" with
    | [_, i] => if i == defaultImpl then none
      else some s!"preset \"{name}\" picks {e.1}:{e.2}, a non-default impl; the composer has no impl pick, so the link would open the default impl"
    | _ => none

/-- A preset with no `@impl` entry has no impl reason. -/
theorem implReasons_nil_of_no_impl (presets name)
    (h : ∀ e ∈ (presetEntries presets name [] [] (presets.length + 2)).1, (e.2.splitOn "@").length ≠ 2) :
    implReasons presets name = [] := by
  unfold implReasons
  rw [List.filterMap_eq_nil_iff]
  intro e he
  have := h e he
  cases hs : e.2.splitOn "@" with
  | nil => rfl
  | cons a t =>
    cases t with
    | nil => rfl
    | cons b u =>
      cases u with
      | nil => rw [hs] at this; exact absurd rfl this
      | cons c w => rfl

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

/-- The refusal text of a refuted variant: the first live refuting row among its rows. -/
def refusalOf (rows : List LRow) (idx : List Nat) : Option String :=
  (live (idx.filterMap fun i => rows[i]?)).find? (·.status == "refuted") |>.map fun r => "refuted by the finding \"" ++ clip r.candidate ++ "\""

/-- The errors of a ledger: a `supersededBy` that names no row's `id`. -/
def supersedeErrors (rows : List LRow) : List String :=
  rows.filterMap fun r =>
    match r.supersededBy with
    | some s => if rows.any (·.id == some s) then none
      else some s!"ledger row \"{clip r.candidate}\": supersededBy \"{s}\" names no ledger row id"
    | none => none

/-- **A dangling `supersededBy` is an error**: the ledger has no error exactly when every `supersededBy` names an `id` of a row. -/
theorem supersedeErrors_nil_iff (rows : List LRow) :
    supersedeErrors rows = [] ↔ ∀ r ∈ rows, ∀ s, r.supersededBy = some s → ∃ r' ∈ rows, r'.id = some s := by
  unfold supersedeErrors
  rw [List.filterMap_eq_nil_iff]
  refine ⟨fun h r hr s hs => ?_, fun h r hr => ?_⟩
  · have := h r hr
    rw [hs] at this
    simp only [] at this
    split at this
    · rename_i ha
      obtain ⟨r', hr', he⟩ := List.any_eq_true.1 ha
      exact ⟨r', hr', by simpa using he⟩
    · cases this
  · cases hs : r.supersededBy with
    | none => rfl
    | some s =>
      obtain ⟨r', hr', he⟩ := h r hr s hs
      have : rows.any (·.id == some s) = true := List.any_eq_true.2 ⟨r', hr', by simp [he]⟩
      simp [this]

/-- In a ledger with no error, a row of a variant that has a `supersededBy` brings the row of that `id` into the variant's rows. -/
theorem varRows_superseded_by (rows : List LRow) (p : PartInfo) (v : String) (hok : supersedeErrors rows = []) (i : Nat)
    (hi : i ∈ rowsFor rows p v) (r : LRow) (hr : rows[i]? = some r) (s : String) (hs : r.supersededBy = some s) :
    ∃ j, j ∈ varRows rows p v ∧ ∃ h : j < rows.length, rows[j].id = some s := by
  obtain ⟨r', hr', he⟩ := (supersedeErrors_nil_iff rows).1 hok r (List.mem_of_getElem? hr) s hs
  have hsome : (idxOf rows s).isSome = true := by
    rw [idxOf, List.findIdx?_isSome]
    exact List.any_eq_true.2 ⟨r', hr', by simp [he]⟩
  obtain ⟨j, hj⟩ := Option.isSome_iff_exists.1 hsome
  have hn : nextOf rows i = some j := by simp [nextOf, hr, hs, hj]
  obtain ⟨hlt, hid, _⟩ := List.findIdx?_eq_some_iff_getElem.1 hj
  exact ⟨j, varRows_superseding rows p v i j hi hn, hlt, by simpa using hid⟩

/-- The coupled group of a part in the part contract (`solo` when the contract has no row). -/
def groupOf (id : String) : String := ((Fw.Parts.Contract.parts.find? (·.id == id)).map (·.group.name)).getD "solo"

/-- The part is page-level in the part contract. -/
def pageLevelOf (id : String) : Bool := ((Fw.Parts.Contract.parts.find? (·.id == id)).map Fw.Parts.Contract.pageLevel).getD false

/-- One part's card: every variant with its class and rows (`varRows`: the superseding rows join by identity). -/
def partOut (rows : List LRow) (proved : List (String × String)) (p : PartInfo) : PartOut :=
  { id := p.id, slot := p.slot, group := groupOf p.id, pageLevel := pageLevelOf p.id, other := otherRows rows p
    variants := p.variants.map fun v =>
      let idx := varRows rows p v.name
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

/-! ## Fixtures

Small registries checked at build time. The goldens (`console.compose`) check the same decisions through the wire. -/

namespace Fixture
open Fw.Console.BuildsOpen

private def vf (n k : String) (l : String := "") : VariantFact := { name := n, kind := k, limit := l }
private def pi (id slot : String) (vs : List VariantFact) (req : List (String × List String) := []) : PartInfo :=
  { id := id, slot := slot, variants := vs, impls := ["plain"], requires := req, conflicts := [] }

/-- Two regions given out of page order; `b` requires `a:fast`. -/
def parts : List PartInfo :=
  [pi "p.late" "morph" [vf "faithful" "faithful", vf "fast" "optimized", vf "bad" "optimized"],
   pi "p.early" "hero" [vf "faithful" "faithful", vf "fast" "optimized", vf "look" "optimized" "look change: dimmer"]
     [("p.early:fast", ["p.late:fast"])]]

def rows : List LRow :=
  [{ part := "p.late", candidate := "p.late `fast`", status := "measured", flag := none },
   { part := "p.late", candidate := "p.late `bad`", status := "refuted", flag := some "p.late:bad" },
   { part := "p.early", candidate := "p.early `fast`", status := "proved", flag := none }]

#guard (ordered parts).map (·.id) == ["p.early", "p.late"]
#guard (decide parts rows [] []).link == some ""
#guard (decide parts rows [] [("p.late", "fast")]).link == some "?fw=p.late:fast"
#guard (decide parts rows [] [("p.late", "fast"), ("p.early", "look")]).link == some "?fw=p.early:look,p.late:fast"
#guard (decide parts rows [] [("p.late", "bad")]).link == none
#guard (decide parts rows [] [("p.early", "fast")]).link == none
#guard (decide parts rows [] [("p.early", "fast"), ("p.late", "fast")]).link == some "?fw=p.early:fast,p.late:fast"
#guard (decide parts rows [] [("p.nope", "x")]).link == none
#guard (decide parts rows [] [("p.late", "nope")]).link == none
#guard (decide parts rows [] [("p.late", "fast"), ("p.late", "faithful")]).link == some ""
#guard ((table parts rows []).map fun p => (p.id, p.variants.map (·.cls.name))) ==
  [("p.early", ["original", "ledger-proved", "look-change"]), ("p.late", ["original", "measured", "refuted"])]
#guard supersedeErrors rows == []

/-- The rows above with the refuting row of `p.late:bad` superseded by a proved row whose text names no variant. -/
def fixedRows : List LRow :=
  [{ part := "p.late", candidate := "p.late `fast`", status := "measured", flag := none },
   { part := "p.late", candidate := "p.late `bad`", status := "refuted", flag := some "p.late:bad", id := some "bad.falsified",
     supersededBy := some "bad.fixed" },
   { part := "p.early", candidate := "p.early `fast`", status := "proved", flag := none },
   { part := "p.late", candidate := "the fixed driver", status := "proved", flag := none, id := some "bad.fixed" }]

#guard supersedeErrors fixedRows == []
#guard ((table parts fixedRows []).map fun p => (p.id, p.variants.map (·.cls.name))) ==
  [("p.early", ["original", "ledger-proved", "look-change"]), ("p.late", ["original", "measured", "ledger-proved"])]
#guard ((table parts fixedRows []).map fun p => (p.id, p.variants.map (·.rows), p.other)) ==
  [("p.early", [[], [2], []], []), ("p.late", [[], [0], [1, 3]], [])]
#guard ((table parts fixedRows []).flatMap fun p => p.variants.filterMap (·.refusal)) == []
#guard (decide parts fixedRows [] [("p.late", "bad")]).link == some "?fw=p.late:bad"
#guard (supersedeErrors (fixedRows.take 3)).length == 1
#guard (supersedeErrors (fixedRows.map fun r => { r with id := none })).length == 1

/-- Presets: one with a default impl, one with a non-default impl. -/
def presets : List PresetFact :=
  [{ name := "ok", base := none, fw := [("p.late", "fast@mui")] }, { name := "alt", base := none, fw := [("p.late", "fast@plain")] }]

#guard implReasons presets "ok" == []
#guard (implReasons presets "alt").length == 1

end Fixture

end Fw.Console.Compose
