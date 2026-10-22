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
* `rowsFor`: the ledger rows whose `flags` name a variant; `flagErrors` and `supersedeErrors` refuse a ledger that breaks it.
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

/-- The identity columns of one findings-ledger row: `flags` (the `part:variant` keys it is about, `none` when the field is
missing), the optional single `flag` the preset gate reads, `id`, and `supersededBy` (the `id` of the row that replaced it). -/
structure LRow where
  part : String
  candidate : String
  status : String
  flag : Option String := none
  flags : Option (List String) := none
  id : Option String := none
  supersededBy : Option String := none
deriving Repr, DecidableEq

/-- The flags of a row; a row without the field has none. -/
def LRow.flagList (r : LRow) : List String := r.flags.getD []

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

/-- The flag key of variant `v` of part `p`. -/
def flagKey (p : PartInfo) (v : String) : String := p.id ++ ":" ++ v

/-- A ledger row speaks of variant `v` of part `p` exactly when its `flags` list has the key `p.id:v`. -/
def matchRow (p : PartInfo) (v : String) (r : LRow) : Bool := r.flagList.contains (flagKey p v)

/-- The indices of the ledger rows that speak of variant `v` of part `p`, in ledger order. -/
def rowsFor (rows : List LRow) (p : PartInfo) (v : String) : List Nat :=
  (rows.zipIdx.filter (fun e => matchRow p v e.1)).map (·.2)

theorem mem_rowsFor (rows : List LRow) (p : PartInfo) (v : String) (i : Nat) :
    i ∈ rowsFor rows p v ↔ ∃ h : i < rows.length, flagKey p v ∈ rows[i].flagList := by
  simp only [rowsFor, matchRow, List.mem_map, List.mem_filter, List.contains_iff_mem]
  constructor
  · rintro ⟨⟨r, j⟩, ⟨hm, hk⟩, rfl⟩
    obtain ⟨hlt, hget⟩ := List.getElem?_eq_some_iff.1 (List.mem_zipIdx_iff_getElem?.1 hm)
    exact ⟨hlt, by rw [hget]; exact hk⟩
  · rintro ⟨hlt, hk⟩
    exact ⟨(rows[i], i), ⟨List.mem_zipIdx_iff_getElem?.2 (by simp [hlt]), hk⟩, rfl⟩

/-! ## Flag errors -/

/-- The first 80 characters of a text. -/
def clip (s : String) : String := String.ofList (s.toList.take 80)

/-- A key `part:variant` names a registered variant of a registered part. -/
def knownFlag (parts : List PartInfo) (f : String) : Bool :=
  match f.splitOn ":" with
  | [a, b] => parts.any fun p => p.id == a && hasVariant p b
  | _ => false

/-- The flag errors of one row: no `flags` field, a flag naming no registered variant, a `flag` missing from its `flags`. -/
def rowFlagErrors (parts : List PartInfo) (r : LRow) : List String :=
  match r.flags with
  | none => [s!"ledger row \"{clip r.candidate}\": no flags field (the part:variant flags it is about, [] for none)"]
  | some fs =>
    (fs.filter (!knownFlag parts ·)).map (fun f => s!"ledger row \"{clip r.candidate}\": flag \"{f}\" names no registered part:variant") ++
    match r.flag with
    | some f => if fs.contains f then [] else [s!"ledger row \"{clip r.candidate}\": its flag \"{f}\" is not in its flags"]
    | none => []

/-- The flag errors of a ledger. -/
def flagErrors (parts : List PartInfo) (rows : List LRow) : List String := rows.flatMap (rowFlagErrors parts)

/-- **No flag error exactly when every row has a `flags` list of registered keys that holds its `flag`.** -/
theorem flagErrors_nil_iff (parts : List PartInfo) (rows : List LRow) :
    flagErrors parts rows = [] ↔ ∀ r ∈ rows, ∃ fs, r.flags = some fs ∧ (∀ f ∈ fs, knownFlag parts f = true) ∧
      ∀ f, r.flag = some f → f ∈ fs := by
  simp only [flagErrors, List.flatMap_eq_nil_iff]
  refine forall_congr' fun r => imp_congr_right fun _ => ?_
  unfold rowFlagErrors
  cases hfs : r.flags with
  | none => simp
  | some fs =>
    cases hf : r.flag with
    | none => simp [List.filter_eq_nil_iff]
    | some f => by_cases hc : f ∈ fs <;> simp [List.filter_eq_nil_iff, hc]

/-- **A row without `flags` is an error.** -/
theorem flagErrors_missing (parts : List PartInfo) (rows : List LRow) (r : LRow) (hr : r ∈ rows) (h : r.flags = none) :
    flagErrors parts rows ≠ [] := by
  intro hok
  obtain ⟨fs, hfs, _⟩ := (flagErrors_nil_iff parts rows).1 hok r hr
  simp [h] at hfs

/-- **A flag naming no registered part:variant is an error.** -/
theorem flagErrors_unknown (parts : List PartInfo) (rows : List LRow) (r : LRow) (hr : r ∈ rows) (fs : List String)
    (h : r.flags = some fs) (f : String) (hf : f ∈ fs) (hu : knownFlag parts f = false) : flagErrors parts rows ≠ [] := by
  intro hok
  obtain ⟨gs, hgs, hk, _⟩ := (flagErrors_nil_iff parts rows).1 hok r hr
  rw [h] at hgs
  cases hgs
  simp [hk f hf] at hu

/-- **A `flag` that is not in the row's `flags` is an error.** -/
theorem flagErrors_flag_not_in (parts : List PartInfo) (rows : List LRow) (r : LRow) (hr : r ∈ rows) (fs : List String)
    (h : r.flags = some fs) (f : String) (hf : r.flag = some f) (hn : f ∉ fs) : flagErrors parts rows ≠ [] := by
  intro hok
  obtain ⟨gs, hgs, _, hin⟩ := (flagErrors_nil_iff parts rows).1 hok r hr
  rw [h] at hgs
  cases hgs
  exact hn (hin f hf)

/-! ## Superseded rows -/

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

/-- Row `i` reaches a live row by following `supersededBy` ids through at most `fuel` rows. A dangling id, a
self-reference or a cycle never does. -/
def reachesLive (rows : List LRow) : Nat → Nat → Bool
  | 0, _ => false
  | fuel + 1, i =>
    match rows[i]? with
    | none => false
    | some r => r.live || match nextOf rows i with
      | some j => reachesLive rows fuel j
      | none => false

/-- A row that reaches a live row is live itself or has that live row among its successors. -/
theorem reachesLive_sound (rows : List LRow) (fuel i : Nat) (h : reachesLive rows fuel i = true) :
    ∃ j ∈ i :: successors rows fuel i, ∃ hj : j < rows.length, rows[j].live = true := by
  induction fuel generalizing i with
  | zero => simp [reachesLive] at h
  | succ f ih =>
    cases hr : rows[i]? with
    | none => simp [reachesLive, hr] at h
    | some r =>
      obtain ⟨hlt, hget⟩ := List.getElem?_eq_some_iff.1 hr
      by_cases hl : r.live = true
      · exact ⟨i, List.mem_cons_self .., hlt, by rw [hget]; exact hl⟩
      · cases hn : nextOf rows i with
        | none => simp [reachesLive, hr, hn, hl] at h
        | some j =>
          have hj : reachesLive rows f j = true := by simpa [reachesLive, hr, hn, hl] using h
          obtain ⟨k, hk, hklt, hkl⟩ := ih j hj
          refine ⟨k, ?_, hklt, hkl⟩
          simp only [successors, hn]
          exact List.mem_cons_of_mem _ hk

/-- The row that supersedes a row is a row of the ledger. -/
theorem nextOf_lt (rows : List LRow) (i j : Nat) (h : nextOf rows i = some j) : j < rows.length := by
  unfold nextOf idxOf at h
  cases hs : rows[i]?.bind (·.supersededBy) with
  | none => simp [hs] at h
  | some s =>
    rw [hs, Option.bind_some] at h
    exact (List.findIdx?_eq_some_iff_getElem.1 h).1

/-- The indices of the rows whose `part` text names part `p` and that speak of none of its variants. -/
def otherRows (rows : List LRow) (p : PartInfo) : List Nat :=
  (rows.zipIdx.filter (fun e => (rowParts e.1.part).contains p.id && !(p.variants.any (fun v => matchRow p v.name e.1)))).map (·.2)

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

/-- The refusal text of a refuted variant: the first live refuting row among its rows. -/
def refusalOf (rows : List LRow) (idx : List Nat) : Option String :=
  (live (idx.filterMap fun i => rows[i]?)).find? (·.status == "refuted") |>.map fun r => "refuted by the finding \"" ++ clip r.candidate ++ "\""

/-- The chain errors of a ledger: a superseded row whose `supersededBy` chain reaches no live row within `rows.length` rows
(a dangling id, a self-reference or a cycle), and a row whose `id` an earlier row already has. -/
def chainErrors (rows : List LRow) : List String :=
  rows.zipIdx.filterMap (fun e =>
    match e.1.supersededBy with
    | some s =>
      if reachesLive rows rows.length e.2 then none
      else if rows.any (·.id == some s) then
        some s!"ledger row \"{clip e.1.candidate}\": its supersededBy chain from \"{s}\" reaches no live row (a self-reference, a cycle or a dangling id on the way)"
      else some s!"ledger row \"{clip e.1.candidate}\": supersededBy \"{s}\" names no ledger row id"
    | none => none) ++
  rows.zipIdx.filterMap fun e =>
    match e.1.id with
    | some s => if idxOf rows s == some e.2 then none else some s!"ledger row \"{clip e.1.candidate}\": id \"{s}\" is an earlier row's id"
    | none => none

/-- **No chain error exactly when every superseded row reaches a live row and no two rows share an `id`.** -/
theorem chainErrors_nil_iff (rows : List LRow) :
    chainErrors rows = [] ↔
      (∀ i (h : i < rows.length), rows[i].live = false → reachesLive rows rows.length i = true) ∧
      (∀ i (h : i < rows.length) s, rows[i].id = some s → idxOf rows s = some i) := by
  unfold chainErrors
  rw [List.append_eq_nil_iff, List.filterMap_eq_nil_iff, List.filterMap_eq_nil_iff]
  refine and_congr ⟨fun h i hi hl => ?_, fun h e he => ?_⟩ ⟨fun h i hi s hs => ?_, fun h e he => ?_⟩
  · have := h (rows[i], i) (List.mem_zipIdx_iff_getElem?.2 (by simp))
    cases hs : rows[i].supersededBy with
    | none => simp [LRow.live, hs] at hl
    | some s =>
      simp only [hs] at this
      split at this
      · assumption
      · split at this <;> cases this
  · obtain ⟨hlt, hget⟩ := List.getElem?_eq_some_iff.1 (List.mem_zipIdx_iff_getElem?.1 he)
    cases hs : e.1.supersededBy with
    | none => rfl
    | some s =>
      have hl : rows[e.2].live = false := by simp [LRow.live, hget, hs]
      simp [h e.2 hlt hl]
  · have := h (rows[i], i) (List.mem_zipIdx_iff_getElem?.2 (by simp))
    simp only [hs] at this
    split at this
    · simpa using (by assumption : (idxOf rows s == some i) = true)
    · cases this
  · obtain ⟨hlt, hget⟩ := List.getElem?_eq_some_iff.1 (List.mem_zipIdx_iff_getElem?.1 he)
    cases hs : e.1.id with
    | none => rfl
    | some s => simp [h e.2 hlt s (by rw [hget]; exact hs)]

/-- The flags of row `i` that the row superseding it does not have. -/
def lostFlags (rows : List LRow) (i : Nat) : List String :=
  match nextOf rows i with
  | some j => ((rows[i]?.map (·.flagList)).getD []).filter fun f => !((rows[j]?.map (·.flagList)).getD []).contains f
  | none => []

/-- The cross-flag errors of a ledger: a row superseded by a row that is not about every flag of it. -/
def crossErrors (rows : List LRow) : List String :=
  rows.zipIdx.filterMap fun e =>
    match lostFlags rows e.2 with
    | [] => none
    | fs => some s!"ledger row \"{clip e.1.candidate}\": its supersededBy row is not about {", ".intercalate fs}"

/-- The errors of a ledger's `id` and `supersededBy` columns: the chain errors and the cross-flag errors. -/
def supersedeErrors (rows : List LRow) : List String := chainErrors rows ++ crossErrors rows

theorem crossErrors_nil_iff (rows : List LRow) :
    crossErrors rows = [] ↔ ∀ i, i < rows.length → lostFlags rows i = [] := by
  unfold crossErrors
  rw [List.filterMap_eq_nil_iff]
  constructor
  · intro h i hi
    have := h (rows[i], i) (List.mem_zipIdx_iff_getElem?.2 (by simp))
    revert this
    cases lostFlags rows i <;> simp
  · intro h e he
    obtain ⟨hlt, _⟩ := List.getElem?_eq_some_iff.1 (List.mem_zipIdx_iff_getElem?.1 he)
    simp [h e.2 hlt]

/-- **No error exactly when every superseded row reaches a live row, no two rows share an `id`, and every superseding row
is about every flag of the row it supersedes.** -/
theorem supersedeErrors_nil_iff (rows : List LRow) :
    supersedeErrors rows = [] ↔
      ((∀ i (h : i < rows.length), rows[i].live = false → reachesLive rows rows.length i = true) ∧
        (∀ i (h : i < rows.length) s, rows[i].id = some s → idxOf rows s = some i)) ∧
      ∀ i, i < rows.length → lostFlags rows i = [] := by
  rw [supersedeErrors, List.append_eq_nil_iff, chainErrors_nil_iff, crossErrors_nil_iff]

/-- **A row superseded by a row not about one of its flags is an error.** -/
theorem supersedeErrors_cross (rows : List LRow) (i j : Nat) (hi : i < rows.length) (hn : nextOf rows i = some j) (f : String)
    (hf : f ∈ rows[i].flagList) (hj : f ∉ (rows[j]'(nextOf_lt rows i j hn)).flagList) : supersedeErrors rows ≠ [] := by
  intro hok
  have hl := ((supersedeErrors_nil_iff rows).1 hok).2 i hi
  have hjl := nextOf_lt rows i j hn
  simp only [lostFlags, hn, List.getElem?_eq_getElem hi, List.getElem?_eq_getElem hjl, Option.map_some, Option.getD_some,
    List.filter_eq_nil_iff] at hl
  exact hj (by simpa using hl f hf)

/-- **In a ledger with no error, the row superseding a row is about every flag of it.** -/
theorem supersedeErrors_nil_about (rows : List LRow) (hok : supersedeErrors rows = []) (i j : Nat) (hi : i < rows.length)
    (hn : nextOf rows i = some j) (f : String) (hf : f ∈ rows[i].flagList) :
    f ∈ (rows[j]'(nextOf_lt rows i j hn)).flagList :=
  Classical.byContradiction fun hj => supersedeErrors_cross rows i j hi hn f hf hj hok

/-- **In a ledger with no error, every superseded row reaches a live row** among its successors. -/
theorem supersedeErrors_nil_reaches (rows : List LRow) (hok : supersedeErrors rows = []) (i : Nat) (hi : i < rows.length)
    (hs : rows[i].live = false) : ∃ j ∈ successors rows rows.length i, ∃ hj : j < rows.length, rows[j].live = true := by
  obtain ⟨j, hj, hjlt, hjl⟩ := reachesLive_sound rows _ i ((supersedeErrors_nil_iff rows).1 hok |>.1.1 i hi hs)
  rcases List.mem_cons.1 hj with rfl | hj
  · simp [hs] at hjl
  · exact ⟨j, hj, hjlt, hjl⟩

/-- The successors of a row in a set of rows that `nextOf` maps into itself stay in the set. -/
theorem successors_closed (rows : List LRow) (S : List Nat) (hc : ∀ i ∈ S, ∀ j, nextOf rows i = some j → j ∈ S)
    (fuel i : Nat) (hi : i ∈ S) : ∀ j ∈ successors rows fuel i, j ∈ S := by
  induction fuel generalizing i with
  | zero => simp [successors]
  | succ f ih =>
    cases hn : nextOf rows i with
    | none => simp [successors, hn]
    | some k =>
      simp only [successors, hn, List.mem_cons]
      rintro j (rfl | hj)
      · exact hc i hi j hn
      · exact ih k (hc i hi k hn) j hj

/-- **A self-reference or a cycle is an error**: rows that are all superseded and whose `supersededBy` ids name rows of the
same set make the error list non-empty. -/
theorem supersedeErrors_cycle (rows : List LRow) (S : List Nat) (hs : ∀ i ∈ S, ∃ h : i < rows.length, rows[i].live = false)
    (hc : ∀ i ∈ S, ∀ j, nextOf rows i = some j → j ∈ S) (i : Nat) (hi : i ∈ S) : supersedeErrors rows ≠ [] := by
  intro hok
  obtain ⟨hlt, hl⟩ := hs i hi
  obtain ⟨j, hj, hjlt, hjl⟩ := supersedeErrors_nil_reaches rows hok i hlt hl
  obtain ⟨_, hjs⟩ := hs j (successors_closed rows S hc _ i hi j hj)
  simp [hjs] at hjl

/-- **A row whose `supersededBy` names its own `id` is an error.** -/
theorem supersedeErrors_self (rows : List LRow) (i : Nat) (hi : i < rows.length) (s : String)
    (hs : rows[i].supersededBy = some s) (hid : idxOf rows s = some i) : supersedeErrors rows ≠ [] := by
  refine supersedeErrors_cycle rows [i] (fun k hk => ?_) (fun k hk j hj => ?_) i (List.mem_singleton_self i)
  · rw [List.mem_singleton.1 hk]; exact ⟨hi, by simp [LRow.live, hs]⟩
  · rw [List.mem_singleton.1 hk] at hj
    simp [nextOf, List.getElem?_eq_getElem hi, hs, hid] at hj
    simp [hj]

/-- **In a ledger with no error, every row superseding a row of a variant, transitively, is a row of the variant.** -/
theorem rowsFor_successor (rows : List LRow) (p : PartInfo) (v : String) (hok : supersedeErrors rows = []) (fuel i : Nat)
    (hi : i ∈ rowsFor rows p v) : ∀ j ∈ successors rows fuel i, j ∈ rowsFor rows p v := by
  refine successors_closed rows _ (fun k hk j hn => ?_) fuel i hi
  obtain ⟨hklt, hkf⟩ := (mem_rowsFor rows p v k).1 hk
  exact (mem_rowsFor rows p v j).2 ⟨nextOf_lt rows k j hn, supersedeErrors_nil_about rows hok k j hklt hn _ hkf⟩

/-- **In a ledger with no error, a superseded row of a variant has a live row of the variant among its successors.** -/
theorem rowsFor_reaches_live (rows : List LRow) (p : PartInfo) (v : String) (hok : supersedeErrors rows = []) (i : Nat)
    (hi : i ∈ rowsFor rows p v) (hlt : i < rows.length) (hs : rows[i].live = false) :
    ∃ j ∈ rowsFor rows p v, ∃ hj : j < rows.length, rows[j].live = true := by
  obtain ⟨j, hj, hjlt, hjl⟩ := supersedeErrors_nil_reaches rows hok i hlt hs
  exact ⟨j, rowsFor_successor rows p v hok _ i hi j hj, hjlt, hjl⟩

/-- The coupled group of a part in the part contract (`solo` when the contract has no row). -/
def groupOf (id : String) : String := ((Fw.Parts.Contract.parts.find? (·.id == id)).map (·.group.name)).getD "solo"

/-- The part is page-level in the part contract. -/
def pageLevelOf (id : String) : Bool := ((Fw.Parts.Contract.parts.find? (·.id == id)).map Fw.Parts.Contract.pageLevel).getD false

/-- One part's card: every variant with its class and rows (`rowsFor`: the rows whose `flags` name it). -/
def partOut (rows : List LRow) (proved : List (String × String)) (p : PartInfo) : PartOut :=
  { id := p.id, slot := p.slot, group := groupOf p.id, pageLevel := pageLevelOf p.id, other := otherRows rows p
    variants := p.variants.map fun v =>
      let idx := rowsFor rows p v.name
      let rs := idx.filterMap fun i => rows[i]?
      let c := classOf v (proved.contains (p.id, v.name)) rs
      { name := v.name, kind := v.kind, isDefault := v.name == defaultOf p, cls := c, rows := idx,
        refusal := if c == .refuted then refusalOf rows idx else none } }

/-- **Every row on a variant's card is about that variant**: its `flags` name it. -/
theorem partOut_rows_about (rows : List LRow) (proved : List (String × String)) (p : PartInfo) (o : VarOut)
    (ho : o ∈ (partOut rows proved p).variants) (i : Nat) (hi : i ∈ o.rows) :
    ∃ h : i < rows.length, flagKey p o.name ∈ rows[i].flagList := by
  obtain ⟨v, _, rfl⟩ := List.mem_map.1 ho
  exact (mem_rowsFor rows p v.name i).1 hi

/-- **The superseding rows' class reaches the card.** In a ledger with no error, let `news` be the live rows of variant `v`'s
rows. The card of `v` lists `rowsFor`, its class is `classOf` of `news`, and every superseded row of `v` brings a row of
`news` into the card's rows. -/
theorem partOut_superseding (rows : List LRow) (proved : List (String × String)) (p : PartInfo) (v : VariantFact)
    (hv : v ∈ p.variants) (hok : supersedeErrors rows = []) (news : List LRow)
    (hnews : live ((rowsFor rows p v.name).filterMap fun i => rows[i]?) = news) :
    ∃ o ∈ (partOut rows proved p).variants, o.name = v.name ∧ o.rows = rowsFor rows p v.name ∧
      o.cls = classOf v (proved.contains (p.id, v.name)) news ∧
      ∀ i ∈ rowsFor rows p v.name, ∀ hi : i < rows.length, rows[i].live = false →
        ∃ j ∈ o.rows, ∃ hj : j < rows.length, rows[j] ∈ news := by
  refine ⟨_, List.mem_map_of_mem hv, rfl, rfl, ?_, fun i hr hi hs => ?_⟩
  · have hll : ∀ l : List LRow, live (live l) = live l := fun l => by simp [live, List.filter_filter]
    simp only [classOf, ← hnews, hll]
  · obtain ⟨j, hj, hjlt, hjl⟩ := rowsFor_reaches_live rows p v.name hok i hr hi hs
    refine ⟨j, hj, hjlt, ?_⟩
    rw [← hnews, live, List.mem_filter]
    exact ⟨List.mem_filterMap.2 ⟨j, hj, List.getElem?_eq_getElem hjlt⟩, hjl⟩

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
      generalize hE : searchErrors parts presets (params (body s)) = es at h
      cases es with
      | nil => cases h
      | cons a t =>
        rw [verdictOf_refused _ _ _ _ (List.cons_ne_nil a t)] at h
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
  [{ part := "p.late", candidate := "p.late `fast`", status := "measured", flags := some ["p.late:fast"] },
   { part := "p.late", candidate := "p.late `bad`", status := "refuted", flag := some "p.late:bad",
     flags := some ["p.late:bad"] },
   { part := "p.early", candidate := "p.early `fast`", status := "proved", flags := some ["p.early:fast"] }]

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

/-- The rows above with the refuting row of `p.late:bad` superseded by a proved row about `p.late:bad`. -/
def fixedRows : List LRow :=
  [{ part := "p.late", candidate := "p.late `fast`", status := "measured", flags := some ["p.late:fast"] },
   { part := "p.late", candidate := "p.late `bad`", status := "refuted", flag := some "p.late:bad",
     flags := some ["p.late:bad"], id := some "bad.falsified",
     supersededBy := some "bad.fixed" },
   { part := "p.early", candidate := "p.early `fast`", status := "proved", flags := some ["p.early:fast"] },
   { part := "p.late", candidate := "the fixed driver", status := "proved", flags := some ["p.late:bad"],
     id := some "bad.fixed" }]

#guard supersedeErrors fixedRows == []
#guard ((table parts fixedRows []).map fun p => (p.id, p.variants.map (·.cls.name))) ==
  [("p.early", ["original", "ledger-proved", "look-change"]), ("p.late", ["original", "measured", "ledger-proved"])]
#guard ((table parts fixedRows []).map fun p => (p.id, p.variants.map (·.rows), p.other)) ==
  [("p.early", [[], [2], []], []), ("p.late", [[], [0], [1, 3]], [])]
#guard ((table parts fixedRows []).flatMap fun p => p.variants.filterMap (·.refusal)) == []
#guard (decide parts fixedRows [] [("p.late", "bad")]).link == some "?fw=p.late:bad"
#guard (supersedeErrors (fixedRows.take 3)).length == 1
#guard (supersedeErrors (fixedRows.map fun r => { r with id := none })).length == 1

/-- `fixedRows` with row `i`'s `supersededBy` set to `s`. -/
def withSup (i : Nat) (s : String) : List LRow := fixedRows.modify i fun r => { r with supersededBy := some s }

#guard (supersedeErrors (withSup 1 "bad.falsified")).length == 1
#guard (supersedeErrors (withSup 1 "bad.falsified")).head?.map (fun e => (e.splitOn "self-reference").length) == some 2
#guard (supersedeErrors (withSup 3 "bad.falsified")).length == 2
#guard (supersedeErrors (fixedRows ++
    [{ part := "p.late", candidate := "a second fix", status := "proved", flags := some ["p.late:bad"], id := some "bad.fixed" }]
    )).length == 1

/-- `fixedRows` with the fix itself superseded by a later row: a chain of two. -/
def chainRows : List LRow :=
  withSup 3 "bad.fixed2" ++
    [{ part := "p.late", candidate := "the second fix", status := "measured", flags := some ["p.late:bad"], id := some "bad.fixed2" }]

#guard supersedeErrors chainRows == []
#guard ((table parts chainRows []).map fun p => (p.id, p.variants.map (·.rows), p.variants.map (·.cls.name))) ==
  [("p.early", [[], [2], []], ["original", "ledger-proved", "look-change"]),
   ("p.late", [[], [0], [1, 3, 4]], ["original", "measured", "measured"])]

#guard knownFlag parts "p.late:bad"
#guard !knownFlag parts "p.late:nope"
#guard !knownFlag parts "p.nope:fast"
#guard !knownFlag parts "p.late"
#guard !knownFlag parts "p.late:fast:x"
#guard flagErrors parts rows == []
#guard flagErrors parts chainRows == []
#guard (flagErrors parts (rows.modify 0 fun r => { r with flags := none })).length == 1
#guard (flagErrors parts (rows.modify 0 fun r => { r with flags := some ["p.late:nope", "p.nope:fast"] })).length == 2
#guard (flagErrors parts (rows.modify 1 fun r => { r with flags := some ["p.late:fast"] })).length == 1
#guard (flagErrors parts (rows.modify 0 fun r => { r with flags := some [] })) == []

/-- `fixedRows` with the fix about `p.late:fast` only: the superseded row's `p.late:bad` is lost. -/
def crossRows : List LRow := fixedRows.modify 3 fun r => { r with flags := some ["p.late:fast"] }

#guard (crossErrors crossRows).length == 1
#guard (supersedeErrors crossRows).length == 1
#guard chainErrors crossRows == []
#guard supersedeErrors (fixedRows.modify 3 fun r => { r with flags := some ["p.late:bad", "p.late:fast"] }) == []

/-- Presets: one with a default impl, one with a non-default impl. -/
def presets : List PresetFact :=
  [{ name := "ok", base := none, fw := [("p.late", "fast@mui")] }, { name := "alt", base := none, fw := [("p.late", "fast@plain")] }]

#guard implReasons presets "ok" == []
#guard (implReasons presets "alt").length == 1

end Fixture

end Fw.Console.Compose
