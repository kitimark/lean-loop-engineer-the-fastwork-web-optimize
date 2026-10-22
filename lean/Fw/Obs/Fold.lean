import Lean.Data.Json
open Lean (Json toJson)
/-!
# `Fw.Obs.Fold`: reading a transcript as a fold over its lines, and resuming it from saved state

`fw watch` summarizes each transcript (`summarizeTranscript`, `signalsOf`) as one pass over its lines. The pass is a
`List.foldl` of a step over the non-empty lines. A transcript only grows, so the state after the first `a` bytes can
be saved and the next pass reads only the appended bytes. This file proves that this equals reading the whole file
(`pass_eq_full`) and decides when a saved state may be resumed (`decide`). The step body (JSON to fields) is TS.
-/

namespace Fw.Obs.Fold

/-- The byte of `\n`. -/
def nl : Nat := 10

/-- The pieces between newlines, empty ones kept; `cur` is the open piece, reversed. The last piece is the unterminated tail. -/
def split (cur : List Nat) : List Nat → List (List Nat)
  | [] => [cur.reverse]
  | b :: bs => if b = nl then cur.reverse :: split [] bs else split (b :: cur) bs

/-- The non-empty lines of a byte string, the unterminated tail included. -/
def lines (bs : List Nat) : List (List Nat) := (split [] bs).filter (fun l => !l.isEmpty)

/-- The pieces a prefix closes with its newline (the open piece `cur` first). -/
def closed (cur : List Nat) : List Nat → List (List Nat)
  | [] => [cur.reverse]
  | b :: bs => if b = nl then cur.reverse :: closed [] bs else closed (b :: cur) bs

theorem split_closed (p : List Nat) : ∀ cur b, split cur (p ++ nl :: b) = closed cur p ++ split [] b := by
  induction p with
  | nil => intro cur b; simp [split, closed, nl]
  | cons c p ih =>
    intro cur b
    by_cases h : c = nl
    · simp [split, closed, h, ih]
    · simp [split, closed, h, ih]

/-- `bs` is empty or ends with a newline: a whole number of lines. -/
def Complete (bs : List Nat) : Prop := bs = [] ∨ ∃ p, bs = p ++ [nl]

theorem lines_nil : lines [] = [] := by simp [lines, split]

theorem lines_closed (p : List Nat) (b : List Nat) :
    lines (p ++ nl :: b) = (closed [] p).filter (fun l => !l.isEmpty) ++ lines b := by
  simp [lines, split_closed, List.filter_append]

/-- The lines of a whole number of lines followed by more bytes are the lines of each (the cut falls on a line end). -/
theorem lines_append {a : List Nat} (h : Complete a) (b : List Nat) : lines (a ++ b) = lines a ++ lines b := by
  rcases h with rfl | ⟨p, rfl⟩
  · simp [lines_nil]
  · have h1 : p ++ [nl] ++ b = p ++ nl :: b := by simp
    have h2 : p ++ [nl] = p ++ nl :: [] := rfl
    rw [h1, lines_closed]
    rw [h2, lines_closed, lines_nil]
    simp

/-- Fold a step over the lines of a byte string. -/
def feed {σ : Type} (step : σ → List Nat → σ) (s : σ) (bs : List Nat) : σ := (lines bs).foldl step s

/-- The append lemma: after a whole number of lines, reading the rest on top of the state equals reading all. -/
theorem feed_append {σ : Type} (step : σ → List Nat → σ) (s : σ) {a : List Nat} (h : Complete a) (b : List Nat) :
    feed step s (a ++ b) = feed step (feed step s a) b := by
  simp [feed, lines_append h, List.foldl_append]

/-- The part of the appended bytes that ends with the last newline, and the unterminated tail after it. -/
def cut (bs : List Nat) : List Nat × List Nat :=
  (((bs.reverse).dropWhile (fun b => b != nl)).reverse, ((bs.reverse).takeWhile (fun b => b != nl)).reverse)

theorem cut_append (bs : List Nat) : (cut bs).1 ++ (cut bs).2 = bs := by
  have := List.takeWhile_append_dropWhile (p := fun b => b != nl) (l := bs.reverse)
  unfold cut
  rw [← List.reverse_append, this, List.reverse_reverse]

theorem cut_complete (bs : List Nat) : Complete (cut bs).1 := by
  unfold cut Complete
  generalize bs.reverse = r
  induction r with
  | nil => simp
  | cons b r ih =>
    by_cases h : b = nl
    · right; exact ⟨(r).reverse, by simp [List.dropWhile, h]⟩
    · have h' : (b != nl) = true := by simpa using h
      simpa [List.dropWhile, h'] using ih

theorem takeWhile_nl (r : List Nat) : nl ∉ r.takeWhile (fun b => b != nl) := by
  induction r with
  | nil => simp
  | cons b r ih =>
    by_cases h : b = nl
    · simp [List.takeWhile, h]
    · have h' : (b != nl) = true := by simpa using h
      simp [List.takeWhile, h', ih, Ne.symm h]

theorem cut_tail (bs : List Nat) : nl ∉ (cut bs).2 := by
  unfold cut
  simpa using takeWhile_nl bs.reverse

theorem complete_append {a c : List Nat} (ha : Complete a) (hc : Complete c) : Complete (a ++ c) := by
  rcases hc with rfl | ⟨p, rfl⟩
  · simpa using ha
  · exact Or.inr ⟨a ++ p, by simp⟩

/-- One pass over the saved state and the bytes appended since: the pass reads the complete lines into the state and the
unterminated tail only into its result; the complete lines are what the next pass starts from. -/
theorem pass_eq_full {σ : Type} (step : σ → List Nat → σ) (init : σ) {a : List Nat} (ha : Complete a) (b : List Nat) :
    feed step (feed step (feed step init a) (cut b).1) (cut b).2 = feed step init (a ++ b) := by
  have e : a ++ b = a ++ ((cut b).1 ++ (cut b).2) := by rw [cut_append]
  rw [e, feed_append step init ha, feed_append step _ (cut_complete b)]

/-- The saved offset stays a whole number of lines, and the saved state is the fold of exactly the bytes before it. -/
theorem resume_inv {σ : Type} (step : σ → List Nat → σ) (init : σ) {a : List Nat} (ha : Complete a) (b : List Nat) :
    Complete (a ++ (cut b).1) ∧ feed step (feed step init a) (cut b).1 = feed step init (a ++ (cut b).1) :=
  ⟨complete_append ha (cut_complete b), (feed_append step init ha _).symm⟩

/-- A pass: the new saved state with its bytes, from the old ones and the appended bytes. -/
def advance {σ : Type} (step : σ → List Nat → σ) (st : σ × List Nat) (b : List Nat) : σ × List Nat :=
  (feed step st.1 (cut b).1, st.2 ++ (cut b).1)

/-- Any number of passes keep the invariant: the saved state is the fold of the saved bytes, a whole number of lines. -/
theorem chain_inv {σ : Type} (step : σ → List Nat → σ) (init : σ) (chunks : List (List Nat)) :
    Complete (chunks.foldl (advance step) (init, [])).2 ∧
      (chunks.foldl (advance step) (init, [])).1 = feed step init (chunks.foldl (advance step) (init, [])).2 := by
  have gen : ∀ (cs : List (List Nat)) (st : σ × List Nat), Complete st.2 → st.1 = feed step init st.2 →
      Complete (cs.foldl (advance step) st).2 ∧ (cs.foldl (advance step) st).1 = feed step init (cs.foldl (advance step) st).2 := by
    intro cs
    induction cs with
    | nil => intro st h1 h2; exact ⟨h1, h2⟩
    | cons b cs ih =>
      intro st h1 h2
      apply ih
      · exact complete_append h1 (cut_complete b)
      · simp only [advance]; rw [h2]; exact (feed_append step init h1 _).symm
  exact gen chunks (init, []) (Or.inl rfl) (by simp [feed, lines_nil])

/-! ### When a saved state may be resumed -/

/-- What the saved state was written for and where it stopped: the schema and code it was made with, the file's inode,
and the offset (a whole number of lines). -/
structure Entry where
  schema : Nat
  code : String
  ino : Nat
  offset : Nat
deriving DecidableEq, Repr

/-- The file and code now: the schema and code hash, the file's inode and size. -/
structure Now where
  schema : Nat
  code : String
  ino : Nat
  size : Nat
deriving DecidableEq, Repr

/-- Read from the saved offset, or read the whole file. -/
inductive Mode where
  | resume (offset : Nat)
  | full
deriving DecidableEq, Repr

/-- `anchorSame`: the bytes just before the offset are the ones saved with the state. Any failed check reads the whole file. -/
def decide (e : Entry) (n : Now) (anchorSame : Bool) : Mode :=
  if e.schema ≠ n.schema then .full
  else if e.code ≠ n.code then .full
  else if n.size < e.offset then .full
  else if e.ino ≠ n.ino then .full
  else if anchorSame = false then .full
  else .resume e.offset

theorem decide_schema (e : Entry) (n : Now) (a : Bool) (h : e.schema ≠ n.schema) : decide e n a = .full := by
  simp [decide, h]

theorem decide_code (e : Entry) (n : Now) (a : Bool) (h : e.code ≠ n.code) : decide e n a = .full := by
  simp [decide, h]

theorem decide_shrunk (e : Entry) (n : Now) (a : Bool) (h : n.size < e.offset) : decide e n a = .full := by
  simp [decide, h]

theorem decide_inode (e : Entry) (n : Now) (a : Bool) (h : e.ino ≠ n.ino) : decide e n a = .full := by
  simp [decide, h]

theorem decide_anchor (e : Entry) (n : Now) : decide e n false = .full := by
  simp [decide]

/-- Resuming happens exactly when nothing above failed, and then the offset is inside the file. -/
theorem decide_resume_iff (e : Entry) (n : Now) (a : Bool) :
    decide e n a = .resume e.offset ↔
      e.schema = n.schema ∧ e.code = n.code ∧ e.offset ≤ n.size ∧ e.ino = n.ino ∧ a = true := by
  unfold decide
  by_cases h1 : e.schema = n.schema <;> by_cases h2 : e.code = n.code <;> by_cases h3 : n.size < e.offset <;>
    by_cases h4 : e.ino = n.ino <;> cases a <;> simp [*] <;> omega

structure Call where
  id : String
  msg : String
  tool : String
  ts : Nat
deriving DecidableEq, Repr

structure Open where
  newest : Option String := none
  calls : List Call := []
deriving DecidableEq, Repr

inductive Ev where
  | assistant (msg : String) (calls : List (String × String × Nat))
  | result (id : String)
deriving DecidableEq, Repr

def stepEv (s : Open) : Ev → Open
  | .assistant m cs => ⟨some m, s.calls.filter (·.msg == m) ++ cs.map (fun x => ⟨x.1, m, x.2.1, x.2.2⟩)⟩
  | .result i => { s with calls := s.calls.filter (·.id != i) }

def inflightOf (s : Open) : Option Call :=
  s.calls.foldl (fun r c => match r with | none => some c | some p => if p.ts ≤ c.ts then some c else some p) none

theorem assistant_clears (s : Open) (m : String) (cs : List (String × String × Nat)) :
    ∀ c ∈ (stepEv s (.assistant m cs)).calls, c.msg = m := by
  intro c hc
  simp only [stepEv, List.mem_append, List.mem_filter, List.mem_map] at hc
  rcases hc with ⟨_, h⟩ | ⟨⟨_, _, _⟩, _, rfl⟩
  · simpa using h
  · rfl

theorem older_call_gone (s : Open) (m : String) (cs : List (String × String × Nat)) (c : Call) (h : c.msg ≠ m) :
    c ∉ (stepEv s (.assistant m cs)).calls := fun hc => h (assistant_clears s m cs c hc)

theorem assistant_nocalls (s : Open) (m : String) (h : ∀ c ∈ s.calls, c.msg ≠ m) :
    inflightOf (stepEv s (.assistant m [])) = none := by
  have : (stepEv s (.assistant m [])).calls = [] := by
    simp only [stepEv, List.map_nil, List.append_nil]
    exact List.filter_eq_nil_iff.mpr fun c hc => by simpa using h c hc
  simp [inflightOf, this]

theorem same_msg_keeps (s : Open) (m : String) (cs : List (String × String × Nat)) (c : Call)
    (hc : c ∈ s.calls) (hm : c.msg = m) : c ∈ (stepEv s (.assistant m cs)).calls := by
  simp only [stepEv, List.mem_append, List.mem_filter]
  exact Or.inl ⟨hc, by simp [hm]⟩

theorem inflight_resume (a b : List Ev) :
    inflightOf (b.foldl stepEv (a.foldl stepEv {})) = inflightOf ((a ++ b).foldl stepEv {}) := by
  rw [List.foldl_append]

theorem open_pass_eq_full (rd : List Nat → Ev) {a : List Nat} (ha : Complete a) (b : List Nat) :
    feed (fun s l => stepEv s (rd l)) (feed (fun s l => stepEv s (rd l)) (feed (fun s l => stepEv s (rd l)) {} a) (cut b).1) (cut b).2
      = feed (fun s l => stepEv s (rd l)) {} (a ++ b) :=
  pass_eq_full _ _ ha b

def inflightCases : List (String × List Ev × Option (String × Nat)) :=
  let u (m i t : String) (a : Nat) : Ev := .assistant m [(i, t, a)]
  [("no records", [], none),
   ("one call open", [u "m1" "c1" "Bash" 10], some ("Bash", 10)),
   ("call closed by its result", [u "m1" "c1" "Bash" 10, .result "c1"], none),
   ("missing result: the next assistant message clears it", [u "m1" "c1" "Bash" 10, u "m2" "c2" "Read" 20, .result "c2"], none),
   ("missing result: the next message's own call is the one in flight", [u "m1" "c1" "Bash" 10, u "m2" "c2" "Read" 20], some ("Read", 20)),
   ("missing result: a closing text message clears it", [u "m1" "c1" "Bash" 10, .assistant "m2" []], none),
   ("parallel calls of one message stay open together", [.assistant "m1" [("c1", "Bash", 10), ("c2", "Read", 12)]], some ("Read", 12)),
   ("parallel calls: one result leaves the other open", [.assistant "m1" [("c1", "Bash", 10), ("c2", "Read", 12)], .result "c2"], some ("Bash", 10)),
   ("streamed copies of one message share its id and add up", [u "m1" "c1" "Bash" 10, u "m1" "c2" "Read" 11], some ("Read", 11)),
   ("results out of order", [.assistant "m1" [("c1", "Bash", 10), ("c2", "Read", 12)], .result "c1", .result "c2"], none),
   ("an unknown result changes nothing", [u "m1" "c1" "Bash" 10, .result "zz"], some ("Bash", 10)),
   ("tie in time: the later call", [.assistant "m1" [("c1", "Bash", 10), ("c2", "Read", 10)]], some ("Read", 10))]

#guard inflightCases.all fun (_, evs, e) =>
  (inflightOf (evs.foldl stepEv {})).map (fun c => (c.tool, c.ts)) == e

def evJson : Ev → Json
  | .assistant m cs => Json.mkObj [("k", .str "assistant"), ("msg", .str m),
      ("calls", Json.arr (cs.toArray.map fun (i, t, a) => Json.mkObj [("id", .str i), ("tool", .str t), ("at", toJson a)]))]
  | .result i => Json.mkObj [("k", .str "result"), ("id", .str i)]

def inflightGoldenText : String :=
  String.join (inflightCases.map fun (name, evs, e) =>
    (Json.mkObj [("name", .str name), ("events", Json.arr (evs.toArray.map evJson)),
      ("expect", match e with | none => Json.null | some (t, a) => Json.mkObj [("tool", .str t), ("since", toJson a)])]).compress ++ "\n")

def inflightGoldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "watch-inflight.jsonl"

/-! ### Golden vectors (`packages/contracts/golden/obs/watch-fold.jsonl`) -/

/-- The UTF-8 bytes of a text, as the file holds them. -/
def bytesOf (t : String) : List Nat := t.toUTF8.toList.map (·.toNat)

/-- Texts for `cut`: whole lines, a torn tail, no newline, blank lines, a multi-byte character. -/
def cutCases : List (String × String) := [
  ("empty file", ""), ("one whole line", "{\"a\":1}\n"), ("two whole lines", "a\nb\n"),
  ("a torn last line", "a\nb\n{\"c\":"), ("no newline at all", "{\"a\":1}"), ("only a newline", "\n"),
  ("blank lines are not lines", "\n\na\n\n"), ("a torn line after blanks", "a\n\n\nb"),
  ("a multi-byte character counts in bytes", "\"é\"\nx"), ("a multi-byte character in a whole line", "\"é\"\n")]

/-- Cases for `decide`: name, entry, now, anchorSame. -/
def decideCases : List (String × Entry × Now × Bool) :=
  let e : Entry := { schema := 1, code := "c1", ino := 7, offset := 100 }
  let n : Now := { schema := 1, code := "c1", ino := 7, size := 150 }
  [("grown: resume at the saved offset", e, n, true), ("unchanged size: resume, nothing to read", e, { n with size := 100 }, true),
   ("one byte short of the offset: full", e, { n with size := 99 }, true), ("empty saved state on a new file: resume at 0", { e with offset := 0 }, { n with size := 0 }, true),
   ("other schema: full", e, { n with schema := 2 }, true), ("other code hash: full", e, { n with code := "c2" }, true),
   ("other inode: full", e, { n with ino := 8 }, true), ("bytes before the offset differ: full", e, n, false),
   ("shrunk and other inode: full", e, { n with size := 10, ino := 9 }, true)]

/-- The lines of the golden file. -/
def goldenText : String :=
  String.join (cutCases.map fun (name, t) =>
    let bs := bytesOf t
    let (c, tl) := cut bs
    (Json.mkObj [("name", .str name), ("kind", .str "cut"), ("text", .str t), ("consumed", toJson c.length),
      ("tail", toJson tl.length), ("lines", toJson (lines bs).length)]).compress ++ "\n") ++
  String.join (decideCases.map fun (name, e, n, a) =>
    let m := match decide e n a with
      | .resume o => Json.mkObj [("mode", .str "resume"), ("offset", toJson o)]
      | .full => Json.mkObj [("mode", .str "full")]
    (Json.mkObj [("name", .str name), ("kind", .str "decide"),
      ("entry", Json.mkObj [("schema", toJson e.schema), ("code", .str e.code), ("ino", toJson e.ino), ("offset", toJson e.offset)]),
      ("now", Json.mkObj [("schema", toJson n.schema), ("code", .str n.code), ("ino", toJson n.ino), ("size", toJson n.size)]),
      ("anchorSame", toJson a), ("expect", m)]).compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "watch-fold.jsonl"

#guard (cut (bytesOf "a\nb")).1.length == 2 && (cut (bytesOf "a\nb")).2.length == 1
#guard (lines (bytesOf "\n\na\n\n")).length == 1

end Fw.Obs.Fold
