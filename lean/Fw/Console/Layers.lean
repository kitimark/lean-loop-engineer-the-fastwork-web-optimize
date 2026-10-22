import Fw.Console.Compose
import Fw.Parts.Footprint
import Fw.Engine.Compose
import Fw.Parts.FootprintData
namespace Fw.Console.Layers
open Fw.Console.BuildsOpen Fw.Console.Compose
open Fw.Parts.Footprint (Access same splitKind reads writes)

inductive Grade | E | E1 | Q | L
deriving Repr, DecidableEq

def Grade.rank : Grade → Nat | .E => 0 | .E1 => 1 | .Q => 2 | .L => 3

def Grade.name : Grade → String | .E => "E" | .E1 => "E1" | .Q => "Q" | .L => "L"

def Grade.max (a b : Grade) : Grade := if a.rank < b.rank then b else a

def worst : List Grade → Grade
  | [] => .E
  | g :: gs => g.max (worst gs)

theorem Grade.max_eq_E (a b : Grade) : a.max b = .E ↔ a = .E ∧ b = .E := by
  cases a <;> cases b <;> decide

theorem Grade.max_L_left (b : Grade) : Grade.L.max b = .L := by cases b <;> decide

theorem Grade.max_L_right (a : Grade) : a.max .L = .L := by cases a <;> decide

theorem worst_eq_E (gs : List Grade) : worst gs = .E ↔ ∀ g ∈ gs, g = .E := by
  induction gs with
  | nil => simp [worst]
  | cons g gs ih => simp [worst, Grade.max_eq_E, ih]

theorem worst_L (gs : List Grade) (h : Grade.L ∈ gs) : worst gs = .L := by
  induction gs with
  | nil => cases h
  | cons g gs ih =>
    rcases List.mem_cons.1 h with rfl | h'
    · exact Grade.max_L_left _
    · simp only [worst]; rw [ih h']; exact Grade.max_L_right _

structure VarL where
  name : String
  kind : String := "optimized"
  visClass : String := ""
  limit : String := ""
  lean : String := ""
  refuted : String := ""
  files : List String := []
deriving Repr, DecidableEq

structure SnapPath where
  path : String
  variant : String
  composited : Bool
deriving Repr, DecidableEq

structure LayerL where
  id : String
  text : Bool
  props : Option (List String) := none
  paths : List SnapPath := []
deriving Repr, DecidableEq

structure PartL where
  id : String
  slot : String := ""
  variants : List VarL
  impls : List String := []
  requires : List (String × List String) := []
  conflicts : List (String × List String) := []
  layers : List LayerL := []
deriving Repr

structure Change where
  id : String
  label : String := ""
  picks : List (String × String)
  lean : String := ""
deriving Repr

structure Arm where
  original : Bool := false
  changes : List String := []
  picks : List (String × String) := []
  opts : List (String × String) := []
deriving Repr

structure Page where
  parts : List PartL
  changes : List Change := []
  accesses : List Access
deriving Repr

def PartL.dflt (p : PartL) : String := (p.variants.head?.map (·.name)).getD "faithful"

def PartL.var (p : PartL) (v : String) : Option VarL := p.variants.find? (·.name == v)

def PartL.fact (p : PartL) : PartFact :=
  { id := p.id, variants := p.variants.map (·.name), impls := p.impls, requires := p.requires,
    conflicts := p.conflicts, layers := p.layers.map (·.id) }

def PartL.info (p : PartL) : PartInfo :=
  { id := p.id, slot := p.slot, variants := p.variants.map fun v => { name := v.name, kind := v.kind, limit := v.limit },
    impls := p.impls, requires := p.requires, conflicts := p.conflicts }

def Page.part (pg : Page) (id : String) : Option PartL := pg.parts.find? (·.id == id)

def Page.change (pg : Page) (id : String) : Option Change := pg.changes.find? (·.id == id)

def Page.layer (pg : Page) (l : String) : Option (PartL × LayerL) :=
  pg.parts.findSome? fun p => (p.layers.find? (·.id == l)).map fun x => (p, x)

def key (e : String × String) : String := e.1 ++ ":" ++ e.2

def own (pg : Page) (e : String × String) : List Access :=
  match pg.part e.1 with
  | none => []
  | some p => if e.2 == p.dflt then [] else
      pg.accesses.filter fun a => a.part == p.id && a.variants.contains e.2 && !a.variants.contains p.dflt

def cleared (pg : Page) (e : String × String) : List Access :=
  match pg.part e.1 with
  | none => []
  | some p => if e.2 == p.dflt then [] else
      pg.accesses.filter fun a => a.part == p.id && a.variants.contains p.dflt && !a.variants.contains e.2

def faithfulReads (pg : Page) (p : PartL) : List String :=
  (pg.accesses.filter fun a => a.part == p.id && a.variants.contains p.dflt).flatMap reads

def extractWhy (p : PartL) (v : VarL) : Option String :=
  if v.name == p.dflt then none else
  let d := ((p.var p.dflt).map (·.files)).getD []
  if d.isEmpty then some "its part lists no files"
  else if v.files.all d.contains && d.all v.files.contains then
    some "it differs from the default only by a branch inside a shared file"
  else none

def affectsW (w r : String) : Bool := same w r || (w == "scrollY" && (splitKind r).1 == "rect")

def anyPair {α β : Type} (xs : List α) (ys : List β) (f : α → β → Bool) : Bool := xs.any fun x => ys.any (f x)

def rowsCoupled (p q : String) : Bool :=
  match Fw.Parts.Contract.parts.find? (·.id == p), Fw.Parts.Contract.parts.find? (·.id == q) with
  | some P, some Q => !(Fw.Parts.Contract.i2 P Q && Fw.Parts.Contract.i4 P Q)
  | _, _ => false

inductive Kind | change | pick | option
deriving Repr, DecidableEq

def Kind.name : Kind → String | .change => "change" | .pick => "pick" | .option => "option"

structure Unit where
  id : String
  kind : Kind
  picks : List (String × String)
  proof : String
  layer : Option (LayerL × String × String) := none
deriving Repr

def composite (o : String) : Bool := o == "c" || o == "cs"

def snap (o : String) : Bool := o == "s" || o == "cs"

def pickUnit (pg : Page) (e : String × String) : Unit :=
  { id := key e, kind := .pick, picks := [e], proof := (((pg.part e.1).bind (·.var e.2)).map (·.lean)).getD "" }

def changeUnit (pg : Page) (c : String) : Option Unit :=
  (pg.change c).map fun ch => { id := ch.id, kind := .change, picks := ch.picks, proof := ch.lean }

def optUnit (pg : Page) (o : String × String) : Option Unit :=
  (pg.layer o.1).map fun pl => { id := key o, kind := .option, picks := [], proof := "", layer := some (pl.2, pl.1.id, o.2) }

def unitsOf (pg : Page) (a : Arm) : List Unit :=
  a.changes.filterMap (changeUnit pg) ++ a.picks.map (pickUnit pg) ++ a.opts.filterMap (optUnit pg)

def Unit.writes (pg : Page) (u : Unit) : List String :=
  u.picks.flatMap (fun e => (own pg e ++ cleared pg e).flatMap Fw.Parts.Footprint.writes) ++
  match u.layer with
  | some (_, pid, o) => if composite o then ["cssVar:will-change/" ++ pid] else []
  | none => []

def Unit.reads (pg : Page) (u : Unit) : List String :=
  u.picks.flatMap fun e => (pg.accesses.filter fun r => r.part == e.1 && r.variants.contains e.2).flatMap Fw.Parts.Footprint.reads

def Unit.targets (pg : Page) (u : Unit) : List String :=
  (u.picks.flatMap fun e => ((own pg e ++ cleared pg e).filter (·.op.isWrite)).map (·.owner)).filter
    fun o => o != "" && o != "?" && o != "document"

def Unit.parts (u : Unit) : List String := u.picks.map (·.1)

def linkB (pg : Page) (a b : Unit) : Bool :=
  anyPair (a.writes pg) (b.writes pg) same || anyPair (a.writes pg) (b.reads pg) affectsW ||
    (a.targets pg).any (fun t => (b.parts ++ b.targets pg).contains t) || anyPair a.parts b.parts rowsCoupled

def clash (pg : Page) (a b : Unit) : Bool := linkB pg a b || linkB pg b a

def whyLink (pg : Page) (a b : Unit) : Option String :=
  ((a.writes pg).findSome? fun w => ((b.writes pg).find? (same w)).map fun _ => s!"both write {w}") <|>
  ((a.writes pg).findSome? fun w => ((b.reads pg).find? (affectsW w)).map fun r => s!"{a.id} writes {w}, which {b.id} reads as {r}") <|>
  (((a.targets pg).find? fun t => (b.parts ++ b.targets pg).contains t).map fun t => s!"{a.id} writes an element of {t} (I1)") <|>
  (a.parts.findSome? fun p => (b.parts.find? (rowsCoupled p)).map fun q => s!"the contract rows of {p} and {q} fail I2 or I4")

def why (pg : Page) (a b : Unit) : String := ((whyLink pg a b) <|> (whyLink pg b a)).getD ""

theorem clash_symm (pg : Page) (a b : Unit) : clash pg a b = clash pg b a := Bool.or_comm _ _

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

def owned (pg : Page) (a : Arm) : List ((String × String) × String) :=
  (unitsOf pg a).flatMap fun u => u.picks.map fun e => (e, u.id)

def expandedPicks (pg : Page) (a : Arm) : List (String × String) := (unitsOf pg a).flatMap (·.picks)

def selOf (pg : Page) (a : Arm) (p : PartL) : String :=
  match ((expandedPicks pg a).filter (·.1 == p.id)).getLast? with
  | some e => e.2
  | none => p.dflt

def faithfulParts (pg : Page) (us : List Unit) : List PartL :=
  pg.parts.filter fun p => !(us.any fun u => u.parts.contains p.id)

def hits (pg : Page) (u : Unit) (q : PartL) : Bool := anyPair (u.writes pg) (faithfulReads pg q) affectsW

def layerInfo (id : String) : PartInfo :=
  { id, slot := "", variants := ["", "c", "s", "cs"].map fun n => { name := n, kind := "", limit := "" }, impls := [],
    requires := [], conflicts := [] }

def layerInfos (pg : Page) : List PartInfo :=
  (ordered (pg.parts.map PartL.info)).flatMap fun pi => (((pg.part pi.id).map (·.layers)).getD []).map (layerInfo ·.id)

def fwEnts (pg : Page) (a : Arm) : List (String × String) := entries (ordered (pg.parts.map PartL.info)) (expandedPicks pg a)

def fwlEnts (pg : Page) (a : Arm) : List (String × String) := entries (layerInfos pg) a.opts

def searchOf (pg : Page) (a : Arm) : String := canonical none ((fwEnts pg a).map key) ((fwlEnts pg a).map key)

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

def Refusal.code : Refusal → String
  | .unknownChange .. => "unknown-change" | .unknownPart .. => "unknown-part" | .unknownVariant .. => "unknown-variant"
  | .unknownLayer .. => "unknown-layer" | .notExtractable .. => "not-extractable" | .refuted .. => "refuted"
  | .setTwice .. => "set-twice" | .notOffered .. => "not-offered" | .compositeWillChange .. => "composite-will-change"
  | .pathNoVariant .. => "path-no-variant" | .snapLeaves .. => "snap-leaves-compositor" | .originalArm => "original-arm"
  | .coupled .. => "coupled" | .clash .. => "clash" | .uncovered .. => "uncovered-reader"
  | .sharedReader .. => "shared-reader" | .rule .. => "rule"

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

def originalReasons (a : Arm) : List Refusal :=
  if a.original && !(a.changes.isEmpty && a.picks.isEmpty && a.opts.isEmpty) then [.originalArm] else []

def unknownReasons (pg : Page) (a : Arm) : List Refusal :=
  a.changes.filterMap (fun c => if (pg.change c).isSome then none else some (.unknownChange c)) ++
  (expandedPicks pg a).filterMap (fun e => match pg.part e.1 with
    | none => some (.unknownPart e.1)
    | some p => if (p.var e.2).isSome then none else some (.unknownVariant e.1 e.2)) ++
  a.opts.filterMap fun o => if (pg.layer o.1).isSome then none else some (.unknownLayer o.1)

def extractReasons (pg : Page) (a : Arm) : List Refusal :=
  (expandedPicks pg a).filterMap fun e =>
    (pg.part e.1).bind fun p => (p.var e.2).bind fun v => (extractWhy p v).map (.notExtractable (key e))

def refutedReasons (pg : Page) (us : List Unit) : List Refusal :=
  us.flatMap fun u => u.picks.filterMap fun e =>
    ((pg.part e.1).bind (·.var e.2)).bind fun v => if v.refuted == "" then none else some (.refuted u.id (key e) v.refuted)

def setTwiceReasons (pg : Page) (a : Arm) : List Refusal :=
  (pairsOf (owned pg a)).filterMap fun (x, y) => if x.1.1 == y.1.1 then some (.setTwice x.1.1 x.2 y.2) else none

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

def coupledReasons (pg : Page) (us : List Unit) : List Refusal :=
  us.flatMap fun u =>
    if u.kind == .change && u.proof == "" then
      (pairsOf u.picks).filterMap fun (x, y) =>
        if clash pg (pickUnit pg x) (pickUnit pg y) then some (.coupled u.id (key x) (key y)) else none
    else []

def clashReasons (pg : Page) (us : List Unit) : List Refusal :=
  (pairsOf us).filterMap fun (x, y) => if clash pg x y then some (.clash x.id y.id (why pg x y)) else none

def coverReasons (pg : Page) (us : List Unit) : List Refusal :=
  (faithfulParts pg us).flatMap fun q =>
    (us.filterMap fun u =>
      if hits pg u q && u.proof == "" && !((u.parts ++ u.targets pg).contains q.id) then
        some (.uncovered u.id q.id (((u.writes pg).find? fun w => (faithfulReads pg q).any (affectsW w)).getD ""))
      else none) ++
    (pairsOf (us.filter (hits pg · q))).map fun (x, y) => .sharedReader q.id x.id y.id

def ruleReasons (pg : Page) (a : Arm) : List Refusal :=
  match validate (pg.parts.map PartL.fact) [] (searchOf pg a) with
  | .ok _ => []
  | .refused rs => rs.map .rule

def reasonsOf (pg : Page) (a : Arm) : List Refusal :=
  let us := unitsOf pg a
  originalReasons a ++ unknownReasons pg a ++ extractReasons pg a ++ refutedReasons pg us ++ setTwiceReasons pg a ++
    optionReasons pg a ++ coupledReasons pg us ++ clashReasons pg us ++ coverReasons pg us ++ ruleReasons pg a

def keysOf (pg : Page) (sel : List (String × String)) : List String :=
  pg.parts.map fun p => key (p.id, (((sel.filter (·.1 == p.id)).getLast?).map (·.2)).getD p.dflt)

def reqOk (pg : Page) (base kept : List (String × String)) (e : String × String) : Bool :=
  ((((pg.part e.1).map (·.requires)).getD []).lookup (key e)).getD [] |>.all fun n => (keysOf pg (base ++ kept)).contains n

def keepOk {α : Type} (ok : List α → α → Bool) (S : List α) : List α := S.filter (ok S)

def closeReq {α : Type} (ok : List α → α → Bool) (S : List α) : List α :=
  if _h : (keepOk ok S).length < S.length then closeReq ok (keepOk ok S) else S
termination_by S.length

theorem closeReq_closed {α : Type} (ok : List α → α → Bool) (S : List α) :
    ∀ x ∈ closeReq ok S, ok (closeReq ok S) x = true := by
  induction S using closeReq.induct ok with
  | case1 S h ih => rw [closeReq]; simp only [h, ↓reduceDIte]; exact ih
  | case2 S h =>
    rw [closeReq]; simp only [h, ↓reduceDIte]
    have hle := List.length_filter_le (ok S) S
    simp only [keepOk] at h
    exact List.length_filter_eq_length_iff.1 (by omega)

def changePicks (pg : Page) (a : Arm) : List (String × String) :=
  ((unitsOf pg a).filter (·.kind == .change)).flatMap (·.picks)

def keptOf (pg : Page) (a : Arm) : List (String × String) :=
  closeReq (fun k e => reqOk pg (changePicks pg a) k e) (a.picks.filter fun e => !(changePicks pg a).any (·.1 == e.1))

def fixOf (pg : Page) (a : Arm) : List (String × String) := a.picks.filter fun e => !(keptOf pg a).contains e

theorem fix_closed_requires (pg : Page) (a : Arm) :
    ∀ e ∈ keptOf pg a, reqOk pg (changePicks pg a) (keptOf pg a) e = true :=
  closeReq_closed _ _

def varGrade (v : VarL) : Grade :=
  if v.kind == "faithful" then .E
  else if lookChange v.limit || v.visClass == "L" then .L
  else if (v.visClass == "E" || v.visClass == "E-s") && v.lean != "" then .E
  else if v.visClass == "E1" && v.lean != "" then .E1
  else .Q

def unitGrade (pg : Page) (u : Unit) : Grade :=
  match u.layer with
  | some (l, _, o) => if l.text && composite o && !snap o then .L else .Q
  | none => worst (u.picks.map fun e => (((pg.part e.1).bind (·.var e.2)).map varGrade).getD .Q)

def expected (pg : Page) (a : Arm) : Grade := worst ((unitsOf pg a).map (unitGrade pg))

def verdict (pg : Page) (a : Arm) : Option Grade := if expected pg a == .E then some .E else none

def hyps (pg : Page) (a : Arm) : List String :=
  if verdict pg a == some .E then
    ((unitsOf pg a).filterMap fun u => if u.proof == "" then none else some u.proof).eraseDups ++ ["ReadsOnly", "I5"]
  else []

def lookNotes (pg : Page) (a : Arm) : List String :=
  (if expected pg a == .L then ["look change, pending your review"] else []) ++
  ((unitsOf pg a).filterMap fun u => match u.layer with
    | some (l, _, o) => if l.text && composite o && !snap o then some s!"C1 pending: strips ({l.id})" else none
    | none => none) ++
  (if verdict pg a == none then ["expected grade, not a verdict: the arm's worst measured cell decides"] else [])

def mayAnimate (l : LayerL) (prop : String) : Bool := match l.props with | none => true | some ps => ps.contains prop

def layerPremises (l : LayerL) (o : String) : List String :=
  (if composite o then ["P1", "P2"] else []) ++ (if snap o then ["S1", "T1"] else []) ++
  (if l.text && composite o && !snap o && (mayAnimate l "translate" || mayAnimate l "scale") then ["C1"] else []) ++
  (if composite o && mayAnimate l "scale" then ["C2"] else []) ++
  (if composite o && !snap o && mayAnimate l "translate" then ["C5"] else []) ++
  (if composite o && mayAnimate l "filter" then ["C6"] else [])

def premises (pg : Page) (a : Arm) : List (String × List String) :=
  ("page", ["P3", "P4"]) :: (unitsOf pg a).filterMap fun u => u.layer.map fun (l, _, o) => (l.id, layerPremises l o)

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

def decideArm (pg : Page) (a : Arm) : Out :=
  let rs := reasonsOf pg a
  { link := if rs.isEmpty then some (searchOf pg a) else none, reasons := rs, units := unitsOf pg a,
    grade := expected pg a, verdict := verdict pg a, hyps := hyps pg a, notes := lookNotes pg a,
    premises := premises pg a, fix := if (setTwiceReasons pg a).isEmpty then [] else fixOf pg a }

theorem link_iff (pg : Page) (a : Arm) : (decideArm pg a).link.isSome = (decideArm pg a).reasons.isEmpty := by
  unfold decideArm; simp only []; split <;> simp_all

theorem decideArm_link (pg : Page) (a : Arm) (c : String) (h : (decideArm pg a).link = some c) :
    c = searchOf pg a ∧ reasonsOf pg a = [] := by
  unfold decideArm at h; simp only [] at h
  split at h
  · rename_i hr; simp at h; exact ⟨h.symm, by simpa using hr⟩
  · simp at h

theorem refused_of_mem (pg : Page) (a : Arm) (r : Refusal) (h : r ∈ reasonsOf pg a) : (decideArm pg a).link = none := by
  unfold decideArm; simp only []
  split
  · rename_i hr; simp at hr; simp [hr] at h
  · rfl

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

theorem allowed_no_clash (pg : Page) (a : Arm) (h : (decideArm pg a).link.isSome = true) (i j : Nat)
    (hi : i < (unitsOf pg a).length) (hj : j < (unitsOf pg a).length) (hne : i ≠ j) :
    clash pg (unitsOf pg a)[i] (unitsOf pg a)[j] = false := by
  rcases Nat.lt_or_gt_of_ne hne with hlt | hgt
  · exact allowed_pairwise_independent pg a h i j hlt hj
  · rw [clash_symm]; exact allowed_pairwise_independent pg a h j i hgt hi

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

def flatten (pg : Page) (a : Arm) : Arm := { a with changes := [], picks := expandedPicks pg a }

theorem flatMap_picks_opts (pg : Page) (os : List (String × String)) :
    (os.filterMap (optUnit pg)).flatMap (·.picks) = [] := by
  induction os with
  | nil => rfl
  | cons o os ih => cases h : optUnit pg o <;> simp only [List.filterMap_cons, h, ih]
                    <;> simp [optUnit] at h <;> obtain ⟨_, _, _, rfl⟩ := h <;> simp [ih]

theorem expand_idem (pg : Page) (a : Arm) : expandedPicks pg (flatten pg a) = expandedPicks pg a := by
  have hp : ∀ ps : List (String × String), (ps.map (pickUnit pg)).flatMap (·.picks) = ps := by
    intro ps; induction ps with
    | nil => rfl
    | cons e ps ih => simp [pickUnit, ih]
  simp only [expandedPicks, unitsOf, flatten, List.filterMap_nil, List.nil_append, List.flatMap_append, hp,
    flatMap_picks_opts, List.append_nil]

theorem search_flatten (pg : Page) (a : Arm) : searchOf pg (flatten pg a) = searchOf pg a := by
  simp only [searchOf, fwEnts, fwlEnts, expand_idem]; rfl

theorem search_entries_inj (pg : Page) (hnd : ((layerInfos pg).map (·.id)).Nodup) (a b : Arm)
    (h : fwlEnts pg a = fwlEnts pg b) : ∀ l ∈ layerInfos pg, choice a.opts l = choice b.opts l :=
  entries_inj (layerInfos pg) hnd a.opts b.opts h

theorem look_E_iff_all_E (pg : Page) (a : Arm) :
    verdict pg a = some .E ↔ ∀ u ∈ unitsOf pg a, unitGrade pg u = .E := by
  unfold verdict expected
  rw [← List.forall_mem_map (f := unitGrade pg) (P := fun g => g = .E), ← worst_eq_E]
  split <;> simp_all

theorem look_measured_of_nonE (pg : Page) (a : Arm) (u : Unit) (hu : u ∈ unitsOf pg a) (hg : unitGrade pg u ≠ .E) :
    verdict pg a = none := by
  cases hv : verdict pg a with
  | none => rfl
  | some g =>
    have : g = .E := by unfold verdict at hv; split at hv <;> simp_all
    subst this
    exact absurd ((look_E_iff_all_E pg a).1 hv u hu) hg

theorem look_L_of_unit_L (pg : Page) (a : Arm) (u : Unit) (hu : u ∈ unitsOf pg a) (hg : unitGrade pg u = .L) :
    expected pg a = .L :=
  worst_L _ (List.mem_map.2 ⟨u, hu, hg⟩)

theorem option_not_E (pg : Page) (a : Arm) (u : Unit) (hu : u ∈ unitsOf pg a) (l : LayerL) (pid o : String)
    (hl : u.layer = some (l, pid, o)) : verdict pg a = none := by
  refine look_measured_of_nonE pg a u hu ?_
  simp only [unitGrade, hl]; split <;> simp

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

theorem premises_complete (pg : Page) (a : Arm) (l : LayerL) (o : String) (hc : composite o = true) :
    "P1" ∈ layerPremises l o ∧ "P2" ∈ layerPremises l o ∧ ("page", ["P3", "P4"]) ∈ premises pg a := by
  simp [layerPremises, premises, hc]

theorem snap_drops_C5 (l : LayerL) (o : String) (hs : snap o = true) :
    "C5" ∉ layerPremises l o ∧ "S1" ∈ layerPremises l o ∧ "T1" ∈ layerPremises l o := by
  refine ⟨?_, by simp [layerPremises, hs], by simp [layerPremises, hs]⟩
  simp only [layerPremises, hs, Bool.not_true, Bool.and_false, Bool.false_and, ↓reduceIte,
    List.mem_append]
  intro h
  rcases h with ((((h | h) | h) | h) | h) <;> (repeat' split at h) <;> simp_all

theorem text_composite_C1 (l : LayerL) (o : String) (ht : l.text = true) (hc : composite o = true) (hs : snap o = false)
    (hm : l.props = none) : "C1" ∈ layerPremises l o := by
  simp [layerPremises, ht, hc, hs, mayAnimate, hm]

def extractable (pg : Page) : List (String × String) :=
  pg.parts.flatMap fun p =>
    (p.variants.filter fun v => v.name != p.dflt && v.refuted == "" && (extractWhy p v).isNone).map (p.id, ·.name)

def declared (pg : Page) (x y : String × String) : Bool :=
  let has (e f : String × String) := (((((pg.part e.1).map (·.conflicts)).getD []).lookup (key e)).getD []).contains (key f)
  has x y || has y x

def registryErrors (pg : Page) : List String :=
  (pg.changes.filterMap fun c =>
    let rs := reasonsOf pg { changes := [c.id] }
    if rs.isEmpty then none else some s!"change {c.id} fails alone: {"; ".intercalate (rs.map (·.text))}") ++
  ((pairsOf (extractable pg)).filterMap fun (x, y) =>
    if x.1 != y.1 && clash pg (pickUnit pg x) (pickUnit pg y) && !declared pg x y then
      some s!"undeclared conflict: {key x} and {key y} clash ({why pg (pickUnit pg x) (pickUnit pg y)}), and part.json conflicts lists neither"
    else none)

def declaredLayerErrors : List String :=
  let decls := Fw.Parts.FootprintData.layerDecls
  let facts : List PartFact := (decls.map (·.1)).eraseDups.map fun p =>
    { id := p, variants := ["faithful"], impls := [], requires := [], conflicts := [],
      layers := (decls.filter (·.1 == p)).map (·.2.1) }
  decls.filterMap fun (_, l, _) =>
    if validate facts [] s!"?fwl={l}:c" == .ok s!"?fwl={l}:c" then none else some l

#guard declaredLayerErrors == []
#guard Fw.Parts.FootprintData.layerDecls.length > 0


def exAccess (part file : String) (op : Fw.Parts.Footprint.Op) (name owner : String) (vs : List String) : Access :=
  { part, file, line := 1, op, name, owner, ctx := "raf", variants := vs }

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
        { name := "steps", visClass := "E1", lean := "Fw.Demo.steps_within_one", files := ["steps.ts"] },
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

def exShared : Page := { exPage with
  parts := exPage.parts.map fun p => if p.id == "demo.c" then
      { p with variants := [{ name := "faithful", kind := "faithful", files := ["c.ts"] },
        { name := "alt", files := ["c.ts", "c-alt.ts"] }] } else p
  accesses := exPage.accesses.map fun a => if a.part == "demo.c" then { a with variants := ["faithful", "alt"] } else a }

def exCodes (a : Arm) : List String := (reasonsOf exPage a).map (·.code)

#guard exCodes { picks := [("hero.exit", "threaded"), ("hero.countdown", "hidden-pause")] } = ["clash", "rule"]
#guard (decideArm exPage { picks := [("hero.exit", "threaded")] }).link = some "?fw=hero.exit:threaded"
#guard (decideArm exPage { picks := [("hero.exit", "threaded")] }).verdict = some .E
#guard (decideArm exPage { picks := [("hero.exit", "threaded")] }).hyps = ["Fw.Demo.threaded_same", "ReadsOnly", "I5"]
#guard exCodes { changes := ["strip-pair"] } = ["coupled", "uncovered-reader"]
#guard (decideArm exPage { changes := ["strip-pair-proved"] }).link = some "?fw=demo.a:fast,demo.b:fast"
#guard (decideArm exPage { picks := [("hero.exit", "threaded"), ("hero.accent", "steps")] }).link =
  some "?fw=hero.accent:steps,hero.exit:threaded"
#guard (decideArm exPage { picks := [("hero.exit", "threaded"), ("hero.accent", "steps")] }).grade = .E1
#guard (decideArm exPage { picks := [("hero.exit", "threaded"), ("hero.accent", "steps")] }).verdict = none
#guard exCodes { picks := [("hero", "scene-pause")], opts := [("hero_copy", "c")] } = ["composite-will-change"]
#guard (decideArm exPage { opts := [("hero_copy", "c")] }).link = some "?fwl=hero_copy:c"
#guard (decideArm exPage { opts := [("hero_copy", "c")] }).grade = .L
#guard (decideArm exPage { opts := [("hero_copy", "c")] }).notes.contains "C1 pending: strips (hero_copy)" = true
#guard (decideArm exPage { opts := [("hero_copy", "c")] }).premises =
  [("page", ["P3", "P4"]), ("hero_copy", ["P1", "P2", "C1", "C2", "C5", "C6"])]
#guard (decideArm exPage { opts := [("hero.countdown_strip", "s")] }).link = some "?fwl=hero.countdown_strip:s"
#guard exCodes { picks := [("hero.countdown", "hidden-pause")], opts := [("hero.countdown_strip", "s")] } =
  ["snap-leaves-compositor"]
#guard exCodes { picks := [("hero.accent", "steps")], opts := [("hero.accent_mark", "s")] } = ["path-no-variant"]
#guard exCodes { opts := [("hero_copy", "s")] } = ["not-offered"]
#guard exCodes { opts := [("hero_copy", "x")] } = ["not-offered"]
#guard exCodes { opts := [("nope", "c")] } = ["unknown-layer"]
#guard exCodes { changes := ["nope"] } = ["unknown-change"]
#guard exCodes { picks := [("nope", "x")] } = ["unknown-part"]
#guard exCodes { picks := [("hero", "x")] } = ["unknown-variant"]
#guard exCodes { picks := [("hero.countdown", "strip")] } = ["not-extractable"]
#guard exCodes { picks := [("hero.accent", "gone")] } = ["refuted"]
#guard varGrade { name := "steps", visClass := "E1" } = .Q
#guard exCodes { changes := ["strip-pair-proved"], picks := [("demo.a", "fast")] } =
  ["set-twice", "clash", "uncovered-reader", "shared-reader"]
#guard (decideArm exPage { changes := ["strip-pair-proved"], picks := [("demo.a", "fast")] }).fix = [("demo.a", "fast")]
#guard (decideArm exPage { changes := ["a-slow"], picks := [("demo.a", "fast"), ("demo.b", "fast")] }).fix =
  [("demo.a", "fast"), ("demo.b", "fast")]
#guard exCodes { picks := [("demo.a", "fast")] } = ["uncovered-reader"]
#guard exCodes { picks := [("hero.exit", "threaded"), ("demo.a", "fast")] } = ["uncovered-reader", "shared-reader"]
#guard (reasonsOf exShared { picks := [("demo.a", "fast"), ("demo.c", "alt")] }).map (·.code) = ["clash"]
#guard (reasonsOf exShared { picks := [("demo.a", "fast")] }).map (·.code) = ["uncovered-reader"]
#guard exCodes { changes := ["a-slow"], picks := [("demo.b", "fast")] } = ["rule"]
#guard exCodes { original := true, picks := [("hero.exit", "threaded")] } = ["original-arm"]
#guard (decideArm exPage { original := true }).link = some ""
#guard searchOf exPage
    { picks := [("hero.accent", "steps"), ("hero.exit", "threaded")],
      opts := [("hero.countdown_strip", "s"), ("hero_copy", "c")] } =
  "?fw=hero.accent:steps,hero.exit:threaded&fwl=hero_copy:c,hero.countdown_strip:s"
#guard (registryErrors exPage).map (·.splitOn ":" |>.head!) =
  ["change strip-pair fails alone", "undeclared conflict", "undeclared conflict", "undeclared conflict"]
#guard (registryErrors exPage).contains
  "undeclared conflict: hero:scene-pause and hero.exit:threaded clash (hero:scene-pause writes an element of hero.exit (I1)), and part.json conflicts lists neither"

end Fw.Console.Layers
