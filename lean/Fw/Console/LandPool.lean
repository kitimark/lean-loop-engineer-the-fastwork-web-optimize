import Fw.Console.LandSpeed
/-!
# Proposal: a fair-share floor under the land pool size

`Fw.Console.LandSpeed.poolSize c ℓ = max 1 (c − ℓ)` runs the land's checks one after another as soon as the one-minute
load average `ℓ` (rounded up) reaches the core count `c`. On this machine that is the normal state (load 14 to 20 on 8
cores), so a land costs the *sum* of its checks (282 s for the snapshot-extract land).

This module is **wired** into `apps/runner/src/land.ts` (task land-pool-fair) through the ops `console.landPool` and
`console.landRetry` (`Fw.Wire.Console`). It states the change as `poolFair`, keeps every theorem of `poolSize`, and proves the two facts the
change rests on, under the standard model of a fair CPU scheduler:

* with `ℓ` runnable threads of other work and `k` of ours, every thread gets `c / (ℓ + k)` of a core when `ℓ + k ≥ c`,
  so the share of the machine that is ours is `k / (ℓ + k)`: it **grows with `k`** (`share_mono`), and a pool of one is
  the *smallest* share we could ask for under saturation (the old rule picks exactly that);
* the others' share `ℓ / (ℓ + k)` stays at least `2/3` while `k ≤ ℓ / 2` (`others_share_floor`), so the floor takes at
  most a third of what the others had.

**Empirical premise (MEASURED, 2026-10-18, `ps -axo state,pcpu` three samples 2 s apart, load average 15.2 to 15.6):** the
load comes from running processes (12, 7 and 6 in state `R`, 725 %, 395 %, 438 % CPU: `mathview`, `jq`, test runs of
other agents), not from the nine idle `lake serve` / `lean --server` processes, which sleep (state `S`, 0.0 % CPU) and add
nothing to a load average that counts runnable threads. So "the load is from idle lake serve" does not hold on this
machine; the saturation is real, which is why the floor is fair-share and not "ignore the load".
-/
namespace Fw.Console.LandPool
open Fw.Console.LandSpeed

/-- The pool size with a fair-share floor: the cores not taken by other work, but never fewer than half the cores
(at least one).
$$\operatorname{poolFair}(c, \ell) = \max\bigl(1,\ \lfloor c/2 \rfloor,\ c - \ell\bigr)$$ -/
def poolFair (cores loadCeil : Nat) : Nat := max (max 1 (cores / 2)) (cores - loadCeil)

/-- The pool is never empty.
$$\forall c, \ell:\ 1 \le \operatorname{poolFair}(c, \ell)$$ -/
theorem poolFair_pos (c l : Nat) : 1 ≤ poolFair c l := by
  unfold poolFair; omega

/-- **Floor.** Under any load the pool is at least half the cores.
$$\forall c, \ell:\ \lfloor c/2 \rfloor \le \operatorname{poolFair}(c, \ell)$$ -/
theorem poolFair_floor (c l : Nat) : c / 2 ≤ poolFair c l := by
  unfold poolFair; omega

/-- **Never smaller than today's pool.** The proposal only ever adds parallelism.
$$\forall c, \ell:\ \operatorname{pool}(c, \ell) \le \operatorname{poolFair}(c, \ell)$$ -/
theorem poolSize_le_poolFair (c l : Nat) : poolSize c l ≤ poolFair c l := by
  unfold poolSize poolFair; omega

/-- **No change on a machine that is not saturated.** While the free cores `c − ℓ` are at least half the cores, the
proposal gives today's pool.
$$\forall c, \ell:\ \lfloor c/2 \rfloor \le c - \ell \Rightarrow \operatorname{poolFair}(c, \ell) = \operatorname{pool}(c, \ell)$$ -/
theorem poolFair_eq_of_light (c l : Nat) (h : c / 2 ≤ c - l) : poolFair c l = poolSize c l := by
  unfold poolFair poolSize; omega

/-- **Never more than the cores** (with at least one).
$$\forall c \ge 1, \ell:\ \operatorname{poolFair}(c, \ell) \le c$$ -/
theorem poolFair_le_cores (c l : Nat) (hc : 1 ≤ c) : poolFair c l ≤ c := by
  unfold poolFair; omega

/-- **Monotone in load.** More load never gives a larger pool.
$$\forall c, \ell \le \ell':\ \operatorname{poolFair}(c, \ell') \le \operatorname{poolFair}(c, \ell)$$ -/
theorem poolFair_anti_load (c l l' : Nat) (h : l ≤ l') : poolFair c l' ≤ poolFair c l := by
  unfold poolFair; omega

/-- **Monotone in cores.** More cores never give a smaller pool.
$$\forall c \le c', \ell:\ \operatorname{poolFair}(c, \ell) \le \operatorname{poolFair}(c', \ell)$$ -/
theorem poolFair_mono_cores (c c' l : Nat) (h : c ≤ c') : poolFair c l ≤ poolFair c' l := by
  unfold poolFair; omega

/-- **Our share grows with the pool (cross-multiplied).** With `ℓ` runnable threads of other work, the fraction of the
machine that `k` of our threads hold is `k / (ℓ + k)` under a fair scheduler; it is monotone in `k`.
$$\forall \ell, k \le k':\ \frac{k}{\ell + k} \le \frac{k'}{\ell + k'},\ \text{i.e. } k\,(\ell + k') \le k'\,(\ell + k)$$
So a pool of one is the smallest share under saturation, and any larger pool is at least as fast. -/
theorem share_mono (l k k' : Nat) (h : k ≤ k') : k * (l + k') ≤ k' * (l + k) := by
  have : k * l ≤ k' * l := Nat.mul_le_mul_right l h
  calc k * (l + k') = k * l + k * k' := by rw [Nat.mul_add]
    _ ≤ k' * l + k' * k := by rw [Nat.mul_comm k' k]; omega
    _ = k' * (l + k) := by rw [Nat.mul_add]

/-- **The others keep at least two thirds.** If the pool is at most half the other load, the others' share
`ℓ / (ℓ + k)` is at least `2/3` (cross-multiplied: `2 (ℓ + k) ≤ 3 ℓ`).
$$\forall \ell, k:\ 2k \le \ell \Rightarrow \frac{2}{3} \le \frac{\ell}{\ell + k},\ \text{i.e. } 2\,(\ell + k) \le 3\,\ell$$ -/
theorem others_share_floor (l k : Nat) (h : 2 * k ≤ l) : 2 * (l + k) ≤ 3 * l := by omega

/-- **Under saturation the floor costs the others at most a third.** When the load is at least the cores
(`c ≤ ℓ`, the case where the old rule gives a pool of one) the proposal's pool `k = ⌊c/2⌋` satisfies `2k ≤ ℓ`, so
`others_share_floor` applies.
$$\forall c, \ell:\ c \le \ell \Rightarrow 2\,\operatorname{poolFair}(c, \ell) \le \ell \ \lor\ \operatorname{poolFair}(c,\ell) = 1$$ -/
theorem poolFair_saturated (c l : Nat) (h : c ≤ l) : 2 * poolFair c l ≤ l ∨ poolFair c l = 1 := by
  unfold poolFair; omega

#guard poolFair 8 0 == 8
#guard poolFair 8 3 == 5
#guard poolFair 8 4 == 4
#guard poolFair 8 5 == 4
#guard poolFair 8 20 == 4
#guard poolFair 10 23 == 5
#guard poolFair 1 9 == 1
#guard poolFair 0 0 == 1
#guard poolSize 8 5 == 3
#guard poolSize 8 20 == 1

/-! ## The timeout fallback: a check that timed out under load re-runs alone -/

/-- Re-run a check alone iff it failed and its output shows a failure that load can cause (a timeout). Here `r` = the
first run passed, `f` = the output shows a load failure.
$$\operatorname{rerun}(r, f) = \neg r \land f$$ -/
def rerunAlone (passed loadFailure : Bool) : Bool := !passed && loadFailure

/-- The pool a re-run uses: one check, alone.
$$\operatorname{rerunPool} = 1$$ -/
def rerunPool : Nat := 1

/-- The result that counts: the re-run's when there was one, else the first run's.
$$\operatorname{settle}(r, f, r') = \begin{cases} r' & \operatorname{rerun}(r, f) \\ r & \text{otherwise} \end{cases}$$ -/
def settle (passed loadFailure second : Bool) : Bool := if rerunAlone passed loadFailure then second else passed

/-- A passing check is never re-run.
$$\forall f:\ \operatorname{rerun}(\top, f) = \bot$$ -/
theorem rerunAlone_pass (f : Bool) : rerunAlone true f = false := by simp [rerunAlone]

/-- A failure without a load signature is final: the code, not the load, failed it.
$$\forall r:\ \operatorname{rerun}(r, \bot) = \bot$$ -/
theorem rerunAlone_noload (r : Bool) : rerunAlone r false = false := by simp [rerunAlone]

/-- A timed-out check re-runs.
$$\operatorname{rerun}(\bot, \top) = \top$$ -/
theorem rerunAlone_timeout : rerunAlone false true = true := rfl

/-- The re-run is alone: its pool is one, never more than the pool of the land.
$$\forall c, \ell:\ \operatorname{rerunPool} = 1 \le \operatorname{poolFair}(c, \ell)$$ -/
theorem rerunPool_le (c l : Nat) : rerunPool ≤ poolFair c l := poolFair_pos c l

/-- After a re-run, the re-run's result counts.
$$\operatorname{rerun}(r, f) \Rightarrow \operatorname{settle}(r, f, r') = r'$$ -/
theorem settle_rerun (r f r' : Bool) (h : rerunAlone r f = true) : settle r f r' = r' := by simp [settle, h]

/-- Without a re-run, the first result counts.
$$\neg\operatorname{rerun}(r, f) \Rightarrow \operatorname{settle}(r, f, r') = r$$ -/
theorem settle_norerun (r f r' : Bool) (h : rerunAlone r f = false) : settle r f r' = r := by simp [settle, h]

/-- A pass stays a pass, and a failure that is not a load failure stays a failure.
$$\forall r, f, r':\ r = \top \lor f = \bot \Rightarrow \operatorname{settle}(r, f, r') = r$$ -/
theorem settle_first (r f r' : Bool) (h : r = true ∨ f = false) : settle r f r' = r := by
  rcases h with rfl | rfl <;> simp [settle, rerunAlone]

/-- **The pool size and the re-run change no verdict.** Whatever order the settled results arrive in (any pool, serial or
not), the land's verdict is the same.
$$\forall E, D \sim D':\ \operatorname{verdict}(E, D) = \operatorname{verdict}(E, D')$$ -/
theorem verdict_pool_free (expected : List String) (done done' : List (String × Bool)) (hp : done.Perm done') :
    verdict expected done = verdict expected done' := verdict_perm expected done done' hp

#guard rerunAlone false true
#guard !rerunAlone false false
#guard !rerunAlone true true
#guard settle false true true
#guard !settle false false true

end Fw.Console.LandPool
