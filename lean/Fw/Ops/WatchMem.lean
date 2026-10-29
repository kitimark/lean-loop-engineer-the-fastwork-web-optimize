import Lean.Data.Json
import Fw.Ops.Wire
/-!
# What `fw watch` keeps in memory

A watcher that runs for days holds only a bounded window of each growing log and reads each byte of it once.
`push`/`window` decide which timing samples stay (the newest `cap` by start time, ties in file order);
`readFrom`/`nextCursor` decide where a tick resumes reading an append-only log; `over` decides when the watcher's
own resident size raises an alert. Consumers: `apps/runner/src/watch-collect.ts` (window, cursor) and
`apps/runner/src/watch.ts` (`ops.watchRss`); goldens in `packages/contracts/golden/ops/ops.watch{Window,Cursor,Rss}.jsonl`.
-/
namespace Fw.Ops.WatchMem

/-- A timing sample as the window sees it: its start time and its position in the file. -/
structure Row where
  ms : Nat
  seq : Nat
deriving DecidableEq, Repr

/-- `x` placed before the first row that starts later, so an equal start time keeps file order. -/
def ins (x : Row) : List Row → List Row
  | [] => [x]
  | y :: ys => if x.ms < y.ms then x :: y :: ys else y :: ins x ys

/-- The last `cap` rows. -/
def keepLast (cap : Nat) (l : List Row) : List Row := l.drop (l.length - cap)

/-- One new row against the window `w`. -/
def push (cap : Nat) (w : List Row) (x : Row) : List Row := keepLast cap (ins x w)

/-- The window after reading `rows` in file order, starting empty. -/
def window (cap : Nat) (rows : List Row) : List Row := rows.foldl (push cap) []

theorem mem_ins (x z : Row) (w : List Row) : z ∈ ins x w ↔ z = x ∨ z ∈ w := by
  induction w with
  | nil => simp [ins]
  | cons y ys ih =>
    unfold ins
    split <;> simp_all [or_left_comm]

theorem ins_length (x : Row) (w : List Row) : (ins x w).length = w.length + 1 := by
  induction w with
  | nil => simp [ins]
  | cons y ys ih => unfold ins; split <;> simp_all

/-- A window is ordered by start time. -/
abbrev Sorted (l : List Row) : Prop := l.Pairwise fun a b => a.ms ≤ b.ms

theorem ins_sorted (x : Row) (w : List Row) (h : Sorted w) : Sorted (ins x w) := by
  induction w with
  | nil => simp [ins]
  | cons y ys ih =>
    unfold ins
    unfold Sorted at h ih ⊢
    rw [List.pairwise_cons] at h
    split
    · rename_i hlt
      rw [List.pairwise_cons]
      refine ⟨?_, List.pairwise_cons.2 h⟩
      intro z hz
      rcases List.mem_cons.1 hz with rfl | hz
      · omega
      · exact Nat.le_trans (Nat.le_of_lt hlt) (h.1 z hz)
    · rename_i hge
      rw [List.pairwise_cons]
      refine ⟨?_, ih h.2⟩
      intro z hz
      rcases (mem_ins x z ys).1 hz with rfl | hz
      · omega
      · exact h.1 z hz

theorem keepLast_length (cap : Nat) (l : List Row) : (keepLast cap l).length = min cap l.length := by
  simp only [keepLast, List.length_drop]; omega

theorem keepLast_sorted (cap : Nat) (l : List Row) (h : Sorted l) : Sorted (keepLast cap l) :=
  h.sublist (List.drop_sublist _ _)

/-- A push grows the window by one row and then cuts it to `cap`. -/
theorem push_length (cap : Nat) (w : List Row) (x : Row) : (push cap w x).length = min cap (w.length + 1) := by
  simp [push, keepLast_length, ins_length]

theorem push_sorted (cap : Nat) (w : List Row) (x : Row) (h : Sorted w) : Sorted (push cap w x) :=
  keepLast_sorted cap _ (ins_sorted x w h)

/-- What a push cuts is a prefix of the ordered merge: the rows kept are the newest. -/
theorem push_suffix (cap : Nat) (w : List Row) (x : Row) :
    ∃ pre, ins x w = pre ++ push cap w x :=
  ⟨_, (List.take_append_drop _ _).symm⟩

theorem fold_push (cap : Nat) (rows w : List Row) (hl : w.length ≤ cap) (hs : Sorted w) :
    (rows.foldl (push cap) w).length ≤ cap ∧ Sorted (rows.foldl (push cap) w) := by
  induction rows generalizing w with
  | nil => exact ⟨hl, hs⟩
  | cons r rs ih =>
    refine ih (push cap w r) ?_ (push_sorted cap w r hs)
    rw [push_length]; exact Nat.min_le_left _ _

/-- However many samples the file holds, the window holds at most `cap`. -/
theorem window_length_le (cap : Nat) (rows : List Row) : (window cap rows).length ≤ cap :=
  (fold_push cap rows [] (Nat.zero_le _) (List.Pairwise.nil)).1

theorem window_sorted (cap : Nat) (rows : List Row) : Sorted (window cap rows) :=
  (fold_push cap rows [] (Nat.zero_le _) (List.Pairwise.nil)).2

/-- Where a tick resumes reading a log: at its cursor while the same file only grew; from the start when the file is
another file (`same` false) or shorter than the cursor. -/
def readFrom (cursor size : Nat) (same : Bool) : Nat := if same && decide (cursor ≤ size) then cursor else 0

/-- The cursor after reading a chunk that begins at `from`: just past the chunk's last newline (`nl` is its index in the
chunk), so a half-written last line is read again whole. -/
def nextCursor (start : Nat) : Option Nat → Nat
  | some i => start + i + 1
  | none => start

/-- A log that only grew (cursor not past the end) is read from the cursor. -/
theorem read_grown (cursor size : Nat) (h : cursor ≤ size) : readFrom cursor size true = cursor := by
  simp [readFrom, h]

/-- A log shorter than the cursor was truncated: it is read from the start. -/
theorem read_truncated (cursor size : Nat) (h : size < cursor) (same : Bool) : readFrom cursor size same = 0 := by
  have : ¬ cursor ≤ size := by omega
  simp [readFrom, this]

/-- Another file under the same name is read from the start. -/
theorem read_replaced (cursor size : Nat) : readFrom cursor size false = 0 := by
  simp [readFrom]

/-- The read never starts past the end of the file. -/
theorem readFrom_le (cursor size : Nat) (same : Bool) : readFrom cursor size same ≤ size := by
  unfold readFrom; split
  · rename_i h; simp at h; exact h.2
  · exact Nat.zero_le _

/-- A chunk without a newline leaves the cursor at its start, however long the line is: the reader grows its buffer instead. -/
theorem next_none (start : Nat) : nextCursor start none = start := rfl

/-- The cursor stays inside the chunk that was read. -/
theorem nextCursor_le (start len : Nat) (nl : Option Nat) (h : ∀ i, nl = some i → i < len) :
    start ≤ nextCursor start nl ∧ nextCursor start nl ≤ start + len := by
  cases nl with
  | none => simp [nextCursor]
  | some i => have := h i rfl; simp [nextCursor]; omega

/-- The resident-size bound of the watcher, in KiB (`ps` unit): 512 MB. MEASURED (local, 20 min, 60 s ticks): bounded watcher
peaks 250 MB by `ps` (289 MB at a tick); the unbounded one averaged 585 MB and peaked 842 MB. -/
def rssBoundKb : Nat := 524288

/-- The watcher raises its alert exactly above the bound. -/
def over (rssKb : Nat) : Bool := decide (rssBoundKb < rssKb)

theorem over_iff (rssKb : Nat) : over rssKb = true ↔ rssBoundKb < rssKb := by simp [over]

/-- At the bound itself the watcher is quiet. -/
theorem not_over_at_bound : over rssBoundKb = false := by simp [over]

/-- A larger resident size never clears the alert. -/
theorem over_mono (a b : Nat) (hab : a ≤ b) (h : over a = true) : over b = true := by
  simp only [over_iff] at *; omega

/-- KiB as whole MiB, rounded to nearest. -/
def mb (kb : Nat) : Nat := (kb + 512) / 1024

/-- The tick line of a watcher with resident size `rssKb` and heap `heapKb`. -/
def tickLine (rssKb heapKb : Nat) : String :=
  s!"TICK rss={mb rssKb}MB heap={mb heapKb}MB bound={mb rssBoundKb}MB"

/-- The detail text of the alert. -/
def rssDetail (rssKb : Nat) : String := s!"fw watch holds {mb rssKb} MB resident, over the {mb rssBoundKb} MB bound"

#guard (window 3 [⟨5, 0⟩, ⟨1, 1⟩, ⟨5, 2⟩, ⟨3, 3⟩, ⟨9, 4⟩]).map (·.seq) = [0, 2, 4]
#guard (window 2 [⟨5, 0⟩, ⟨5, 1⟩, ⟨5, 2⟩]).map (·.seq) = [1, 2]
#guard (window 0 [⟨5, 0⟩]) = []
#guard readFrom 100 150 true = 100
#guard readFrom 100 99 true = 0
#guard readFrom 100 150 false = 0
#guard nextCursor 100 (some 41) = 142 && nextCursor 100 none = 100
#guard over 524288 = false && over 524289 = true
#guard tickLine 524288 100000 = "TICK rss=512MB heap=98MB bound=512MB"

end Fw.Ops.WatchMem

/-! ## Wire: `ops.watchWindow`, `ops.watchCursor`, `ops.watchRss` -/

namespace Fw.Wire.WatchMem
open Lean Fw.Ops.WatchMem Fw.Wire.Ops

/-- `ops.watchWindow`: `cap`, `ms` [start times in file order] → `keep` (file positions of the kept rows, oldest start first). -/
def opWindow (req : Json) : Except String Reply := do
  let cap ← nat req "cap"
  let ms ← (← arrD req "ms").mapM fun j => match j.getNat? with
    | .ok n => pure n
    | .error _ => throw "ms: not a number"
  let rows := ms.zipIdx.map fun (m, i) => Row.mk m i
  pure [("keep", .arr ((window cap rows).toArray.map fun r => toJson r.seq))]

/-- `ops.watchCursor`: `cursor`, `size`, `same`, `nl`? (index of the last newline of the chunk read) → `from`, `next`. -/
def opCursor (req : Json) : Except String Reply := do
  let cursor ← nat req "cursor"
  let size ← nat req "size"
  let same ← boolD req "same" true
  let start := readFrom cursor size same
  let nl := match req.getObjVal? "nl" with
    | .ok j => j.getNat?.toOption
    | .error _ => none
  pure [("from", toJson start), ("next", toJson (nextCursor start nl))]

/-- `ops.watchRss`: `rssKb`, `heapKb`? → `over`, `boundKb`, `line` (the tick line), `detail` (the alert text). -/
def opRss (req : Json) : Except String Reply := do
  let rss ← nat req "rssKb"
  let heap ← natD req "heapKb" 0
  pure [("over", toJson (over rss)), ("boundKb", toJson rssBoundKb), ("line", .str (tickLine rss heap)),
    ("detail", .str (rssDetail rss))]

def ops : List String := ["ops.watchWindow", "ops.watchCursor", "ops.watchRss"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.watchWindow" => some (opWindow req)
  | "ops.watchCursor" => some (opCursor req)
  | "ops.watchRss" => some (opRss req)
  | _ => none

end Fw.Wire.WatchMem
