import Fw.Gate.Shard

/-!
# Measured unit costs of the gate shard plan (task `gate-shard-balance`)

The cost table of `Fw.Gate.Shard` comes from a CI run of the gate. A job of that run is observed as a `JobObs`:
its fixed time (checkout, install, browser start, upload: the job's time outside the probe phase and the sweeps),
the wall time of its probe phase, a raw weight for each probe it ran, and the wall time of each whole sweep it ran.

The probe phase runs `conc` = 4 loads at once, so a probe's own wall time is not its share of the job. `reduce`
charges each probe its weight plus the job's per-probe overhead, divided by the concurrency and rounded up
(`probeCost`), so the probe costs of a job add up to at least its measured probe phase (`probeCost_cover`). The
setup of an engine is the rounded-up mean of its jobs' fixed times. The data lives in `Fw.Gate.ShardObs`
(generated from the run's logs and artifacts by `packages/gate-breakpoints/scripts/shard-obs.mjs`).
-/
namespace Fw.Gate.ShardCosts
open Fw.Gate.Shard

/-- The number of loads the probe phase of a job runs at once (`pool(tasks, concurrency, …)` in `run.mjs`, 4).

$$\mathrm{conc} = 4$$
-/
def conc : Nat := 4

/-- Division rounded up, on natural numbers.

$$\forall a, b,\quad \operatorname{cdiv}(a, b) = \left\lfloor \frac{a + b - 1}{b} \right\rfloor \quad (\text{Lean } \mathbb N \text{ division: } x / 0 = 0, \text{ so } \operatorname{cdiv}(a, 0) = 0)$$

The least $q$ with $q \cdot b \ge a$, for $b \ge 1$. -/
def cdiv (a b : Nat) : Nat := (a + b - 1) / b

#guard cdiv 7 4 == 2
#guard cdiv 8 4 == 2
#guard cdiv 0 4 == 0
#guard cdiv 5 0 == 0

/-- Rounding up covers the dividend.

$$\forall a, b,\quad b \ge 1 \Rightarrow a \le b \cdot \operatorname{cdiv}(a, b)$$
-/
theorem le_mul_cdiv (a b : Nat) (hb : 0 < b) : a ≤ b * cdiv a b := by
  unfold cdiv
  have h := Nat.div_add_mod (a + b - 1) b
  have hm := Nat.mod_lt (a + b - 1) hb
  omega

/-- Rounding up overshoots by less than the divisor.

$$\forall a, b,\quad b \ge 1 \Rightarrow b \cdot \operatorname{cdiv}(a, b) < a + b$$
-/
theorem mul_cdiv_lt (a b : Nat) (hb : 0 < b) : b * cdiv a b < a + b := by
  unfold cdiv
  have h := Nat.div_add_mod (a + b - 1) b
  omega

/-- One job of a measured run, in milliseconds.

$$\mathrm{JobObs} = (\text{setup}, \text{wall}, P, W), \quad P, W \in (\mathrm{String} \times \mathbb N)^{*}$$

`setup`: the job's time outside its probe phase and sweeps; `probeWall`: the wall time of its probe phase;
`probes`: each probe id with its raw weight (the sum of the settle waits of its two arms); `sweeps`: each whole
sweep it ran (`desktop`, `phone`, `touch`, `pain`) with its wall time. -/
structure JobObs where
  setup : Nat
  probeWall : Nat
  probes : List (String × Nat)
  sweeps : List (String × Nat)
deriving Repr

/-- The total raw weight of a job's probes.

$$\forall j,\quad \operatorname{weight}(j) = \sum_{(p, w) \in j.P} w$$
-/
def weight (j : JobObs) : Nat := (j.probes.map (·.2)).sum

/-- The per-probe overhead of a job: the part of its probe phase (times the concurrency) its weights do not
explain, spread evenly over its probes.

$$\forall j,\quad \operatorname{over}(j) = \left\lfloor \frac{\mathrm{conc} \cdot j.\text{wall} \mathbin{∸} \operatorname{weight}(j)}{\max(1, |j.P|)} \right\rfloor$$

Page load, navigation and measuring cost time even when nothing waits. -/
def over (j : JobObs) : Nat := (conc * j.probeWall - weight j) / max 1 j.probes.length

/-- The cost of a probe of raw weight $w$ that ran in job $j$.

$$\forall j, w,\quad \operatorname{probeCost}(j, w) = \operatorname{cdiv}(w + \operatorname{over}(j), \mathrm{conc})$$

Its weight plus the job's overhead, shared by the four loads running at once. -/
def probeCost (j : JobObs) (w : Nat) : Nat := cdiv (w + over j) conc

/-- The cost table and setup of one engine from its observed jobs: every probe with its `probeCost`, then every
sweep with its wall time; setup is the rounded-up mean of the jobs' fixed times.

$$\forall J,\quad \operatorname{reduce}(J) = \Big(\operatorname{cdiv}\big(\textstyle\sum_{j \in J} j.\text{setup}, |J|\big),\ [\,(p, \operatorname{probeCost}(j, w))\,]_{j \in J,\ (p, w) \in j.P} \mathbin{+\!\!+} [\,(s, t)\,]_{j \in J,\ (s, t) \in j.W}\Big)$$

With no jobs the setup is $\operatorname{cdiv}(0, 0) = 0$ and the table is empty. -/
def reduce (js : List JobObs) : EngCosts where
  setup := cdiv (js.map (·.setup)).sum js.length
  costs := js.flatMap (fun j => j.probes.map fun (p, w) => (p, probeCost j w)) ++ js.flatMap (·.sweeps)

#guard over { setup := 0, probeWall := 10, probes := [("a", 4), ("b", 6)], sweeps := [] } == 15
#guard probeCost { setup := 0, probeWall := 10, probes := [("a", 4), ("b", 6)], sweeps := [] } 4 == 5
#guard over { setup := 0, probeWall := 1, probes := [("a", 9)], sweeps := [] } == 0
#guard over { setup := 0, probeWall := 5, probes := [], sweeps := [] } == 20
#guard (reduce [{ setup := 3, probeWall := 10, probes := [("a", 4), ("b", 6)], sweeps := [("pain", 7)] },
    { setup := 4, probeWall := 0, probes := [], sweeps := [("phone", 9)] }]).costs ==
  [("a", 5), ("b", 6), ("pain", 7), ("phone", 9)]
#guard (reduce [{ setup := 3, probeWall := 0, probes := [], sweeps := [] },
    { setup := 4, probeWall := 0, probes := [], sweeps := [] }]).setup == 4
#guard (reduce []).setup == 0 ∧ (reduce []).costs == []

/-- A probe's cost covers its weight plus its job's overhead, shared four ways, and overshoots by less than one
millisecond per load slot.

$$\forall j, w,\quad w + \operatorname{over}(j) \le \mathrm{conc} \cdot \operatorname{probeCost}(j, w) < w + \operatorname{over}(j) + \mathrm{conc}$$
-/
theorem probeCost_bounds (j : JobObs) (w : Nat) :
    w + over j ≤ conc * probeCost j w ∧ conc * probeCost j w < w + over j + conc :=
  ⟨le_mul_cdiv _ _ (by decide), mul_cdiv_lt _ _ (by decide)⟩

/-- **The probe costs of a job cover its probe phase**, up to the rounding of the even overhead split: with $n \ge 1$
probes, $\mathrm{conc}$ times their summed cost is at least $\mathrm{conc}$ times the measured wall, less $n - 1$.

$$\forall j,\quad |j.P| \ge 1 \Rightarrow \mathrm{conc} \cdot j.\text{wall} \le \mathrm{conc} \cdot \sum_{(p, w) \in j.P} \operatorname{probeCost}(j, w) + (|j.P| - 1)$$

(The loss of $n - 1$ comes from rounding the overhead down; it is under 1 ms per probe.) -/
theorem probeCost_cover (j : JobObs) (hn : 0 < j.probes.length) :
    conc * j.probeWall ≤ conc * (j.probes.map fun (_, w) => probeCost j w).sum + (j.probes.length - 1) := by
  -- each probe: conc * cost ≥ w + over j, so conc * Σ cost ≥ weight + n * over
  have hsum : ∀ ps : List (String × Nat),
      (ps.map (·.2)).sum + ps.length * over j ≤ conc * (ps.map fun (_, w) => probeCost j w).sum := by
    intro ps
    induction ps with
    | nil => simp
    | cons p ps ih =>
      have h1 := (probeCost_bounds j p.2).1
      simp only [List.map_cons, List.sum_cons, List.length_cons, Nat.mul_add, Nat.succ_mul] at ih ⊢
      omega
  have hs := hsum j.probes
  have hmax : max 1 j.probes.length = j.probes.length := by omega
  have hdiv := Nat.div_add_mod (conc * j.probeWall - weight j) j.probes.length
  have hmod := Nat.mod_lt (conc * j.probeWall - weight j) hn
  unfold over at hs
  rw [hmax] at hs
  unfold weight at hdiv hmod
  have hw : weight j = (j.probes.map (·.2)).sum := rfl
  rw [hw] at hs
  omega

/-- Every observed unit is in the table, in observation order: the probes of each job, then the sweeps.

$$\forall J,\quad [\,u\,]_{(u, c) \in \operatorname{reduce}(J).\text{costs}} = [\,p\,]_{j \in J,\ (p, w) \in j.P} \mathbin{+\!\!+} [\,s\,]_{j \in J,\ (s, t) \in j.W}$$

So `costOf` charges a measured unit its own measured cost, unless an earlier job measured the same name. -/
theorem reduce_names (js : List JobObs) :
    (reduce js).costs.map (·.1) = js.flatMap (fun j => j.probes.map (·.1)) ++ js.flatMap (fun j => j.sweeps.map (·.1)) := by
  simp only [reduce, List.map_append, List.map_flatMap, List.map_map]
  rfl

end Fw.Gate.ShardCosts
