import Lean.Data.Json
/-!
# Workflow journal cache: append-only fold, read plan, settled runs

Golden: `golden/console/journal-cache.jsonl`.
-/
namespace Fw.Console.JournalFold

/-- The fold of a journal: `step` consumes one complete line. -/
def fold {A L : Type} (step : A → L → A) (a : A) (ls : List L) : A := ls.foldl step a

/-- **Incremental equals full**: folding the committed lines, then only the appended ones, is folding the whole journal. -/
theorem fold_append {A L : Type} (step : A → L → A) (a : A) (pre post : List L) :
    fold step (fold step a pre) post = fold step a (pre ++ post) := by
  simp [fold, List.foldl_append]

/-- The view of a journal: the fold of its complete lines, then the torn last line (if any) read as a line of its own. -/
def view {A L : Type} (step : A → L → A) (a : A) (ls : List L) (torn : Option L) : A :=
  match torn with
  | none => fold step a ls
  | some t => step (fold step a ls) t

/-- **The cached view equals the full view**: the cache keeps the fold of the lines before the offset, so reading only
the bytes after it gives the view of the whole journal, whatever the torn tail is. -/
theorem view_incremental {A L : Type} (step : A → L → A) (a : A) (pre post : List L) (torn : Option L) :
    view step (fold step a pre) post torn = view step a (pre ++ post) torn := by
  cases torn <;> simp [view, fold, List.foldl_append]

/-- The bytes up to and including the last newline: the length of the committed prefix. -/
def commitEnd : List Nat → Nat
  | [] => 0
  | b :: r => if 10 ∈ r then commitEnd r + 1 else if b = 10 then 1 else 0

/-- The committed prefix is within the bytes read. -/
theorem commitEnd_le (bs : List Nat) : commitEnd bs ≤ bs.length := by
  induction bs with
  | nil => simp [commitEnd]
  | cons b r ih => simp only [commitEnd]; split <;> (try split) <;> simp <;> omega

/-- **No newline in the new bytes: the offset stays.** -/
theorem commitEnd_append_nonl (a b : List Nat) (h : ∀ x ∈ b, x ≠ 10) : commitEnd (a ++ b) = commitEnd a := by
  have hb : 10 ∉ b := fun hm => h 10 hm rfl
  induction a with
  | nil =>
    cases b with
    | nil => simp [commitEnd]
    | cons x r =>
      have hx : x ≠ 10 := h x (by simp)
      have hr : 10 ∉ r := fun hm => h 10 (by simp [hm]) rfl
      simp [commitEnd, hx, hr]
  | cons x r ih =>
    simp only [List.cons_append, commitEnd, List.mem_append, ih]
    simp [hb]

/-- **A newline in the new bytes: the offset moves by the committed length of the new bytes alone.** -/
theorem commitEnd_append_nl (a b : List Nat) (h : 10 ∈ b) : commitEnd (a ++ b) = a.length + commitEnd b := by
  induction a with
  | nil => simp
  | cons x r ih =>
    simp only [List.cons_append, commitEnd, List.mem_append, h, or_true, ite_true, ih, List.length_cons]
    omega

/-- What the cache holds of one journal file: size and mtime at the last read, and the committed offset. -/
structure Cached where
  size : Nat
  mtime : Nat
  offset : Nat
deriving DecidableEq, Repr

/-- What a stat of the file shows now. -/
structure Stat where
  size : Nat
  mtime : Nat
deriving DecidableEq, Repr

/-- The three ways to bring the cache up to date. -/
inductive Act where | hit | tail | full
deriving DecidableEq, Repr

/-- Same size and mtime: no read. Larger and the guard bytes (the head and the end of the committed prefix) unchanged: an
append, read from the offset. Anything else (smaller, the same size with another mtime, changed guard bytes): a rewrite,
read in full. -/
def plan (c : Cached) (s : Stat) (guard : Bool) : Act :=
  if s.size = c.size ∧ s.mtime = c.mtime then .hit
  else if c.size < s.size ∧ guard = true then .tail
  else .full

/-- **Hit**: an unchanged stat reads nothing. -/
theorem plan_hit (c : Cached) (s : Stat) (g : Bool) (h : s.size = c.size ∧ s.mtime = c.mtime) : plan c s g = .hit := by
  simp [plan, h]

/-- **Tail**: a larger file with another stat and unchanged guard bytes is read from the offset. -/
theorem plan_tail (c : Cached) (s : Stat) (h : ¬(s.size = c.size ∧ s.mtime = c.mtime)) (hg : c.size < s.size) :
    plan c s true = .tail := by
  simp [plan, h, hg]

/-- **Shrink**: a smaller file is read in full. -/
theorem plan_shrink (c : Cached) (s : Stat) (g : Bool) (h : s.size < c.size) : plan c s g = .full := by
  have h1 : ¬(s.size = c.size ∧ s.mtime = c.mtime) := fun ⟨e, _⟩ => by omega
  have h2 : ¬(c.size < s.size ∧ g = true) := fun ⟨e, _⟩ => by omega
  simp [plan, h1, h2]

/-- **Rewrite**: the same size with another mtime is read in full. -/
theorem plan_rewrite (c : Cached) (s : Stat) (g : Bool) (hs : s.size = c.size) (hm : s.mtime ≠ c.mtime) :
    plan c s g = .full := by
  have h1 : ¬(s.size = c.size ∧ s.mtime = c.mtime) := fun ⟨_, e⟩ => hm e
  have h2 : ¬(c.size < s.size ∧ g = true) := fun ⟨e, _⟩ => by omega
  simp [plan, h1, h2]

/-- **Changed guard bytes**: a larger file whose head or committed end changed is read in full. -/
theorem plan_guard (c : Cached) (s : Stat) (h : ¬(s.size = c.size ∧ s.mtime = c.mtime)) : plan c s false = .full := by
  simp [plan, h]

/-- **A tail read starts at the committed offset, never past the old size**, when the cache is consistent. -/
theorem tail_from_offset (c : Cached) (hc : c.offset ≤ c.size) (s : Stat) (g : Bool) (h : plan c s g = .tail) :
    c.offset ≤ s.size := by
  unfold plan at h
  split at h
  · cases h
  · split at h
    · rename_i hh; omega
    · cases h

/-- A settled run: its previous signature and the one now, whether its run file exists, and whether every event of it was
accepted. -/
structure Settle where
  sameSig : Bool
  ended : Bool
  allSent : Bool
deriving DecidableEq, Repr

/-- A run is skipped when it ended, all its events were accepted, and nothing it depends on changed. -/
def skip (s : Settle) : Bool := s.sameSig && s.ended && s.allSent

/-- **Skip needs all three**: the skip is taken only when the signature is unchanged. -/
theorem skip_sig (s : Settle) (h : skip s = true) : s.sameSig = true := by
  simp [skip] at h; exact h.1.1

/-- **Skip needs the run to have ended** (a running run can still append). -/
theorem skip_ended (s : Settle) (h : skip s = true) : s.ended = true := by
  simp [skip] at h; exact h.1.2

/-- **Skip needs every event accepted** (a refused event is retried on the next sweep). -/
theorem skip_sent (s : Settle) (h : skip s = true) : s.allSent = true := by
  simp [skip] at h; exact h.2

/-- **Skipping loses nothing**: when every event of the run is already accepted, sending them again adds no new key. -/
theorem skip_no_new_keys (sent evs : List String) (h : ∀ k ∈ evs, k ∈ sent) : evs.filter (fun k => k ∉ sent) = [] := by
  apply List.filter_eq_nil_iff.mpr
  intro k hk
  simpa using h k hk

open Lean

/-- Action name. -/
def Act.name : Act → String | .hit => "hit" | .tail => "tail" | .full => "full"

/-- One read-plan case. -/
def planCase (c : Cached) (s : Stat) (g : Bool := true) : Json :=
  Json.mkObj [("kind", "plan"), ("cached", Json.mkObj [("size", c.size), ("mtime", c.mtime), ("offset", c.offset)]),
    ("stat", Json.mkObj [("size", s.size), ("mtime", s.mtime)]), ("guard", g), ("act", (plan c s g).name)]

/-- One committed-prefix case over a byte list. -/
def commitCase (bs : List Nat) : Json :=
  Json.mkObj [("kind", "commit"), ("bytes", Json.arr (bs.toArray.map fun b => toJson b)), ("end", commitEnd bs)]

/-- One settle case. -/
def skipCase (s : Settle) : Json :=
  Json.mkObj [("kind", "skip"), ("sameSig", s.sameSig), ("ended", s.ended), ("allSent", s.allSent), ("skip", skip s)]

/-- One safety-tick case: the first tick after `t` for period `p` (`Fw.Console.ReconcileSched.nextTick`). -/
def tickCase (p t : Nat) : Json :=
  Json.mkObj [("kind", "tick"), ("period", p), ("t", t), ("next", (t / p + 1) * p)]

/-- Golden cases. -/
def cases : List Json :=
  [planCase ⟨100, 5, 100⟩ ⟨100, 5⟩, planCase ⟨100, 5, 90⟩ ⟨100, 5⟩, planCase ⟨100, 5, 100⟩ ⟨150, 6⟩,
   planCase ⟨100, 5, 90⟩ ⟨150, 6⟩, planCase ⟨100, 5, 100⟩ ⟨150, 5⟩, planCase ⟨100, 5, 100⟩ ⟨40, 6⟩,
   planCase ⟨100, 5, 100⟩ ⟨100, 6⟩, planCase ⟨0, 0, 0⟩ ⟨12, 3⟩, planCase ⟨100, 5, 100⟩ ⟨0, 7⟩, planCase ⟨100, 5, 100⟩ ⟨150, 6⟩ false, planCase ⟨100, 5, 100⟩ ⟨100, 5⟩ false,
   commitCase [], commitCase [10], commitCase [97, 10, 98], commitCase [97, 10, 98, 10], commitCase [97, 98],
   commitCase [10, 10, 99, 99, 99], commitCase [97, 10, 98, 10, 99, 100, 101],
   skipCase ⟨true, true, true⟩, skipCase ⟨false, true, true⟩, skipCase ⟨true, false, true⟩, skipCase ⟨true, true, false⟩,
   skipCase ⟨false, false, false⟩,
   tickCase 10000 0, tickCase 10000 9999, tickCase 10000 10000, tickCase 10000 12345, tickCase 1 7]

/-- The golden text. -/
def goldenText : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- Golden path, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/journal-cache.jsonl"

/-- Write the golden file. -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output? -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.JournalFold
