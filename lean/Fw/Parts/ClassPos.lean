import Lean.Data.Json

/-! Class positions of a className expression and of a classList call: the tokens they record as classes and the ones
they report as unmodelled. part-footprint.mjs mirrors `go` and `listToks` branch for branch and replays the golden. -/
namespace Fw.Parts.ClassPos

mutual
inductive E where
  | str (s : String)
  | id (n : String)
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

def helpers : List String := ["cx", "cls", "clsx", "classNames", "classnames"]

def sepOk : List E → Bool
  | [.str s] => !s.isEmpty && s.all isSep
  | _ => false

def joinToks (ts : List Tok) (args : List E) : List Tok := if sepOk args then ts else marker "join separator" ts

def methodToks (n : String) (elems : Option (List Tok)) (recv argToks : List Tok) (args : List E) : List Tok :=
  match n == "join", elems with
  | true, some ts => joinToks ts args
  | _, _ => marker ("method " ++ n) (recv ++ argToks)

def hole (ts : List Tok) : List Tok × List Piece := (ts, [.hole ts])

def idToks (n : String) : List Tok := if n == "undefined" then [] else marker ("id " ++ n) []

def listOr (l : Bool) (form : String) (ts : List Tok) : List Tok := if l then ts else marker form ts

mutual
def go (l : Bool) : E → List Tok × List Piece
  | .str s => ((tokens s).map (Tok.mk .cls), [.text s])
  | .id n => hole (idToks n)
  | .member _ => hole (marker "member" [])
  | .mod m => hole [⟨.mod, "css#" ++ m⟩]
  | .modKey m => hole (marker ("module key " ++ m) [])
  | .cmp _ _ => hole []
  | .not _ => hole []
  | .cond _ c a => hole ((go l c).1 ++ (go l a).1)
  | .and _ r => hole (go l r).1
  | .or a b => hole ((go l a).1 ++ (go l b).1)
  | .nullish a b => hole ((go l a).1 ++ (go l b).1)
  | .tmpl qs es => let ps := goTmpl qs es; (words ps, ps)
  | .concat a b => let ps := (go false a).2 ++ (go false b).2; (words ps, ps)
  | .arr es => hole (listOr l "array" (goList l es))
  | .obj ps => hole (listOr l "object" (goProps ps))
  | .call n args => hole (if helpers.contains n then goList true args else marker ("call " ++ n) (goList false args))
  | .method recv n args => hole (methodToks n (goElems recv) (go false recv).1 (goList false args) args)
  | .spread e => hole (marker "spread" (go l e).1)
  | .other kids => hole (marker "other" (goList false kids))

def goElems : E → Option (List Tok)
  | .arr es => some (goList false es)
  | .method (.arr es) "filter" _ => some (goList false es)
  | _ => none

def goList (l : Bool) : List E → List Tok
  | [] => []
  | e :: es => (go l e).1 ++ goList l es

def goProps : List P → List Tok
  | [] => []
  | .key k _ :: ps => (tokens k).map (Tok.mk .cls) ++ goProps ps
  | .comp k _ :: ps => (go false k).1 ++ goProps ps
  | .spread e :: ps => marker "spread" (go true e).1 ++ goProps ps

def goTmpl (qs : List String) : List E → List Piece
  | [] => qs.map .text
  | e :: es => .text (qs.headD "") :: (go false e).2 ++ goTmpl qs.tail es
end

def toks (e : E) : List Tok := (go false e).1

def Kind.opens : Kind → Bool
  | .lost | .glued => true
  | .cls | .mod => false

def writes (ts : List Tok) : List (String × String) :=
  ts.filterMap (fun t => match t.kind with
    | .cls => some ("setClass", t.name)
    | .mod => some ("setModuleClass", t.name)
    | .lost | .glued => none) ++
  (if ts.any (·.kind.opens) then [("setClass", "?")] else [])

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

def holeMark : Char := Char.ofNat 1

def tokenToks (w : String) : List Tok :=
  if w.any (· == holeMark) then [⟨.glued, w.map fun c => if c == holeMark then '*' else c⟩]
  else if w.isEmpty || w.any isSep then marker "invalid token" [⟨.cls, w⟩]
  else [⟨.cls, w⟩]

def valueToks : V → List Tok
  | .str vs => vs.flatMap tokenToks
  | .mod n => [⟨.mod, n⟩]
  | .modKey m => marker ("module key " ++ m) []
  | .unknown => marker "unresolved" []

def listMethods : List String := ["add", "remove", "toggle", "replace", "contains"]

def tokenArgs (m : String) (args : List V) : List V := if m == "toggle" || m == "contains" then args.take 1 else args

def listToks (m : String) (args : List V) : List Tok := (tokenArgs m args).flatMap valueToks

def listWrites (m : String) (ts : List Tok) : List (String × String) :=
  if m == "contains" then (writes ts).map fun w => ("classRead", w.2) else writes ts

def names (ts : List Tok) : List String := ts.map (·.name)

theorem lose_names (ts : List Tok) : names (ts.map Tok.lose) = names ts := by
  simp [names, Tok.lose]

theorem lose_all_lost (ts : List Tok) : ∀ t ∈ ts.map Tok.lose, t.kind = .lost := by
  simp [Tok.lose]

theorem str_tokens (s : String) : toks (.str s) = (tokens s).map (Tok.mk .cls) := rfl

theorem cond_test_irrelevant (t t' c a : E) : toks (.cond t c a) = toks (.cond t' c a) := rfl

theorem and_left_irrelevant (a a' r : E) : toks (.and a r) = toks (.and a' r) := rfl

theorem cmp_empty (a b : E) : toks (.cmp a b) = [] := rfl

theorem not_empty (a : E) : toks (.not a) = [] := rfl

theorem undefined_empty : toks (.id "undefined") = [] := rfl

theorem id_lost (n : String) (h : n ≠ "undefined") : toks (.id n) = marker ("id " ++ n) [] := by
  have : (n == "undefined") = false := by simpa using h
  simp [toks, go, hole, idToks, this]

theorem member_lost (p : String) : toks (.member p) = marker "member" [] := rfl

theorem mod_class (m : String) : toks (.mod m) = [⟨.mod, "css#" ++ m⟩] := rfl

theorem modKey_lost (m : String) : toks (.modKey m) = marker ("module key " ++ m) [] := rfl

theorem or_both (a b : E) : toks (.or a b) = toks a ++ toks b := rfl

theorem nullish_both (a b : E) : toks (.nullish a b) = toks a ++ toks b := rfl

theorem cond_branches (t c a : E) : toks (.cond t c a) = toks c ++ toks a := rfl

theorem arr_list (es : List E) : (go true (.arr es)).1 = goList true es := rfl

theorem arr_lost (es : List E) : toks (.arr es) = marker "array" (goList false es) := rfl

theorem obj_list (ps : List P) : (go true (.obj ps)).1 = goProps ps := rfl

theorem obj_lost (ps : List P) : toks (.obj ps) = marker "object" (goProps ps) := rfl

theorem tmpl_words (qs : List String) (es : List E) : toks (.tmpl qs es) = words (goTmpl qs es) := rfl

theorem concat_words (a b : E) : toks (.concat a b) = words ((go false a).2 ++ (go false b).2) := rfl

theorem tmpl_list_irrelevant (l : Bool) (qs : List String) (es : List E) : go l (.tmpl qs es) = go false (.tmpl qs es) :=
  rfl

theorem spread_lost (e : E) (ps : List P) : goProps (.spread e :: ps) = marker "spread" (go true e).1 ++ goProps ps :=
  rfl

theorem call_helper (n : String) (args : List E) (h : n ∈ helpers) : toks (.call n args) = goList true args := by
  simp [toks, go, hole, h]

theorem call_other (n : String) (args : List E) (h : n ∉ helpers) :
    toks (.call n args) = marker ("call " ++ n) (goList false args) := by
  simp [toks, go, hole, h]

theorem helper_arr (n : String) (es : List E) (h : n ∈ helpers) : toks (.call n [.arr es]) = goList true es := by
  rw [call_helper n _ h]; simp [goList, arr_list]

theorem helper_obj (n : String) (ps : List P) (h : n ∈ helpers) : toks (.call n [.obj ps]) = goProps ps := by
  rw [call_helper n _ h]; simp [goList, obj_list]

theorem join_ok (es args : List E) (h : sepOk args = true) :
    toks (.method (.arr es) "join" args) = goList false es := by
  simp [toks, go, goElems, methodToks, hole, joinToks, h]

theorem join_glued (es args : List E) (h : sepOk args = false) :
    toks (.method (.arr es) "join" args) = marker "join separator" (goList false es) := by
  simp [toks, go, goElems, methodToks, hole, joinToks, h]

theorem join_names (es a b : List E) (ha : sepOk a = true) (hb : sepOk b = true) :
    toks (.method (.arr es) "join" a) = toks (.method (.arr es) "join" b) := by
  rw [join_ok es a ha, join_ok es b hb]

theorem filter_irrelevant (es f args : List E) :
    toks (.method (.method (.arr es) "filter" f) "join" args) = toks (.method (.arr es) "join" args) := by
  simp [toks, go, goElems, hole, methodToks]

theorem method_other (recv : E) (n : String) (args : List E) (h : n ≠ "join") :
    toks (.method recv n args) = marker ("method " ++ n) (toks recv ++ goList false args) := by
  have : (n == "join") = false := by simpa using h
  simp [toks, go, hole, methodToks, this]

theorem join_unmodelled (recv : E) (args : List E) (h : goElems recv = none) :
    toks (.method recv "join" args) = marker "method join" (toks recv ++ goList false args) := by
  simp [toks, go, hole, methodToks, h]

theorem spread_arg (e : E) : toks (.spread e) = marker "spread" (toks e) := rfl

theorem other_lost (kids : List E) : toks (.other kids) = marker "other" (goList false kids) := rfl

theorem marker_mem (form : String) (ts : List Tok) : ⟨.lost, form⟩ ∈ marker form ts := List.mem_cons_self

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
  have : ts.any (·.kind.opens) = true := List.any_eq_true.mpr ⟨t, ht, hk⟩
  simp [writes, this]

theorem lost_open (ts : List Tok) (h : ∃ t ∈ ts, t.kind = .lost) : ("setClass", "?") ∈ writes ts := by
  obtain ⟨t, ht, hk⟩ := h
  exact opens_open ts ⟨t, ht, by simp [hk, Kind.opens]⟩

theorem glued_open (ts : List Tok) (h : ∃ t ∈ ts, t.kind = .glued) : ("setClass", "?") ∈ writes ts := by
  obtain ⟨t, ht, hk⟩ := h
  exact opens_open ts ⟨t, ht, by simp [hk, Kind.opens]⟩

theorem marker_open (form : String) (ts : List Tok) (us : List Tok) : ("setClass", "?") ∈ writes (us ++ marker form ts) :=
  lost_open _ ⟨_, List.mem_append_right _ (marker_mem form ts), rfl⟩

theorem call_other_open (n : String) (args : List E) (h : n ∉ helpers) : ("setClass", "?") ∈ writes (toks (.call n args)) := by
  rw [call_other n args h]; exact marker_open _ _ []

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
  rw [spread_arg]; exact marker_open _ _ []

theorem obj_spread_open (n : String) (ps : List P) (e : E) (hn : n ∈ helpers) (h : P.spread e ∈ ps) :
    ("setClass", "?") ∈ writes (toks (.call n [.obj ps])) := by
  rw [helper_obj n ps hn]; exact lost_open _ ⟨_, obj_spread_marker ps e h, rfl⟩

theorem other_open (kids : List E) : ("setClass", "?") ∈ writes (toks (.other kids)) := by
  rw [other_lost]; exact marker_open _ _ []

theorem id_open (n : String) (h : n ≠ "undefined") : ("setClass", "?") ∈ writes (toks (.id n)) := by
  rw [id_lost n h]; exact marker_open _ _ []

theorem member_open (p : String) : ("setClass", "?") ∈ writes (toks (.member p)) := by
  rw [member_lost]; exact marker_open _ _ []

theorem modKey_open (m : String) : ("setClass", "?") ∈ writes (toks (.modKey m)) := by
  rw [modKey_lost]; exact marker_open _ _ []

theorem arr_open (es : List E) : ("setClass", "?") ∈ writes (toks (.arr es)) := by
  rw [arr_lost]; exact marker_open _ _ []

theorem obj_open (ps : List P) : ("setClass", "?") ∈ writes (toks (.obj ps)) := by
  rw [obj_lost]; exact marker_open _ _ []

theorem glued_word_open (a b : Atom) (w : List Atom) : ("setClass", "?") ∈ writes (wordToks (a :: b :: w)) := by
  rw [glued_reported]; exact glued_open _ ⟨_, List.mem_cons_self, rfl⟩

theorem token_glued (w : String) (h : w.any (· == holeMark) = true) :
    tokenToks w = [⟨.glued, w.map fun c => if c == holeMark then '*' else c⟩] := by
  simp [tokenToks, h]

theorem token_invalid (w : String) (h : w.any (· == holeMark) = false) (hw : (w.isEmpty || w.any isSep) = true) :
    tokenToks w = marker "invalid token" [⟨.cls, w⟩] := by
  simp only [tokenToks, h, hw]; rfl

theorem token_class (w : String) (h : w.any (· == holeMark) = false) (hw : (w.isEmpty || w.any isSep) = false) :
    tokenToks w = [⟨.cls, w⟩] := by
  simp only [tokenToks, h, hw]; rfl

theorem value_str (vs : List String) : valueToks (.str vs) = vs.flatMap tokenToks := rfl

theorem value_mod (n : String) : valueToks (.mod n) = [⟨.mod, n⟩] := rfl

theorem value_modKey (m : String) : valueToks (.modKey m) = marker ("module key " ++ m) [] := rfl

theorem value_unknown : valueToks .unknown = marker "unresolved" [] := rfl

theorem token_glued_open (w : String) (h : w.any (· == holeMark) = true) : ("setClass", "?") ∈ writes (tokenToks w) := by
  rw [token_glued w h]; exact glued_open _ ⟨_, List.mem_cons_self, rfl⟩

theorem token_invalid_open (w : String) (h : w.any (· == holeMark) = false) (hw : (w.isEmpty || w.any isSep) = true) :
    ("setClass", "?") ∈ writes (tokenToks w) := by
  rw [token_invalid w h hw]; exact marker_open _ _ []

theorem value_modKey_open (m : String) : ("setClass", "?") ∈ writes (valueToks (.modKey m)) := by
  rw [value_modKey]; exact marker_open _ _ []

theorem value_unknown_open : ("setClass", "?") ∈ writes (valueToks .unknown) := by
  rw [value_unknown]; exact marker_open _ _ []

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

private def s (x : String) : E := .str x
private def v (x : String) : E := .id x

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
    .or (s "fallback") (v "x"),
    .or (v "x") (s "fallback"),
    .nullish (v "x") (s "dflt"),
    .nullish (s "first") (s "second"),
    .tmpl ["row ", " tail"] [.cond (v "f") (s "flip") (s "")],
    .tmpl ["a ", ""] [.cmp (v "r") (s "exit")],
    .tmpl ["", " ", ""] [.mod "a", .mod "b"],
    .tmpl ["btn-", ""] [v "size"],
    .tmpl ["", "", ""] [.mod "a", .mod "b"],
    .tmpl ["x", " y"] [.cond (v "c") (s "a") (s "b")],
    .concat (s "a ") (.cond (v "c") (s "on") (s "off")),
    .concat (s "btn-") (v "size"),
    .concat (s "a") (s "b"),
    .concat (.concat (s "x ") (.tmpl ["y ", ""] [v "z"])) (s " w"),
    .arr [s "p", .and (v "q") (s "q-on"), .cmp (v "r") (s "no")],
    .call "clsx" [.obj [.key "a" (v "b"), .key "c d" (v "e"), .comp (.mod "f") (v "g"), .comp (v "k") (v "h")]],
    .call "clsx" [.obj [.spread (.cond (v "on") (.obj [.key "k" (v "t")]) (.obj [])), .key "a" (v "b")]],
    .call "cx" [.mod "row", .and (v "flip") (s "rowFlip"), .cond (.cmp (v "k") (s "no")) (s "yes") (s "")],
    .call "cls" [s "tab", .and (.cmp (v "id") (s "act")) (.mod "isActive")],
    .call "clsx" [s "a", .cmp (v "r") (s "exit")],
    .call "classNames" [s "a", .arr [s "b"]],
    .call "classnames" [s "a", .mod "b"],
    .call "other" [s "ignored", .mod "m"],
    .method (.method (.arr [s "o", .and (v "a") (s "is-a"), .and (.cmp (v "b") (s "z")) (s "is-b")]) "filter"
      [v "Boolean"]) "join" [s " "],
    .method (.arr [s "a", .mod "b"]) "join" [s " "],
    .method (.method (.arr [s "a", s "b"]) "filter" [v "keep"]) "join" [s "  "],
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
    s "a\u00A0b c",
    s "a\u3000b\x0Bc d",
    v "undefined",
    .cond (.cmp (v "t") (v "id")) (.mod "isActive") (v "undefined"),
    .tmpl ["", " ", " ", ""] [.mod "svg", .mod "idleFrame", .member "frameCls[k]"],
    .cond (v "className") (.tmpl ["", " ", ""] [.mod "card", v "className"]) (.mod "card"),
    .call "cx" [.mod "dot", .modKey "css"],
    .tmpl ["", " ", ""] [.mod "underlineFrame", .modKey "css"],
    .and (.cmp (v "r") (s "exit")) (.cond (v "z") (s "deep") (.and (v "w") (s "deeper")))]

def listCases : List (String × List V) :=
  [ ("add", [.str ["a"]]),
    ("add", [.str ["a b"]]),
    ("add", [.str [""]]),
    ("add", [.str ["a\u00A0b"]]),
    ("toggle", [.str ["is-on"], .unknown]),
    ("toggle", [.str ["a", "b"]]),
    ("toggle", [.str ["is-\x01"]]),
    ("toggle", [.mod "m.css#on"]),
    ("toggle", [.modKey "m.css"]),
    ("remove", [.unknown]),
    ("replace", [.str ["a"], .str ["b"]]),
    ("contains", [.str ["a"], .str ["b"]]),
    ("contains", [.unknown])]

def isIdent (k : String) : Bool :=
  match k.toList with
  | c :: cs => (c.isAlpha || c == '_' || c == '$') && cs.all fun d => d.isAlphanum || d == '_' || d == '$'
  | [] => false

mutual
def render : E → String
  | .str s => "'" ++ s ++ "'"
  | .id n => n
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
  | .other kids => "(" ++ ", ".intercalate ("0" :: renderList kids) ++ ")"

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

def namesOf (k : Kind) (ts : List Tok) : List String := ts.filterMap fun t => if t.kind == k then some t.name else none

def strs (xs : List String) : Lean.Json := Lean.Json.arr (xs.map Lean.Json.str).toArray

def row (e : E) : Lean.Json :=
  let ts := toks e
  Lean.Json.mkObj [("src", render e), ("classes", strs (namesOf .cls ts)), ("modules", strs (namesOf .mod ts)),
    ("findings", Lean.Json.arr ((findings ts).map fun (k, n) => strs [k, n]).toArray),
    ("writes", Lean.Json.arr ((writes ts).map fun (o, n) => strs [o, n]).toArray)]

def V.json : V → Lean.Json
  | .str vs => Lean.Json.mkObj [("str", strs vs)]
  | .mod n => Lean.Json.mkObj [("mod", n)]
  | .modKey m => Lean.Json.mkObj [("modKey", m)]
  | .unknown => Lean.Json.mkObj [("unknown", true)]

def listRow (c : String × List V) : Lean.Json :=
  let ts := listToks c.1 c.2
  Lean.Json.mkObj [("method", c.1), ("args", Lean.Json.arr (c.2.map V.json).toArray),
    ("findings", Lean.Json.arr ((findings ts).map fun (k, n) => strs [k, n]).toArray),
    ("writes", Lean.Json.arr ((listWrites c.1 ts).map fun (o, n) => strs [o, n]).toArray)]

def head : Lean.Json :=
  Lean.Json.mkObj [("helpers", strs helpers), ("separators", strs ([' ', '\t', '\n', Char.ofNat 12, '\r'].map toString)),
    ("listMethods", strs listMethods)]

def goldenText (_ : Unit := ()) : String :=
  String.join ((head :: cases.map row ++ listCases.map listRow).map fun j => j.compress ++ "\n")

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
#guard toks (.call "cx" [.arr [s "a"]]) == [⟨.cls, "a"⟩]
#guard toks (.obj [.key "a" (v "b")]) == [⟨.lost, "object"⟩, ⟨.lost, "a"⟩]
#guard toks (.call "cx" [.obj [.key "a" (v "b")]]) == [⟨.cls, "a"⟩]
#guard names (toks (.method (.arr [s "a", .arr [s "b"]]) "join" [s " "])) == ["a", "array", "b"]
#guard toks (v "undefined") == [] && toks (v "cls") == [⟨.lost, "id cls"⟩]
#guard toks (.member "frameCls[k]") == [⟨.lost, "member"⟩]
#guard toks (.modKey "v") == [⟨.lost, "module key v"⟩]
#guard tokens "a\u00A0b c" == ["a\u00A0b", "c"] && tokens "a\x0Bb" == ["a\x0Bb"]
#guard listToks "add" [.str ["a b"]] == [⟨.lost, "invalid token"⟩, ⟨.lost, "a b"⟩]
#guard listToks "toggle" [.str ["is-\x01"], .unknown] == [⟨.glued, "is-*"⟩]
#guard listToks "replace" [.str ["a"], .mod "m#b"] == [⟨.cls, "a"⟩, ⟨.mod, "m#b"⟩]
#guard listWrites "contains" (listToks "contains" [.unknown]) == [("classRead", "?")]
#guard listWrites "add" (listToks "add" [.modKey "m"]) == [("setClass", "?")]
#guard toks (.method (.arr [s "a", s "b"]) "join" [s "-"]) == [⟨.lost, "join separator"⟩, ⟨.lost, "a"⟩, ⟨.lost, "b"⟩]
#guard toks (.method (.arr [s "a"]) "join" [s "\t"]) == [⟨.cls, "a"⟩]
#guard sepOk [s " "] && sepOk [s " \t"] && !sepOk [s ""] && !sepOk [s "-"] && !sepOk [] && !sepOk [v "x"]
#guard !sepOk [s " ", s " "]
#guard writes [⟨.cls, "a"⟩, ⟨.mod, "m"⟩] == [("setClass", "a"), ("setModuleClass", "m")]
#guard writes [⟨.lost, "a"⟩, ⟨.cls, "b"⟩, ⟨.lost, "c"⟩] == [("setClass", "b"), ("setClass", "?")]
#guard writes [⟨.glued, "a*"⟩, ⟨.cls, "a"⟩] == [("setClass", "a"), ("setClass", "?")]
#guard findings [⟨.lost, "a"⟩, ⟨.cls, "b"⟩, ⟨.glued, "c*"⟩, ⟨.mod, "m"⟩] == [("unmodelled-class", "a"), ("glued-class", "c*")]
#guard tokens "a\x0Cb\r\nc" == ["a", "b", "c"] && tokens "a b" == ["a b"]
#guard isIdent "a" && isIdent "_b$1" && !isIdent "c d" && !isIdent "1a" && !isIdent ""
#guard (cases.map toks).getLast? == some [⟨.cls, "deep"⟩, ⟨.cls, "deeper"⟩]

/-- Print the golden, or with `--check <file>` compare it byte for byte (exit 1 on a difference). -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readFile path
    if cur == goldenText () then
      IO.eprintln s!"footprint classpos golden: {path} is up to date ({cases.length + listCases.length + 1} lines)"
      return 0
    IO.eprintln s!"footprint classpos golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.ClassPos
