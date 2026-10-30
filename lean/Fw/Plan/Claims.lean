import Lean.Data.Json

/-!
# Claim lint (task claim-lint): a status tag needs its kind of source, and a number that names an artifact key equals it
Rule table, examples and accepted limits: `research/notes/2026/10-30-claim-lint.md`; golden `packages/contracts/golden/plan/claims.jsonl`.
-/

namespace Fw.Plan.Claims
open Lean


structure Q where
  num : Int
  den : Nat
deriving Repr, BEq, Inhabited

structure Dec where
  m : Int
  e : Nat
deriving Repr, BEq, Inhabited

def Dec.toQ (d : Dec) : Q := ⟨d.m, 10 ^ d.e⟩

def roundQ (q : Q) (d : Nat) : Int :=
  let r : Nat := (2 * q.num.natAbs * 10 ^ d + q.den) / (2 * q.den)
  if q.num < 0 then -(r : Int) else r

/-- Key rule: the written `w` equals `q` rounded half away from zero to `w`'s own decimal places. -/
def numOk (w : Dec) (q : Q) : Bool := roundQ q w.e == w.m

theorem numOk_iff (w : Dec) (q : Q) : numOk w q = true ↔ roundQ q w.e = w.m := by
  simp [numOk]

theorem roundQ_half (n den d : Nat) (h : 0 < den) :
    2 * ((2 * n * 10 ^ d + den) / (2 * den)) * den ≤ 2 * n * 10 ^ d + den ∧
    2 * n * 10 ^ d < 2 * ((2 * n * 10 ^ d + den) / (2 * den)) * den + den := by
  have h2 : 0 < 2 * den := by omega
  have hm := Nat.mod_lt (2 * n * 10 ^ d + den) h2
  have hd := Nat.div_add_mod (2 * n * 10 ^ d + den) (2 * den)
  generalize (2 * n * 10 ^ d + den) / (2 * den) = r at *
  generalize (2 * n * 10 ^ d + den) % (2 * den) = k at *
  generalize 2 * n * 10 ^ d = x at *
  have e1 : 2 * den * r = 2 * (r * den) := by rw [Nat.mul_comm r den, Nat.mul_assoc]
  have e2 : 2 * r * den = 2 * (r * den) := by rw [Nat.mul_assoc]
  rw [e2]
  rw [e1] at hd
  omega

theorem roundQ_nonneg_close (q : Q) (d : Nat) (h : 0 < q.den) (hn : 0 ≤ q.num) :
    2 * (roundQ q d).natAbs * q.den ≤ 2 * q.num.natAbs * 10 ^ d + q.den ∧
    2 * q.num.natAbs * 10 ^ d < 2 * (roundQ q d).natAbs * q.den + q.den := by
  have hlt : ¬ q.num < 0 := by omega
  simp only [roundQ, hlt, ↓reduceIte, Int.natAbs_natCast]
  exact roundQ_half q.num.natAbs q.den d h

theorem roundQ_exact (m : Int) (e d : Nat) (h : e ≤ d) : roundQ ⟨m, 10 ^ e⟩ d = m * (10 ^ (d - e) : Nat) := by
  have hp : 0 < 10 ^ e := Nat.pow_pos (by decide)
  have hsplit : 10 ^ d = 10 ^ (d - e) * 10 ^ e := by rw [← Nat.pow_add]; congr 1; omega
  have hdiv : (2 * m.natAbs * 10 ^ d + 10 ^ e) / (2 * 10 ^ e) = m.natAbs * 10 ^ (d - e) := by
    rw [hsplit]
    have : 2 * m.natAbs * (10 ^ (d - e) * 10 ^ e) + 10 ^ e = (m.natAbs * 10 ^ (d - e)) * (2 * 10 ^ e) + 10 ^ e := by
      simp only [Nat.mul_comm, Nat.mul_left_comm, Nat.mul_assoc]
    rw [this, Nat.add_comm, Nat.add_mul_div_right _ _ (by omega)]
    have : 10 ^ e / (2 * 10 ^ e) = 0 := Nat.div_eq_of_lt (by omega)
    omega
  simp only [roundQ, hdiv]
  rcases Int.lt_or_le m 0 with hm | hm
  · simp only [hm, ↓reduceIte]
    have := Int.natAbs_of_nonneg (show 0 ≤ -m by omega)
    rw [Int.natAbs_neg] at this
    push_cast
    rw [this]; simp [Int.neg_mul]
  · simp only [show ¬ m < 0 by omega, ↓reduceIte]
    push_cast
    rw [Int.natAbs_of_nonneg hm]

def Q.le (a b : Q) : Bool := decide (a.num * b.den ≤ b.num * a.den)
def Q.eqv (a b : Q) : Bool := a.num * b.den == b.num * a.den

/-- Range rule: `a to b` over listed values holds iff `a` is their least and `b` their greatest value. -/
def rangeOk (a b : Q) (xs : List Q) : Bool :=
  xs.all (fun x => a.le x && x.le b) && xs.any (fun x => x.eqv a) && xs.any (fun x => x.eqv b)

theorem rangeOk_iff (a b : Q) (xs : List Q) :
    rangeOk a b xs = true ↔
      (∀ x ∈ xs, a.le x = true ∧ x.le b = true) ∧ (∃ x ∈ xs, x.eqv a = true) ∧ (∃ x ∈ xs, x.eqv b = true) := by
  simp [rangeOk, List.all_eq_true, List.any_eq_true, and_assoc]

theorem rangeOk_nil (a b : Q) : rangeOk a b [] = false := by simp [rangeOk]


inductive Tag | confirmed | measured | inferred
deriving Repr, BEq, DecidableEq, Inhabited

def Tag.name : Tag → String
  | .confirmed => "CONFIRMED" | .measured => "MEASURED" | .inferred => "INFERRED"

structure Cites where
  source : Bool
  run : Bool
  committed : Bool
  scratch : Bool
  bound : Bool
  thm : Bool
deriving Repr, BEq, Inhabited

def tagOk : Tag → Cites → Bool
  | .confirmed, c => c.source
  | .measured, c => (c.run || c.committed) && !c.scratch
  | .inferred, _ => true

/-- Status rule: the tag's own source, and a theorem name whenever the sentence states a bound. -/
def claimOk (t : Tag) (c : Cites) : Bool := tagOk t c && (!c.bound || c.thm)

theorem claim_ok_iff (t : Tag) (c : Cites) :
    claimOk t c = true ↔
      (t = .confirmed → c.source = true) ∧
      (t = .measured → (c.run = true ∨ c.committed = true) ∧ c.scratch = false) ∧
      (c.bound = true → c.thm = true) := by
  obtain ⟨s, r, co, sc, b, th⟩ := c
  cases t <;> cases s <;> cases r <;> cases co <;> cases sc <;> cases b <;> cases th <;> decide

theorem confirmed_ok_iff (c : Cites) : claimOk .confirmed c = true ↔ c.source = true ∧ (c.bound = true → c.thm = true) := by
  simp [claim_ok_iff]

theorem measured_ok_iff (c : Cites) :
    claimOk .measured c = true ↔ (c.run = true ∨ c.committed = true) ∧ c.scratch = false ∧ (c.bound = true → c.thm = true) := by
  simp [claim_ok_iff, and_assoc]

theorem measured_scratch_refused (c : Cites) (h : c.scratch = true) : claimOk .measured c = false := by
  simp [claimOk, tagOk, h]

theorem inferred_ok_iff (c : Cites) : claimOk .inferred c = true ↔ (c.bound = true → c.thm = true) := by
  simp [claim_ok_iff]


def isSep (c : Char) : Bool :=
  c.isWhitespace || c == '`' || c == '(' || c == ')' || c == ',' || c == ';' || c == '|'

structure Tok where
  s : List Char
  pos : Nat
  stop : Nat
  sep : Char
  code : Bool
deriving Repr, Inhabited

def stripTail : List Char → List Char
  | cs => (cs.reverse.dropWhile (fun c => c == '.' || c == ':' || c == '!' || c == '?')).reverse

def stripQuotes (cs : List Char) : List Char :=
  if cs.contains '[' then cs
  else
    let q := fun c => c == '"' || c == '\''
    stripTail ((cs.dropWhile q).reverse.dropWhile q).reverse

def stripStars (cs : List Char) : List Char :=
  if cs.all (· == '*') then cs else ((cs.dropWhile (· == '*')).reverse.dropWhile (· == '*')).reverse

def strip (cs : List Char) : List Char := stripQuotes (stripStars (stripTail (stripStars cs)))

def tokensAux : List Char → Bool → Nat → Nat → List Char → List Tok → List Tok
  | [], code, i, st, cur, acc => (if cur.isEmpty then acc else ⟨strip cur.reverse, st, i, ' ', code⟩ :: acc).reverse
  | c :: rest, code, i, st, cur, acc =>
    if isSep c then
      let acc := if cur.isEmpty then acc else ⟨strip cur.reverse, st, i, c, code⟩ :: acc
      tokensAux rest (if c == '`' then !code else code) (i + 1) (i + 1) [] acc
    else tokensAux rest code (i + 1) (if cur.isEmpty then i else st) (c :: cur) acc

def tokens (cs : List Char) : List Tok := (tokensAux cs false 0 0 [] []).filter (fun t => !t.s.isEmpty)

def parseDec (cs : List Char) : Option Dec :=
  let (neg, r) : Bool × List Char := match cs with
    | '-' :: r => (true, r) | '+' :: r => (false, r) | '−' :: r => (true, r) | r => (false, r)
  let r := if r.getLast? == some '%' then r.dropLast else r
  let (ip, r1) := r.span Char.isDigit
  let val := fun (ds : List Char) => ds.foldl (fun a c => a * 10 + (c.toNat - '0'.toNat)) 0
  let mk := fun (m : Nat) (e : Nat) => some (⟨if neg then -(m : Int) else m, e⟩ : Dec)
  if ip.isEmpty then none
  else match r1 with
    | [] => mk (val ip) 0
    | '.' :: fp => if !fp.isEmpty && fp.all Char.isDigit then mk (val (ip ++ fp)) fp.length else none
    | _ => none

def isPrefixOf (p s : List Char) : Bool := p.isPrefixOf s
def infixOf (p : List Char) : List Char → Bool
  | [] => p.isEmpty
  | c :: r => p.isPrefixOf (c :: r) || infixOf p r

def exts : List String :=
  ["md", "json", "jsonl", "lean", "ts", "tsx", "mts", "mjs", "js", "cjs", "sh", "yml", "yaml", "txt", "toml", "css", "html",
   "py", "cpp", "c", "h", "mm", "swift", "log", "csv", "svg", "lock"]
def tops : List String :=
  ["apps", "packages", "lean", "research", "docs", "results", "scripts", ".github", "snapshot", "refs", ".claude"]

def isUrl (cs : List Char) : Bool := isPrefixOf "http://".toList cs || isPrefixOf "https://".toList cs

def normPath (cs : List Char) : List Char :=
  let p := cs.takeWhile (fun c => c != ':' && c != '@')
  if isPrefixOf "./".toList p then p.drop 2 else p

def extOf (p : List Char) : List Char :=
  match (p.reverse.takeWhile (· != '.')).reverse with
  | e => if e.length < p.length && !e.isEmpty && e.all Char.isAlphanum then e else []

def isPath (cs : List Char) : Bool :=
  let p := normPath cs
  let slashes := p.count '/'
  !isUrl cs && p.any Char.isAlpha && !(cs.any fun c => c == '[' || c == '<' || c == '\'' || c == '=') &&
    (exts.contains (String.ofList (extOf p)) || slashes ≥ 2 ||
      (slashes == 1 && tops.contains (String.ofList (p.takeWhile (· != '/')))))

def isSha (cs : List Char) : Bool :=
  7 ≤ cs.length && cs.length ≤ 40 && cs.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')) && cs.any Char.isDigit &&
    cs.any Char.isAlpha

def isRunId (cs : List Char) : Bool :=
  let ds := if isPrefixOf "run:".toList cs then cs.drop 4 else cs
  ds.length ≥ 9 && ds.all Char.isDigit

def isLeanName (cs : List Char) : Bool := isPrefixOf "Fw.".toList cs && cs.length > 3

def isTheorem (cs : List Char) : Bool :=
  isLeanName cs ||
    (match cs with | c :: _ => c.isAlpha | [] => false) && cs.contains '_' && cs.any Char.isLower &&
      cs.all (fun c => c.isAlphanum || c == '_' || c == '.' || c == '\'')

def isScratch (cs : List Char) : Bool :=
  infixOf "scratchpad".toList cs || isPrefixOf "/tmp".toList cs || infixOf "/tmp/".toList cs ||
    isPrefixOf "/private/".toList cs || isPrefixOf ".local/".toList cs || infixOf "/.local/".toList cs ||
    isPrefixOf "~/".toList cs || isPrefixOf "/Users/".toList cs || isPrefixOf "/home/".toList cs

def tagOf (cs : List Char) : Option Tag :=
  if cs == "CONFIRMED".toList then some .confirmed
  else if cs == "MEASURED".toList then some .measured
  else if cs == "INFERRED".toList then some .inferred
  else none

def isBoundWord (cs : List Char) : Bool :=
  let l := cs.map Char.toLower
  l == "bound".toList || l == "bounds".toList || l == "bounded".toList


inductive BKind | prose | table
deriving BEq, Repr, Inhabited

structure Block where
  line : Nat
  kind : BKind
  lines : List String
deriving Repr, Inhabited

def ltrim (cs : List Char) : List Char := cs.dropWhile Char.isWhitespace

def startsItem (cs : List Char) : Bool :=
  let t := ltrim cs
  match t with
  | '#' :: _ => true
  | c :: ' ' :: _ => c == '-' || c == '*' || c == '+'
  | _ =>
    let (ds, r) := t.span Char.isDigit
    !ds.isEmpty && isPrefixOf ". ".toList r

def isFence (cs : List Char) : Bool := let t := ltrim cs; isPrefixOf "```".toList t || isPrefixOf "~~~".toList t

structure BState where
  code : Bool := false
  cur : Option Block := none
  out : List Block := []

def BState.flush (st : BState) : BState :=
  match st.cur with
  | some b => { st with cur := none, out := { b with lines := b.lines.reverse } :: st.out }
  | none => st

def stepLine (st : BState) (n : Nat) (l : String) : BState :=
  let cs := l.toList
  if isFence cs then { st.flush with code := !st.code }
  else if st.code then st
  else if (ltrim cs).isEmpty then st.flush
  else if (ltrim cs).head? == some '|' then
    match st.cur with
    | some b => if b.kind == .table then { st with cur := some { b with lines := l :: b.lines } }
                else { st.flush with cur := some ⟨n, .table, [l]⟩ }
    | none => { st with cur := some ⟨n, .table, [l]⟩ }
  else
    match st.cur with
    | some b => if b.kind == .prose && !startsItem cs && !(b.lines.getLast?.map (fun h => (ltrim h.toList).head? == some '#')).getD false
                then { st with cur := some { b with lines := l :: b.lines } }
                else { st.flush with cur := some ⟨n, .prose, [l]⟩ }
    | none => { st with cur := some ⟨n, .prose, [l]⟩ }

def blocks (text : String) : List Block :=
  let ls := text.splitOn "\n"
  let st := (ls.zip (List.range ls.length)).foldl (fun st (l, i) => stepLine st (i + 1) l) {}
  st.flush.out.reverse

def endsSentence (c : Char) (rest : List Char) : Bool :=
  (c == '.' || c == '?' || c == '!') &&
    (match rest with | d :: _ => d == ' ' || d == '\n' | [] => false) &&
    (match ltrim rest with | d :: _ => 'A' ≤ d && d ≤ 'Z' | [] => false)

def sentencesAux : List Char → Nat → Nat → List Char → List (Nat × List Char) → List (Nat × List Char)
  | [], _, st, cur, acc => (if cur.isEmpty then acc else (st, cur.reverse) :: acc).reverse
  | c :: rest, nl, st, cur, acc =>
    let nl' := if c == '\n' then nl + 1 else nl
    if endsSentence c rest then sentencesAux rest nl' nl' [] ((st, (c :: cur).reverse) :: acc)
    else if cur.isEmpty && c.isWhitespace then sentencesAux rest nl' nl' cur acc
    else sentencesAux rest nl' st (c :: cur) acc

def sentences (b : Block) : List (Nat × List Char) :=
  (sentencesAux ("\n".intercalate b.lines).toList 0 0 [] []).map fun (k, s) => (b.line + k, s)

structure Unit' where
  line : Nat
  cs : List Char
  toks : List Tok
  scope : List Tok
deriving Inhabited

def isHeading (b : Block) : Bool :=
  b.kind == .prose && (b.lines.head?.map fun l => (ltrim l.toList).head? == some '#').getD false

def blockToks (b : Block) : List Tok := tokens ("\n".intercalate b.lines).toList

def units (bs : List Block) : List Unit' :=
  let arr := bs.toArray
  let bt := arr.map blockToks
  let heads := (List.range arr.size).filter fun k => isHeading arr[k]!
  let nextHead := fun k => ((heads.filter (· > k)).head?).getD arr.size
  (List.range arr.size).flatMap fun k =>
    let b := arr[k]!
    let headToks := (((heads.filter (· ≤ k)).getLast?).map (bt[·]!)).getD []
    let capToks := if b.kind == .table && k > 0 && arr[k - 1]!.kind == .prose then bt[k - 1]! else []
    let scope := if isHeading b then ((List.range arr.size).filter fun j => k ≤ j && j < nextHead k).flatMap (bt[·]!)
      else bt[k]! ++ headToks ++ capToks
    match b.kind with
    | .prose => (sentences b).map fun (n, s) => ⟨n, s, tokens s, scope⟩
    | .table => (b.lines.zip (List.range b.lines.length)).map fun (l, i) =>
      let ts := tokens l.toList
      ⟨b.line + i, l.toList, ts, ts ++ scope⟩


inductive Content | json (j : Json) | lines (ls : List String)
deriving Inhabited

structure Ctx where
  notePaths : List String
  committed : List String
  files : List (String × Content)
deriving Inhabited

def lastSeg (p : String) : String := ((p.splitOn "/").getLast?).getD p

def resolve (notePaths : List String) (f : List Char) : Option String :=
  let p := String.ofList (normPath f)
  if p.contains '/' then some p
  else match (notePaths.filter (fun q => q.contains '/' && lastSeg q == p)).eraseDups with
    | [q] => some q
    | _ => none

inductive Seg | field (s : String) | index (n : Nat)
deriving Repr, BEq, Inhabited

def unquote (cs : List Char) : Option String :=
  match cs, cs.getLast? with
  | '\'' :: r, some '\'' => if r.length ≥ 1 then some (String.ofList r.dropLast) else none
  | '"' :: r, some '"' => if r.length ≥ 1 then some (String.ofList r.dropLast) else none
  | _, _ => none

def isIdent (c : Char) : Bool := c.isAlphanum || c == '_' || c == '$' || c == '-'

def parseKeyAux : Nat → List Char → List Seg → Option (List Seg)
  | 0, _, _ => none
  | _ + 1, [], acc => some acc.reverse
  | f + 1, '.' :: r, acc =>
    let (id, r') := r.span isIdent
    if id.isEmpty then none else parseKeyAux f r' (.field (String.ofList id) :: acc)
  | f + 1, '[' :: r, acc =>
    let (inner, r') := r.span (· != ']')
    match r' with
    | ']' :: r'' =>
      let seg := match unquote inner with
        | some s => Seg.field s
        | none => if !inner.isEmpty && inner.all Char.isDigit then
            .index (inner.foldl (fun a c => a * 10 + (c.toNat - '0'.toNat)) 0) else .field (String.ofList inner)
      parseKeyAux f r'' (seg :: acc)
    | _ => none
  | _, _, _ => none

def parseKey (cs : List Char) : Option (List Seg) :=
  let (id, r) := cs.span isIdent
  let start := if id.isEmpty then [] else [Seg.field (String.ofList id)]
  if id.isEmpty && cs.head? != some '[' then none else parseKeyAux (cs.length + 1) r start.reverse

def isKeyish (cs : List Char) : Bool :=
  (cs.contains '[' || cs.contains '.') && exts.all (fun e => !(isPrefixOf ('.' :: e.toList).reverse cs.reverse)) &&
    (match cs with | c :: _ => c.isAlpha || c == '[' | [] => false) && (parseKey cs).isSome

def selectKeys : List String := ["id", "name", "arm", "key"]

def pick (j : Json) : Seg → Option Json
  | .field s => match j with
    | .obj _ => (j.getObjVal? s).toOption
    | .arr a =>
      match a.toList.filter (fun e => selectKeys.any fun k => (e.getObjValAs? String k).toOption == some s) with
      | [e] => some e
      | _ => none
    | _ => none
  | .index n => match j with
    | .arr a => a[n]?
    | .obj _ => (j.getObjVal? (toString n)).toOption
    | _ => none

def lookup (j : Json) (ks : List Seg) : Option Json := ks.foldlM pick j

def jsonQ : Json → Option Q
  | .num n => some ⟨n.mantissa, 10 ^ n.exponent⟩
  | _ => none

def fileOf (cx : Ctx) (p : String) : Option Content := (cx.files.find? (·.1 == p)).map (·.2)


structure Finding where
  line : Nat
  code : String
  detail : String
deriving Repr, BEq, Inhabited

def showQ (q : Q) : String :=
  if q.den == 1 then toString q.num
  else
    let e := (List.range 20).find? (fun k => 10 ^ k == q.den)
    match e with
    | some k =>
      let a := q.num.natAbs
      let ip := a / 10 ^ k
      let fp := toString (a % 10 ^ k)
      let fp := String.ofList (List.replicate (k - fp.length) '0') ++ fp
      (if q.num < 0 then "-" else "") ++ toString ip ++ "." ++ fp
    | none => s!"{q.num}/{q.den}"

def showDec (d : Dec) : String := showQ d.toQ

def str (cs : List Char) : String := String.ofList cs

def statusFindings (cx : Ctx) (u : Unit') : List Finding :=
  let tags := (u.toks.filterMap fun t => if t.code then none else tagOf t.s).eraseDups
  if tags.isEmpty || tags.length == 3 then [] else
  let scratch := u.toks.any (isScratch ·.s)
  let ts := u.scope.map (·.s)
  let committed := ts.any fun t =>
    isPath t && (cx.committed.contains (str (normPath t)) ||
      ((resolve cx.notePaths t).map cx.committed.contains).getD false)
  let c : Cites := {
    source := ts.any fun t => isPath t || isUrl t || isSha t || isRunId t || isLeanName t
    run := ts.any isRunId
    committed
    scratch
    bound := u.toks.any (isBoundWord ·.s)
    thm := ts.any isTheorem }
  tags.flatMap fun t =>
    (match t with
      | .confirmed => if c.source then [] else [⟨u.line, "confirmedNoSource", "CONFIRMED names no path, sha, URL, run id or Lean name"⟩]
      | .measured =>
        (if c.run || c.committed then [] else [⟨u.line, "measuredNoSource", "MEASURED names no run id and no committed path"⟩]) ++
        (if c.scratch then [⟨u.line, "measuredScratch", "MEASURED cites a scratch or local path"⟩] else [])
      | .inferred => []) ++
    (if c.bound && !c.thm then [⟨u.line, "boundNoTheorem", s!"{t.name} states a bound and names no theorem"⟩] else [])

def claimedAfter (toks : List Tok) (i : Nat) (refStarts : List Nat) : Option Dec :=
  let nextRef := (refStarts.filter (· > i)).foldl min toks.length
  ((toks.drop (i + 2)).take (nextRef - (i + 2))).findSome? (fun t => parseDec t.s)

def refStarts (toks : List Tok) : List Nat :=
  (List.range toks.length).filter fun i =>
    match toks[i]?, toks[i + 1]? with
    | some a, some b => isPrefixOf "nosj.".toList a.s.reverse && isKeyish b.s
    | _, _ => false

def keyFinding (cx : Ctx) (line : Nat) (f k : List Char) (w : Dec) : Option Finding :=
  match resolve cx.notePaths f with
  | none => some ⟨line, "refUnread", s!"{str f} names no unique note path"⟩
  | some p =>
    match fileOf cx p with
    | some (.json j) =>
      match (parseKey k).bind (lookup j) with
      | none => some ⟨line, "keyMissing", s!"{p} {str k}: no such key"⟩
      | some v =>
        match jsonQ v with
        | some q => if numOk w q then none
                    else some ⟨line, "keyMismatch", s!"{p} {str k}: written {showDec w}, value {showQ q}"⟩
        | none => none
    | _ => some ⟨line, "refUnread", s!"{p} was not read"⟩

def keyFindings (cx : Ctx) (u : Unit') : List Finding :=
  let rs := refStarts u.toks
  rs.filterMap fun i =>
    match u.toks[i]?, u.toks[i + 1]?, claimedAfter u.toks i rs with
    | some a, some b, some w => keyFinding cx u.line a.s b.s w
    | _, _, _ => none

def numAt (toks : List Tok) (i : Nat) : Option Dec := toks[i]?.bind (parseDec ·.s)

def listAt (toks : List Tok) (j : Nat) : List Dec :=
  let rec go : Nat → Nat → List Dec → List Dec
    | 0, _, acc => acc.reverse
    | f + 1, k, acc =>
      match toks[k]?, numAt toks k with
      | some t, some d => if t.sep == ',' && (numAt toks (k + 1)).isSome then go f (k + 1) (d :: acc) else (d :: acc).reverse
      | _, _ => acc.reverse
  let xs := go toks.length j []
  if xs.length ≥ 2 then xs else []

def rangeStarts (toks : List Tok) : List Nat :=
  (List.range toks.length).filter fun i =>
    (numAt toks i).isSome && (toks[i + 1]?.map (·.s == "to".toList)).getD false && (numAt toks (i + 2)).isSome

def rangeFindings (u : Unit') : List Finding :=
  let rs := rangeStarts u.toks
  let refs := refStarts u.toks
  rs.filterMap fun i =>
    let stop := (rs.filter (· > i)).foldl min u.toks.length
    let xs := (refs.find? (fun r => r > i + 2 && r < stop)).bind fun r =>
      match listAt u.toks (r + 2) with | [] => none | xs => some xs
    match numAt u.toks i, numAt u.toks (i + 2), xs with
    | some a, some b, some xs =>
      if rangeOk a.toQ b.toQ (xs.map Dec.toQ) then none
      else
        let lo := xs.foldl (fun m x => if x.toQ.le m.toQ then x else m) xs.head!
        let hi := xs.foldl (fun m x => if m.toQ.le x.toQ then x else m) xs.head!
        some ⟨u.line, "rangeEnds", s!"{showDec a} to {showDec b}, listed {", ".intercalate (xs.map showDec)}: least {showDec lo}, greatest {showDec hi}"⟩
    | _, _, _ => none

def opQ (op : List Char) (a b : Q) : Option Q :=
  if op == ['/'] then
    if b.num == 0 then none
    else some ⟨a.num * b.den * (if b.num < 0 then -1 else 1), a.den * b.num.natAbs⟩
  else if op == ['*'] || op == ['×'] then some ⟨a.num * b.num, a.den * b.den⟩
  else if op == ['+'] then some ⟨a.num * b.den + b.num * a.den, a.den * b.den⟩
  else if op == ['-'] || op == ['−'] then some ⟨a.num * b.den - b.num * a.den, a.den * b.den⟩
  else none

def splitSlash (cs : List Char) : Option (Dec × Dec) :=
  match cs.splitOn '/' with
  | [a, b] => do pure (← parseDec a, ← parseDec b)
  | _ => none

def isOpTok (cs : List Char) : Bool := ["/", "*", "×", "·", "+", "-", "−", "=", "\\cdot", "\\times"].contains (str cs)

def asWritten (ts : List Tok) (k : Nat) (q : Q) : Q :=
  let pct := (ts[k]?.map (·.s.getLast? == some '%')).getD false || (ts[k + 1]?.map (·.s == ['%'])).getD false
  if pct then ⟨q.num * 100, q.den⟩ else q

def arithFindings (u : Unit') : List Finding :=
  let ts := u.toks
  (List.range ts.length).filterMap fun i =>
    let s := fun k => (ts[k]?.map (·.s)).getD []
    let eqAt := fun k => s k == ['=']
    let plain := fun (k : Nat) => (ts[k]?.map fun t => !t.code && t.sep.isWhitespace).getD false
    let free := fun (last : Nat) => (i == 0 || !isOpTok (s (i - 1))) && !isOpTok (s (last + 1)) &&
      (ts[last]?.map (!·.code)).getD false && (List.range (last - i)).all (fun d => plain (i + d))
    let r : Option (Dec × List Char × Dec × Nat) :=
      if eqAt (i + 3) then
        if !free (i + 4) then none else
        match numAt ts i, numAt ts (i + 2) with
        | some a, some b => if (opQ (s (i + 1)) a.toQ b.toQ).isSome then some (a, s (i + 1), b, i + 4) else none
        | _, _ => none
      else if eqAt (i + 1) && (numAt ts i).isNone && free (i + 2) then
        (splitSlash (s i)).map fun (a, b) => (a, ['/'], b, i + 2)
      else none
    r.bind fun (a, op, b, k) =>
      (numAt ts k).bind fun c =>
      (opQ op a.toQ b.toQ).bind fun q =>
        let q := asWritten ts k q
        if numOk c q then none
        else some ⟨u.line, "arithMismatch", s!"{showDec a} {str op} {showDec b} = {showDec c}: rounds to {showDec ⟨roundQ q c.e, c.e⟩}"⟩

def bound (c : Char) : Bool := c.isAlphanum

def findSeg (seg cs : List Char) (start : Nat) : Option Nat :=
  (List.range (cs.length + 1)).find? (fun i =>
    i ≥ start && isPrefixOf seg (cs.drop i) &&
      (i == 0 || !(seg.head?.map bound).getD false || !(cs[i - 1]?.map bound).getD false) &&
      (!(seg.getLast?.map bound).getD false || !(cs[i + seg.length]?.map bound).getD false)) |>.map (· + seg.length)

def segsOf (q : List Char) : List (List Char) :=
  let parts := (str q).splitOn "..." |>.flatMap (·.splitOn "…")
  (parts.map fun p => (ltrim (ltrim p.toList).reverse).reverse).filter (!·.isEmpty)

def segsIn (segs : List (List Char)) (line : List Char) : Bool :=
  (segs.foldlM (fun (k : Nat) sg => findSeg sg line k) 0).isSome

def quoteFindings (cx : Ctx) (u : Unit') : List Finding :=
  u.toks.filterMap fun t =>
    if !isPrefixOf "txt.".toList t.s.reverse then none else
    let after := ltrim (u.cs.drop t.stop)
    match after with
    | q :: rest =>
      if q != '\'' && q != '"' then none else
      let body := rest.takeWhile (· != q)
      if body.length == rest.length then none else
      let segs := segsOf body
      match resolve cx.notePaths t.s with
      | none => some ⟨u.line, "refUnread", s!"{str t.s} names no unique note path"⟩
      | some p =>
        match fileOf cx p with
        | some (.lines ls) =>
          if ls.any (fun l => segsIn segs l.toList) then none
          else some ⟨u.line, "quoteMissing", s!"{p}: no line holds '{str body}'"⟩
        | _ => some ⟨u.line, "refUnread", s!"{p} was not read"⟩
    | [] => none


def cells (l : String) : List String :=
  let cs := (l.splitOn "|").map fun c => str (ltrim (ltrim c.toList).reverse).reverse
  (cs.drop 1).dropLast

def isRule (l : String) : Bool := (cells l).all fun c => c.toList.all fun ch => ch == '-' || ch == ':' || ch == ' '

def dropTicks (s : String) : String := str (s.toList.filter (· != '`'))
def trimS (s : String) : String := str (ltrim (ltrim s.toList).reverse).reverse

def caption (b : Block) : Option (List Char × List Char × List (String × String)) := do
  let cs := (dropTicks (" ".intercalate b.lines)).toList
  let ts := tokens cs
  let i ← (List.range ts.length).find? fun i => (ts[i]?.map (·.s == "under".toList)).getD false
  let t ← ts[i + 1]?
  if !t.s.contains '<' then none
  let j ← (List.range ts.length).find? fun j => j > i + 1 && (ts[j]?.map (·.s == "in".toList)).getD false
  let f ← ts[j + 1]?
  if !isPrefixOf "nosj.".toList f.s.reverse then none
  let rest := str (cs.drop f.stop)
  let pairs := (rest.splitOn ",").filterMap fun item =>
    match item.splitOn " = " with
    | [h, k] =>
      let h := trimS (((h.splitOn ": ").getLast?).getD h)
      let k := str (stripTail (trimS k).toList)
      if h.isEmpty || k.isEmpty then none else some (h, k)
    | _ => none
  if pairs.isEmpty then none
  pure (t.s, f.s, pairs)

def fill (tpl : List Char) (hdr row : List String) : Option String :=
  let rec go : Nat → List Char → List Char → Option (List Char)
    | 0, _, _ => none
    | _ + 1, [], acc => some acc.reverse
    | f + 1, '<' :: r, acc =>
      let (name, r') := r.span (· != '>')
      match r' with
      | '>' :: r'' =>
        let col := (List.range hdr.length).find? fun k => (hdr[k]?.map (·.toLower == (str name).toLower)).getD false
        match col.bind (row[·]?) with
        | some v => go f r'' (v.toList.reverse ++ acc)
        | none => none
      | _ => none
    | f + 1, c :: r, acc => go f r (c :: acc)
  (go (tpl.length + 1) tpl []).map str

def tableFindings (cx : Ctx) (cap : Block) (t : Block) : List Finding :=
  match caption cap with
  | none => []
  | some (tpl, f, pairs) =>
    match t.lines with
    | h :: rows =>
      let hdr := cells h
      (rows.zip (List.range rows.length)).flatMap fun (l, i) =>
        if isRule l then [] else
        let row := cells l
        match fill tpl hdr row with
        | none => [⟨t.line + 1 + i, "refUnread", s!"{str tpl}: a slot names no column"⟩]
        | some key =>
          pairs.filterMap fun (head, k) =>
            let col := (List.range hdr.length).find? fun c => (hdr[c]?.map (· == head)).getD false
            match col.bind (row[·]?) with
            | some cell =>
              match parseDec (dropTicks cell).toList with
              | some w => keyFinding cx (t.line + 1 + i) f (key ++ "." ++ k).toList w
              | none => none
            | none => none
    | [] => []


def notePathsOf (us : List Unit') : List String :=
  (us.flatMap fun u => u.toks.filterMap fun t => if isPath t.s then some (str (normPath t.s)) else none).eraseDups

def tablePairs (bs : List Block) : List (Block × Block) :=
  (bs.zip (bs.drop 1)).filter fun (a, b) => a.kind == .prose && b.kind == .table

/-- Every finding of one note, in line order. -/
def lint (text : String) (committed : List String) (files : List (String × Content)) : List Finding :=
  let bs := blocks text
  let us := units bs
  let cx : Ctx := ⟨notePathsOf us, committed, files⟩
  let fs := us.flatMap (fun u => statusFindings cx u ++ keyFindings cx u ++ rangeFindings u ++ arithFindings u ++
    quoteFindings cx u) ++ (tablePairs bs).flatMap (fun (c, t) => tableFindings cx c t)
  fs.mergeSort (fun a b => a.line ≤ b.line)

/-- The files the rules read (JSON keys, `.txt` quotes, captions) and every path the note names. -/
def reads (text : String) : List String × List String :=
  let bs := blocks text
  let us := units bs
  let np := notePathsOf us
  let refFiles := us.flatMap fun u =>
    (refStarts u.toks).filterMap (fun i => u.toks[i]?.bind (resolve np ·.s)) ++
    u.toks.filterMap fun t => if isPrefixOf "txt.".toList t.s.reverse then resolve np t.s else none
  let capFiles := (tablePairs bs).filterMap fun (c, _) => (caption c).bind fun (_, f, _) => resolve np f
  ((refFiles ++ capFiles).eraseDups, np)


def findingJson (f : Finding) : Json := Json.mkObj [("line", f.line), ("code", f.code), ("detail", f.detail)]

def contentOf (j : Json) : Option (String × Content) := do
  let p ← (j.getObjValAs? String "path").toOption
  match j.getObjVal? "json", j.getObjValAs? (List String) "lines" with
  | .ok v, _ => pure (p, .json v)
  | _, .ok ls => pure (p, .lines ls)
  | _, _ => none

/-- One request: `claims.reads` (text) or `claims.lint` (text, committed, files). -/
def handle (req : Json) : Json :=
  let text := (req.getObjValAs? String "text").toOption.getD ""
  match req.getObjValAs? String "op" with
  | .ok "claims.reads" =>
    let (rs, ps) := reads text
    Json.mkObj [("reads", toJson rs), ("paths", toJson ps)]
  | .ok "claims.lint" =>
    let committed := (req.getObjValAs? (List String) "committed").toOption.getD []
    let files := ((req.getObjValAs? (Array Json) "files").toOption.getD #[]).toList.filterMap contentOf
    Json.mkObj [("findings", .arr ((lint text committed files).map findingJson).toArray)]
  | _ => Json.mkObj [("error", "unknown op")]


def navSummaryPath : String := "results/nav-cta-webkit-match/summary.json"

def cvw (k : String) (mx st al fl wt : Nat) : String × Json :=
  (k, Json.mkObj [("maxChanged", mx), ("settledChanged", st), ("allowed", al), ("failing", fl), ("maxWithText", wt)])

def navSummary : Json := Json.mkObj [("chromiumVsWebkit", Json.mkObj [
  cvw "1280/exit/faithful" 314 153 256 3 803, cvw "1280/entry/faithful" 2516 145 256 3 3063,
  cvw "1280/exit/logical" 163 153 256 0 803, cvw "1280/entry/logical" 163 145 256 0 585,
  cvw "390/exit/faithful" 231 121 78 17 667, cvw "390/entry/faithful" 1338 124 78 17 1757,
  cvw "390/exit/logical" 148 121 78 17 667, cvw "390/entry/logical" 148 124 78 17 535])]

def navCaption : String :=
  "Keys, all under `chromiumVsWebkit['<width>/<scenario>/<arm>']` in summary.json: Worst frame = `maxChanged`, " ++
  "Settled = `settledChanged`, Allowed = `allowed`, Frames over bound = `failing`, Worst with label = `maxWithText`."

def navTable (entryLogicalSettled : Nat) : String := "\n".intercalate [
  "| Width | Scenario | Arm | Worst frame | Settled | Allowed | Frames over bound | Worst with label |",
  "|---|---|---|---|---|---|---|---|",
  "| 1280 | exit | faithful | 314 | 153 | 256 | 3 | 803 |",
  "| 1280 | exit | logical | 163 | 153 | 256 | 0 | 803 |",
  "| 1280 | entry | faithful | 2516 | 145 | 256 | 3 | 3063 |",
  s!"| 1280 | entry | logical | 163 | {entryLogicalSettled} | 256 | 0 | 585 |",
  "| 390 | exit | faithful | 231 | 121 | 78 | 17 | 667 |",
  "| 390 | exit | logical | 148 | 121 | 78 | 17 | 667 |",
  "| 390 | entry | faithful | 1338 | 124 | 78 | 17 | 1757 |",
  "| 390 | entry | logical | 148 | 124 | 78 | 17 | 535 |"]

def navNote (entryLogicalSettled : Nat) : String :=
  navCaption ++ "\n\n" ++ navTable entryLogicalSettled ++ "\n\nFiles: `" ++ navSummaryPath ++ "`.\n"

def verdictPath : String := "results/end-floor-writes/r3/verdict.txt"

def verdictLines : List String := [
  "end-floor wktr-j1 v2p qwrite: floor 138 arm 133 reference 133 per 100 frames, cut 5, band 10 spread 10, frames floor 96 reference 48 arm 48, leaks 0/0, verdict no writes",
  "end-floor wktr-j2 v2p qstyle: floor 154 arm 147 reference 114 per 100 frames, cut 7, band 2 spread 1, frames floor 531 reference 448 arm 265, leaks 0/0, verdict carries",
  "end-floor wktr-j2 v2p qwrite: floor 154 arm 114 reference 114 per 100 frames, cut 40, band 2 spread 1, frames floor 531 reference 448 arm 448, leaks 0/0, verdict carries"]

def flipRange (lo : Nat) : String :=
  s!"- The floor here (133 to 154) is higher than the all-paused floor of the end-wktr-flip lane ({lo} to 83; " ++
  "`results/end-wktr-flip/r1/wktr-jN/accel-end-base-thr-off-1.json`\n  `rows[rs-flip-pall]`: 83, 71, 81 per 100 frames). " ++
  "What differs, from the mode strings (`packages/measure-wktr/src/accel-cli.mjs:31-39`):"

structure Case where
  name : String
  text : String
  committed : List String := []
  files : List (String × Content) := []

def contentJson : String × Content → Json
  | (p, .lines ls) => Json.mkObj [("path", p), ("lines", toJson ls)]
  | (p, .json j) => Json.mkObj [("path", p), ("json", j)]

def verdictFile : String × Content := (verdictPath, .lines verdictLines)
def navFile : String × Content := (navSummaryPath, .json navSummary)

def lintCases : List Case := [
  { name := "end-floor-writes r2: range low end below the least listed value (42c52ed52)", text := flipRange 70 },
  { name := "end-floor-writes r2 variant: range ends are the least and greatest", text := flipRange 71 },
  { name := "watch-memory r2: a KiB/1000 range (e64ac7211), unchecked: no artifact key",
    text := "| before (whole-file reads) | 842 MB | 585 MB | -5 MB/min (sawtooth 150 to 860 MB, no trend) |" },
  { name := "watch-memory r2 variant: KiB over 1024 written as MB", text := "Before-arm low sample: 152032/1024 = 148 MB." },
  { name := "watch-memory r2 variant: KiB over 1000 written as MB", text := "Before-arm low sample: 152032/1000 = 148 MB." },
  { name := "watch-memory r2: 1.7 x with no written operands (e64ac7211), unchecked: no artifact key",
    text := "The tick line's own reading (taken inside the tick, at its peak) was at most 289 MB. " ++
      "`Fw.Ops.WatchMem.rssBoundKb` is 512 MB:\n1.7 x the after-arm peak, below the before-arm mean." },
  { name := "watch-memory r2 variant: 1.7 x written with the operands 512 / 289",
    text := "`Fw.Ops.WatchMem.rssBoundKb` is 512 MB: 512 / 289 = 1.7 x the after-arm peak." },
  { name := "watch-memory r2 variant: 1.8 x written with the operands 512 / 289",
    text := "`Fw.Ops.WatchMem.rssBoundKb` is 512 MB: 512 / 289 = 1.8 x the after-arm peak." },
  { name := "nav-cta-webkit-match variant: captioned table equals summary.json", text := navNote 145,
    committed := [navSummaryPath], files := [navFile] },
  { name := "nav-cta-webkit-match variant: entry logical Settled copied from the exit row", text := navNote 153,
    committed := [navSummaryPath], files := [navFile] },
  { name := "nav-cta-webkit-match variant: sentence key reference",
    text := s!"Files: `{navSummaryPath}`. Entry settles at `summary.json` `chromiumVsWebkit['1280/entry/logical'].settledChanged` 145 px.",
    files := [navFile] },
  { name := "nav-cta-webkit-match variant: sentence key reference with the exit value",
    text := s!"Files: `{navSummaryPath}`. Entry settles at `summary.json` `chromiumVsWebkit['1280/entry/logical'].settledChanged` 153 px.",
    files := [navFile] },
  { name := "nav-cta-webkit-match variant: key not in the file",
    text := s!"`{navSummaryPath}` `chromiumVsWebkit['1280/entry/smooth'].settledChanged` 145 px.",
    files := [navFile] },
  { name := "nav-cta-webkit-match r2: a 1280 claim true for exit only (d547444e1), unchecked: no artifact key",
    text := "- **Other animated parts do not differ** (INFERRED from a local debug run, not a result; the CI frames of run " ++
      "40858439757 show the logical arm within 10 px of its settled floor at 1280): the unmask `mask-position` animation " ++
      "and the `::after` sheen" },
  { name := "end-floor-writes variant: verdict.txt quote with elided parts",
    text := s!"Source `{verdictPath}`: verdict.txt 'wktr-j2 v2p qwrite: floor 154 arm 114 ... cut 40 ... verdict carries'.",
    files := [verdictFile] },
  { name := "end-floor-writes variant: wktr-j1 numbers quoted under wktr-j2",
    text := s!"Source `{verdictPath}`: verdict.txt 'wktr-j2 v2p qwrite: floor 138 arm 133 ... cut 5'.",
    files := [verdictFile] },
  { name := "end-floor-writes variant: cut 4 is not cut 40",
    text := s!"Source `{verdictPath}`: verdict.txt 'wktr-j2 v2p qwrite: floor 154 ... cut 4'.",
    files := [verdictFile] },
  { name := "nav-cta-webkit-match variant: CONFIRMED with summary.json",
    text := "CONFIRMED summary.json `chromiumVsWebkit`: 1280/exit/logical maxChanged 163, settledChanged 153 (10)." },
  { name := "end-floor-writes (8fd84b2ba): CONFIRMED with a WebKit sha", text := "## Why (CONFIRMED, WebKit 862f17d, file:line)" },
  { name := "mistake-retro (f35b1de4e): CONFIRMED from local journals only",
    text := "- **Review-loop counts are CONFIRMED** from the workflow run journals (local-only, `ready_to_land: false`):" },
  { name := "nav-cta-webkit-match (12fe2a483): MEASURED with a run id",
    text := "## Results (MEASURED, run 40858439757, head 07a9b1285; Linux Chrome Headless Shell and Playwright WebKit)" },
  { name := "watch-memory r2: MEASURED with no run id and no committed path (e64ac7211)",
    text := "All numbers below are MEASURED local harness numbers of our own tool\n(not a site result), copies of " ++
      "`.fw-console/` read through `FW_CONSOLE_DIR`, `FW_WATCH_REAP=0`, `--interval 60`\n" ++
      "(stricter than the 300 s of the Monitor: more ticks per hour)." },
  { name := "watch-memory variant: MEASURED locally from a scratch sampler",
    text := "MEASURED locally: at most 289 MB (sampler `scratchpad/wm/sample.mjs`)." },
  { name := "watch-memory variant: MEASURED with a committed artifact",
    text := "MEASURED locally: at most 289 MB (`results/watch-memory/samples.json`).",
    committed := ["results/watch-memory/samples.json"] },
  { name := "watch-memory variant: MEASURED with an uncommitted artifact",
    text := "MEASURED locally: at most 289 MB (`results/watch-memory/samples.json`)." },
  { name := "end-floor-writes variant: INFERRED bound with its theorem",
    text := "INFERRED: a window whose frames each hold a recalc reads at least 100 per 100 frames, a lower bound (`rate_one_per_frame`)." },
  { name := "end-floor-writes variant: INFERRED bound without a theorem",
    text := "INFERRED: a window whose frames each hold a recalc reads at least 100 per 100 frames, a lower bound." },
  { name := "end-floor-writes r2: a Lesson generalized past j2 (42c52ed52 ledger), unchecked: no artifact key",
    text := "Lesson: The WebKit end-of-page floor is the flip's own running tracks (one recalc per frame), not a DOM write: " ++
      "silence the six listed writer sets and the floor stays, so a writer-level cut cannot lower it; cutting it means " ++
      "fewer or cheaper concurrent flip tracks, a look-change question." },
  { name := "end-floor-writes r2: frame counts for the wrong rows (42c52ed52), unchecked: no artifact key",
    text := "- j1 and j3: each rep window is 3 frames and holds 4 recalcs (frame counts 1, 1, 2: 32 frames with one recalc, 16 with\n" ++
      "  two, 0 with none, in `rs-flip-pall` and `rs-flip-qwrite` alike). The extra recalc per rep is also there with all\n" ++
      "  writers silenced (qwrite 133 and 135)." },
  { name := "fenced code is skipped", text := "```\nMEASURED 70 to 83: 83, 71, 81\n```\n" },
  { name := "geom-track-style: a claims legend carries all three tags",
    text := "Claims: CONFIRMED (source or Lean), MEASURED (CI run), INFERRED." },
  { name := "a tag inside a code span is a mention", text := "A `MEASURED` tag needs a run id." },
  { name := "circleci-series variant: a heading tag draws on its section",
    text := "## Result (MEASURED)\n\n- First land: run 40858439757 read Actions `operational`.\n" },
  { name := "circleci-series variant: a heading tag over a section with no run id",
    text := "## Result (MEASURED)\n\n- First land: the decision read Actions `operational`.\n" },
  { name := "pain-dark-scroll variant: a table row tag with no caption source",
    text := "| layer | base | arm | status |\n|---|---|---|---|\n| pseudo-element layers | none | 2, reason `animation`, backing 0 | MEASURED |\n" },
  { name := "pain-dark-scroll variant: a table row tag drawn from its caption",
    text := "Run 40858439757, layer tree dumps.\n\n| layer | base | arm | status |\n|---|---|---|---|\n| pseudo-element layers | none | 2, reason `animation`, backing 0 | MEASURED |\n" },
  { name := "init-cost-depth variant: arithmetic inside a code span is unchecked", text := "Each definition holds more than 256 elements (`5 * 256 + 1 = 1281` lets)." },
  { name := "carousel-swap-webkit variant: a chained sum is unchecked", text := "One cycle = 1250 + 900 + 900 = 3050 ms." },
  { name := "jev-replay variant: a percent result", text := "Owner share 65/116 = 56.0 % of the replayed steps." },
  { name := "jev-decision-model variant: a percent result without a space", text := "185/280 = 66% (modal owner per stream)." }]

def readCases : List Case := [
  { name := "reads: caption table file", text := navNote 145 },
  { name := "reads: verdict.txt quote", text := s!"Source `{verdictPath}`: verdict.txt 'wktr-j2 v2p qwrite: floor 154'." }]

def lintReq (c : Case) : Json := Json.mkObj [("op", "claims.lint"), ("text", c.text), ("committed", toJson c.committed),
  ("files", .arr (c.files.map contentJson).toArray)]

def readReq (c : Case) : Json := Json.mkObj [("op", "claims.reads"), ("text", c.text)]

def goldenLines (_ : Unit) : List String :=
  ((lintCases.map fun c => (c.name, lintReq c)) ++ (readCases.map fun c => (c.name, readReq c))).map fun (n, r) =>
    (Json.mkObj [("name", n), ("req", r), ("res", handle r)]).compress

/-- The exact bytes of `packages/contracts/golden/plan/claims.jsonl`. -/
def goldenText (_ : Unit := ()) : String := String.intercalate "" ((goldenLines ()).map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

partial def serve (inp : IO.FS.Stream) (out : IO.FS.Stream) : IO Unit := do
  let l ← inp.getLine
  if l.isEmpty then return
  let res := match Json.parse l with
    | .ok j => handle j
    | .error e => Json.mkObj [("error", e)]
  out.putStrLn res.compress
  out.flush
  serve inp out

/-- Driver: print the golden, `--check <file>` to compare bytes, or `--serve` to answer one JSON request per stdin line. -/
def run (args : List String) : IO UInt32 := do
  if args.contains "--serve" then
    serve (← IO.getStdin) (← IO.getStdout)
    return 0
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"claims golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"claims golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print (goldenText ())
    return 0


#guard parseDec "1.77".toList == some ⟨177, 2⟩
#guard parseDec "-5".toList == some ⟨-5, 0⟩
#guard parseDec "40%".toList == some ⟨40, 0⟩
#guard parseDec "v2p".toList == none
#guard parseDec "1.".toList == none
#guard roundQ ⟨152032, 1024⟩ 0 == 148
#guard roundQ ⟨152032, 1000⟩ 0 == 152
#guard roundQ ⟨512, 289⟩ 1 == 18
#guard roundQ ⟨-25, 10⟩ 0 == -3
#guard numOk ⟨148, 0⟩ ⟨152032, 1024⟩
#guard !numOk ⟨150, 0⟩ ⟨152032, 1024⟩
#guard numOk ⟨1, 0⟩ ⟨1, 2⟩
#guard rangeOk ⟨71, 1⟩ ⟨83, 1⟩ [⟨83, 1⟩, ⟨71, 1⟩, ⟨81, 1⟩]
#guard !rangeOk ⟨70, 1⟩ ⟨83, 1⟩ [⟨83, 1⟩, ⟨71, 1⟩, ⟨81, 1⟩]
#guard isPath "results/nav-cta-webkit-match/summary.json".toList
#guard isPath "watch-mem.test.ts:240-250".toList
#guard isPath "apps/runner".toList
#guard !isPath "MB/min".toList
#guard !isPath "chromiumVsWebkit['1280/entry/logical'].settledChanged".toList
#guard isSha "07a9b1285".toList && !isSha "1152".toList
#guard isRunId "40858439757".toList && !isRunId "3000".toList
#guard isTheorem "rate_one_per_frame".toList && isTheorem "Fw.Plan.Claims.numOk".toList && !isTheorem "MB".toList
#guard isScratch "/private/tmp/x/scratchpad/wm/sample.mjs".toList && !isScratch "results/a.json".toList
#guard parseKey "chromiumVsWebkit['1280/entry/logical'].settledChanged".toList ==
  some [.field "chromiumVsWebkit", .field "1280/entry/logical", .field "settledChanged"]
#guard parseKey "rows[3].rs.wins".toList == some [.field "rows", .index 3, .field "rs", .field "wins"]
#guard parseKey "rows[rs-flip-pall]".toList == some [.field "rows", .field "rs-flip-pall"]
#guard parseKey "x[".toList == none
#guard claimOk .measured ⟨false, true, false, false, false, false⟩
#guard !claimOk .measured ⟨true, false, false, false, false, false⟩
#guard !claimOk .measured ⟨true, true, true, true, false, false⟩
#guard claimOk .inferred ⟨false, false, false, false, false, false⟩
#guard !claimOk .confirmed ⟨false, false, false, false, false, false⟩
#guard !claimOk .confirmed ⟨true, false, false, false, true, false⟩
#guard (sentences ⟨1, .prose, ["- One a.b 1.5 MB.", "Two (x). three"]⟩).map (·.1) == [1, 2]
#guard (blocks "a\n\n| x |\n|---|\n| 1 |\n```\nMEASURED\n```\n- b").map (·.line) == [1, 3, 9]
#guard (lint "MEASURED locally: at most 289 MB (sampler `sample.mjs`, scratch)." [] []).map (·.code) == ["measuredNoSource"]
#guard (lint "MEASURED, run 40858439757: inside the bound." [] []).map (·.code) == ["boundNoTheorem"]
#guard (lint "Before min 152032/1000 = 148." [] []).map (·.code) == ["arithMismatch"]
#guard (lint "Before min 152032/1024 = 148, ratio 512 / 289 = 1.77." [] []).map (·.code) == []
#guard (lint "Share 1/4 = 25 %." [] []).map (·.code) == []
#guard (lint "Sum 2 \\cdot 8 + 4 = 20." [] []).map (·.code) == []
#guard (lint "`1 / 2 = 0` in Nat." [] []).map (·.code) == []
#guard (lint "Claims: CONFIRMED (source), MEASURED (CI run), INFERRED." [] []).map (·.code) == []
#guard (lint "# H (MEASURED)\n\nRun 123456789." [] []).map (·.code) == []
#guard (lint "# H (MEASURED)\n\nNo run." [] []).map (·.code) == ["measuredNoSource"]
#guard (tokens "**CONFIRMED** x".toList).map (·.s) == ["CONFIRMED".toList, ['x']]
#guard (tokens "a `b` c".toList).map (·.code) == [false, true, false]

end Fw.Plan.Claims
