import Fw.Console.Compose
import Fw.Parts.Footprint
import Fw.Engine.Compose
import Fw.Parts.FootprintData
/-!
# Layer composer: units, clash, expansion, look grade and premises of an arm

An arm is a base (the faithful page, or the original snapshot), a list of Changes (named sets of picks with an optional
combined theorem), the user's own picks and layer options (`layer:c` composite, `layer:s` snap, `layer:cs` both). Each
Change, pick and option is one unit. The decisions run over the whole expanded page:

* `clash`: two units touch each other (a shared write, a write or clear that a read of the other sees, a write into the
  other's elements, or contract rows failing I2 or I4). Between units it refuses the arm; inside one Change it is
  coupled and needs the Change's combined theorem.
* Expansion never overrides: a part set by two units refuses the arm, and `fix` names the user picks to drop, closed
  under `requires`.
* `look`: a grade `E < E1 < Q < L`. Only `E` composes (`look_E_sound`, from `Fw.Engine.lego_swap_visible_units`); any
  other grade is the expected grade, and the verdict comes from the arm's own measured cells.
* `premises`: what a run of the arm must check, per layer option and for the page.
* `searchOf`: the canonical search `?fw=...&fwl=...`, which `Fw.Console.BuildsOpen.validate` accepts for every allowed
  arm (`link_resolves`).

Footprints come from the extractor (`Fw.Parts.FootprintData`): a pick's own records are those of its variant and not
of the default; its cleared records are those of the default and not of the variant. A variant with no own file has
no footprint of its own and is refused as not extractable.
-/
namespace Fw.Console.Layers
open Fw.Console.BuildsOpen Fw.Console.Compose
open Fw.Parts.Footprint (Access same splitKind reads writes)

/-! ## Look grade -/

/-- A look grade: `E` the same look (a theorem), `E1` within one level (a theorem bounds it), `Q` measured only, `L`
a look change. -/
inductive Grade | E | E1 | Q | L
deriving Repr, DecidableEq

/-- Order of the grades: `E` best, `L` worst. -/
def Grade.rank : Grade → Nat | .E => 0 | .E1 => 1 | .Q => 2 | .L => 3

/-- Golden name of a grade. -/
def Grade.name : Grade → String | .E => "E" | .E1 => "E1" | .Q => "Q" | .L => "L"

/-- The worse of two grades. -/
def Grade.max (a b : Grade) : Grade := if a.rank < b.rank then b else a

/-- The worst grade of a list; `E` for none. -/
def worst : List Grade → Grade
  | [] => .E
  | g :: gs => g.max (worst gs)

theorem Grade.max_eq_E (a b : Grade) : a.max b = .E ↔ a = .E ∧ b = .E := by
  cases a <;> cases b <;> decide

theorem Grade.max_L_left (b : Grade) : Grade.L.max b = .L := by cases b <;> decide

theorem Grade.max_L_right (a : Grade) : a.max .L = .L := by cases a <;> decide

/-- The worst grade is `E` exactly when every grade is `E`. -/
theorem worst_eq_E (gs : List Grade) : worst gs = .E ↔ ∀ g ∈ gs, g = .E := by
  induction gs with
  | nil => simp [worst]
  | cons g gs ih => simp [worst, Grade.max_eq_E, ih]

/-- One `L` makes the worst grade `L`. -/
theorem worst_L (gs : List Grade) (h : Grade.L ∈ gs) : worst gs = .L := by
  induction gs with
  | nil => cases h
  | cons g gs ih =>
    rcases List.mem_cons.1 h with rfl | h'
    · exact Grade.max_L_left _
    · simp only [worst]; rw [ih h']; exact Grade.max_L_right _

/-! ## Facts -/

/-- One variant as the layer decisions read its part.json entry: `visClass` and `lean` from its provenance (`""` when
absent), `refuted` the ledger's refusal text (`""` when not refuted), `files` its `files` list (`[]` when the part lists
none). -/
structure VarL where
  name : String
  kind : String := "optimized"
  visClass : String := ""
  limit : String := ""
  lean : String := ""
  refuted : String := ""
  files : List String := []
deriving Repr, DecidableEq

/-- A snapped animation path a layer offers: its id, the variant whose code runs it, and whether its stepped values
stay on the compositor. -/
structure SnapPath where
  path : String
  variant : String
  composited : Bool
deriving Repr, DecidableEq

/-- A declared layer: its id, whether it holds text, the properties it animates (`none` while not extracted) and its
snapped paths. -/
structure LayerL where
  id : String
  text : Bool
  props : Option (List String) := none
  paths : List SnapPath := []
deriving Repr, DecidableEq

/-- One part: its variants (the head is the default), impls, rules and declared layers. -/
structure PartL where
  id : String
  slot : String := ""
  variants : List VarL
  impls : List String := []
  requires : List (String × List String) := []
  conflicts : List (String × List String) := []
  layers : List LayerL := []
deriving Repr

/-- A Change: a named set of picks, with the combined theorem that covers picks touching each other (`""` none). -/
structure Change where
  id : String
  label : String := ""
  picks : List (String × String)
  lean : String := ""
deriving Repr

/-- An arm: the original snapshot or the faithful page, then Change ids, user picks and layer options
`(layer, opts)`. -/
structure Arm where
  original : Bool := false
  changes : List String := []
  picks : List (String × String) := []
  opts : List (String × String) := []
deriving Repr

/-- The registry, the Changes and the extracted accesses one decision reads. -/
structure Page where
  parts : List PartL
  changes : List Change := []
  accesses : List Access
deriving Repr

/-- The default variant's name. -/
def PartL.dflt (p : PartL) : String := (p.variants.head?.map (·.name)).getD "faithful"

/-- A variant by name. -/
def PartL.var (p : PartL) (v : String) : Option VarL := p.variants.find? (·.name == v)

/-- The part as `BuildsOpen` reads it, with its layer ids. -/
def PartL.fact (p : PartL) : PartFact :=
  { id := p.id, variants := p.variants.map (·.name), impls := p.impls, requires := p.requires,
    conflicts := p.conflicts, layers := p.layers.map (·.id) }

/-- The part as `Compose` reads it. -/
def PartL.info (p : PartL) : PartInfo :=
  { id := p.id, slot := p.slot, variants := p.variants.map fun v => { name := v.name, kind := v.kind, limit := v.limit },
    impls := p.impls, requires := p.requires, conflicts := p.conflicts }

def Page.part (pg : Page) (id : String) : Option PartL := pg.parts.find? (·.id == id)

def Page.change (pg : Page) (id : String) : Option Change := pg.changes.find? (·.id == id)

/-- A layer by id, with its part. -/
def Page.layer (pg : Page) (l : String) : Option (PartL × LayerL) :=
  pg.parts.findSome? fun p => (p.layers.find? (·.id == l)).map fun x => (p, x)

/-- The key `part:variant`. -/
def key (e : String × String) : String := e.1 ++ ":" ++ e.2

/-! ## Footprints -/

/-- The records a pick adds: of its variant and not of the default. None for the default or an unknown part. -/
def own (pg : Page) (e : String × String) : List Access :=
  match pg.part e.1 with
  | none => []
  | some p => if e.2 == p.dflt then [] else
      pg.accesses.filter fun a => a.part == p.id && a.variants.contains e.2 && !a.variants.contains p.dflt

/-- The records a pick removes: of the default and not of its variant. -/
def cleared (pg : Page) (e : String × String) : List Access :=
  match pg.part e.1 with
  | none => []
  | some p => if e.2 == p.dflt then [] else
      pg.accesses.filter fun a => a.part == p.id && a.variants.contains p.dflt && !a.variants.contains e.2

/-- The wires a part at its default variant reads. -/
def faithfulReads (pg : Page) (p : PartL) : List String :=
  (pg.accesses.filter fun a => a.part == p.id && a.variants.contains p.dflt).flatMap reads

/-- Why a non-default variant has no footprint of its own: its part lists no files, or it lists the default's files
(it differs only by a branch inside a shared file). `none` when it is extractable. -/
def extractWhy (p : PartL) (v : VarL) : Option String :=
  if v.name == p.dflt then none else
  let d := ((p.var p.dflt).map (·.files)).getD []
  if d.isEmpty then some "its part lists no files"
  else if v.files.all d.contains && d.all v.files.contains then
    some "it differs from the default only by a branch inside a shared file"
  else none

/-- A written wire changes a read one: the same signal up to an open owner or name, or a scroll write and any box read
(`Fw.Parts.Contract.affects` on wires). -/
def affectsW (w r : String) : Bool := same w r || (w == "scrollY" && (splitKind r).1 == "rect")

/-- Some pair of the two lists satisfies `f`. -/
def anyPair {α β : Type} (xs : List α) (ys : List β) (f : α → β → Bool) : Bool := xs.any fun x => ys.any (f x)

/-- The contract rows of two parts fail I2 or I4 (`Fw.Parts.Contract`); false when a row is missing. -/
def rowsCoupled (p q : String) : Bool :=
  match Fw.Parts.Contract.parts.find? (·.id == p), Fw.Parts.Contract.parts.find? (·.id == q) with
  | some P, some Q => !(Fw.Parts.Contract.i2 P Q && Fw.Parts.Contract.i4 P Q)
  | _, _ => false

/-! ## Units -/

/-- What a unit is. -/
inductive Kind | change | pick | option
deriving Repr, DecidableEq

/-- Golden name of a kind. -/
def Kind.name : Kind → String | .change => "change" | .pick => "pick" | .option => "option"

/-- A unit: its id, its picks, the theorem it cites (`""` none) and, for an option, the layer, its part id and the
option. -/
structure Unit where
  id : String
  kind : Kind
  picks : List (String × String)
  proof : String
  layer : Option (LayerL × String × String) := none
deriving Repr

/-- Composite is on (`c` or `cs`). -/
def composite (o : String) : Bool := o == "c" || o == "cs"

/-- Snap is on (`s` or `cs`). -/
def snap (o : String) : Bool := o == "s" || o == "cs"

/-- One pick as a unit; it cites its variant's own theorem. -/
def pickUnit (pg : Page) (e : String × String) : Unit :=
  { id := key e, kind := .pick, picks := [e], proof := (((pg.part e.1).bind (·.var e.2)).map (·.lean)).getD "" }

/-- A known Change as a unit; it cites the Change's combined theorem. -/
def changeUnit (pg : Page) (c : String) : Option Unit :=
  (pg.change c).map fun ch => { id := ch.id, kind := .change, picks := ch.picks, proof := ch.lean }

/-- An option on a known layer as a unit; it sets no part. -/
def optUnit (pg : Page) (o : String × String) : Option Unit :=
  (pg.layer o.1).map fun pl => { id := key o, kind := .option, picks := [], proof := "", layer := some (pl.2, pl.1.id, o.2) }

/-- The units of an arm: its known Changes, its picks, its options on known layers. -/
def unitsOf (pg : Page) (a : Arm) : List Unit :=
  a.changes.filterMap (changeUnit pg) ++ a.picks.map (pickUnit pg) ++ a.opts.filterMap (optUnit pg)

/-- The wires a unit writes or clears; a composite option writes `will-change` on its layer's part. -/
def Unit.writes (pg : Page) (u : Unit) : List String :=
  u.picks.flatMap (fun e => (own pg e ++ cleared pg e).flatMap Fw.Parts.Footprint.writes) ++
  match u.layer with
  | some (_, pid, o) => if composite o then ["cssVar:will-change/" ++ pid] else []
  | none => []

/-- The wires a unit's own records read. -/
def Unit.reads (pg : Page) (u : Unit) : List String := u.picks.flatMap fun e => (own pg e).flatMap Fw.Parts.Footprint.reads

/-- The parts owning the elements a unit writes or clears (resolved owners only). -/
def Unit.targets (pg : Page) (u : Unit) : List String :=
  (u.picks.flatMap fun e => ((own pg e ++ cleared pg e).filter (·.op.isWrite)).map (·.owner)).filter
    fun o => o != "" && o != "?" && o != "document"

/-- The parts a unit sets. -/
def Unit.parts (u : Unit) : List String := u.picks.map (·.1)

/-- One direction of a clash: `a` writes what `b` writes, writes what `b` reads, writes an element of `b`, or a
contract row of `a` fails I2 or I4 against one of `b`. -/
def linkB (pg : Page) (a b : Unit) : Bool :=
  anyPair (a.writes pg) (b.writes pg) same || anyPair (a.writes pg) (b.reads pg) affectsW ||
    (a.targets pg).any (fun t => (b.parts ++ b.targets pg).contains t) || anyPair a.parts b.parts rowsCoupled

/-- Two units clash: either direction links. -/
def clash (pg : Page) (a b : Unit) : Bool := linkB pg a b || linkB pg b a

/-- The first reason `a` links to `b`, as text. -/
def whyLink (pg : Page) (a b : Unit) : Option String :=
  ((a.writes pg).findSome? fun w => ((b.writes pg).find? (same w)).map fun _ => s!"both write {w}") <|>
  ((a.writes pg).findSome? fun w => ((b.reads pg).find? (affectsW w)).map fun r => s!"{a.id} writes {w}, which {b.id} reads as {r}") <|>
  (((a.targets pg).find? fun t => (b.parts ++ b.targets pg).contains t).map fun t => s!"{a.id} writes an element of {t} (I1)") <|>
  (a.parts.findSome? fun p => (b.parts.find? (rowsCoupled p)).map fun q => s!"the contract rows of {p} and {q} fail I2 or I4")

/-- The reason text of a clash. -/
def why (pg : Page) (a b : Unit) : String := ((whyLink pg a b) <|> (whyLink pg b a)).getD ""

/-- Clash is symmetric. -/
theorem clash_symm (pg : Page) (a b : Unit) : clash pg a b = clash pg b a := Bool.or_comm _ _

/-! ## Pairs -/

/-- Every pair `(l[i], l[j])` with `i < j`. -/
def pairsOf {α : Type} : List α → List (α × α)
  | [] => []
  | x :: xs => xs.map (x, ·) ++ pairsOf xs

theorem mem_pairsOf {α : Type} (l : List α) (i j : Nat) (hij : i < j) (hj : j < l.length) :
    (l[i]'(by omega), l[j]) ∈ pairsOf l := by
  induction l generalizing i j with
  | nil => simp at hj
  | cons x xs ih =>
    simp only [pairsOf, List.mem_append, List.mem_map]
    cases i with
    | zero =>
      left
      cases j with
      | zero => omega
      | succ j => exact ⟨xs[j]'(by simp at hj; omega), List.getElem_mem _, by simp⟩
    | succ i =>
      right
      cases j with
      | zero => omega
      | succ j => simpa using ih i j (by omega) (by simpa using hj)

/-! ## The expanded page -/

/-- The picks of the expanded page, each with the unit that sets it. -/
def owned (pg : Page) (a : Arm) : List ((String × String) × String) :=
  (unitsOf pg a).flatMap fun u => u.picks.map fun e => (e, u.id)

/-- The picks of the expanded page. -/
def expandedPicks (pg : Page) (a : Arm) : List (String × String) := (unitsOf pg a).flatMap (·.picks)

/-- The variant a part runs in the expanded page. -/
def selOf (pg : Page) (a : Arm) (p : PartL) : String :=
  match ((expandedPicks pg a).filter (·.1 == p.id)).getLast? with
  | some e => e.2
  | none => p.dflt

/-- The parts no unit sets. -/
def faithfulParts (pg : Page) (us : List Unit) : List PartL :=
  pg.parts.filter fun p => !(us.any fun u => u.parts.contains p.id)

/-- A unit writes a wire the faithful part reads. -/
def hits (pg : Page) (u : Unit) (q : PartL) : Bool := anyPair (u.writes pg) (faithfulReads pg q) affectsW

/-! ## The canonical search -/

/-- A layer as a pseudo-part whose variants are its options, `""` (no option) first. -/
def layerInfo (id : String) : PartInfo :=
  { id, slot := "", variants := ["", "c", "s", "cs"].map fun n => { name := n, kind := "", limit := "" }, impls := [],
    requires := [], conflicts := [] }

/-- Every declared layer, in page order of its part, then declaration order. -/
def layerInfos (pg : Page) : List PartInfo :=
  (ordered (pg.parts.map PartL.info)).flatMap fun pi => (((pg.part pi.id).map (·.layers)).getD []).map (layerInfo ·.id)

/-- The `fw` entries: the expanded page's non-default variants in page order. -/
def fwEnts (pg : Page) (a : Arm) : List (String × String) := entries (ordered (pg.parts.map PartL.info)) (expandedPicks pg a)

/-- The `fwl` entries: the options in page order. -/
def fwlEnts (pg : Page) (a : Arm) : List (String × String) := entries (layerInfos pg) a.opts

/-- The canonical search of an arm. -/
def searchOf (pg : Page) (a : Arm) : String := canonical none ((fwEnts pg a).map key) ((fwlEnts pg a).map key)

/-! ## Refusals: the closed list -/

/-- Why an arm gets no link. Each constructor is one reason of the closed list. -/
inductive Refusal where
  | unknownChange (id : String)
  | unknownPart (part : String)
  | unknownVariant (part variant : String)
  | unknownLayer (layer : String)
  | notExtractable (pick why : String)
  | refuted (unit pick why : String)
  | setTwice (part a b : String)
  | notOffered (layer opt : String)
  | compositeWillChange (layer pick : String)
  | pathNoVariant (layer pick : String)
  | snapLeaves (layer path : String)
  | originalArm
  | coupled (change a b : String)
  | clash (a b why : String)
  | uncovered (unit part wire : String)
  | sharedReader (part a b : String)
  | rule (text : String)
deriving Repr, DecidableEq

/-- Golden code of a refusal. -/
def Refusal.code : Refusal → String
  | .unknownChange .. => "unknown-change" | .unknownPart .. => "unknown-part" | .unknownVariant .. => "unknown-variant"
  | .unknownLayer .. => "unknown-layer" | .notExtractable .. => "not-extractable" | .refuted .. => "refuted"
  | .setTwice .. => "set-twice" | .notOffered .. => "not-offered" | .compositeWillChange .. => "composite-will-change"
  | .pathNoVariant .. => "path-no-variant" | .snapLeaves .. => "snap-leaves-compositor" | .originalArm => "original-arm"
  | .coupled .. => "coupled" | .clash .. => "clash" | .uncovered .. => "uncovered-reader"
  | .sharedReader .. => "shared-reader" | .rule .. => "rule"

/-- The text of a refusal. -/
def Refusal.text : Refusal → String
  | .unknownChange c => s!"unknown change \"{c}\""
  | .unknownPart p => s!"unknown part \"{p}\""
  | .unknownVariant p v => s!"part \"{p}\" has no variant \"{v}\""
  | .unknownLayer l => s!"unknown layer \"{l}\""
  | .notExtractable k w => s!"{k} is not extractable: {w}"
  | .refuted u k w => s!"{u}: {k} is {w}"
  | .setTwice p a b => s!"part {p} is set by both {a} and {b}"
  | .notOffered l o => s!"layer {l} does not offer option \"{o}\""
  | .compositeWillChange l k => s!"composite on layer {l}: its variant {k} may write will-change (its CSS is not extracted)"
  | .pathNoVariant l k => s!"layer {l} has no snapped path for {k}"
  | .snapLeaves l p => s!"snap on layer {l}: the stepped values of path {p} leave the compositor"
  | .originalArm => "the original arm takes no change, pick or option"
  | .coupled c a b => s!"change {c}: {a} and {b} are coupled without a combined proof"
  | .clash a b w => s!"{a} and {b} clash: {w}"
  | .uncovered u p w => s!"{u} writes {w}, which faithful part {p} reads, outside its proof"
  | .sharedReader p a b => s!"faithful part {p} reads writes of both {a} and {b}"
  | .rule t => t

/-- Any change, pick or option on the original arm. -/
def originalReasons (a : Arm) : List Refusal :=
  if a.original && !(a.changes.isEmpty && a.picks.isEmpty && a.opts.isEmpty) then [.originalArm] else []

/-- Unknown Change ids, parts, variants and layers. -/
def unknownReasons (pg : Page) (a : Arm) : List Refusal :=
  a.changes.filterMap (fun c => if (pg.change c).isSome then none else some (.unknownChange c)) ++
  (expandedPicks pg a).filterMap (fun e => match pg.part e.1 with
    | none => some (.unknownPart e.1)
    | some p => if (p.var e.2).isSome then none else some (.unknownVariant e.1 e.2)) ++
  a.opts.filterMap fun o => if (pg.layer o.1).isSome then none else some (.unknownLayer o.1)

/-- Picks of variants with no footprint of their own. -/
def extractReasons (pg : Page) (a : Arm) : List Refusal :=
  (expandedPicks pg a).filterMap fun e =>
    (pg.part e.1).bind fun p => (p.var e.2).bind fun v => (extractWhy p v).map (.notExtractable (key e))

/-- Units picking a refuted variant. -/
def refutedReasons (pg : Page) (us : List Unit) : List Refusal :=
  us.flatMap fun u => u.picks.filterMap fun e =>
    ((pg.part e.1).bind (·.var e.2)).bind fun v => if v.refuted == "" then none else some (.refuted u.id (key e) v.refuted)

/-- Parts set by two units. -/
def setTwiceReasons (pg : Page) (a : Arm) : List Refusal :=
  (pairsOf (owned pg a)).filterMap fun (x, y) => if x.1.1 == y.1.1 then some (.setTwice x.1.1 x.2 y.2) else none

/-- Options the layer does not offer, composite over a variant that may write `will-change`, snap without a
compositor path for the chosen variant. -/
def optionReasons (pg : Page) (a : Arm) : List Refusal :=
  a.opts.flatMap fun o =>
    match pg.layer o.1 with
    | none => []
    | some (p, l) =>
      let v := selOf pg a p
      (if layerOpts.contains o.2 then [] else [.notOffered l.id o.2]) ++
      (if composite o.2 && v != p.dflt then [.compositeWillChange l.id (key (p.id, v))] else []) ++
      (if snap o.2 then
        if l.paths.isEmpty then [.notOffered l.id "s"]
        else match l.paths.find? (·.variant == v) with
          | none => [.pathNoVariant l.id (key (p.id, v))]
          | some sp => if sp.composited then [] else [.snapLeaves l.id sp.path]
       else [])

/-- Picks inside a Change without a combined theorem that clash with each other. -/
def coupledReasons (pg : Page) (us : List Unit) : List Refusal :=
  us.flatMap fun u =>
    if u.kind == .change && u.proof == "" then
      (pairsOf u.picks).filterMap fun (x, y) =>
        if clash pg (pickUnit pg x) (pickUnit pg y) then some (.coupled u.id (key x) (key y)) else none
    else []

/-- Two units that clash. -/
def clashReasons (pg : Page) (us : List Unit) : List Refusal :=
  (pairsOf us).filterMap fun (x, y) => if clash pg x y then some (.clash x.id y.id (why pg x y)) else none

/-- A faithful part reading a unit's write outside the unit's parts, targets and theorem; a faithful part reading the
writes of two units. -/
def coverReasons (pg : Page) (us : List Unit) : List Refusal :=
  (faithfulParts pg us).flatMap fun q =>
    (us.filterMap fun u =>
      if hits pg u q && u.proof == "" && !((u.parts ++ u.targets pg).contains q.id) then
        some (.uncovered u.id q.id (((u.writes pg).find? fun w => (faithfulReads pg q).any (affectsW w)).getD ""))
      else none) ++
    (pairsOf (us.filter (hits pg · q))).map fun (x, y) => .sharedReader q.id x.id y.id

/-- The site's own rules on the search (`BuildsOpen.validate`). -/
def ruleReasons (pg : Page) (a : Arm) : List Refusal :=
  match validate (pg.parts.map PartL.fact) [] (searchOf pg a) with
  | .ok _ => []
  | .refused rs => rs.map .rule

/-- Every reason, in check order. -/
def reasonsOf (pg : Page) (a : Arm) : List Refusal :=
  let us := unitsOf pg a
  originalReasons a ++ unknownReasons pg a ++ extractReasons pg a ++ refutedReasons pg us ++ setTwiceReasons pg a ++
    optionReasons pg a ++ coupledReasons pg us ++ clashReasons pg us ++ coverReasons pg us ++ ruleReasons pg a

/-! ## Fix: the user picks to drop -/

/-- The `part:variant` keys of a selection over the registry: each part's last pick, else its default. -/
def keysOf (pg : Page) (sel : List (String × String)) : List String :=
  pg.parts.map fun p => key (p.id, (((sel.filter (·.1 == p.id)).getLast?).map (·.2)).getD p.dflt)

/-- Every `requires` key of a pick is in the selection of `base ++ kept`. -/
def reqOk (pg : Page) (base kept : List (String × String)) (e : String × String) : Bool :=
  ((((pg.part e.1).map (·.requires)).getD []).lookup (key e)).getD [] |>.all fun n => (keysOf pg (base ++ kept)).contains n

/-- The members passing `ok` against the whole list. -/
def keepOk {α : Type} (ok : List α → α → Bool) (S : List α) : List α := S.filter (ok S)

/-- Drop every member that fails `ok` until none does. -/
def closeReq {α : Type} (ok : List α → α → Bool) (S : List α) : List α :=
  if _h : (keepOk ok S).length < S.length then closeReq ok (keepOk ok S) else S
termination_by S.length

/-- What `closeReq` keeps passes `ok` against itself. -/
theorem closeReq_closed {α : Type} (ok : List α → α → Bool) (S : List α) :
    ∀ x ∈ closeReq ok S, ok (closeReq ok S) x = true := by
  induction S using closeReq.induct ok with
  | case1 S h ih => rw [closeReq]; simp only [h, ↓reduceDIte]; exact ih
  | case2 S h =>
    rw [closeReq]; simp only [h, ↓reduceDIte]
    have hle := List.length_filter_le (ok S) S
    simp only [keepOk] at h
    exact List.length_filter_eq_length_iff.1 (by omega)

/-- The picks of the arm's Changes. -/
def changePicks (pg : Page) (a : Arm) : List (String × String) :=
  ((unitsOf pg a).filter (·.kind == .change)).flatMap (·.picks)

/-- The user picks kept after the fix: those sharing no part with a Change, closed under `requires`. -/
def keptOf (pg : Page) (a : Arm) : List (String × String) :=
  closeReq (fun k e => reqOk pg (changePicks pg a) k e) (a.picks.filter fun e => !(changePicks pg a).any (·.1 == e.1))

/-- The user picks the fix drops. -/
def fixOf (pg : Page) (a : Arm) : List (String × String) := a.picks.filter fun e => !(keptOf pg a).contains e

/-- Every kept pick's requirements hold in the fixed arm. -/
theorem fix_closed_requires (pg : Page) (a : Arm) :
    ∀ e ∈ keptOf pg a, reqOk pg (changePicks pg a) (keptOf pg a) e = true :=
  closeReq_closed _ _

/-! ## Look grade of an arm -/

/-- The grade a variant claims: `L` for a look change, `E` for class `E` or `E-s` with a theorem, `E1` for class `E1`,
`Q` otherwise; the default is `E`. -/
def varGrade (v : VarL) : Grade :=
  if v.kind == "faithful" then .E
  else if lookChange v.limit || v.visClass == "L" then .L
  else if (v.visClass == "E" || v.visClass == "E-s") && v.lean != "" then .E
  else if v.visClass == "E1" then .E1
  else .Q

/-- The grade of a unit: an option is `L` on a text layer composited without snap (C1 pending), `Q` otherwise; a pick
or Change is the worst grade of its picks (an unknown pick is `Q`). -/
def unitGrade (pg : Page) (u : Unit) : Grade :=
  match u.layer with
  | some (l, _, o) => if l.text && composite o && !snap o then .L else .Q
  | none => worst (u.picks.map fun e => (((pg.part e.1).bind (·.var e.2)).map varGrade).getD .Q)

/-- The expected grade: the worst unit grade. -/
def expected (pg : Page) (a : Arm) : Grade := worst ((unitsOf pg a).map (unitGrade pg))

/-- The verdict before any run: `E` when every unit is `E`; otherwise none, the arm's measured cells decide. -/
def verdict (pg : Page) (a : Arm) : Option Grade := if expected pg a == .E then some .E else none

/-- The hypotheses an `E` verdict holds under: the units' theorems, `ReadsOnly` and I5. -/
def hyps (pg : Page) (a : Arm) : List String :=
  if verdict pg a == some .E then
    ((unitsOf pg a).filterMap fun u => if u.proof == "" then none else some u.proof).eraseDups ++ ["ReadsOnly", "I5"]
  else []

/-- Notes next to the grade. -/
def lookNotes (pg : Page) (a : Arm) : List String :=
  (if expected pg a == .L then ["look change, pending your review"] else []) ++
  ((unitsOf pg a).filterMap fun u => match u.layer with
    | some (l, _, o) => if l.text && composite o && !snap o then some s!"C1 pending: strips ({l.id})" else none
    | none => none) ++
  (if verdict pg a == none then ["expected grade, not a verdict: the arm's worst measured cell decides"] else [])

/-! ## Premises -/

/-- A layer may animate a property: its properties are not extracted, or they list it. -/
def mayAnimate (l : LayerL) (prop : String) : Bool := match l.props with | none => true | some ps => ps.contains prop

/-- The premises a run checks for one layer option. -/
def layerPremises (l : LayerL) (o : String) : List String :=
  (if composite o then ["P1", "P2"] else []) ++ (if snap o then ["S1", "T1"] else []) ++
  (if l.text && composite o && !snap o && (mayAnimate l "translate" || mayAnimate l "scale") then ["C1"] else []) ++
  (if composite o && mayAnimate l "scale" then ["C2"] else []) ++
  (if composite o && !snap o && mayAnimate l "translate" then ["C5"] else []) ++
  (if composite o && mayAnimate l "filter" then ["C6"] else [])

/-- The premises of an arm: P3 and P4 for the page, then each option's. -/
def premises (pg : Page) (a : Arm) : List (String × List String) :=
  ("page", ["P3", "P4"]) :: (unitsOf pg a).filterMap fun u => u.layer.map fun (l, _, o) => (l.id, layerPremises l o)

/-! ## The decision -/

/-- The answer for an arm: a link only when no reason refuses it, the units, the look, the premises and the fix. -/
structure Out where
  link : Option String
  reasons : List Refusal
  units : List Unit
  grade : Grade
  verdict : Option Grade
  hyps : List String
  notes : List String
  premises : List (String × List String)
  fix : List (String × String)

/-- Decide an arm. -/
def decideArm (pg : Page) (a : Arm) : Out :=
  let rs := reasonsOf pg a
  { link := if rs.isEmpty then some (searchOf pg a) else none, reasons := rs, units := unitsOf pg a,
    grade := expected pg a, verdict := verdict pg a, hyps := hyps pg a, notes := lookNotes pg a,
    premises := premises pg a, fix := if (setTwiceReasons pg a).isEmpty then [] else fixOf pg a }

/-! ## Theorems: the link -/

/-- A link exists exactly when no reason refuses the arm. -/
theorem link_iff (pg : Page) (a : Arm) : (decideArm pg a).link.isSome = (decideArm pg a).reasons.isEmpty := by
  unfold decideArm; simp only []; split <;> simp_all

/-- A link is the arm's canonical search, with no reason. -/
theorem decideArm_link (pg : Page) (a : Arm) (c : String) (h : (decideArm pg a).link = some c) :
    c = searchOf pg a ∧ reasonsOf pg a = [] := by
  unfold decideArm at h; simp only [] at h
  split at h
  · rename_i hr; simp at h; exact ⟨h.symm, by simpa using hr⟩
  · simp at h

/-- Any reason refuses the arm. -/
theorem refused_of_mem (pg : Page) (a : Arm) (r : Refusal) (h : r ∈ reasonsOf pg a) : (decideArm pg a).link = none := by
  unfold decideArm; simp only []
  split
  · rename_i hr; simp at hr; simp [hr] at h
  · rfl

/-- The site's rules accept the search of every allowed arm (`BuildsOpen.validate`, the proved mirror of
`resolve.ts`, now with `fwl`). -/
theorem link_resolves (pg : Page) (a : Arm) (c : String) (h : (decideArm pg a).link = some c) :
    ∃ c', validate (pg.parts.map PartL.fact) [] c = .ok c' := by
  obtain ⟨rfl, hr⟩ := decideArm_link pg a c h
  cases hv : validate (pg.parts.map PartL.fact) [] (searchOf pg a) with
  | ok c' => exact ⟨c', rfl⟩
  | refused rs =>
    have hne := validate_refused_ne _ _ _ _ hv
    obtain ⟨r, hr'⟩ := List.exists_mem_of_ne_nil rs hne
    have : Refusal.rule r ∈ reasonsOf pg a := by
      simp only [reasonsOf, List.mem_append]
      right; simp [ruleReasons, hv, hr']
    simp [hr] at this

/-! ## Theorems: refusals, one per reason family -/

theorem originalArm_refused (pg : Page) (a : Arm) (ho : a.original = true)
    (hs : ¬ (a.changes.isEmpty && a.picks.isEmpty && a.opts.isEmpty) = true) : (decideArm pg a).link = none :=
  have hb : (a.original && !(a.changes.isEmpty && a.picks.isEmpty && a.opts.isEmpty)) = true := by
    rw [ho, Bool.true_and, Bool.not_eq_true']; exact Bool.eq_false_iff.2 hs
  have hx : Refusal.originalArm ∈ originalReasons a := by
    rw [originalReasons]; split
    · exact List.mem_singleton_self _
    · contradiction
  refused_of_mem pg a .originalArm (by simp [reasonsOf, hx])

theorem unknownChange_refused (pg : Page) (a : Arm) (c : String) (hc : c ∈ a.changes) (hn : pg.change c = none) :
    (decideArm pg a).link = none :=
  have hx : Refusal.unknownChange c ∈ unknownReasons pg a := by
    simp only [unknownReasons, List.mem_append, List.mem_filterMap]; exact Or.inl (Or.inl ⟨c, hc, by simp [hn]⟩)
  refused_of_mem pg a (.unknownChange c) (by simp [reasonsOf, hx])

theorem notExtractable_refused (pg : Page) (a : Arm) (e : String × String) (he : e ∈ expandedPicks pg a) (p : PartL)
    (hp : pg.part e.1 = some p) (v : VarL) (hv : p.var e.2 = some v) (w : String) (hw : extractWhy p v = some w) :
    (decideArm pg a).link = none :=
  have hx : Refusal.notExtractable (key e) w ∈ extractReasons pg a := by
    simp only [extractReasons, List.mem_filterMap]; exact ⟨e, he, by simp [hp, hv, hw]⟩
  refused_of_mem pg a (.notExtractable (key e) w) (by simp [reasonsOf, hx])

/-- **Expansion never overrides**: in an allowed arm no two units set one part. -/
theorem expand_one_owner (pg : Page) (a : Arm) (h : (decideArm pg a).link.isSome = true) (i j : Nat) (hij : i < j)
    (hj : j < (owned pg a).length) : ((owned pg a)[i]'(by omega)).1.1 ≠ ((owned pg a)[j]).1.1 := by
  intro heq
  have hm := mem_pairsOf (owned pg a) i j hij hj
  have hr : Refusal.setTwice ((owned pg a)[i]'(by omega)).1.1 ((owned pg a)[i]'(by omega)).2 ((owned pg a)[j]).2 ∈
      reasonsOf pg a := by
    have hx : Refusal.setTwice ((owned pg a)[i]'(by omega)).1.1 ((owned pg a)[i]'(by omega)).2 ((owned pg a)[j]).2 ∈
        setTwiceReasons pg a := by
      simp only [setTwiceReasons, List.mem_filterMap]; exact ⟨_, hm, by simp [heq]⟩
    simp [reasonsOf, hx]
  rw [refused_of_mem pg a _ hr] at h; cases h

/-- **Units of an allowed arm do not clash** (the decision's form of "pairwise independent on their variant rows"). -/
theorem allowed_pairwise_independent (pg : Page) (a : Arm) (h : (decideArm pg a).link.isSome = true) (i j : Nat)
    (hij : i < j) (hj : j < (unitsOf pg a).length) : clash pg ((unitsOf pg a)[i]'(by omega)) (unitsOf pg a)[j] = false := by
  cases hc : clash pg ((unitsOf pg a)[i]'(by omega)) (unitsOf pg a)[j] with
  | false => rfl
  | true =>
    have hm := mem_pairsOf (unitsOf pg a) i j hij hj
    have hr : Refusal.clash ((unitsOf pg a)[i]'(by omega)).id ((unitsOf pg a)[j]).id
        (why pg ((unitsOf pg a)[i]'(by omega)) (unitsOf pg a)[j]) ∈ reasonsOf pg a := by
      have hx : Refusal.clash ((unitsOf pg a)[i]'(by omega)).id ((unitsOf pg a)[j]).id
          (why pg ((unitsOf pg a)[i]'(by omega)) (unitsOf pg a)[j]) ∈ clashReasons pg (unitsOf pg a) := by
        simp only [clashReasons, List.mem_filterMap]; exact ⟨_, hm, by simp [hc]⟩
      simp [reasonsOf, hx]
    rw [refused_of_mem pg a _ hr] at h; cases h

/-- Any two distinct units of an allowed arm do not clash, in either order. -/
theorem allowed_no_clash (pg : Page) (a : Arm) (h : (decideArm pg a).link.isSome = true) (i j : Nat)
    (hi : i < (unitsOf pg a).length) (hj : j < (unitsOf pg a).length) (hne : i ≠ j) :
    clash pg (unitsOf pg a)[i] (unitsOf pg a)[j] = false := by
  rcases Nat.lt_or_gt_of_ne hne with hlt | hgt
  · exact allowed_pairwise_independent pg a h i j hlt hj
  · rw [clash_symm]; exact allowed_pairwise_independent pg a h j i hgt hi

/-- **A clear seen by a read refuses the arm**: a unit whose pick clears a record writing `w`, and another unit reading
a wire `w` affects (golden: threaded + hidden-pause). -/
theorem clear_read_refused (pg : Page) (a : Arm) (i j : Nat) (hij : i < j) (hj : j < (unitsOf pg a).length)
    (e : String × String) (he : e ∈ ((unitsOf pg a)[i]'(by omega)).picks) (rec : Access) (hrec : rec ∈ cleared pg e)
    (w : String) (hw : w ∈ Fw.Parts.Footprint.writes rec) (r : String) (hr : r ∈ ((unitsOf pg a)[j]).reads pg) (ha : affectsW w r = true) :
    (decideArm pg a).link = none := by
  cases hl : (decideArm pg a).link with
  | none => rfl
  | some c =>
    have hs : (decideArm pg a).link.isSome = true := by simp [hl]
    have h0 := allowed_pairwise_independent pg a hs i j hij hj
    have hwm : w ∈ ((unitsOf pg a)[i]'(by omega)).writes pg := by
      simp only [Unit.writes, List.mem_append, List.mem_flatMap]
      exact Or.inl ⟨e, he, rec, Or.inr hrec, hw⟩
    have : linkB pg ((unitsOf pg a)[i]'(by omega)) (unitsOf pg a)[j] = true := by
      simp only [linkB, anyPair, Bool.or_eq_true, List.any_eq_true]
      exact Or.inl (Or.inl (Or.inr ⟨w, hwm, r, hr, ha⟩))
    simp [clash, this] at h0

/-- A Change whose picks clash, with no combined theorem, refuses the arm. -/
theorem coupled_refused (pg : Page) (a : Arm) (u : Unit) (hu : u ∈ unitsOf pg a) (hk : u.kind = .change)
    (hp : u.proof = "") (i j : Nat) (hij : i < j) (hj : j < u.picks.length)
    (hc : clash pg (pickUnit pg (u.picks[i]'(by omega))) (pickUnit pg u.picks[j]) = true) :
    (decideArm pg a).link = none := by
  refine refused_of_mem pg a (.coupled u.id (key (u.picks[i]'(by omega))) (key u.picks[j])) ?_
  have hx : Refusal.coupled u.id (key (u.picks[i]'(by omega))) (key u.picks[j]) ∈ coupledReasons pg (unitsOf pg a) := by
    simp only [coupledReasons, List.mem_flatMap]
    refine ⟨u, hu, ?_⟩
    simp only [hk, hp, beq_self_eq_true, Bool.and_self, ↓reduceIte, List.mem_filterMap]
    exact ⟨_, mem_pairsOf u.picks i j hij hj, by simp [hc]⟩
  simp [reasonsOf, hx]

/-! ## Theorems: expansion -/

/-- The arm with its Changes written out as raw picks. -/
def flatten (pg : Page) (a : Arm) : Arm := { a with changes := [], picks := expandedPicks pg a }

/-- Options set no part. -/
theorem flatMap_picks_opts (pg : Page) (os : List (String × String)) :
    (os.filterMap (optUnit pg)).flatMap (·.picks) = [] := by
  induction os with
  | nil => rfl
  | cons o os ih => cases h : optUnit pg o <;> simp only [List.filterMap_cons, h, ih]
                    <;> simp [optUnit] at h <;> obtain ⟨_, _, _, rfl⟩ := h <;> simp [ih]

/-- **Expansion is idempotent**: writing out the Changes as picks gives the same expanded page. -/
theorem expand_idem (pg : Page) (a : Arm) : expandedPicks pg (flatten pg a) = expandedPicks pg a := by
  have hp : ∀ ps : List (String × String), (ps.map (pickUnit pg)).flatMap (·.picks) = ps := by
    intro ps; induction ps with
    | nil => rfl
    | cons e ps ih => simp [pickUnit, ih]
  simp only [expandedPicks, unitsOf, flatten, List.filterMap_nil, List.nil_append, List.flatMap_append, hp,
    flatMap_picks_opts, List.append_nil]

/-- A Change and the same raw picks give one search (the reason the arm record is stored). -/
theorem search_flatten (pg : Page) (a : Arm) : searchOf pg (flatten pg a) = searchOf pg a := by
  simp only [searchOf, fwEnts, fwlEnts, expand_idem]; rfl

/-- **The layer entries name one option per layer**: arms with the same `fwl` entries give every layer the same
option (`Compose.entries_inj` over the layer pseudo-parts). -/
theorem search_entries_inj (pg : Page) (hnd : ((layerInfos pg).map (·.id)).Nodup) (a b : Arm)
    (h : fwlEnts pg a = fwlEnts pg b) : ∀ l ∈ layerInfos pg, choice a.opts l = choice b.opts l :=
  entries_inj (layerInfos pg) hnd a.opts b.opts h

/-! ## Theorems: look -/

/-- The verdict is `E` exactly when every unit is `E`. -/
theorem look_E_iff_all_E (pg : Page) (a : Arm) :
    verdict pg a = some .E ↔ ∀ u ∈ unitsOf pg a, unitGrade pg u = .E := by
  unfold verdict expected
  rw [← List.forall_mem_map (f := unitGrade pg) (P := fun g => g = .E), ← worst_eq_E]
  split <;> simp_all

/-- One unit that is not `E` leaves the verdict to the measured cells. -/
theorem look_measured_of_nonE (pg : Page) (a : Arm) (u : Unit) (hu : u ∈ unitsOf pg a) (hg : unitGrade pg u ≠ .E) :
    verdict pg a = none := by
  cases hv : verdict pg a with
  | none => rfl
  | some g =>
    have : g = .E := by unfold verdict at hv; split at hv <;> simp_all
    subst this
    exact absurd ((look_E_iff_all_E pg a).1 hv u hu) hg

/-- One `L` unit makes the arm's expected grade `L`. -/
theorem look_L_of_unit_L (pg : Page) (a : Arm) (u : Unit) (hu : u ∈ unitsOf pg a) (hg : unitGrade pg u = .L) :
    expected pg a = .L :=
  worst_L _ (List.mem_map.2 ⟨u, hu, hg⟩)

/-- An option is never `E`, so an arm with one has no `E` verdict before a run. -/
theorem option_not_E (pg : Page) (a : Arm) (u : Unit) (hu : u ∈ unitsOf pg a) (l : LayerL) (pid o : String)
    (hl : u.layer = some (l, pid, o)) : verdict pg a = none := by
  refine look_measured_of_nonE pg a u hu ?_
  simp only [unitGrade, hl]; split <;> simp

/-- **E composes.** For an allowed arm whose verdict is `E`: parts `0..n-1` of the page, `S` the parts its units set,
`u` the index in `unitsOf` of the unit setting each. Given the modelling premises (arms read only the variants of
parts they are not independent of; non-clashing units have independent parts, the footprint premise; every set part is
independent of every unset part, the cover premise; each `E` unit, swapped alone, keeps the band of each of its parts,
its theorem), swapping all units at once keeps the visible page from every start offset. -/
theorem look_E_sound {V : Type} (pg : Page) (a : Arm) (Indep : Nat → Nat → Prop)
    (arm : Nat → (Nat → V) → Fw.Engine.PartArm) (vp : Fw.Engine.Rect) (n : Nat) (S : Nat → Bool) (u : Nat → Nat)
    (sel sel' : Nat → V) (y : Rat)
    (hok : (decideArm pg a).link.isSome = true) (hE : verdict pg a = some .E)
    (hu : ∀ i, S i = true → u i < (unitsOf pg a).length)
    (ha : Fw.Engine.ReadsOnly Indep arm)
    (hfoot : ∀ i j (hi : S i = true) (hj : S j = true),
      clash pg ((unitsOf pg a)[u i]'(hu i hi)) ((unitsOf pg a)[u j]'(hu j hj)) = false → u i ≠ u j → Indep i j)
    (hcover : ∀ i q, S i = true → S q = false → Indep i q)
    (hunit : ∀ j (hj : S j = true), unitGrade pg ((unitsOf pg a)[u j]'(hu j hj)) = .E →
      (arm j (Fw.Engine.swapSet sel sel' fun i => S i && u i == u j)).height = (arm j sel).height ∧
      ∀ y', Fw.Engine.visible vp ((arm j (Fw.Engine.swapSet sel sel' fun i => S i && u i == u j)).scene y') =
        Fw.Engine.visible vp ((arm j sel).scene y')) :
    Fw.Engine.visible vp (Fw.Engine.stackScene y ((List.range n).map fun j => arm j (Fw.Engine.swapSet sel sel' S))) =
      Fw.Engine.visible vp (Fw.Engine.stackScene y ((List.range n).map fun j => arm j sel)) := by
  refine Fw.Engine.lego_swap_visible_units Indep arm vp n S u sel sel' y ha hcover ?_ ?_
  · intro i j hi hj hne
    exact hfoot i j hi hj (allowed_no_clash pg a hok _ _ (hu i hi) (hu j hj) hne) hne
  · intro j hj
    exact hunit j hj ((look_E_iff_all_E pg a).1 hE _ (List.getElem_mem _))

/-! ## Theorems: premises -/

/-- **Premises are complete**: a composite option adds P1 and P2, and the page always carries P3 and P4. -/
theorem premises_complete (pg : Page) (a : Arm) (l : LayerL) (o : String) (hc : composite o = true) :
    "P1" ∈ layerPremises l o ∧ "P2" ∈ layerPremises l o ∧ ("page", ["P3", "P4"]) ∈ premises pg a := by
  simp [layerPremises, premises, hc]

/-- **Snap drops C5** and adds S1 and T1. -/
theorem snap_drops_C5 (l : LayerL) (o : String) (hs : snap o = true) :
    "C5" ∉ layerPremises l o ∧ "S1" ∈ layerPremises l o ∧ "T1" ∈ layerPremises l o := by
  refine ⟨?_, by simp [layerPremises, hs], by simp [layerPremises, hs]⟩
  simp only [layerPremises, hs, Bool.not_true, Bool.and_false, Bool.false_and, ↓reduceIte,
    List.mem_append]
  intro h
  rcases h with ((((h | h) | h) | h) | h) <;> (repeat' split at h) <;> simp_all

/-- A text layer composited without snap gets C1. -/
theorem text_composite_C1 (l : LayerL) (o : String) (ht : l.text = true) (hc : composite o = true) (hs : snap o = false)
    (hm : l.props = none) : "C1" ∈ layerPremises l o := by
  simp [layerPremises, ht, hc, hs, mayAnimate, hm]

/-! ## Registry checks -/

/-- Every extractable, unrefuted non-default pick of the registry. -/
def extractable (pg : Page) : List (String × String) :=
  pg.parts.flatMap fun p =>
    (p.variants.filter fun v => v.name != p.dflt && v.refuted == "" && (extractWhy p v).isNone).map (p.id, ·.name)

/-- A part.json `conflicts` entry of one pick names the other. -/
def declared (pg : Page) (x y : String × String) : Bool :=
  let has (e f : String × String) := (((((pg.part e.1).map (·.conflicts)).getD []).lookup (key e)).getD []).contains (key f)
  has x y || has y x

/-- Registry errors that fail the op: a Change that is refused alone over the faithful page; two extractable picks of
different parts that clash with no `conflicts` entry. -/
def registryErrors (pg : Page) : List String :=
  (pg.changes.filterMap fun c =>
    let rs := reasonsOf pg { changes := [c.id] }
    if rs.isEmpty then none else some s!"change {c.id} fails alone: {"; ".intercalate (rs.map (·.text))}") ++
  ((pairsOf (extractable pg)).filterMap fun (x, y) =>
    if x.1 != y.1 && clash pg (pickUnit pg x) (pickUnit pg y) && !declared pg x y then
      some s!"undeclared conflict: {key x} and {key y} clash ({why pg (pickUnit pg x) (pickUnit pg y)}), and part.json conflicts lists neither"
    else none)

/-- The layer ids of the `part.json` files (as the extractor read them) whose `?fwl=<id>:c` the search does not accept
as written, over a registry declaring exactly those layers. -/
def declaredLayerErrors : List String :=
  let decls := Fw.Parts.FootprintData.layerDecls
  let facts : List PartFact := (decls.map (·.1)).eraseDups.map fun p =>
    { id := p, variants := ["faithful"], impls := [], requires := [], conflicts := [],
      layers := (decls.filter (·.1 == p)).map (·.2.1) }
  decls.filterMap fun (_, l, _) =>
    if validate facts [] s!"?fwl={l}:c" == .ok s!"?fwl={l}:c" then none else some l

#guard declaredLayerErrors == []
#guard Fw.Parts.FootprintData.layerDecls.length > 0


/-! ## Examples

A synthetic page in the shape of the hero: `hero.exit:threaded` clears the faithful driver's `--exit-opacity` write,
which `hero.countdown:hidden-pause` and the faithful `hero` read; `hero:scene-pause` writes an attribute on `hero.exit`;
`demo.a:fast` writes `--strip`, which `demo.b:fast` and the faithful `demo.c` read. -/

/-- One extracted record of the examples. -/
def exAccess (part file : String) (op : Fw.Parts.Footprint.Op) (name owner : String) (vs : List String) : Access :=
  { part, file, line := 1, op, name, owner, ctx := "raf", variants := vs }

/-- The example page. -/
def exPage : Page where
  parts := [
    { id := "hero",
      variants := [{ name := "faithful", kind := "faithful", files := ["hero.ts"] },
        { name := "scene-pause", files := ["hero.ts", "scene.ts"] }],
      layers := [{ id := "hero_copy", text := true }] },
    { id := "hero.exit",
      variants := [{ name := "faithful", kind := "faithful", files := ["driver.ts"] },
        { name := "threaded", visClass := "E", lean := "Fw.Demo.threaded_same", files := ["threaded.ts"] }],
      conflicts := [("hero.exit:threaded", ["hero.countdown:hidden-pause"])] },
    { id := "hero.countdown",
      variants := [{ name := "faithful", kind := "faithful", files := ["countdown.ts"] },
        { name := "hidden-pause", files := ["countdown.ts", "hidden.ts"] },
        { name := "strip", files := ["countdown.ts"] }],
      layers := [{ id := "hero.countdown_strip", text := false,
                   paths := [{ path := "steps", variant := "faithful", composited := true },
                             { path := "js", variant := "hidden-pause", composited := false }] }] },
    { id := "hero.accent",
      variants := [{ name := "faithful", kind := "faithful", files := ["accent.ts"] },
        { name := "steps", visClass := "E1", files := ["steps.ts"] },
        { name := "gone", refuted := "refuted by its run", files := ["gone.ts"] }],
      layers := [{ id := "hero.accent_mark", text := false,
                   paths := [{ path := "steps", variant := "faithful", composited := true }] }] },
    { id := "demo.a",
      variants := [{ name := "faithful", kind := "faithful", files := ["a.ts"] }, { name := "fast", files := ["a-fast.ts"] },
        { name := "slow", files := ["a-slow.ts"] }] },
    { id := "demo.b",
      variants := [{ name := "faithful", kind := "faithful", files := ["b.ts"] }, { name := "fast", files := ["b-fast.ts"] }],
      requires := [("demo.b:fast", ["demo.a:fast"])] },
    { id := "demo.c", variants := [{ name := "faithful", kind := "faithful", files := ["c.ts"] }] }]
  changes := [
    { id := "strip-pair", picks := [("demo.a", "fast"), ("demo.b", "fast")] },
    { id := "strip-pair-proved", picks := [("demo.a", "fast"), ("demo.b", "fast")], lean := "Fw.Demo.strip_pair" },
    { id := "a-slow", picks := [("demo.a", "slow")], lean := "Fw.Demo.a_slow" }]
  accesses := [
    exAccess "hero" "hero.ts" .cssVar "--exit-opacity" "" ["faithful", "scene-pause"],
    exAccess "hero" "scene.ts" .setAttr "data-fw-hero-scene" "hero.exit" ["scene-pause"],
    exAccess "hero.exit" "driver.ts" .setVar "--exit-opacity" "hero.exit" ["faithful"],
    exAccess "hero.exit" "threaded.ts" .setVar "--exit-anim" "hero.exit" ["threaded"],
    exAccess "hero.countdown" "countdown.ts" .setStyle "transform" "hero.countdown" ["faithful", "hidden-pause", "strip"],
    exAccess "hero.countdown" "hidden.ts" .cssVar "--exit-opacity" "" ["hidden-pause"],
    exAccess "hero.accent" "accent.ts" .setStyle "opacity" "hero.accent" ["faithful"],
    exAccess "hero.accent" "steps.ts" .setStyle "transform" "hero.accent" ["steps"],
    exAccess "hero.accent" "gone.ts" .setStyle "transform" "hero.accent" ["gone"],
    exAccess "demo.a" "a-fast.ts" .setVar "--strip" "demo.a" ["fast"],
    exAccess "demo.a" "a-slow.ts" .setVar "--slow" "demo.a" ["slow"],
    exAccess "demo.b" "b-fast.ts" .cssVar "--strip" "" ["fast"],
    exAccess "demo.c" "c.ts" .cssVar "--strip" "" ["faithful"],
    exAccess "demo.c" "c.ts" .cssVar "--exit-opacity" "" ["faithful"]]

/-- The refusal codes of an example arm. -/
def exCodes (a : Arm) : List String := (reasonsOf exPage a).map (·.code)

-- A clear seen by a read: threaded clears the faithful `--exit-opacity` write that hidden-pause reads.
#guard exCodes { picks := [("hero.exit", "threaded"), ("hero.countdown", "hidden-pause")] } = ["clash", "rule"]
-- Threaded alone: allowed, `E` under its theorem, `ReadsOnly` and I5.
#guard (decideArm exPage { picks := [("hero.exit", "threaded")] }).link = some "?fw=hero.exit:threaded"
#guard (decideArm exPage { picks := [("hero.exit", "threaded")] }).verdict = some .E
#guard (decideArm exPage { picks := [("hero.exit", "threaded")] }).hyps = ["Fw.Demo.threaded_same", "ReadsOnly", "I5"]
-- A coupled Change: refused without a combined theorem, allowed with one.
#guard exCodes { changes := ["strip-pair"] } = ["coupled", "uncovered-reader"]
#guard (decideArm exPage { changes := ["strip-pair-proved"] }).link = some "?fw=demo.a:fast,demo.b:fast"
-- Units that do not clash: allowed, expected grade `E1`, no verdict before a run.
#guard (decideArm exPage { picks := [("hero.exit", "threaded"), ("hero.accent", "steps")] }).link =
  some "?fw=hero.accent:steps,hero.exit:threaded"
#guard (decideArm exPage { picks := [("hero.exit", "threaded"), ("hero.accent", "steps")] }).grade = .E1
#guard (decideArm exPage { picks := [("hero.exit", "threaded"), ("hero.accent", "steps")] }).verdict = none
-- Composite on a layer whose part runs a non-default variant.
#guard exCodes { picks := [("hero", "scene-pause")], opts := [("hero_copy", "c")] } = ["composite-will-change"]
-- Composite on a text layer without snap: allowed, `L`, C1 pending.
#guard (decideArm exPage { opts := [("hero_copy", "c")] }).link = some "?fwl=hero_copy:c"
#guard (decideArm exPage { opts := [("hero_copy", "c")] }).grade = .L
#guard (decideArm exPage { opts := [("hero_copy", "c")] }).notes.contains "C1 pending: strips (hero_copy)" = true
#guard (decideArm exPage { opts := [("hero_copy", "c")] }).premises =
  [("page", ["P3", "P4"]), ("hero_copy", ["P1", "P2", "C1", "C2", "C5", "C6"])]
-- Snap: a compositor path, a path that leaves it, no path for the variant, no path at all.
#guard (decideArm exPage { opts := [("hero.countdown_strip", "s")] }).link = some "?fwl=hero.countdown_strip:s"
#guard exCodes { picks := [("hero.countdown", "hidden-pause")], opts := [("hero.countdown_strip", "s")] } =
  ["snap-leaves-compositor"]
#guard exCodes { picks := [("hero.accent", "steps")], opts := [("hero.accent_mark", "s")] } = ["path-no-variant"]
#guard exCodes { opts := [("hero_copy", "s")] } = ["not-offered"]
#guard exCodes { opts := [("hero_copy", "x")] } = ["not-offered"]
-- Unknown names.
#guard exCodes { opts := [("nope", "c")] } = ["unknown-layer"]
#guard exCodes { changes := ["nope"] } = ["unknown-change"]
#guard exCodes { picks := [("nope", "x")] } = ["unknown-part"]
#guard exCodes { picks := [("hero", "x")] } = ["unknown-variant"]
-- A branch-only variant and a refuted one.
#guard exCodes { picks := [("hero.countdown", "strip")] } = ["not-extractable"]
#guard exCodes { picks := [("hero.accent", "gone")] } = ["refuted"]
-- A part set twice: the fix drops the user pick.
#guard exCodes { changes := ["strip-pair-proved"], picks := [("demo.a", "fast")] } =
  ["set-twice", "clash", "uncovered-reader", "shared-reader"]
#guard (decideArm exPage { changes := ["strip-pair-proved"], picks := [("demo.a", "fast")] }).fix = [("demo.a", "fast")]
-- The fix is closed under `requires`: demo.b:fast needs demo.a:fast, which the Change replaces.
#guard (decideArm exPage { changes := ["a-slow"], picks := [("demo.a", "fast"), ("demo.b", "fast")] }).fix =
  [("demo.a", "fast"), ("demo.b", "fast")]
-- A faithful reader outside every proof, and one reading two units.
#guard exCodes { picks := [("demo.a", "fast")] } = ["uncovered-reader"]
#guard exCodes { picks := [("hero.exit", "threaded"), ("demo.a", "fast")] } = ["uncovered-reader", "shared-reader"]
-- The site's own rules: demo.b:fast requires demo.a:fast.
#guard exCodes { changes := ["a-slow"], picks := [("demo.b", "fast")] } = ["rule"]
-- The original arm.
#guard exCodes { original := true, picks := [("hero.exit", "threaded")] } = ["original-arm"]
#guard (decideArm exPage { original := true }).link = some ""
-- The canonical search: `fw` and `fwl` entries in page order.
#guard searchOf exPage
    { picks := [("hero.accent", "steps"), ("hero.exit", "threaded")],
      opts := [("hero.countdown_strip", "s"), ("hero_copy", "c")] } =
  "?fw=hero.accent:steps,hero.exit:threaded&fwl=hero_copy:c,hero.countdown_strip:s"
-- Registry checks: a Change refused alone, and clashing picks with no `conflicts` entry (threaded and hidden-pause
-- declare theirs).
#guard (registryErrors exPage).map (·.splitOn ":" |>.head!) =
  ["change strip-pair fails alone", "undeclared conflict", "undeclared conflict", "undeclared conflict"]
#guard (registryErrors exPage).contains
  "undeclared conflict: hero:scene-pause and hero.exit:threaded clash (hero:scene-pause writes an element of hero.exit (I1)), and part.json conflicts lists neither"

end Fw.Console.Layers
