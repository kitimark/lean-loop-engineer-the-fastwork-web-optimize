import Lean.Data.Json
/-!
# `Fw.Obs.LandInputsCost`: why the land-inputs vitest grew with no co-runner

The dry land runs `apps/runner/test/land-inputs.test.ts`. It grew from p50 19.8 s to 29-31 s over 675 local rows at
load 3.5-4.7, with the test file unchanged and tracked files up 6-7 percent. The cost is not in the file count alone.
Most of the step is `inputKey` (`apps/runner/src/land.ts`): one key lists the tracked files (`git ls-files`, a process
spawn), keeps those in scope of a check's globs, and hashes them. The fixture test calls it once per outsider path
and twice per glob of every check.

Model (all whole numbers; µs and ns):
* `calls`: the number of `inputKey` calls of a test (`callsBound n g`: at most `n · (g + 3)` for `n` checks with `g`
  globs in all, so one more check or glob adds calls, each paying the spawn).
* `pairs`: sum over calls of (tracked files) × (globs of the call's check). One scope test per pair.
* `hashed`: sum over calls of the files in scope, each read and hashed once.
* `cost r m w = spawns · spawnUs + pairs · pairNs / 1000 + hashed · hashUs + calls · fixedUs`, with `spawns = calls`
  while the listing is spawned per call (`orig`, `globs`) and `1` once it is kept per index state (`cached`).
* The three modes are the code before (`orig`: globs split again for every path), after the compiled scope (`globs`),
  and after the compiled scope and the kept listing (`cached`).

Rates (µs and ns) are MEASURED by `bench.mjs`-style micro runs on this Mac at load 3.5-4: a `git ls-files` spawn 8 ms,
a scope test per (file, glob) pair 335 ns before and 20 ns after, hashing 45 µs per real file and 20 µs per
two-byte fixture file, 240 µs of writes per fixture call. The rows below are per-test durations of vitest runs of the
test file; the model is within `band` percent of each (`rows_in_band`). The `orig` fixture row is under-predicted by
about 30 percent: vitest ran the original recursion slower than plain node (19.1 s there, 24-26 s under vitest;
INFERRED, not isolated).

Proved: `cost_cached_le_globs`, `cost_globs_le_orig`, `cost_mono_pairs`, `cost_mono_calls`, `callsBound_mono_checks`,
`callsBound_mono_globs`, `cached_free_of_calls_spawn`, `rows_in_band`, `rows_calls_within_bound`.
-/
namespace Fw.Obs.LandInputsCost

/-- How the key lists and scopes files: as before, with the compiled scope test, or with the listing kept too. -/
inductive Mode where
  | orig
  | globs
  | cached
deriving DecidableEq, Repr

/-- Measured rates: spawn in µs, the scope test per pair in ns (before and after), hashing per file in µs, and the
other work per call in µs. -/
structure Rates where
  spawnUs   : Nat
  pairOldNs : Nat
  pairNewNs : Nat
  hashUs    : Nat
  fixedUs   : Nat
deriving DecidableEq, Repr

/-- The work of one test: `calls` key computations, the (file, glob) pairs they scan and the files they hash. -/
structure Work where
  calls  : Nat
  pairs  : Nat
  hashed : Nat
deriving DecidableEq, Repr

/-- The scope test cost of one pair, in ns. -/
def pairNs (r : Rates) : Mode → Nat
  | .orig => r.pairOldNs
  | _ => r.pairNewNs

/-- Process spawns of `git ls-files`: one per call, or one in all when the listing is kept. -/
def spawns (m : Mode) (w : Work) : Nat :=
  match m with
  | .cached => if w.calls = 0 then 0 else 1
  | _ => w.calls

/-- The predicted duration of a test, in µs. -/
def cost (r : Rates) (m : Mode) (w : Work) : Nat :=
  spawns m w * r.spawnUs + w.pairs * pairNs r m / 1000 + w.hashed * r.hashUs + w.calls * r.fixedUs

/-- Upper bound on the calls of the fixture test with `n` checks and `g` globs in all. -/
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

/-- The kept listing spawns at most once, whatever the number of calls. -/
theorem cached_free_of_calls_spawn (w : Work) : spawns .cached w ≤ 1 := by
  show (if w.calls = 0 then 0 else 1) ≤ 1
  split <;> omega

/-- A scope test that is no slower per pair, and a listing spawned no more often, never cost more. -/
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

/-! ## Measured rows -/

/-- One measured test: which test, mode, work, and the vitest duration in ms (the mean of the runs listed). -/
structure Row where
  test   : String
  mode   : Mode
  work   : Work
  measMs : Nat
deriving Repr

def rates : Rates := { spawnUs := 8000, pairOldNs := 335, pairNewNs := 20, hashUs := 45, fixedUs := 0 }

/-- Fixture test rates: two-byte files hash in 20 µs and each call writes twice (240 µs). -/
def fixtureRates : Rates := { rates with hashUs := 20, fixedUs := 240 }

/-- Fixture test: 9 checks, 226 globs, 99 files. Work counted by replaying the test's loops. -/
def fixtureWork : Work := ⟨1867, 4588650, 51639⟩

/-- Real-root key test: 23 checks, 736 globs, 4229 tracked files, each key computed twice. -/
def realWork : Work := ⟨46, 6225088, 21298⟩

/-- The durations are vitest per-test durations of `land-inputs.test.ts` on this Mac (load 3.6-7). The `orig` rows are
the mean of two runs (26348 and 24291 ms; 3924 and 3889 ms); `globs` is one run; `cached` is the mean of two. -/
def rows : List Row := [
  ⟨"fixture", .orig, fixtureWork, 25320⟩, ⟨"fixture", .globs, fixtureWork, 16214⟩, ⟨"fixture", .cached, fixtureWork, 1573⟩,
  ⟨"real", .orig, realWork, 3907⟩, ⟨"real", .globs, realWork, 2047⟩, ⟨"real", .cached, realWork, 1087⟩]

def ratesOf (r : Row) : Rates := if r.test = "fixture" then fixtureRates else rates

/-- The prediction in whole ms. -/
def predMs (r : Row) : Nat := cost (ratesOf r) r.mode r.work / 1000

/-- The band, in percent of the measurement. -/
def band : Nat := 35

/-- The prediction is within `band` percent of the measurement. -/
def inBand (r : Row) : Bool := 100 * (max (predMs r) r.measMs - min (predMs r) r.measMs) ≤ band * r.measMs

theorem rows_in_band : rows.all inBand = true := by decide

/-- The measured call counts respect `callsBound` (9 checks, 226 globs in the fixture; 23 checks, 736 globs, x2 real). -/
theorem rows_calls_within_bound :
    fixtureWork.calls ≤ callsBound 9 226 ∧ realWork.calls ≤ 2 * callsBound 23 736 := by decide

/-- Wire form of a row, for `packages/contracts/golden/obs/land-inputs-cost.jsonl`. -/
def rowJson (r : Row) : Lean.Json :=
  Lean.Json.mkObj [("test", r.test), ("mode", match r.mode with | .orig => "orig" | .globs => "globs" | .cached => "cached"),
    ("calls", r.work.calls), ("pairs", r.work.pairs), ("hashed", r.work.hashed), ("measMs", r.measMs),
    ("predMs", predMs r), ("band", band), ("inBand", inBand r)]

end Fw.Obs.LandInputsCost
