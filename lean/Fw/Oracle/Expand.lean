import Lean.Data.Json
import Fw.Oracle.Replay
/-! The D1 row with the repo files it names: allowlisted code files only, a file holding a label word dropped whole,
whole files kept in path order while the state fits its cap, never cut. Design: research/notes/2026/10-2x-jev-file-context.md. -/
namespace Fw.Oracle.Expand
open Fw.Oracle

/-! ## Paths a row names -/

/-- The top-level repo directories a path may start with, in the order the scan tries them. -/
def tops : List String :=
  ["research", "docs", "lean", "lean-math", "apps", "packages", "scripts", ".github", ".claude", ".circleci", "refs",
   "results", "snapshot", ".cache", ".local"]

def bodyChar (c : Char) : Bool := c.isAlphanum || "_.@*{}<>,/+-".toList.contains c

def endChar (c : Char) : Bool := c.isAlphanum || "_*}>".toList.contains c

/-- A path may start after this character (or at the start of the text). -/
def headOk : Option Char → Bool
  | none => true
  | some c => !(c.isAlphanum || "_./-".toList.contains c)

/-- The longest run of path characters that ends on an end character. -/
def tailRun (l : List Char) : List Char :=
  ((l.takeWhile bodyChar).reverse.dropWhile (!endChar ·)).reverse

/-- A top directory, a slash and a nonempty tail at the head of `l`: the first top that matches. -/
def topMatch (l : List Char) : Option (List Char) :=
  tops.findSome? fun t =>
    let p := t.toList ++ ['/']
    if p.isPrefixOf l then
      match tailRun (l.drop p.length) with
      | [] => none
      | r => some (p ++ r)
    else none

def upDir : List Char := "../".toList

/-- The path at the head of `l`, with a leading `../` when one matches. -/
def matchAt (l : List Char) : Option (List Char) :=
  (if upDir.isPrefixOf l then (topMatch (l.drop 3)).map (upDir ++ ·) else none) <|> topMatch l

/-- Every path in a text, left to right, a match never overlapping the one before. -/
def scan : Nat → Option Char → List Char → List (List Char)
  | 0, _, _ => []
  | _, _, [] => []
  | f + 1, prev, c :: cs =>
    match (if headOk prev then matchAt (c :: cs) else none) with
    | some m => m :: scan f m.getLast? ((c :: cs).drop m.length)
    | none => scan f (some c) cs

def isHex (c : Char) : Bool := c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'f'))

/-- A path as a repo path: no leading `../`, no trailing `@<sha>` of 7 to 40 hex digits. -/
def resolve (l : List Char) : String :=
  let l := if upDir.isPrefixOf l then l.drop 3 else l
  let tail := (l.reverse.takeWhile (· != '@')).reverse
  let sha := tail.length < l.length && 7 ≤ tail.length && tail.length ≤ 40 && tail.all isHex
  String.ofList (if sha then l.take (l.length - tail.length - 1) else l)

/-- The list without repeats, each kept at its first place. -/
def dedup (l : List String) : List String := l.foldl (fun acc x => if acc.contains x then acc else acc ++ [x]) []

/-- The repo paths the texts name, in first-seen order. -/
def pathsOf (texts : List String) : List String :=
  dedup (texts.flatMap fun t => (scan t.length none t.toList).map resolve)

#guard pathsOf ["see scripts/checkmap.mjs:2 and lean/Fw/Sched/Admit.lean."] == ["scripts/checkmap.mjs", "lean/Fw/Sched/Admit.lean"]
#guard pathsOf ["../apps/runner/hooks/wait-guard.mjs@ecdc0787, x"] == ["apps/runner/hooks/wait-guard.mjs"]
#guard pathsOf ["lean-math/a.md docs/ x/scripts/y.mjs scripts/z-.mjs"] == ["lean-math/a.md", "scripts/z-.mjs"]
#guard pathsOf ["`.github/workflows/lean.yml` and research/notes/*.md"] == [".github/workflows/lean.yml", "research/notes/*.md"]
#guard pathsOf ["apps/a.ts apps/a.ts", "apps/a.ts@1234567"] == ["apps/a.ts"]

/-! ## Which files are kept -/

/-- Where a kept file may live and what it may be: path prefixes, refused prefixes, extensions; and whether a file
holding a vocabulary word is dropped. -/
structure Cfg where
  prefixes : List String
  deny : List String
  exts : List String
  dropVocab : Bool
deriving Repr, DecidableEq

/-- The leak-safe arm: code only, never `lean/Fw/Oracle/`, vocabulary dropped. -/
def safe : Cfg :=
  { prefixes := ["apps/", "packages/", "scripts/", "lean/Fw/"], deny := ["lean/Fw/Oracle/"],
    exts := [".lean", ".ts", ".tsx", ".mjs", ".js", ".sh", ".yaml"], dropVocab := true }

/-- The naive contrast arm: every text file the row names, under any top directory, no vocabulary drop. -/
def naive : Cfg := { prefixes := tops.map (· ++ "/"), deny := [], exts := [""], dropVocab := false }

def isPattern (p : List Char) : Bool := p.any ("*{}<>".toList.contains ·)

/-- The path is on the allowlist: a prefix, no refused prefix, an extension, no glob character. -/
def allowed (c : Cfg) (p : String) : Bool :=
  let l := p.toList
  c.prefixes.any (·.toList.isPrefixOf l) && !c.deny.any (·.toList.isPrefixOf l) &&
    c.exts.any (·.toList.isSuffixOf l) && !isPattern l

theorem allowed_ledger : allowed safe "docs/team/incidents/ledger.json" = false := by decide
theorem allowed_graph : allowed safe "docs/team/work-graph.json" = false := by decide
theorem allowed_labels : allowed safe "lean/Fw/Oracle/Labels.lean" = false := by decide
theorem allowed_research : allowed safe "research/notes/2026/10-2x-jev-file-context.md" = false := by decide
theorem allowed_checkmap : allowed safe "scripts/checkmap.mjs" = true := by decide
theorem allowed_naive_graph : allowed naive "docs/team/work-graph.json" = true := by decide
theorem allowed_naive_pattern : allowed naive "research/notes/*.md" = false := by decide

/-- The label vocabulary of a row: every mistake class, every written grade word, and the row id. -/
def vocab (id : String) : List String := Labels.mistakeClasses ++ Labels.exactWords ++ [id]

def lower (s : String) : List Char := s.toList.map Char.toLower

/-- The first vocabulary word the text holds, ignoring case. -/
def hit (id text : String) : Option String :=
  let t := lower text
  (vocab id).find? fun w => occurs (lower w) t

/-- Why a named file is not kept. -/
inductive Drop where
  | notAllowed
  | noText
  | vocab (word : String)
deriving Repr, DecidableEq

/-- A named file's verdict: its text, kept whole, or why it is dropped. -/
def verdict (c : Cfg) (id p : String) : Option String → Except Drop String
  | none => if allowed c p then .error .noText else .error .notAllowed
  | some t =>
    if !allowed c p then .error .notAllowed
    else if c.dropVocab then
      match hit id t with
      | some w => .error (.vocab w)
      | none => .ok t
    else .ok t

/-- The kept files with their texts, in path order. -/
def kept (c : Cfg) (id : String) (files : List (String × Option String)) : List (String × String) :=
  files.filterMap fun (p, t) => (verdict c id p t).toOption.map (p, ·)

theorem verdict_ok {c : Cfg} {id p : String} {t : Option String} {x : String} (h : verdict c id p t = .ok x) :
    allowed c p = true ∧ t = some x ∧ (c.dropVocab = true → hit id x = none) := by
  cases t with
  | none => simp only [verdict] at h; split at h <;> simp at h
  | some t =>
    by_cases ha : allowed c p = true
    · by_cases hv : c.dropVocab = true
      · cases hh : hit id t with
        | some w => simp [verdict, ha, hv, hh] at h
        | none =>
          simp only [verdict, ha, hv, hh, Bool.not_true, Bool.false_eq_true, ↓reduceIte, Except.ok.injEq] at h
          subst h
          exact ⟨ha, rfl, fun _ => hh⟩
      · simp only [verdict, ha, hv, Bool.not_true, Bool.false_eq_true, ↓reduceIte, Except.ok.injEq] at h
        subst h
        exact ⟨ha, rfl, fun h' => absurd h' hv⟩
    · simp [verdict, ha] at h

theorem mem_kept {c : Cfg} {id p x : String} {files : List (String × Option String)} (h : (p, x) ∈ kept c id files) :
    (p, some x) ∈ files ∧ verdict c id p (some x) = .ok x := by
  obtain ⟨⟨p', t⟩, hm, he⟩ := List.mem_filterMap.mp h
  cases hv : verdict c id p' t with
  | error e => simp [hv, Except.toOption] at he
  | ok y =>
    simp only [hv, Except.toOption, Option.map_some, Option.some.injEq, Prod.mk.injEq] at he
    obtain ⟨rfl, rfl⟩ := he
    obtain ⟨_, rfl, _⟩ := verdict_ok hv
    exact ⟨hm, hv⟩

theorem kept_allowed {c : Cfg} {id p x : String} {files : List (String × Option String)}
    (h : (p, x) ∈ kept c id files) : allowed c p = true :=
  (verdict_ok (mem_kept h).2).1

theorem kept_whole {c : Cfg} {id p x : String} {files : List (String × Option String)}
    (h : (p, x) ∈ kept c id files) : (p, some x) ∈ files :=
  (mem_kept h).1

theorem kept_vocabFree {c : Cfg} {id p x : String} {files : List (String × Option String)} (hc : c.dropVocab = true)
    (h : (p, x) ∈ kept c id files) : ∀ w ∈ vocab id, ¬ ∃ u v, lower x = u ++ lower w ++ v := by
  have hn := (verdict_ok (mem_kept h).2).2.2 hc
  intro w hw hex
  unfold hit at hn
  have := List.find?_eq_none.mp hn w hw
  exact this ((occurs_iff _ _).mpr hex)

theorem naive_keeps {id p x : String} (h : allowed naive p = true) : verdict naive id p (some x) = .ok x := by
  simp only [verdict, h, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  rfl

#guard (kept safe "inc-x" [("scripts/a.mjs", some "x c-late-check y"), ("scripts/b.mjs", some "ok"),
  ("docs/team/work-graph.json", some "ok"), ("apps/c.ts", none), ("lean/Fw/d.lean", some "INC-X")]) == [("scripts/b.mjs", "ok")]
#guard (kept naive "inc-x" [("scripts/a.mjs", some "x c-late-check y")]) == [("scripts/a.mjs", "x c-late-check y")]
#guard match verdict safe "i" "scripts/a.mjs" (some "a Follow-Up b") with
  | .error (.vocab "follow-up") => true
  | _ => false

/-! ## The expanded row and the cap -/

/-- The `files` text: a header line per kept file, then the file whole. -/
def filesText (ks : List (String × String)) : String :=
  "\n".intercalate (ks.map fun (p, t) => "file: " ++ p ++ "\n" ++ t)

/-- The row with a `files` field holding `ks`, or the row itself when `ks` is empty. -/
def withFiles (row : List (String × String)) : List (String × String) → List (String × String)
  | [] => row
  | ks => row ++ [("files", filesText ks)]

/-- The row with every kept file. -/
def expandRow (c : Cfg) (id : String) (row : List (String × String)) (files : List (String × Option String)) :
    List (String × String) :=
  withFiles row (kept c id files)

/-- The bytes JSON escaping adds to a character (Lean's `Json.escape`: `\"`, `\\`, `\n`, `\r`, other controls `\uXXXX`). -/
def escExtra (c : Char) : Nat :=
  if c == '"' || c == '\\' || c == '\n' || c == '\r' then 1 else if c.toNat < 0x20 then 5 else 0

def escBytes (s : String) : Nat := (s.toList.map fun c => c.utf8Size + escExtra c).sum

/-- The JSON-escaped bytes of the lines of a state. -/
def stateEsc (S : State) : Nat := (S.map fun kl => (kl.2.map escBytes).sum).sum

#guard ["a\"b\\c", "tab\there", "ü日\r\n", "\x01"].all fun s =>
  escBytes s + 2 == ((Lean.Json.str s).compress.toList.map Char.utf8Size).sum

/-- The escaped state size of the row with `ks`. -/
def sizeWith (row : List (String × String)) (ks : List (String × String)) : Nat := stateEsc (rowState d1 (withFiles row ks))

/-- Whole-file fit: walk the files in path order and keep each one the row still fits `stateCap` with. -/
def fit (row : List (String × String)) : List (String × String) → List (String × String) → List (String × String)
  | acc, [] => acc
  | acc, f :: fs => if sizeWith row (acc ++ [f]) ≤ stateCap then fit row (acc ++ [f]) fs else fit row acc fs

/-- The result of expanding one row: the files that fit and the escaped size, or the size with every kept file when not
one fits. -/
inductive Result where
  | same
  | expanded (files : List (String × String)) (esc : Nat)
  | refused (esc : Nat)
deriving Repr, DecidableEq

/-- Expand a row: unchanged when nothing is kept, else the files that fit `stateCap`, else refused. -/
def expand (c : Cfg) (id : String) (row : List (String × String)) (paths : List String)
    (blob : String → Option String) : Result :=
  let ks := kept c id (paths.map fun p => (p, blob p))
  if ks = [] then .same
  else match fit row [] ks with
    | [] => .refused (sizeWith row ks)
    | fs => .expanded fs (sizeWith row fs)

theorem expandRow_noop {c : Cfg} {id : String} {row : List (String × String)} {files : List (String × Option String)}
    (h : kept c id files = []) : expandRow c id row files = row := by
  simp [expandRow, withFiles, h]

theorem fit_mem {row : List (String × String)} : ∀ {acc fs : List (String × String)} {x : String × String},
    x ∈ fit row acc fs → x ∈ acc ∨ x ∈ fs
  | _, [], _, h => .inl h
  | acc, f :: fs, x, h => by
    unfold fit at h
    split at h
    · rcases fit_mem h with h | h
      · rcases List.mem_append.mp h with h | h
        · exact .inl h
        · exact .inr (by simp_all)
      · exact .inr (List.mem_cons_of_mem _ h)
    · rcases fit_mem h with h | h
      · exact .inl h
      · exact .inr (List.mem_cons_of_mem _ h)

theorem fit_fits {row : List (String × String)} : ∀ {acc fs : List (String × String)},
    (acc = [] ∨ sizeWith row acc ≤ stateCap) → fit row acc fs = [] ∨ sizeWith row (fit row acc fs) ≤ stateCap
  | _, [], h => h
  | acc, f :: fs, h => by
    unfold fit
    split
    · exact fit_fits (.inr (by assumption))
    · exact fit_fits h

theorem fit_ne_nil {row : List (String × String)} : ∀ {acc fs : List (String × String)}, acc ≠ [] → fit row acc fs ≠ []
  | _, [], h => h
  | acc, f :: fs, h => by
    unfold fit
    split
    · exact fit_ne_nil (by simp)
    · exact fit_ne_nil h

/-- Not one file fits alone when the fit from nothing keeps nothing. -/
theorem fit_nil {row : List (String × String)} : ∀ {fs : List (String × String)}, fit row [] fs = [] →
    ∀ f ∈ fs, stateCap < sizeWith row [f]
  | [], _ => by simp
  | f :: fs, h => by
    unfold fit at h
    split at h
    · exact absurd h (fit_ne_nil (by simp))
    · rename_i hf
      intro g hg
      rcases List.mem_cons.mp hg with rfl | hg
      · simpa using hf
      · exact fit_nil h g hg

theorem expand_same {c : Cfg} {id : String} {row : List (String × String)} {paths : List String}
    {blob : String → Option String} : expand c id row paths blob = .same ↔ kept c id (paths.map fun p => (p, blob p)) = [] := by
  unfold expand
  by_cases h : kept c id (paths.map fun p => (p, blob p)) = []
  · simp [h]
  · simp only [h, ↓reduceIte, iff_false]
    split <;> simp

theorem expand_expanded {c : Cfg} {id : String} {row : List (String × String)} {paths : List String}
    {blob : String → Option String} {fs : List (String × String)} {n : Nat} (h : expand c id row paths blob = .expanded fs n) :
    fs ≠ [] ∧ (∀ x ∈ fs, x ∈ kept c id (paths.map fun p => (p, blob p))) ∧ n = sizeWith row fs ∧ n ≤ stateCap := by
  unfold expand at h
  by_cases hk : kept c id (paths.map fun p => (p, blob p)) = []
  · simp [hk] at h
  · simp only [hk, ↓reduceIte] at h
    split at h
    · simp at h
    · rename_i _ hne
      simp only [Result.expanded.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨hne, fun x hx => ?_, rfl, ?_⟩
      · rcases fit_mem hx with hx | hx
        · simp at hx
        · exact hx
      · rcases fit_fits (row := row) (fs := kept c id (paths.map fun p => (p, blob p))) (.inl rfl) with h0 | h0
        · exact absurd h0 hne
        · exact h0

/-- Every file of an expanded row is allowed, whole, and (with `dropVocab`) holds no vocabulary word. -/
theorem expand_files {c : Cfg} {id : String} {row : List (String × String)} {paths : List String}
    {blob : String → Option String} {fs : List (String × String)} {n : Nat} (h : expand c id row paths blob = .expanded fs n)
    {p x : String} (hx : (p, x) ∈ fs) : allowed c p = true ∧ (p, some x) ∈ paths.map (fun p => (p, blob p)) ∧
      (c.dropVocab = true → ∀ w ∈ vocab id, ¬ ∃ u v, lower x = u ++ lower w ++ v) := by
  have hk := (expand_expanded h).2.1 _ hx
  exact ⟨kept_allowed hk, kept_whole hk, fun hc => kept_vocabFree hc hk⟩

theorem expand_refused {c : Cfg} {id : String} {row : List (String × String)} {paths : List String}
    {blob : String → Option String} {n : Nat} (h : expand c id row paths blob = .refused n) :
    n = sizeWith row (kept c id (paths.map fun p => (p, blob p))) ∧
      ∀ f ∈ kept c id (paths.map fun p => (p, blob p)), stateCap < sizeWith row [f] := by
  unfold expand at h
  by_cases hk : kept c id (paths.map fun p => (p, blob p)) = []
  · simp [hk] at h
  · simp only [hk, ↓reduceIte] at h
    split at h
    · rename_i hg
      simp only [Result.refused.injEq] at h
      exact ⟨h.symm, fit_nil hg⟩
    · simp at h

theorem expand_local {c : Cfg} {id : String} {row : List (String × String)} {paths : List String}
    {b₁ b₂ : String → Option String} (h : ∀ p ∈ paths, b₁ p = b₂ p) :
    expand c id row paths b₁ = expand c id row paths b₂ := by
  have : (paths.map fun p => (p, b₁ p)) = paths.map fun p => (p, b₂ p) :=
    List.map_congr_left fun p hp => by rw [h p hp]
  simp only [expand, this]

/-! ### Nothing is cut -/

theorem bytes_le_esc (s : String) : bytes s ≤ escBytes s := by
  unfold bytes escBytes
  induction s.toList with
  | nil => simp
  | cons c cs ih => simp only [List.map_cons, List.sum_cons]; omega

theorem sum_le_sum {α : Type} (f g : α → Nat) (h : ∀ a, f a ≤ g a) : ∀ l : List α, (l.map f).sum ≤ (l.map g).sum
  | [] => by simp
  | a :: l => by simp only [List.map_cons, List.sum_cons]; have := sum_le_sum f g h l; have := h a; omega

theorem stateBytes_le_esc (S : State) : stateBytes S ≤ stateEsc S := by
  unfold stateBytes stateEsc linesBytes
  exact sum_le_sum _ _ (fun kl => sum_le_sum _ _ bytes_le_esc kl.2) S

theorem keepLines_all : ∀ (b : Nat) (L : List String), linesBytes L ≤ b → keepLines b L = L
  | _, [], _ => by simp [keepLines]
  | b, x :: xs, h => by
    simp only [linesBytes, List.map_cons, List.sum_cons] at h
    have hx : bytes x ≤ b := by omega
    have := keepLines_all (b - bytes x) xs (by simp only [linesBytes]; omega)
    simp [keepLines, hx, this]

theorem capState_of_le : ∀ (b : Nat) (S : State), stateBytes S ≤ b → capState b S = S
  | _, [], _ => by simp [capState]
  | b, (k, L) :: S, h => by
    have hr : linesBytes L.reverse = linesBytes L := by simp [linesBytes, List.map_reverse, List.sum_reverse]
    simp only [stateBytes, List.map_cons, List.sum_cons] at h
    have hk : keepLines b L.reverse = L.reverse := keepLines_all b _ (by rw [hr]; exact Nat.le_trans (Nat.le_add_right _ _) h)
    have := capState_of_le (b - linesBytes L) S (by simp only [stateBytes]; omega)
    simp [capState, hk, this]

theorem expand_uncut {c : Cfg} {id : String} {row : List (String × String)} {paths : List String}
    {blob : String → Option String} {fs : List (String × String)} {n : Nat} (h : expand c id row paths blob = .expanded fs n) :
    stateBytes (rowState d1 (withFiles row fs)) ≤ stateCap ∧
      capState stateCap (rowState d1 (withFiles row fs)) = rowState d1 (withFiles row fs) := by
  obtain ⟨_, _, hn, hc⟩ := expand_expanded h
  have he : stateEsc (rowState d1 (withFiles row fs)) ≤ stateCap := by unfold sizeWith at hn; omega
  have hb : stateBytes (rowState d1 (withFiles row fs)) ≤ stateCap := Nat.le_trans (stateBytes_le_esc _) he
  exact ⟨hb, capState_of_le _ _ hb⟩

/-- A row whose kept list is empty keeps the D1 state of the plain row, so its body is the D1 body. -/
theorem expand_noop_state {c : Cfg} {id : String} {row : List (String × String)} {files : List (String × Option String)}
    (h : kept c id files = []) : rowState d1 (expandRow c id row files) = rowState d1 row := by
  rw [expandRow_noop h]

def xs (n : Nat) : String := String.ofList (List.replicate n 'x')

#guard expand safe "i" [("title", "t")] ["scripts/a.mjs"] (fun _ => some "c-quota") == .same
#guard expand safe "i" [("title", "t")] ["scripts/a.mjs"] (fun _ => some "x") == .expanded [("scripts/a.mjs", "x")] 21
#guard expand safe "i" [("title", "t")] ["scripts/a.mjs"] (fun _ => some (xs 40000)) == .refused 40020
#guard expand safe "i" [("title", "t")] ["scripts/a.mjs", "scripts/b.mjs", "scripts/c.mjs"]
    (fun p => if p == "scripts/b.mjs" then some (xs 40000) else some "y") ==
  .expanded [("scripts/a.mjs", "y"), ("scripts/c.mjs", "y")] 41

end Fw.Oracle.Expand
