import Lean.Data.Json
import Fw.Ops.Wire
namespace Fw.Ops.WatchMem

structure Row where
  ms : Nat
  seq : Nat
deriving DecidableEq, Repr

def ins (x : Row) : List Row → List Row
  | [] => [x]
  | y :: ys => if x.ms < y.ms then x :: y :: ys else y :: ins x ys

def keepLast (cap : Nat) (l : List Row) : List Row := l.drop (l.length - cap)

def push (cap : Nat) (w : List Row) (x : Row) : List Row := keepLast cap (ins x w)

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

theorem push_length (cap : Nat) (w : List Row) (x : Row) : (push cap w x).length = min cap (w.length + 1) := by
  simp [push, keepLast_length, ins_length]

theorem push_sorted (cap : Nat) (w : List Row) (x : Row) (h : Sorted w) : Sorted (push cap w x) :=
  keepLast_sorted cap _ (ins_sorted x w h)

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

theorem window_length_le (cap : Nat) (rows : List Row) : (window cap rows).length ≤ cap :=
  (fold_push cap rows [] (Nat.zero_le _) (List.Pairwise.nil)).1

theorem window_sorted (cap : Nat) (rows : List Row) : Sorted (window cap rows) :=
  (fold_push cap rows [] (Nat.zero_le _) (List.Pairwise.nil)).2

def readFrom (cursor size : Nat) (same : Bool) : Nat := if same && decide (cursor ≤ size) then cursor else 0

def nextCursor (start : Nat) : Option Nat → Nat
  | some i => start + i + 1
  | none => start

theorem read_grown (cursor size : Nat) (h : cursor ≤ size) : readFrom cursor size true = cursor := by
  simp [readFrom, h]

theorem read_truncated (cursor size : Nat) (h : size < cursor) (same : Bool) : readFrom cursor size same = 0 := by
  have : ¬ cursor ≤ size := by omega
  simp [readFrom, this]

theorem read_replaced (cursor size : Nat) : readFrom cursor size false = 0 := by
  simp [readFrom]

theorem readFrom_le (cursor size : Nat) (same : Bool) : readFrom cursor size same ≤ size := by
  unfold readFrom; split
  · rename_i h; simp at h; exact h.2
  · exact Nat.zero_le _

theorem next_none (start : Nat) : nextCursor start none = start := rfl

theorem nextCursor_le (start len : Nat) (nl : Option Nat) (h : ∀ i, nl = some i → i < len) :
    start ≤ nextCursor start nl ∧ nextCursor start nl ≤ start + len := by
  cases nl with
  | none => simp [nextCursor]
  | some i => have := h i rfl; simp [nextCursor]; omega

def rssBoundKb : Nat := 524288

def over (rssKb : Nat) : Bool := decide (rssBoundKb < rssKb)

theorem over_iff (rssKb : Nat) : over rssKb = true ↔ rssBoundKb < rssKb := by simp [over]

theorem not_over_at_bound : over rssBoundKb = false := by simp [over]

theorem over_mono (a b : Nat) (hab : a ≤ b) (h : over a = true) : over b = true := by
  simp only [over_iff] at *; omega

def mb (kb : Nat) : Nat := (kb + 512) / 1024

def tickLine (rssKb heapKb : Nat) : String :=
  s!"TICK rss={mb rssKb}MB heap={mb heapKb}MB bound={mb rssBoundKb}MB"

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

namespace Fw.Wire.WatchMem
open Lean Fw.Ops.WatchMem Fw.Wire.Ops

def opWindow (req : Json) : Except String Reply := do
  let cap ← nat req "cap"
  let ms ← (← arrD req "ms").mapM fun j => match j.getNat? with
    | .ok n => pure n
    | .error _ => throw "ms: not a number"
  let rows := ms.zipIdx.map fun (m, i) => Row.mk m i
  pure [("keep", .arr ((window cap rows).toArray.map fun r => toJson r.seq))]

def opCursor (req : Json) : Except String Reply := do
  let cursor ← nat req "cursor"
  let size ← nat req "size"
  let same ← boolD req "same" true
  let start := readFrom cursor size same
  let nl := match req.getObjVal? "nl" with
    | .ok j => j.getNat?.toOption
    | .error _ => none
  pure [("from", toJson start), ("next", toJson (nextCursor start nl))]

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
