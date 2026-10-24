import Lean
/-! # Dry land: skip the lake step when a pass on the same inputs is on record -/
namespace Fw.Ops.LandCache
open Lean

/-- The inputs of `lake build` and the axiom check: the `lean/` tree id and the `packages/contracts/golden/` tree id (the only paths outside `lean/` that `include_str` reads). -/
structure Key where
  lean : String
  golden : String
deriving Repr, DecidableEq

inductive Src
  | dryLint
  | checkSh
deriving Repr, DecidableEq

structure Rec where
  key : Key
  src : Src
  pass : Bool
deriving Repr, DecidableEq

def hitFrom (s : Src) (rs : List Rec) (k : Key) : Bool :=
  rs.any fun r => r.src == s && r.pass && r.key == k

/-- A passing record with this key exists. -/
def hit (rs : List Rec) (k : Key) : Bool :=
  rs.any fun r => r.pass && r.key == k

/-- The dry land runs the lake step iff the change touches `lean/` and no pass is on record for the merge tree's key. -/
def runLake (touchesLean : Bool) (rs : List Rec) (k : Key) : Bool :=
  touchesLean && !hit rs k

theorem hit_iff (rs : List Rec) (k : Key) :
    hit rs k = true ↔ ∃ r ∈ rs, r.pass = true ∧ r.key = k := by
  simp [hit]

theorem hit_split (rs : List Rec) (k : Key) :
    hit rs k = (hitFrom .dryLint rs k || hitFrom .checkSh rs k) := by
  induction rs with
  | nil => simp [hit, hitFrom]
  | cons r rs ih =>
    cases r with
    | mk key src pass =>
      cases src <;> cases pass <;> simp_all [hit, hitFrom] <;> grind

theorem hit_of_dryLint (rs : List Rec) (k : Key) (h : hitFrom .dryLint rs k = true) : hit rs k = true := by
  rw [hit_split]; simp [h]

theorem hit_of_checkSh (rs : List Rec) (k : Key) (h : hitFrom .checkSh rs k = true) : hit rs k = true := by
  rw [hit_split]; simp [h]

theorem hit_failed (rs : List Rec) (k : Key) (h : ∀ r ∈ rs, r.pass = false) : hit rs k = false := by
  have : ¬ hit rs k = true := by
    rw [hit_iff]; rintro ⟨r, hr, hp, -⟩; have := h r hr; simp_all
  simpa using this

theorem hit_other_key (rs : List Rec) (k : Key) (h : ∀ r ∈ rs, r.key ≠ k) : hit rs k = false := by
  have : ¬ hit rs k = true := by
    rw [hit_iff]; rintro ⟨r, hr, -, hk⟩; exact h r hr hk
  simpa using this

theorem hit_other_lean (rs : List Rec) (k : Key) (h : ∀ r ∈ rs, r.key.lean ≠ k.lean) : hit rs k = false :=
  hit_other_key rs k fun r hr hk => h r hr (by rw [hk])

theorem runLake_untouched (rs : List Rec) (k : Key) : runLake false rs k = false := by
  simp [runLake]

theorem runLake_miss (rs : List Rec) (k : Key) (h : hit rs k = false) : runLake true rs k = true := by
  simp [runLake, h]

theorem runLake_hit (rs : List Rec) (k : Key) (h : hit rs k = true) : runLake true rs k = false := by
  simp [runLake, h]

/-- Same key, same verdict: if every passing record's key passes `lake build` and the axiom check, a skipped lake step loses no failure. -/
theorem skip_sound (verdict : Key → Bool) (rs : List Rec) (k : Key)
    (prem : ∀ r ∈ rs, r.pass = true → verdict r.key = true)
    (skipped : runLake true rs k = false) : verdict k = true := by
  have h : hit rs k = true := by simpa [runLake] using skipped
  obtain ⟨r, hr, hp, hk⟩ := (hit_iff rs k).1 h
  rw [← hk]; exact prem r hr hp

structure Row where
  recs : List Rec
  key : Key
  touches : Bool
deriving Repr

def Row.hit (r : Row) : Bool := Fw.Ops.LandCache.hit r.recs r.key
def Row.run (r : Row) : Bool := runLake r.touches r.recs r.key

private def k1 : Key := ⟨"L1", "G1"⟩
private def k2 : Key := ⟨"L2", "G1"⟩
private def k3 : Key := ⟨"L1", "G2"⟩

def rows : List Row := [
  ⟨[], k1, true⟩,
  ⟨[⟨k1, .checkSh, true⟩], k1, true⟩,
  ⟨[⟨k1, .dryLint, true⟩], k1, true⟩,
  ⟨[⟨k1, .checkSh, false⟩], k1, true⟩,
  ⟨[⟨k2, .checkSh, true⟩], k1, true⟩,
  ⟨[⟨k3, .dryLint, true⟩], k1, true⟩,
  ⟨[⟨k2, .checkSh, true⟩, ⟨k1, .dryLint, true⟩], k1, true⟩,
  ⟨[⟨k1, .checkSh, true⟩], k1, false⟩,
  ⟨[], k1, false⟩]

def srcName : Src → String
  | .dryLint => "dryLint"
  | .checkSh => "checkSh"

def recJson (r : Rec) : Json :=
  Json.mkObj [("golden", r.key.golden), ("lean", r.key.lean), ("pass", r.pass), ("src", srcName r.src)]

def rowJson (r : Row) : Json :=
  Json.mkObj [("hit", r.hit), ("golden", r.key.golden), ("lean", r.key.lean), ("recs", Json.arr (r.recs.map recJson).toArray),
    ("run", r.run), ("touches", r.touches)]

def jsonl (_ : Unit) : String := String.join (rows.map fun r => (rowJson r).compress ++ "\n")

end Fw.Ops.LandCache
