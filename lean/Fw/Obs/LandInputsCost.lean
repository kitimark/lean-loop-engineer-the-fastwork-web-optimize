import Lean.Data.Json
/-!
# `Fw.Obs.LandInputsCost`: cost model of `inputKey` in the land-inputs test
-/
namespace Fw.Obs.LandInputsCost

inductive Mode where
  | orig
  | globs
  | cached
deriving DecidableEq, Repr

structure Rates where
  spawnUs   : Nat
  pairOldNs : Nat
  pairNewNs : Nat
  hashUs    : Nat
  fixedUs   : Nat
deriving DecidableEq, Repr

structure Work where
  calls  : Nat
  pairs  : Nat
  hashed : Nat
deriving DecidableEq, Repr

def pairNs (r : Rates) : Mode → Nat
  | .orig => r.pairOldNs
  | _ => r.pairNewNs

def spawns (m : Mode) (w : Work) : Nat :=
  match m with
  | .cached => if w.calls = 0 then 0 else 1
  | _ => w.calls

def cost (r : Rates) (m : Mode) (w : Work) : Nat :=
  spawns m w * r.spawnUs + w.pairs * pairNs r m / 1000 + w.hashed * r.hashUs + w.calls * r.fixedUs

def callsBound (n g : Nat) : Nat := n * (g + 3)

theorem callsBound_mono_checks {n n' : Nat} (h : n ≤ n') (g : Nat) : callsBound n g ≤ callsBound n' g :=
  Nat.mul_le_mul_right _ h

theorem callsBound_mono_globs (n : Nat) {g g' : Nat} (h : g ≤ g') : callsBound n g ≤ callsBound n g' :=
  Nat.mul_le_mul_left _ (by omega)

theorem cost_mono_pairs (r : Rates) (m : Mode) {c h p p' : Nat} (hp : p ≤ p') :
    cost r m ⟨c, p, h⟩ ≤ cost r m ⟨c, p', h⟩ := by
  have hs : spawns m ⟨c, p, h⟩ = spawns m ⟨c, p', h⟩ := by cases m <;> rfl
  have : p * pairNs r m / 1000 ≤ p' * pairNs r m / 1000 :=
    Nat.div_le_div_right (Nat.mul_le_mul_right _ hp)
  dsimp only [cost]
  rw [hs]
  omega

theorem cost_mono_calls (r : Rates) {c c' p h : Nat} (hc : c ≤ c') (m : Mode) (hm : m ≠ .cached) :
    cost r m ⟨c, p, h⟩ ≤ cost r m ⟨c', p, h⟩ := by
  have h1 := Nat.mul_le_mul_right r.spawnUs hc
  have h2 := Nat.mul_le_mul_right r.fixedUs hc
  cases m with
  | cached => exact absurd rfl hm
  | orig => dsimp only [cost, spawns]; omega
  | globs => dsimp only [cost, spawns]; omega

theorem cached_free_of_calls_spawn (w : Work) : spawns .cached w ≤ 1 := by
  show (if w.calls = 0 then 0 else 1) ≤ 1
  split <;> omega

theorem cost_globs_le_orig (r : Rates) (h : r.pairNewNs ≤ r.pairOldNs) (w : Work) :
    cost r .globs w ≤ cost r .orig w := by
  have : w.pairs * r.pairNewNs / 1000 ≤ w.pairs * r.pairOldNs / 1000 :=
    Nat.div_le_div_right (Nat.mul_le_mul_left _ h)
  have hs : spawns .globs w = spawns .orig w := rfl
  have e1 : pairNs r .globs = r.pairNewNs := rfl
  have e2 : pairNs r .orig = r.pairOldNs := rfl
  unfold cost
  rw [hs, e1, e2]
  omega

theorem cost_cached_le_globs (r : Rates) (w : Work) : cost r .cached w ≤ cost r .globs w := by
  have : spawns .cached w ≤ spawns .globs w := by
    show (if w.calls = 0 then 0 else 1) ≤ w.calls
    split <;> omega
  have h1 := Nat.mul_le_mul_right r.spawnUs this
  have e1 : pairNs r .globs = r.pairNewNs := rfl
  have e2 : pairNs r .cached = r.pairNewNs := rfl
  unfold cost
  rw [e1, e2]
  omega

structure Row where
  test   : String
  mode   : Mode
  work   : Work
  measMs : Nat
deriving Repr

def rates : Rates := { spawnUs := 8000, pairOldNs := 335, pairNewNs := 20, hashUs := 45, fixedUs := 0 }

def fixtureRates : Rates := { rates with hashUs := 20, fixedUs := 240 }

def fixtureWork : Work := ⟨1867, 4588650, 51639⟩

def realWork : Work := ⟨46, 6225088, 21298⟩

def rows : List Row := [
  ⟨"fixture", .orig, fixtureWork, 25320⟩, ⟨"fixture", .globs, fixtureWork, 16214⟩, ⟨"fixture", .cached, fixtureWork, 1573⟩,
  ⟨"real", .orig, realWork, 3907⟩, ⟨"real", .globs, realWork, 2047⟩, ⟨"real", .cached, realWork, 1087⟩]

def ratesOf (r : Row) : Rates := if r.test = "fixture" then fixtureRates else rates

def predMs (r : Row) : Nat := cost (ratesOf r) r.mode r.work / 1000

def band : Nat := 35

def inBand (r : Row) : Bool := 100 * (max (predMs r) r.measMs - min (predMs r) r.measMs) ≤ band * r.measMs

theorem rows_in_band : rows.all inBand = true := by decide

theorem rows_calls_within_bound :
    fixtureWork.calls ≤ callsBound 9 226 ∧ realWork.calls ≤ 2 * callsBound 23 736 := by decide

def rowJson (r : Row) : Lean.Json :=
  Lean.Json.mkObj [("test", r.test), ("mode", match r.mode with | .orig => "orig" | .globs => "globs" | .cached => "cached"),
    ("calls", r.work.calls), ("pairs", r.work.pairs), ("hashed", r.work.hashed), ("measMs", r.measMs),
    ("predMs", predMs r), ("band", band), ("inBand", inBand r)]

end Fw.Obs.LandInputsCost
