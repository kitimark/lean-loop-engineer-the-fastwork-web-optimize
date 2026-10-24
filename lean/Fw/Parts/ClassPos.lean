import Lean.Data.Json

/-! Class positions of a className expression, a className assignment and a classList call, the class union of two
values, and how a selector class meets an element; part-footprint.mjs mirrors each rule and replays the golden. -/
namespace Fw.Parts.ClassPos

mutual
inductive E where
  | str (s : String)
  | num (src : String)
  | bool (b : Bool)
  | nil
  | id (n : String)
  | const (n : String) (init : E)
  | member (path : String)
  | mod (l : String)
  | modKey (m : String)
  | cmp (a b : E)
  | not (a : E)
  | cond (t c a : E)
  | and (l r : E)
  | or (l r : E)
  | nullish (l r : E)
  | tmpl (qs : List String) (es : List E)
  | concat (l r : E)
  | arr (es : List E)
  | obj (ps : List P)
  | call (name : String) (args : List E)
  | method (recv : E) (name : String) (args : List E)
  | spread (e : E)
  | other (kids : List E)

inductive P where
  | key (k : String) (v : E)
  | comp (k v : E)
  | spread (e : E)
end

inductive Kind where
  | cls
  | mod
  | lost
  | glued
  deriving DecidableEq, Repr

structure Tok where
  kind : Kind
  name : String
  deriving DecidableEq, Repr

inductive Ctx where
  | attr
  | text
  | list
  | join
  | elem
  deriving DecidableEq, Repr

def Ctx.drops : Ctx → Bool
  | .list | .join => true
  | .attr | .text | .elem => false

def Ctx.flat : Ctx → Bool
  | .list => true
  | _ => false

def Tok.lose (t : Tok) : Tok := { t with kind := .lost }

def marker (form : String) (ts : List Tok) : List Tok := ⟨.lost, form⟩ :: ts.map Tok.lose

inductive Piece where
  | text (s : String)
  | hole (ts : List Tok)

inductive Atom where
  | chars (s : String)
  | hole (ts : List Tok)

def isSep (c : Char) : Bool := c == ' ' || c == '\t' || c == '\n' || c == Char.ofNat 12 || c == '\r'

def segs (s : String) : List String := (s.split isSep).toList.map toString

def tokens (s : String) : List String := (segs s).filter (· ≠ "")

def push (w : List Atom) : Atom → List Atom
  | .chars s =>
    if s.isEmpty then w
    else match w.getLast? with
      | some (.chars p) => w.dropLast ++ [.chars (p ++ s)]
      | _ => w ++ [.chars s]
  | .hole ts => w ++ [.hole ts]

def wordsOf : List Piece → List (List Atom) → List Atom → List (List Atom)
  | [], done, cur => done ++ [cur]
  | .hole ts :: ps, done, cur => wordsOf ps done (push cur (.hole ts))
  | .text s :: ps, done, cur =>
    let r := ((segs s).drop 1).foldl (fun acc g => (acc.1 ++ [acc.2], push [] (.chars g)))
      (done, push cur (.chars ((segs s).headD "")))
    wordsOf ps r.1 r.2

def Atom.text : Atom → String
  | .chars s => s
  | .hole _ => "*"

def Atom.toks : Atom → List Tok
  | .chars c => [⟨.cls, c⟩]
  | .hole ts => ts

def wordToks : List Atom → List Tok
  | [] => []
  | [a] => a.toks
  | w => ⟨.glued, String.join (w.map Atom.text)⟩ :: w.flatMap Atom.toks

def words (ps : List Piece) : List Tok := (wordsOf ps [] []).flatMap wordToks

def listHelpers : List String := ["clsx", "classNames", "classnames"]

def joinHelpers : List String := ["cx", "cls"]

def sepOk : List E → Bool
  | [.str s] => !s.isEmpty && s.all isSep
  | _ => false

def joinToks (ts : List Tok) (args : List E) : List Tok := if sepOk args then ts else marker "join separator" ts

def methodToks (n : String) (elems : Option (List Tok)) (recv argToks : List Tok) (args : List E) : List Tok :=
  match n == "join", elems with
  | true, some ts => joinToks ts args
  | _, _ => marker ("method " ++ n) (recv ++ argToks)

def hole (ts : List Tok) : List Tok × List Piece := (ts, [.hole ts])

def boolToks : Ctx → Bool → List Tok
  | .text, b | .elem, b => [⟨.cls, toString b⟩]
  | .join, true => [⟨.cls, "true"⟩]
  | _, _ => []

def testToks (c : Ctx) : List Tok := boolToks c true ++ boolToks c false

def nullToks (c : Ctx) (n : String) : List Tok := if c == .text then [⟨.cls, n⟩] else []

def idToks (c : Ctx) (n : String) : List Tok := if n == "undefined" then nullToks c n else marker ("id " ++ n) []

def isTest : E → Bool
  | .cmp _ _ | .not _ | .bool _ => true
  | _ => false

def isStr : E → Bool
  | .str _ => true
  | _ => false

def calleeCtx (n : String) : Option Ctx :=
  if listHelpers.contains n then some .list else if joinHelpers.contains n then some .join else none

def filterCtx : List E → Ctx
  | [.id "Boolean"] => .join
  | _ => .elem

mutual
def go (c : Ctx) : E → List Tok × List Piece
  | .str s => ((tokens s).map (Tok.mk .cls), [.text s])
  | .num _ => hole (marker "number" [])
  | .bool b => hole (boolToks c b)
  | .nil => hole (nullToks c "null")
  | .id n => hole (idToks c n)
  | .const _ i => go c i
  | .member _ => hole (marker "member" [])
  | .mod m => hole [⟨.mod, "css#" ++ m⟩]
  | .modKey m => hole (marker ("module key " ++ m) [])
  | .cmp _ _ => hole (testToks c)
  | .not _ => hole (testToks c)
  | .cond _ a b => hole ((go c a).1 ++ (go c b).1)
  | .and l r =>
    hole ((if c.drops || isStr l then [] else if isTest l then boolToks c false else (go c l).1) ++ (go c r).1)
  | .or a b => hole ((go c a).1 ++ (go c b).1)
  | .nullish a b => hole ((go c a).1 ++ (go c b).1)
  | .tmpl qs es => let ps := goTmpl qs es; (words ps, ps)
  | .concat a b => let ps := (go .text a).2 ++ (go .text b).2; (words ps, ps)
  | .arr es => hole (if c.flat then goList c es else marker "array" (goList .elem es))
  | .obj ps => hole (if c.flat then goProps ps else marker "object" (goProps ps))
  | .call n args => hole (match calleeCtx n with
    | some k => goList k args
    | none => marker ("call " ++ n) (goList .attr args))
  | .method recv n args => hole (methodToks n (goElems recv) (go .attr recv).1 (goList .attr args) args)
  | .spread e => hole (marker "spread" (go c e).1)
  | .other kids => hole (marker "other" (goList .attr kids))

def goElems : E → Option (List Tok)
  | .arr es => some (goList .elem es)
  | .method (.arr es) "filter" f => some (goList (filterCtx f) es)
  | _ => none

def goList (c : Ctx) : List E → List Tok
  | [] => []
  | e :: es => (go c e).1 ++ goList c es

def goProps : List P → List Tok
  | [] => []
  | .key k _ :: ps => (tokens k).map (Tok.mk .cls) ++ goProps ps
  | .comp k _ :: ps => (go .text k).1 ++ goProps ps
  | .spread e :: ps => marker "spread" (go .list e).1 ++ goProps ps

def goTmpl (qs : List String) : List E → List Piece
  | [] => qs.map .text
  | e :: es => .text (qs.headD "") :: (go .text e).2 ++ goTmpl qs.tail es
end

def toks (e : E) : List Tok := (go .attr e).1

def assignToks (e : E) : List Tok := (go .text e).1

def Kind.opens : Kind → Bool
  | .lost | .glued => true
  | .cls | .mod => false

def isOpen (ts : List Tok) : Bool := ts.any (·.kind.opens)

def writes (ts : List Tok) : List (String × String) :=
  ts.filterMap (fun t => match t.kind with
    | .cls => some ("setClass", t.name)
    | .mod => some ("setModuleClass", t.name)
    | .lost | .glued => none) ++
  (if isOpen ts then [("setClass", "?")] else [])

def assignWrites (ts : List Tok) : List (String × String) := if isOpen ts then [("setClass", "*")] else writes ts

def findings (ts : List Tok) : List (String × String) :=
  ts.filterMap fun t => match t.kind with
    | .lost => some ("unmodelled-class", t.name)
    | .glued => some ("glued-class", t.name)
    | .cls | .mod => none

inductive V where
  | str (vs : List String)
  | mod (name : String)
  | modKey (m : String)
  | unknown
  | alt (vs : List V)

def V.alts : V → List V
  | .alt vs => vs
  | v => [v]

def V.union (a b : V) : V := .alt (a.alts ++ b.alts)

def holeMark : Char := Char.ofNat 1

def tokenToks (w : String) : List Tok :=
  if w.any (· == holeMark) then [⟨.glued, w.map fun c => if c == holeMark then '*' else c⟩]
  else if w.isEmpty || w.any isSep then marker "invalid token" [⟨.cls, w⟩]
  else [⟨.cls, w⟩]

mutual
def valueToks : V → List Tok
  | .str vs => vs.flatMap tokenToks
  | .mod n => [⟨.mod, n⟩]
  | .modKey m => marker ("module key " ++ m) []
  | .unknown => marker "unresolved" []
  | .alt vs => altToks vs

def altToks : List V → List Tok
  | [] => []
  | v :: vs => valueToks v ++ altToks vs
end

def listMethods : List String := ["add", "remove", "toggle", "replace", "contains"]

def tokenArgs (m : String) (args : List V) : List V := if m == "toggle" || m == "contains" then args.take 1 else args

def listToks (m : String) (args : List V) : List Tok := (tokenArgs m args).flatMap valueToks

def listWrites (m : String) (ts : List Tok) : List (String × String) :=
  if m == "contains" then (writes ts).map fun w => ("classRead", w.2) else writes ts

inductive Match where
  | none
  | weak
  | strong
  deriving DecidableEq, Repr

def classMatch (has : String → Bool) (sel : List String) (isOpen : Bool) : Match :=
  if sel.all has then .strong else if isOpen then .weak else .none

inductive Strength where
  | literal
  | dynamic
  | spread
  deriving DecidableEq, Repr

def strength (spread literalAttrs : Bool) : Match → Option Strength
  | .none => none
  | .weak => some (if spread then .spread else .dynamic)
  | .strong => some (if spread then .spread else if literalAttrs then .literal else .dynamic)

def pick (cs : List (String × Strength)) : List String × Bool :=
  let lit := cs.filter (·.2 == .literal)
  let dyn := cs.filter (·.2 != .spread)
  if !lit.isEmpty then (lit.map (·.1), false)
  else if !dyn.isEmpty then (dyn.map (·.1), true)
  else (cs.map (·.1), !cs.isEmpty)

def names (ts : List Tok) : List String := ts.map (·.name)

theorem lose_names (ts : List Tok) : names (ts.map Tok.lose) = names ts := by
  simp [names, Tok.lose]

theorem lose_all_lost (ts : List Tok) : ∀ t ∈ ts.map Tok.lose, t.kind = .lost := by
  simp [Tok.lose]

theorem marker_mem (form : String) (ts : List Tok) : ⟨.lost, form⟩ ∈ marker form ts := List.mem_cons_self

theorem str_tokens (s : String) : toks (.str s) = (tokens s).map (Tok.mk .cls) := rfl

theorem const_init (c : Ctx) (n : String) (i : E) : go c (.const n i) = go c i := rfl

theorem const_toks (n : String) (i : E) : toks (.const n i) = toks i := rfl

theorem const_assign (n : String) (i : E) : assignToks (.const n i) = assignToks i := rfl

theorem cond_test_irrelevant (c : Ctx) (t t' a b : E) : go c (.cond t a b) = go c (.cond t' a b) := rfl

theorem cond_branches (t a b : E) : toks (.cond t a b) = toks a ++ toks b := rfl

theorem or_both (a b : E) : toks (.or a b) = toks a ++ toks b := rfl

theorem nullish_both (a b : E) : toks (.nullish a b) = toks a ++ toks b := rfl

theorem cmp_attr (a b : E) : toks (.cmp a b) = [] := rfl

theorem not_attr (a : E) : toks (.not a) = [] := rfl

theorem cmp_list (a b : E) : (go .list (.cmp a b)).1 = [] := rfl

theorem cmp_join (a b : E) : (go .join (.cmp a b)).1 = [⟨.cls, "true"⟩] := rfl

theorem cmp_text (a b : E) : go .text (.cmp a b) = hole [⟨.cls, "true"⟩, ⟨.cls, "false"⟩] := rfl

theorem not_text (a : E) : go .text (.not a) = hole [⟨.cls, "true"⟩, ⟨.cls, "false"⟩] := rfl

theorem cmp_elem (a b : E) : (go .elem (.cmp a b)).1 = [⟨.cls, "true"⟩, ⟨.cls, "false"⟩] := rfl

theorem bool_attr (b : Bool) : toks (.bool b) = [] := by cases b <;> rfl

theorem bool_text (b : Bool) : (go .text (.bool b)).1 = [⟨.cls, toString b⟩] := rfl

theorem undefined_attr : toks (.id "undefined") = [] := rfl

theorem undefined_text : (go .text (.id "undefined")).1 = [⟨.cls, "undefined"⟩] := rfl

theorem nil_attr : toks .nil = [] := rfl

theorem nil_text : (go .text .nil).1 = [⟨.cls, "null"⟩] := rfl

theorem id_lost (c : Ctx) (n : String) (h : n ≠ "undefined") : (go c (.id n)).1 = marker ("id " ++ n) [] := by
  have : (n == "undefined") = false := by simpa using h
  simp [go, hole, idToks, this]

theorem num_lost (c : Ctx) (src : String) : (go c (.num src)).1 = marker "number" [] := rfl

theorem member_lost (c : Ctx) (p : String) : (go c (.member p)).1 = marker "member" [] := rfl

theorem mod_class (c : Ctx) (m : String) : (go c (.mod m)).1 = [⟨.mod, "css#" ++ m⟩] := rfl

theorem modKey_lost (c : Ctx) (m : String) : (go c (.modKey m)).1 = marker ("module key " ++ m) [] := rfl

theorem and_drops (c : Ctx) (h : c.drops = true) (l l' r : E) : go c (.and l r) = go c (.and l' r) := by
  simp [go, h]

theorem and_str (c : Ctx) (s : String) (r : E) : (go c (.and (.str s) r)).1 = (go c r).1 := by
  simp [go, hole, isStr]

theorem and_test (c : Ctx) (h : c.drops = false) (l r : E) (hs : isStr l = false) (ht : isTest l = true) :
    (go c (.and l r)).1 = boolToks c false ++ (go c r).1 := by
  simp [go, hole, h, hs, ht]

theorem and_reported (c : Ctx) (h : c.drops = false) (l r : E) (hs : isStr l = false) (ht : isTest l = false) :
    (go c (.and l r)).1 = (go c l).1 ++ (go c r).1 := by
  simp [go, hole, h, hs, ht]

theorem and_test_attr (a b r : E) : toks (.and (.cmp a b) r) = toks r := rfl

theorem and_test_text (a b r : E) : (go .text (.and (.cmp a b) r)).1 = ⟨.cls, "false"⟩ :: (go .text r).1 := rfl

theorem arr_list (es : List E) : (go .list (.arr es)).1 = goList .list es := rfl

theorem obj_list (ps : List P) : (go .list (.obj ps)).1 = goProps ps := rfl

theorem arr_lost (c : Ctx) (h : c.flat = false) (es : List E) :
    (go c (.arr es)).1 = marker "array" (goList .elem es) := by
  simp [go, hole, h]

theorem obj_lost (c : Ctx) (h : c.flat = false) (ps : List P) : (go c (.obj ps)).1 = marker "object" (goProps ps) := by
  simp [go, hole, h]

theorem tmpl_words (qs : List String) (es : List E) : toks (.tmpl qs es) = words (goTmpl qs es) := rfl

theorem concat_words (a b : E) : toks (.concat a b) = words ((go .text a).2 ++ (go .text b).2) := rfl

theorem tmpl_ctx_irrelevant (c : Ctx) (qs : List String) (es : List E) : go c (.tmpl qs es) = go .attr (.tmpl qs es) :=
  rfl

theorem concat_ctx_irrelevant (c : Ctx) (a b : E) : go c (.concat a b) = go .attr (.concat a b) := rfl

theorem spread_lost (e : E) (ps : List P) : goProps (.spread e :: ps) = marker "spread" (go .list e).1 ++ goProps ps :=
  rfl

theorem call_list (n : String) (args : List E) (h : n ∈ listHelpers) : toks (.call n args) = goList .list args := by
  simp [toks, go, hole, calleeCtx, h]

theorem call_join (n : String) (args : List E) (h : n ∈ joinHelpers) (h' : n ∉ listHelpers) :
    toks (.call n args) = goList .join args := by
  simp [toks, go, hole, calleeCtx, h, h']

theorem call_other (n : String) (args : List E) (h : n ∉ listHelpers) (h' : n ∉ joinHelpers) :
    toks (.call n args) = marker ("call " ++ n) (goList .attr args) := by
  simp [toks, go, hole, calleeCtx, h, h']

theorem helpers_disjoint (n : String) (h : n ∈ joinHelpers) : n ∉ listHelpers := by
  simp [joinHelpers, listHelpers] at *; rcases h with rfl | rfl <;> decide

theorem list_helper_arr (n : String) (es : List E) (h : n ∈ listHelpers) :
    toks (.call n [.arr es]) = goList .list es := by
  rw [call_list n _ h]; simp [goList, arr_list]

theorem list_helper_obj (n : String) (ps : List P) (h : n ∈ listHelpers) : toks (.call n [.obj ps]) = goProps ps := by
  rw [call_list n _ h]; simp [goList, obj_list]

theorem join_helper_arr (n : String) (es : List E) (h : n ∈ joinHelpers) :
    toks (.call n [.arr es]) = marker "array" (goList .elem es) := by
  rw [call_join n _ h (helpers_disjoint n h)]; simp [goList, arr_lost .join rfl]

theorem join_helper_obj (n : String) (ps : List P) (h : n ∈ joinHelpers) :
    toks (.call n [.obj ps]) = marker "object" (goProps ps) := by
  rw [call_join n _ h (helpers_disjoint n h)]; simp [goList, obj_lost .join rfl]

theorem join_ok (es args : List E) (h : sepOk args = true) :
    toks (.method (.arr es) "join" args) = goList .elem es := by
  simp [toks, go, goElems, methodToks, hole, joinToks, h]

theorem join_glued (es args : List E) (h : sepOk args = false) :
    toks (.method (.arr es) "join" args) = marker "join separator" (goList .elem es) := by
  simp [toks, go, goElems, methodToks, hole, joinToks, h]

theorem join_names (es a b : List E) (ha : sepOk a = true) (hb : sepOk b = true) :
    toks (.method (.arr es) "join" a) = toks (.method (.arr es) "join" b) := by
  rw [join_ok es a ha, join_ok es b hb]

theorem filter_boolean (es args : List E) (h : sepOk args = true) :
    toks (.method (.method (.arr es) "filter" [.id "Boolean"]) "join" args) = goList .join es := by
  have hf : filterCtx [.id "Boolean"] = .join := rfl
  simp [toks, go, goElems, methodToks, hole, joinToks, h, hf]

theorem filter_other (es f args : List E) (hf : filterCtx f = .elem) (h : sepOk args = true) :
    toks (.method (.method (.arr es) "filter" f) "join" args) = goList .elem es := by
  simp [toks, go, goElems, methodToks, hole, joinToks, h, hf]

theorem method_other (recv : E) (n : String) (args : List E) (h : n ≠ "join") :
    toks (.method recv n args) = marker ("method " ++ n) (toks recv ++ goList .attr args) := by
  have : (n == "join") = false := by simpa using h
  simp [toks, go, hole, methodToks, this]

theorem join_unmodelled (recv : E) (args : List E) (h : goElems recv = none) :
    toks (.method recv "join" args) = marker "method join" (toks recv ++ goList .attr args) := by
  simp [toks, go, hole, methodToks, h]

theorem spread_arg (c : Ctx) (e : E) : (go c (.spread e)).1 = marker "spread" (go c e).1 := rfl

theorem other_lost (c : Ctx) (kids : List E) : (go c (.other kids)).1 = marker "other" (goList .attr kids) := rfl

theorem obj_spread_marker (ps : List P) (e : E) (h : P.spread e ∈ ps) : ⟨.lost, "spread"⟩ ∈ goProps ps := by
  induction ps with
  | nil => cases h
  | cons p ps ih =>
    rcases List.mem_cons.mp h with rfl | ht
    · exact List.mem_append_left _ (marker_mem _ _)
    · cases p <;> exact List.mem_append_right _ (ih ht)

theorem glued_reported (a b : Atom) (w : List Atom) :
    wordToks (a :: b :: w) = ⟨.glued, String.join ((a :: b :: w).map Atom.text)⟩ :: (a :: b :: w).flatMap Atom.toks := by
  rfl

theorem chars_kept (c : String) (w : List Atom) (h : Atom.chars c ∈ w) : ⟨.cls, c⟩ ∈ wordToks w := by
  match w, h with
  | [_], h =>
    rw [← List.mem_singleton.mp h]
    simp [wordToks, Atom.toks]
  | _ :: _ :: _, h =>
    rw [glued_reported]
    exact List.mem_cons_of_mem _ (List.mem_flatMap.mpr ⟨.chars c, h, List.mem_singleton_self _⟩)

theorem opens_open (ts : List Tok) (h : ∃ t ∈ ts, t.kind.opens = true) : ("setClass", "?") ∈ writes ts := by
  obtain ⟨t, ht, hk⟩ := h
  have : isOpen ts = true := List.any_eq_true.mpr ⟨t, ht, hk⟩
  simp [writes, this]

theorem lost_open (ts : List Tok) (h : ∃ t ∈ ts, t.kind = .lost) : ("setClass", "?") ∈ writes ts := by
  obtain ⟨t, ht, hk⟩ := h
  exact opens_open ts ⟨t, ht, by simp [hk, Kind.opens]⟩

theorem glued_open (ts : List Tok) (h : ∃ t ∈ ts, t.kind = .glued) : ("setClass", "?") ∈ writes ts := by
  obtain ⟨t, ht, hk⟩ := h
  exact opens_open ts ⟨t, ht, by simp [hk, Kind.opens]⟩

theorem marker_open (form : String) (ts : List Tok) (us : List Tok) : ("setClass", "?") ∈ writes (us ++ marker form ts) :=
  lost_open _ ⟨_, List.mem_append_right _ (marker_mem form ts), rfl⟩

theorem call_other_open (n : String) (args : List E) (h : n ∉ listHelpers) (h' : n ∉ joinHelpers) :
    ("setClass", "?") ∈ writes (toks (.call n args)) := by
  rw [call_other n args h h']; exact marker_open _ _ []

theorem method_other_open (recv : E) (n : String) (args : List E) (h : n ≠ "join") :
    ("setClass", "?") ∈ writes (toks (.method recv n args)) := by
  rw [method_other recv n args h]; exact marker_open _ _ []

theorem join_unmodelled_open (recv : E) (args : List E) (h : goElems recv = none) :
    ("setClass", "?") ∈ writes (toks (.method recv "join" args)) := by
  rw [join_unmodelled recv args h]; exact marker_open _ _ []

theorem join_glued_open (es args : List E) (h : sepOk args = false) :
    ("setClass", "?") ∈ writes (toks (.method (.arr es) "join" args)) := by
  rw [join_glued es args h]; exact marker_open _ _ []

theorem spread_open (e : E) : ("setClass", "?") ∈ writes (toks (.spread e)) := by
  rw [toks, spread_arg]; exact marker_open _ _ []

theorem obj_spread_open (n : String) (ps : List P) (e : E) (hn : n ∈ listHelpers) (h : P.spread e ∈ ps) :
    ("setClass", "?") ∈ writes (toks (.call n [.obj ps])) := by
  rw [list_helper_obj n ps hn]; exact lost_open _ ⟨_, obj_spread_marker ps e h, rfl⟩

theorem other_open (kids : List E) : ("setClass", "?") ∈ writes (toks (.other kids)) := by
  rw [toks, other_lost]; exact marker_open _ _ []

theorem id_open (n : String) (h : n ≠ "undefined") : ("setClass", "?") ∈ writes (toks (.id n)) := by
  rw [toks, id_lost .attr n h]; exact marker_open _ _ []

theorem num_open (src : String) : ("setClass", "?") ∈ writes (toks (.num src)) := by
  rw [toks, num_lost]; exact marker_open _ _ []

theorem member_open (p : String) : ("setClass", "?") ∈ writes (toks (.member p)) := by
  rw [toks, member_lost]; exact marker_open _ _ []

theorem modKey_open (m : String) : ("setClass", "?") ∈ writes (toks (.modKey m)) := by
  rw [toks, modKey_lost]; exact marker_open _ _ []

theorem arr_open (es : List E) : ("setClass", "?") ∈ writes (toks (.arr es)) := by
  rw [toks, arr_lost .attr rfl]; exact marker_open _ _ []

theorem obj_open (ps : List P) : ("setClass", "?") ∈ writes (toks (.obj ps)) := by
  rw [toks, obj_lost .attr rfl]; exact marker_open _ _ []

theorem join_helper_arr_open (n : String) (es : List E) (h : n ∈ joinHelpers) :
    ("setClass", "?") ∈ writes (toks (.call n [.arr es])) := by
  rw [join_helper_arr n es h]; exact marker_open _ _ []

theorem glued_word_open (a b : Atom) (w : List Atom) : ("setClass", "?") ∈ writes (wordToks (a :: b :: w)) := by
  rw [glued_reported]; exact glued_open _ ⟨_, List.mem_cons_self, rfl⟩

theorem assign_open (ts : List Tok) (h : isOpen ts = true) : assignWrites ts = [("setClass", "*")] := by
  simp [assignWrites, h]

theorem assign_closed (ts : List Tok) (h : isOpen ts = false) : assignWrites ts = writes ts := by
  simp [assignWrites, h]

theorem token_glued (w : String) (h : w.any (· == holeMark) = true) :
    tokenToks w = [⟨.glued, w.map fun c => if c == holeMark then '*' else c⟩] := by
  simp [tokenToks, h]

theorem token_invalid (w : String) (h : w.any (· == holeMark) = false) (hw : (w.isEmpty || w.any isSep) = true) :
    tokenToks w = marker "invalid token" [⟨.cls, w⟩] := by
  simp only [tokenToks, h, hw]; rfl

theorem token_class (w : String) (h : w.any (· == holeMark) = false) (hw : (w.isEmpty || w.any isSep) = false) :
    tokenToks w = [⟨.cls, w⟩] := by
  simp only [tokenToks, h, hw]; rfl

theorem value_str (vs : List String) : valueToks (.str vs) = vs.flatMap tokenToks := by simp [valueToks]

theorem value_mod (n : String) : valueToks (.mod n) = [⟨.mod, n⟩] := by simp [valueToks]

theorem value_modKey (m : String) : valueToks (.modKey m) = marker ("module key " ++ m) [] := by simp [valueToks]

theorem value_unknown : valueToks .unknown = marker "unresolved" [] := by simp [valueToks]

theorem alt_flat (vs : List V) : altToks vs = vs.flatMap valueToks := by
  induction vs with
  | nil => simp [altToks]
  | cons v vs ih => simp [altToks, ih]

theorem value_alt (vs : List V) : valueToks (.alt vs) = vs.flatMap valueToks := by
  simp [valueToks, alt_flat]

theorem alts_toks (v : V) : v.alts.flatMap valueToks = valueToks v := by
  cases v <;> simp [V.alts, value_alt]

theorem union_toks (a b : V) : valueToks (a.union b) = valueToks a ++ valueToks b := by
  rw [V.union, value_alt, List.flatMap_append, alts_toks, alts_toks]

theorem union_keeps_left (a b : V) (t : Tok) (h : t ∈ valueToks a) : t ∈ valueToks (a.union b) := by
  rw [union_toks]; exact List.mem_append_left _ h

theorem union_keeps_right (a b : V) (t : Tok) (h : t ∈ valueToks b) : t ∈ valueToks (a.union b) := by
  rw [union_toks]; exact List.mem_append_right _ h

theorem token_glued_open (w : String) (h : w.any (· == holeMark) = true) : ("setClass", "?") ∈ writes (tokenToks w) := by
  rw [token_glued w h]; exact glued_open _ ⟨_, List.mem_cons_self, rfl⟩

theorem token_invalid_open (w : String) (h : w.any (· == holeMark) = false) (hw : (w.isEmpty || w.any isSep) = true) :
    ("setClass", "?") ∈ writes (tokenToks w) := by
  rw [token_invalid w h hw]; exact marker_open _ _ []

theorem value_modKey_open (m : String) : ("setClass", "?") ∈ writes (valueToks (.modKey m)) := by
  rw [value_modKey]; exact marker_open _ _ []

theorem value_unknown_open : ("setClass", "?") ∈ writes (valueToks .unknown) := by
  rw [value_unknown]; exact marker_open _ _ []

theorem union_unknown_open (a : V) : ("setClass", "?") ∈ writes (valueToks (a.union .unknown)) := by
  rw [union_toks, value_unknown]; exact marker_open _ _ _

theorem toggle_first (a : V) (as : List V) : listToks "toggle" (a :: as) = valueToks a := by
  simp [listToks, tokenArgs]

theorem contains_first (a : V) (as : List V) : listToks "contains" (a :: as) = valueToks a := by
  simp [listToks, tokenArgs]

theorem add_all (m : String) (as : List V) (h : m ≠ "toggle" ∧ m ≠ "contains") :
    listToks m as = as.flatMap valueToks := by
  have h1 : (m == "toggle") = false := by simpa using h.1
  have h2 : (m == "contains") = false := by simpa using h.2
  simp [listToks, tokenArgs, h1, h2]

theorem contains_reads (ts : List Tok) : listWrites "contains" ts = (writes ts).map fun w => ("classRead", w.2) := rfl

theorem set_writes (m : String) (ts : List Tok) (h : m ≠ "contains") : listWrites m ts = writes ts := by
  have : (m == "contains") = false := by simpa using h
  simp [listWrites, this]

theorem match_strong (has : String → Bool) (sel : List String) (o : Bool) (h : sel.all has = true) :
    classMatch has sel o = .strong := by
  simp [classMatch, h]

theorem match_weak (has : String → Bool) (sel : List String) (h : sel.all has = false) :
    classMatch has sel true = .weak := by
  simp [classMatch, h]

theorem match_none (has : String → Bool) (sel : List String) (h : sel.all has = false) :
    classMatch has sel false = .none := by
  simp [classMatch, h]

theorem open_never_none (has : String → Bool) (sel : List String) : classMatch has sel true ≠ .none := by
  unfold classMatch; split <;> simp

theorem closed_never_weak (has : String → Bool) (sel : List String) : classMatch has sel false ≠ .weak := by
  unfold classMatch; split <;> simp

theorem weak_not_literal (spread lit : Bool) : strength spread lit .weak ≠ some .literal := by
  cases spread <;> simp [strength]

theorem none_no_strength (spread lit : Bool) : strength spread lit .none = none := rfl

theorem strong_literal (lit : Bool) (h : lit = true) : strength false lit .strong = some .literal := by
  simp [strength, h]

theorem strong_dynamic : strength false false .strong = some .dynamic := rfl

theorem spread_spread (lit : Bool) (m : Match) (h : m ≠ .none) : strength true lit m = some .spread := by
  cases m <;> simp_all [strength]

theorem pick_literal (cs : List (String × Strength)) (h : (cs.filter (·.2 == .literal)).isEmpty = false) :
    pick cs = ((cs.filter (·.2 == .literal)).map (·.1), false) := by
  simp [pick, h]

theorem pick_weak (cs : List (String × Strength)) (h : ∀ c ∈ cs, c.2 ≠ .literal) (hc : cs ≠ []) :
    (pick cs).2 = true := by
  have hl : cs.filter (·.2 == .literal) = [] := List.filter_eq_nil_iff.mpr (by simpa using h)
  unfold pick
  simp only [hl, List.isEmpty_nil, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  split
  · rfl
  · simpa using hc

theorem pick_open_weak (cs : List (String × Match)) (hw : ∀ c ∈ cs, c.2 = .weak) (spread lit : String → Bool)
    (hc : cs ≠ []) :
    (pick (cs.filterMap fun c => (strength (spread c.1) (lit c.1) c.2).map (c.1, ·))).2 = true := by
  apply pick_weak
  · intro d hd
    obtain ⟨c, hc, he⟩ := List.mem_filterMap.mp hd
    rw [hw c hc] at he
    cases hs : spread c.1 <;> simp [strength, hs] at he <;> rw [← he] <;> simp
  · obtain ⟨c, hcs⟩ := List.exists_mem_of_ne_nil cs hc
    intro hn
    have := List.filterMap_eq_nil_iff.mp hn c hcs
    rw [hw c hcs] at this
    cases hs : spread c.1 <;> simp [strength, hs] at this

private def s (x : String) : E := .str x
private def v (x : String) : E := .id x

def sweepInit : E := .cond (v "on") (.mod "sweep") (v "undefined")

def cases : List E :=
  [ s "a b",
    s "a\tb  c",
    v "x",
    .mod "row",
    .member "props.cls",
    .cmp (s "x") (s "y"),
    .not (s "x"),
    .cond (.cmp (v "role") (s "exit")) (s "on") (s "off"),
    .cond (v "x") (s "on") (v "y"),
    .and (v "open") (s "is-open"),
    .and (s "gate") (s "kept"),
    .and (.not (v "n")) (s "a"),
    .and (.num "0") (s "a"),
    .or (s "fallback") (v "x"),
    .or (v "x") (s "fallback"),
    .nullish (v "x") (s "dflt"),
    .nullish (s "first") (s "second"),
    .tmpl ["row ", " tail"] [.cond (v "f") (s "flip") (s "")],
    .tmpl ["a ", ""] [.cmp (v "r") (s "exit")],
    .tmpl ["is-", ""] [.cmp (v "a") (v "b")],
    .tmpl ["x ", ""] [.not (v "a")],
    .tmpl ["x ", ""] [.and (.cmp (v "a") (v "b")) (s "on")],
    .tmpl ["x ", ""] [.and (v "n") (s "a")],
    .tmpl ["x ", ""] [v "undefined"],
    .tmpl ["", ""] [.bool true],
    .tmpl ["", ""] [.nil],
    .tmpl ["", " ", ""] [.mod "a", .mod "b"],
    .tmpl ["btn-", ""] [v "size"],
    .tmpl ["", "", ""] [.mod "a", .mod "b"],
    .tmpl ["x", " y"] [.cond (v "c") (s "a") (s "b")],
    .concat (s "a ") (.cond (v "c") (s "on") (s "off")),
    .concat (s "btn-") (v "size"),
    .concat (s "a") (s "b"),
    .concat (s "a ") (.cmp (v "c") (v "d")),
    .concat (.concat (s "x ") (.tmpl ["y ", ""] [v "z"])) (s " w"),
    .arr [s "p", .and (v "q") (s "q-on"), .cmp (v "r") (s "no")],
    .call "clsx" [.obj [.key "a" (v "b"), .key "c d" (v "e"), .comp (.mod "f") (v "g"), .comp (v "k") (v "h")]],
    .call "clsx" [.obj [.spread (.cond (v "on") (.obj [.key "k" (v "t")]) (.obj [])), .key "a" (v "b")]],
    .call "cx" [.mod "row", .and (v "flip") (s "rowFlip"), .cond (.cmp (v "k") (s "no")) (s "yes") (s "")],
    .call "cls" [s "tab", .and (.cmp (v "id") (s "act")) (.mod "isActive")],
    .call "clsx" [s "a", .cmp (v "r") (s "exit")],
    .call "classNames" [s "a", .arr [s "b"]],
    .call "classnames" [s "a", .mod "b"],
    .call "cx" [.arr [s "a"]],
    .call "cls" [.obj [.key "a" (v "b")]],
    .call "clsx" [.arr [s "a"]],
    .call "cx" [.cmp (v "a") (v "b")],
    .call "cx" [.and (v "n") (.num "1")],
    .call "clsx" [.and (v "n") (s "a"), .bool true, .nil],
    .call "other" [s "ignored", .mod "m"],
    .method (.method (.arr [s "o", .and (v "a") (s "is-a"), .and (.cmp (v "b") (s "z")) (s "is-b")]) "filter"
      [v "Boolean"]) "join" [s " "],
    .method (.arr [s "a", .mod "b"]) "join" [s " "],
    .method (.method (.arr [s "a", s "b"]) "filter" [v "keep"]) "join" [s "  "],
    .method (.method (.arr [s "a", .and (v "k") (s "b")]) "filter" [v "keep"]) "join" [s " "],
    .method (.arr [s "a", .cmp (v "c") (v "d")]) "join" [s " "],
    .method (.arr [s "a", s "b"]) "join" [s "-"],
    .method (.arr [s "a"]) "join" [],
    .method (.arr [s "a"]) "join" [s ""],
    .method (.arr [s "a"]) "join" [v "sep"],
    .method (v "xs") "join" [s " "],
    .method (.method (v "xs") "filter" [v "Boolean"]) "join" [s " "],
    .method (s "a b") "trim" [],
    .call "getClass" [v "variant"],
    .method (v "cls") "trim" [],
    .method (.method (v "items") "map" [v "f"]) "join" [s " "],
    .call "clsx" [.spread (v "xs")],
    .call "clsx" [s "a", .obj [.spread (v "extra")]],
    .method (.arr [v "a", v "b"]) "join" [s "-"],
    .other [s "x", .mod "y"],
    .other [v "x"],
    .arr [s "a", s "b"],
    .obj [.key "a" (v "b")],
    .cond (v "c") (.arr [s "a"]) (s "b"),
    .call "cx" [.cond (v "c") (.arr [s "a"]) (s "b")],
    .call "clsx" [.arr [s "a", .arr [s "b"], .obj [.key "c" (v "d")]]],
    .tmpl ["x ", ""] [.arr [s "a"]],
    .method (.arr [s "a", .arr [s "b"], .obj []]) "join" [s " "],
    s "a b c",
    s "a　b\x0Bc d",
    v "undefined",
    .nil,
    .bool false,
    .num "0",
    .num "a - 1",
    .num "-1",
    .cond (.cmp (v "t") (v "id")) (.mod "isActive") (v "undefined"),
    .tmpl ["", " ", " ", ""] [.mod "svg", .mod "idleFrame", .member "frameCls[k]"],
    .cond (v "className") (.tmpl ["", " ", ""] [.mod "card", v "className"]) (.mod "card"),
    .call "cx" [.mod "dot", .modKey "css"],
    .tmpl ["", " ", ""] [.mod "underlineFrame", .modKey "css"],
    .const "sweep" sweepInit,
    .call "cx" [.mod "word", .const "sweep" sweepInit],
    .const "pair" (s "a b"),
    .tmpl ["", " x"] [.const "k" (.const "j" (.mod "m"))],
    .const "z" (v "p"),
    .const "box" (.cond (.cmp (v "b") (s "none")) (s "") (.tmpl ["", " "] [.mod "boxClip"])),
    .and (.cmp (v "r") (s "exit")) (.cond (v "z") (s "deep") (.and (v "w") (s "deeper")))]

def listCases : List (String × List V) :=
  [ ("add", [.str ["a"]]),
    ("add", [.str ["a b"]]),
    ("add", [.str [""]]),
    ("add", [.str ["a b"]]),
    ("toggle", [.str ["is-on"], .unknown]),
    ("toggle", [.str ["a", "b"]]),
    ("toggle", [.str ["is-\x01"]]),
    ("toggle", [.mod "m.css#on"]),
    ("toggle", [.modKey "m.css"]),
    ("remove", [.unknown]),
    ("replace", [.str ["a"], .str ["b"]]),
    ("contains", [.str ["a"], .str ["b"]]),
    ("contains", [.unknown]),
    ("add", [V.union (.mod "m.css#a") (.mod "m.css#b")]),
    ("toggle", [V.union (.mod "m.css#a") .unknown, .unknown]),
    ("add", [V.union (V.union (.str ["x"]) (.mod "m.css#a")) (.modKey "m.css")])]

def unionCases : List (V × V) :=
  [ (.mod "m.css#a", .mod "m.css#b"),
    (.str ["x", "y"], .mod "m.css#a"),
    (.mod "m.css#a", .unknown),
    (.alt [.mod "m.css#a", .str ["x"]], .modKey "m.css"),
    (.unknown, .alt [.mod "m.css#a", .mod "m.css#b"])]

def matchCases : List (List String × List String × Bool) :=
  [ (["a"], ["a", "b"], false),
    (["a", "b"], ["a"], false),
    (["a", "b"], ["a"], true),
    (["c"], [], true),
    (["c"], [], false),
    ([], [], false)]

def strengthCases : List (Bool × Bool × Match) :=
  [ (false, true, .strong), (false, false, .strong), (true, true, .strong), (false, true, .weak), (true, true, .weak),
    (false, true, .none)]

def pickCases : List (List (String × Strength)) :=
  [ [("a", .literal), ("b", .dynamic), ("c", .spread)],
    [("b", .dynamic), ("c", .spread)],
    [("c", .spread)],
    [],
    [("a", .literal), ("a2", .literal)]]

def isIdent (k : String) : Bool :=
  match k.toList with
  | c :: cs => (c.isAlpha || c == '_' || c == '$') && cs.all fun d => d.isAlphanum || d == '_' || d == '$'
  | [] => false

mutual
def render : E → String
  | .str s => "'" ++ s ++ "'"
  | .num src => src
  | .bool b => toString b
  | .nil => "null"
  | .id n => n
  | .const n _ => n
  | .member p => p
  | .mod l => "css." ++ l
  | .modKey m => m ++ "[k]"
  | .cmp a b => "(" ++ render a ++ " === " ++ render b ++ ")"
  | .not a => "!" ++ render a
  | .cond t c a => "(" ++ render t ++ " ? " ++ render c ++ " : " ++ render a ++ ")"
  | .and l r => "(" ++ render l ++ " && " ++ render r ++ ")"
  | .or l r => "(" ++ render l ++ " || " ++ render r ++ ")"
  | .nullish l r => "(" ++ render l ++ " ?? " ++ render r ++ ")"
  | .tmpl qs es => "`" ++ renderTmpl qs es ++ "`"
  | .concat l r => "(" ++ render l ++ " + " ++ render r ++ ")"
  | .arr es => "[" ++ ", ".intercalate (renderList es) ++ "]"
  | .obj ps => "{" ++ ", ".intercalate (renderProps ps) ++ "}"
  | .call n args => n ++ "(" ++ ", ".intercalate (renderList args) ++ ")"
  | .method r n args => render r ++ "." ++ n ++ "(" ++ ", ".intercalate (renderList args) ++ ")"
  | .spread e => "..." ++ render e
  | .other kids => "(" ++ ", ".intercalate ("null" :: renderList kids) ++ ")"

def renderList : List E → List String
  | [] => []
  | e :: es => render e :: renderList es

def renderProps : List P → List String
  | [] => []
  | .key k v :: ps => ((if isIdent k then k else "'" ++ k ++ "'") ++ ": " ++ render v) :: renderProps ps
  | .comp k v :: ps => ("[" ++ render k ++ "]: " ++ render v) :: renderProps ps
  | .spread e :: ps => ("..." ++ render e) :: renderProps ps

def renderTmpl (qs : List String) : List E → String
  | [] => String.join qs
  | e :: es => qs.headD "" ++ "${" ++ render e ++ "}" ++ renderTmpl qs.tail es
end

mutual
def constsOf : E → List (String × String)
  | .const n i => (n, render i) :: constsOf i
  | .cmp a b | .and a b | .or a b | .nullish a b | .concat a b => constsOf a ++ constsOf b
  | .not a | .spread a => constsOf a
  | .cond t a b => constsOf t ++ constsOf a ++ constsOf b
  | .tmpl _ es | .arr es | .call _ es | .other es => constsList es
  | .obj ps => constsProps ps
  | .method r _ args => constsOf r ++ constsList args
  | .str _ | .num _ | .bool _ | .nil | .id _ | .member _ | .mod _ | .modKey _ => []

def constsList : List E → List (String × String)
  | [] => []
  | e :: es => constsOf e ++ constsList es

def constsProps : List P → List (String × String)
  | [] => []
  | .key _ v :: ps => constsOf v ++ constsProps ps
  | .comp k v :: ps => constsOf k ++ constsOf v ++ constsProps ps
  | .spread e :: ps => constsOf e ++ constsProps ps
end

def namesOf (k : Kind) (ts : List Tok) : List String := ts.filterMap fun t => if t.kind == k then some t.name else none

def strs (xs : List String) : Lean.Json := Lean.Json.arr (xs.map Lean.Json.str).toArray

def pairs (ws : List (String × String)) : Lean.Json := Lean.Json.arr (ws.map fun (a, b) => strs [a, b]).toArray

def row (e : E) : Lean.Json :=
  let ts := toks e
  Lean.Json.mkObj [("src", render e), ("consts", pairs (constsOf e)), ("classes", strs (namesOf .cls ts)),
    ("modules", strs (namesOf .mod ts)), ("open", isOpen ts), ("findings", pairs (findings ts)),
    ("writes", pairs (writes ts)), ("assign", pairs (assignWrites (assignToks e)))]

def V.json : V → Lean.Json
  | .str vs => Lean.Json.mkObj [("str", strs vs)]
  | .mod n => Lean.Json.mkObj [("mod", n)]
  | .modKey m => Lean.Json.mkObj [("modKey", m)]
  | .unknown => Lean.Json.mkObj [("unknown", true)]
  | .alt vs => Lean.Json.mkObj [("alt", Lean.Json.arr (vs.attach.map fun ⟨x, _⟩ => x.json).toArray)]

def listRow (c : String × List V) : Lean.Json :=
  let ts := listToks c.1 c.2
  Lean.Json.mkObj [("method", c.1), ("args", Lean.Json.arr (c.2.map V.json).toArray),
    ("findings", pairs (findings ts)), ("writes", pairs (listWrites c.1 ts))]

def unionRow (c : V × V) : Lean.Json :=
  Lean.Json.mkObj [("union", Lean.Json.arr #[c.1.json, c.2.json]), ("value", (c.1.union c.2).json)]

def Match.name : Match → String
  | .none => "none"
  | .weak => "weak"
  | .strong => "strong"

def Strength.name : Strength → String
  | .literal => "literal"
  | .dynamic => "dynamic"
  | .spread => "spread"

def matchRow (c : List String × List String × Bool) : Lean.Json :=
  Lean.Json.mkObj [("sel", strs c.1), ("classes", strs c.2.1), ("open", c.2.2),
    ("match", (classMatch c.2.1.contains c.1 c.2.2).name)]

def strengthRow (c : Bool × Bool × Match) : Lean.Json :=
  Lean.Json.mkObj [("spread", c.1), ("literalAttrs", c.2.1), ("classMatch", c.2.2.name),
    ("strength", match strength c.1 c.2.1 c.2.2 with | some k => Lean.Json.str k.name | none => Lean.Json.null)]

def pickRow (cs : List (String × Strength)) : Lean.Json :=
  let r := pick cs
  Lean.Json.mkObj [("candidates", Lean.Json.arr (cs.map fun (o, k) => strs [o, k.name]).toArray),
    ("owners", strs r.1), ("weak", r.2)]

def head : Lean.Json :=
  Lean.Json.mkObj [("listHelpers", strs listHelpers), ("joinHelpers", strs joinHelpers),
    ("separators", strs ([' ', '\t', '\n', Char.ofNat 12, '\r'].map toString)), ("listMethods", strs listMethods)]

def goldenRows (_ : Unit := ()) : List Lean.Json :=
  head :: cases.map row ++ listCases.map listRow ++ unionCases.map unionRow ++ matchCases.map matchRow ++
    strengthCases.map strengthRow ++ pickCases.map pickRow

def goldenText (_ : Unit := ()) : String := String.join ((goldenRows ()).map fun j => j.compress ++ "\n")

#guard toks (s "a b") == [⟨.cls, "a"⟩, ⟨.cls, "b"⟩]
#guard toks (.tmpl ["row ", " tail"] [.cond (v "f") (s "flip") (s "")]) == [⟨.cls, "row"⟩, ⟨.cls, "flip"⟩, ⟨.cls, "tail"⟩]
#guard toks (.concat (s "btn-") (v "size")) == [⟨.glued, "btn-*"⟩, ⟨.cls, "btn-"⟩, ⟨.lost, "id size"⟩]
#guard toks (.tmpl ["", "pill"] [v "box"]) == [⟨.glued, "*pill"⟩, ⟨.lost, "id box"⟩, ⟨.cls, "pill"⟩]
#guard toks (.concat (s "a") (s "b")) == [⟨.cls, "ab"⟩]
#guard toks (.tmpl ["", "", ""] [.mod "a", .mod "b"]) == [⟨.glued, "**"⟩, ⟨.mod, "css#a"⟩, ⟨.mod, "css#b"⟩]
#guard toks (.call "clsx" [.obj [.key "a" (v "b"), .comp (.mod "f") (v "g")]]) == [⟨.cls, "a"⟩, ⟨.mod, "css#f"⟩]
#guard toks (.call "other" [s "x"]) == [⟨.lost, "call other"⟩, ⟨.lost, "x"⟩]
#guard toks (.call "getClass" [v "variant"]) == [⟨.lost, "call getClass"⟩, ⟨.lost, "id variant"⟩]
#guard toks (.method (v "c") "trim" []) == [⟨.lost, "method trim"⟩, ⟨.lost, "id c"⟩]
#guard names (toks (.method (.method (v "xs") "map" [v "f"]) "join" [s " "])) ==
  ["method join", "method map", "id xs", "id f"]
#guard toks (.call "clsx" [.spread (v "xs")]) == [⟨.lost, "spread"⟩, ⟨.lost, "id xs"⟩]
#guard toks (.arr [s "a"]) == [⟨.lost, "array"⟩, ⟨.lost, "a"⟩]
#guard toks (.call "clsx" [.arr [s "a"]]) == [⟨.cls, "a"⟩]
#guard toks (.call "cx" [.arr [s "a"]]) == [⟨.lost, "array"⟩, ⟨.lost, "a"⟩]
#guard toks (.obj [.key "a" (v "b")]) == [⟨.lost, "object"⟩, ⟨.lost, "a"⟩]
#guard toks (.call "classnames" [.obj [.key "a" (v "b")]]) == [⟨.cls, "a"⟩]
#guard toks (.call "cls" [.obj [.key "a" (v "b")]]) == [⟨.lost, "object"⟩, ⟨.lost, "a"⟩]
#guard names (toks (.method (.arr [s "a", .arr [s "b"]]) "join" [s " "])) == ["a", "array", "b"]
#guard toks (v "undefined") == [] && toks (v "cls") == [⟨.lost, "id cls"⟩]
#guard toks (.member "frameCls[k]") == [⟨.lost, "member"⟩]
#guard toks (.modKey "v") == [⟨.lost, "module key v"⟩]
#guard tokens "a b c" == ["a b", "c"] && tokens "a\x0Bb" == ["a\x0Bb"]
#guard toks (.const "c" (s "a b")) == [⟨.cls, "a"⟩, ⟨.cls, "b"⟩]
#guard toks (.call "cx" [.mod "word", .const "sweep" sweepInit]) == [⟨.mod, "css#word"⟩, ⟨.mod, "css#sweep"⟩]
#guard toks (.const "z" (v "p")) == [⟨.lost, "id p"⟩]
#guard toks (.tmpl ["is-", ""] [.cmp (v "a") (v "b")]) ==
  [⟨.glued, "is-*"⟩, ⟨.cls, "is-"⟩, ⟨.cls, "true"⟩, ⟨.cls, "false"⟩]
#guard toks (.tmpl ["x ", ""] [.and (.cmp (v "a") (v "b")) (s "on")]) == [⟨.cls, "x"⟩, ⟨.cls, "false"⟩, ⟨.cls, "on"⟩]
#guard toks (.tmpl ["x ", ""] [v "undefined"]) == [⟨.cls, "x"⟩, ⟨.cls, "undefined"⟩]
#guard toks (.tmpl ["", ""] [.nil]) == [⟨.cls, "null"⟩] && toks .nil == [] && toks (.bool true) == []
#guard toks (.cmp (v "a") (v "b")) == [] && toks (.call "cx" [.cmp (v "a") (v "b")]) == [⟨.cls, "true"⟩]
#guard toks (.call "clsx" [.cmp (v "a") (v "b"), .bool true, .bool false, .nil]) == []
#guard toks (.num "0") == [⟨.lost, "number"⟩]
#guard toks (.call "cx" [.and (v "n") (.num "1")]) == [⟨.lost, "number"⟩]
#guard toks (.and (v "n") (s "a")) == [⟨.lost, "id n"⟩, ⟨.cls, "a"⟩]
#guard toks (.and (.not (v "n")) (s "a")) == [⟨.cls, "a"⟩] && toks (.and (s "g") (s "a")) == [⟨.cls, "a"⟩]
#guard toks (.and (.num "0") (s "a")) == [⟨.lost, "number"⟩, ⟨.cls, "a"⟩]
#guard toks (.call "cls" [.and (v "n") (s "a")]) == [⟨.cls, "a"⟩]
#guard toks (.method (.method (.arr [.and (v "n") (s "a")]) "filter" [v "Boolean"]) "join" [s " "]) == [⟨.cls, "a"⟩]
#guard toks (.method (.method (.arr [.and (v "n") (s "a")]) "filter" [v "keep"]) "join" [s " "]) ==
  [⟨.lost, "id n"⟩, ⟨.cls, "a"⟩]
#guard toks (.method (.arr [.cmp (v "a") (v "b")]) "join" [s " "]) == [⟨.cls, "true"⟩, ⟨.cls, "false"⟩]
#guard toks (.method (.arr [v "undefined"]) "join" [s " "]) == []
#guard (cases.map toks).getLast? == some [⟨.cls, "deep"⟩, ⟨.lost, "id w"⟩, ⟨.cls, "deeper"⟩]
#guard boolToks .join false == [] && boolToks .attr true == [] && boolToks .list true == [] &&
  boolToks .elem false == [⟨.cls, "false"⟩]
#guard nullToks .text "null" == [⟨.cls, "null"⟩] && nullToks .elem "null" == [] && nullToks .attr "undefined" == []
#guard calleeCtx "clsx" == some .list && calleeCtx "cx" == some .join && calleeCtx "cls" == some .join &&
  calleeCtx "x" == none
#guard isTest (.cmp (v "a") (v "b")) && isTest (.not (v "a")) && isTest (.bool false) && !isTest (v "a") &&
  !isTest (.num "0")
#guard Ctx.drops .list && Ctx.drops .join && !Ctx.drops .attr && !Ctx.drops .text && !Ctx.drops .elem
#guard filterCtx [v "Boolean"] == .join && filterCtx [v "keep"] == .elem && filterCtx [] == .elem
#guard Ctx.flat .list && !Ctx.flat .join && !Ctx.flat .attr
#guard assignWrites (assignToks (s "a b")) == [("setClass", "a"), ("setClass", "b")]
#guard assignWrites (assignToks (v "x")) == [("setClass", "*")]
#guard assignWrites (assignToks (.tmpl ["", " ", ""] [.mod "accent", .call "stateClass" [v "s"]])) ==
  [("setClass", "*")]
#guard assignWrites (assignToks (.const "c" (.mod "m"))) == [("setModuleClass", "css#m")]
#guard assignWrites (assignToks (v "undefined")) == [("setClass", "undefined")]
#guard listToks "add" [.str ["a b"]] == [⟨.lost, "invalid token"⟩, ⟨.lost, "a b"⟩]
#guard listToks "toggle" [.str ["is-\x01"], .unknown] == [⟨.glued, "is-*"⟩]
#guard listToks "replace" [.str ["a"], .mod "m#b"] == [⟨.cls, "a"⟩, ⟨.mod, "m#b"⟩]
#guard listWrites "contains" (listToks "contains" [.unknown]) == [("classRead", "?")]
#guard listWrites "add" (listToks "add" [.modKey "m"]) == [("setClass", "?")]
#guard listToks "add" [V.union (.mod "a") (.mod "b")] == [⟨.mod, "a"⟩, ⟨.mod, "b"⟩]
#guard listWrites "add" (listToks "add" [V.union (.mod "a") .unknown]) == [("setModuleClass", "a"), ("setClass", "?")]
#guard (V.union (.alt [.mod "a", .mod "b"]) (.mod "c")).alts.length == 3
#guard toks (.method (.arr [s "a", s "b"]) "join" [s "-"]) == [⟨.lost, "join separator"⟩, ⟨.lost, "a"⟩, ⟨.lost, "b"⟩]
#guard toks (.method (.arr [s "a"]) "join" [s "\t"]) == [⟨.cls, "a"⟩]
#guard sepOk [s " "] && sepOk [s " \t"] && !sepOk [s ""] && !sepOk [s "-"] && !sepOk [] && !sepOk [v "x"]
#guard !sepOk [s " ", s " "]
#guard writes [⟨.cls, "a"⟩, ⟨.mod, "m"⟩] == [("setClass", "a"), ("setModuleClass", "m")]
#guard writes [⟨.lost, "a"⟩, ⟨.cls, "b"⟩, ⟨.lost, "c"⟩] == [("setClass", "b"), ("setClass", "?")]
#guard writes [⟨.glued, "a*"⟩, ⟨.cls, "a"⟩] == [("setClass", "a"), ("setClass", "?")]
#guard findings [⟨.lost, "a"⟩, ⟨.cls, "b"⟩, ⟨.glued, "c*"⟩, ⟨.mod, "m"⟩] == [("unmodelled-class", "a"), ("glued-class", "c*")]
#guard isOpen [⟨.cls, "a"⟩, ⟨.glued, "b*"⟩] && !isOpen [⟨.cls, "a"⟩, ⟨.mod, "m"⟩] && !isOpen []
#guard tokens "a\x0Cb\r\nc" == ["a", "b", "c"] && tokens "a\u00A0b" == ["a\u00A0b"]
#guard isIdent "a" && isIdent "_b$1" && !isIdent "c d" && !isIdent "1a" && !isIdent ""
#guard classMatch ["a", "b"].contains ["a"] false == .strong && classMatch ["a"].contains ["a", "b"] true == .weak &&
  classMatch ["a"].contains ["a", "b"] false == .none && classMatch [].contains [] false == .strong
#guard strength false true .strong == some .literal && strength false false .strong == some .dynamic &&
  strength true true .strong == some .spread && strength false true .weak == some .dynamic &&
  strength true false .weak == some .spread && strength false true .none == none
#guard pick [("a", .literal), ("b", .dynamic)] == (["a"], false) && pick [("b", .dynamic), ("c", .spread)] == (["b"], true)
#guard pick [("c", .spread)] == (["c"], true) && pick [] == ([], false)
#guard constsOf (.tmpl ["", ""] [.const "k" (.const "j" (.mod "m"))]) == [("k", "j"), ("j", "css.m")]

/-- Print the golden, or with `--check <file>` compare it byte for byte (exit 1 on a difference). -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readFile path
    if cur == goldenText () then
      IO.eprintln s!"footprint classpos golden: {path} is up to date ({(goldenRows ()).length} lines)"
      return 0
    IO.eprintln s!"footprint classpos golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.ClassPos
