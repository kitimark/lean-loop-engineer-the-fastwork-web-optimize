import Lean.Data.Json
/-!
# Pixel verdict of the visual diff (task `visual-diff`)

The breakpoint gate compares computed styles; it cannot see a fallback font drawing other glyphs, a stacking order or
paint. The visual diff screenshots each part's box in the original and in the rewrite, compares the two images, and
reduces the comparison to a few counts (`Stats`). This module is the pure part: from the counts and a per-part
tolerance (`Tol`) it decides `pass`, `fail` or `unsettled`. The TS side (`packages/visual-diff/src/verdict.mjs`) is
checked against the golden vectors `packages/contracts/golden/gate/pixel.jsonl`, which `goldenLines` writes.

Inputs, for one crop of one part at one probe on one engine ($\mathbb N$ throughout, no floats):
* $n$ = `total`, the pixels of the compared canvas (the larger of the two crops; pixels outside the smaller crop count as
  changed with delta 255, so a size mismatch is a change and never hidden);
* $c$ = `changed`, the pixels that differ and are not antialiasing;
* $a$ = `aa`, the pixels that differ and are classified as antialiasing only (the antialias-only mask);
* $\delta$ = `maxDelta`, the largest channel difference ($0..255$) over the $c$ pixels; $\delta_a$ = `aaMaxDelta`, the same
  over the $a$ pixels;
* $s$ = `settled`, whether both arms drew the same pixels twice in a row (an input: the capture decides it; a page
  still animating is not a stable picture, so it is not judged).

Tolerance (per part): $\rho$ = `ppm`, the largest allowed changed fraction in parts per million; $\tau$ = `delta`, the
largest allowed channel delta; `countAA`, whether antialiasing-only pixels count as changes (default no).

Rules (proved below):
* `pixel_verdict_total`, `verdict_unsettled_iff`, `verdict_pass_iff`, `verdict_fail_iff`: exactly one of pass, fail,
  unsettled holds, and each is characterised;
* `unsettled_never_pass`: an unsettled capture is never `pass`;
* `tolerance_monotone`: a looser tolerance never turns `pass` into `fail`;
* `identical_pass`: identical settled images pass under every tolerance;
* `aa_mask_ignores_aa`: with `countAA = false` the antialiasing pixels never change the verdict.
-/
namespace Fw.Gate.Pixel
open Lean

/-- The tolerance of one part. Looser means larger `ppm`, larger `delta`, and `countAA` off.

$$\mathrm{tol} = (\rho, \tau, \mathit{countAA}) \in \mathbb N \times \mathbb N \times \mathbb B$$
-/
structure Tol where
  ppm : Nat := 2000
  delta : Nat := 64
  countAA : Bool := false
  deriving DecidableEq, Repr, Inhabited

/-- The counts one image comparison produces.

$$\mathrm{st} = (n, c, a, \delta, \delta_a, s) \in \mathbb N^{5} \times \mathbb B$$
-/
structure Stats where
  total : Nat
  changed : Nat
  aa : Nat
  maxDelta : Nat
  aaMaxDelta : Nat
  settled : Bool
  deriving DecidableEq, Repr, Inhabited

/-- The outcome.

$$\mathcal V = \{\mathrm{pass}, \mathrm{fail}, \mathrm{unsettled}\}$$
-/
inductive Verdict where
  | pass
  | fail
  | unsettled
  deriving DecidableEq, Repr, Inhabited

/-- The pixels counted as changed under a tolerance: $c$, plus $a$ when antialiasing counts.

$$\operatorname{eff}(t, st) = c + [\mathit{countAA}_t]\, a$$
-/
def effChanged (t : Tol) (st : Stats) : Nat := st.changed + (if t.countAA then st.aa else 0)

/-- The largest counted channel delta: $\delta$, joined with $\delta_a$ when antialiasing counts.

$$\operatorname{effD}(t, st) = \max(\delta,\ [\mathit{countAA}_t]\, \delta_a)$$
-/
def effDelta (t : Tol) (st : Stats) : Nat := max st.maxDelta (if t.countAA then st.aaMaxDelta else 0)

/-- The comparison within tolerance, for a settled, non-empty canvas: the changed fraction is at most $\rho$ ppm and
the largest delta at most $\tau$.

$$\operatorname{within}(t, st) \iff 10^{6} \cdot \operatorname{eff}(t, st) \le \rho_t \cdot n \ \wedge\ \operatorname{effD}(t, st) \le \tau_t$$
-/
def within (t : Tol) (st : Stats) : Bool :=
  decide (effChanged t st * 1000000 ≤ t.ppm * st.total) && decide (effDelta t st ≤ t.delta)

/-- **The verdict.** Unsettled first (an unstable picture is not judged); an empty canvas (nothing was captured) fails;
otherwise pass exactly when `within`.

$$\operatorname{verdict}(t, st) = \begin{cases} \mathrm{unsettled} & s = \mathrm{false} \\ \mathrm{fail} & s \wedge n = 0 \\ \mathrm{pass} & s \wedge n > 0 \wedge \operatorname{within}(t, st) \\ \mathrm{fail} & s \wedge n > 0 \wedge \neg \operatorname{within}(t, st) \end{cases}$$
-/
def verdict (t : Tol) (st : Stats) : Verdict :=
  if st.settled = false then .unsettled
  else if st.total = 0 then .fail
  else if within t st then .pass
  else .fail

/-- Tolerance order: $t_1 \preceq t_2$ ($t_2$ is at least as loose as $t_1$).

$$t_1 \preceq t_2 \iff \rho_1 \le \rho_2 \ \wedge\ \tau_1 \le \tau_2 \ \wedge\ (\mathit{countAA}_2 \Rightarrow \mathit{countAA}_1)$$
-/
def Tol.le (t1 t2 : Tol) : Prop := t1.ppm ≤ t2.ppm ∧ t1.delta ≤ t2.delta ∧ (t2.countAA = true → t1.countAA = true)

/-- Every outcome is pass, fail or unsettled (the function is total), and they exclude each other.

$$\forall t, st:\ \operatorname{verdict}(t, st) \in \{\mathrm{pass}, \mathrm{fail}, \mathrm{unsettled}\}, \text{ exactly one}$$
-/
theorem pixel_verdict_total (t : Tol) (st : Stats) :
    (verdict t st = .pass ∧ verdict t st ≠ .fail ∧ verdict t st ≠ .unsettled) ∨
    (verdict t st = .fail ∧ verdict t st ≠ .pass ∧ verdict t st ≠ .unsettled) ∨
    (verdict t st = .unsettled ∧ verdict t st ≠ .pass ∧ verdict t st ≠ .fail) := by
  cases h : verdict t st <;> simp

/-- The verdict is `unsettled` exactly when the capture was not settled.

$$\forall t, st:\ \operatorname{verdict}(t, st) = \mathrm{unsettled} \iff s = \mathrm{false}$$
-/
theorem verdict_unsettled_iff (t : Tol) (st : Stats) :
    verdict t st = .unsettled ↔ st.settled = false := by
  unfold verdict
  cases hs : st.settled <;> by_cases h0 : st.total = 0 <;> by_cases hw : within t st = true <;> simp [h0, hw]

/-- The verdict is `pass` exactly when the capture is settled, non-empty and within tolerance.

$$\forall t, st:\ \operatorname{verdict}(t, st) = \mathrm{pass} \iff s \wedge n > 0 \wedge \operatorname{within}(t, st)$$
-/
theorem verdict_pass_iff (t : Tol) (st : Stats) :
    verdict t st = .pass ↔ st.settled = true ∧ 0 < st.total ∧ within t st = true := by
  unfold verdict
  cases hs : st.settled <;> by_cases h0 : st.total = 0 <;> by_cases hw : within t st = true <;> simp [h0, hw] <;> omega

/-- The verdict is `fail` exactly when the capture is settled and empty or out of tolerance.

$$\forall t, st:\ \operatorname{verdict}(t, st) = \mathrm{fail} \iff s \wedge (n = 0 \vee \neg \operatorname{within}(t, st))$$
-/
theorem verdict_fail_iff (t : Tol) (st : Stats) :
    verdict t st = .fail ↔ st.settled = true ∧ (st.total = 0 ∨ within t st = false) := by
  unfold verdict
  cases hs : st.settled <;> by_cases h0 : st.total = 0 <;> by_cases hw : within t st = true <;> simp [h0, hw]

/-- An unsettled capture is never `pass`, whatever the tolerance and whatever the counts.

$$\forall t, st:\ s = \mathrm{false} \implies \operatorname{verdict}(t, st) \ne \mathrm{pass}$$
-/
theorem unsettled_never_pass (t : Tol) (st : Stats) (h : st.settled = false) :
    verdict t st ≠ .pass := by
  intro hp
  have := (verdict_pass_iff t st).1 hp
  rw [h] at this
  exact absurd this.1 (by simp)

/-- A looser tolerance counts fewer changes and a smaller delta.

$$\forall t_1, t_2, st:\ t_1 \preceq t_2 \implies \operatorname{eff}(t_2, st) \le \operatorname{eff}(t_1, st) \ \wedge\ \operatorname{effD}(t_2, st) \le \operatorname{effD}(t_1, st)$$
-/
theorem eff_antitone {t1 t2 : Tol} (h : t1.le t2) (st : Stats) :
    effChanged t2 st ≤ effChanged t1 st ∧ effDelta t2 st ≤ effDelta t1 st := by
  obtain ⟨_, _, h3⟩ := h
  unfold effChanged effDelta
  cases c1 : t1.countAA <;> cases c2 : t2.countAA <;> simp_all <;> omega

/-- A looser tolerance never turns `pass` into `fail`: if $t_1 \preceq t_2$ and $t_1$ passes, $t_2$ passes.

$$\forall t_1, t_2, st:\ t_1 \preceq t_2 \wedge \operatorname{verdict}(t_1, st) = \mathrm{pass} \implies \operatorname{verdict}(t_2, st) = \mathrm{pass}$$
-/
theorem tolerance_monotone {t1 t2 : Tol} (h : t1.le t2) (st : Stats)
    (hp : verdict t1 st = .pass) : verdict t2 st = .pass := by
  rw [verdict_pass_iff] at hp ⊢
  obtain ⟨hs, hn, hw⟩ := hp
  refine ⟨hs, hn, ?_⟩
  obtain ⟨e1, e2⟩ := eff_antitone h st
  obtain ⟨p, d, _⟩ := h
  simp only [within, Bool.and_eq_true, decide_eq_true_eq] at hw ⊢
  obtain ⟨w1, w2⟩ := hw
  refine ⟨?_, Nat.le_trans e2 (Nat.le_trans w2 d)⟩
  have hm : t1.ppm * st.total ≤ t2.ppm * st.total := Nat.mul_le_mul_right _ p
  have hm2 : effChanged t2 st * 1000000 ≤ effChanged t1 st * 1000000 := Nat.mul_le_mul_right _ e1
  exact Nat.le_trans hm2 (Nat.le_trans w1 hm)

/-- Identical, settled, non-empty images pass under every tolerance.

$$\forall t, st:\ s \wedge n > 0 \wedge c = a = \delta = \delta_a = 0 \implies \operatorname{verdict}(t, st) = \mathrm{pass}$$
-/
theorem identical_pass (t : Tol) (st : Stats) (hs : st.settled = true) (hn : 0 < st.total)
    (hc : st.changed = 0) (ha : st.aa = 0) (hd : st.maxDelta = 0) (hda : st.aaMaxDelta = 0) :
    verdict t st = .pass := by
  rw [verdict_pass_iff]
  refine ⟨hs, hn, ?_⟩
  simp [within, effChanged, effDelta, hc, ha, hd, hda]

/-- With antialiasing off the mask, antialiasing-only pixels never change the verdict: two captures that differ only in
$a$ and $\delta_a$ get the same verdict.

$$\forall t, st, a', d':\ \mathit{countAA}_t = \mathrm{false} \implies \operatorname{verdict}(t, st) = \operatorname{verdict}(t, st[a := a', \delta_a := d'])$$
-/
theorem aa_mask_ignores_aa (t : Tol) (ht : t.countAA = false) (st : Stats) (a' d' : Nat) :
    verdict t st = verdict t { st with aa := a', aaMaxDelta := d' } := by
  simp [verdict, within, effChanged, effDelta, ht]

/-! ## Golden vectors -/

/-- A golden case: a name, the tolerance and the counts.

$$\mathrm{case} = (\mathit{name}, t, st) \in \Sigma^{*} \times \mathrm{Tol} \times \mathrm{Stats}$$
-/
structure Case where
  name : String
  tol : Tol
  st : Stats

/-- The wire name of a verdict.

$$\mathrm{name}(\mathrm{pass}) = \text{pass},\ \mathrm{name}(\mathrm{fail}) = \text{fail},\ \mathrm{name}(\mathrm{unsettled}) = \text{unsettled}$$
-/
def Verdict.name : Verdict → String
  | .pass => "pass"
  | .fail => "fail"
  | .unsettled => "unsettled"

private def tolJson (t : Tol) : Json :=
  Json.mkObj [("ppm", t.ppm), ("delta", t.delta), ("countAA", t.countAA)]

private def statsJson (s : Stats) : Json :=
  Json.mkObj [("total", s.total), ("changed", s.changed), ("aa", s.aa), ("maxDelta", s.maxDelta),
              ("aaMaxDelta", s.aaMaxDelta), ("settled", s.settled)]

private def mk (name : String) (t : Tol) (total changed aa md amd : Nat) (settled : Bool := true) : Case :=
  { name, tol := t, st := { total, changed, aa, maxDelta := md, aaMaxDelta := amd, settled } }

/-- The cases: both sides of every threshold edge, the antialiasing switch, the empty canvas, the unsettled flag.

$$\mathrm{cases} \in \mathrm{Case}^{*}, \quad |\mathrm{cases}| = 22$$
-/
def cases : List Case :=
  let d : Tol := {}
  let strict : Tol := { ppm := 0, delta := 0 }
  let aa : Tol := { d with countAA := true }
  [ mk "identical" d 10000 0 0 0 0
  , mk "identical under the strictest tolerance" strict 10000 0 0 0 0
  , mk "ratio exactly at the limit (2000 ppm of 10000 = 20 px)" d 10000 20 0 10 0
  , mk "ratio one pixel over the limit" d 10000 21 0 10 0
  , mk "delta exactly at the limit" d 10000 1 0 64 0
  , mk "delta one over the limit" d 10000 1 0 65 0
  , mk "strict: one changed pixel fails" strict 10000 1 0 1 0
  , mk "strict: nothing counted passes" strict 10000 0 0 0 0
  , mk "antialiasing ignored: 5000 aa pixels, delta 255" d 10000 0 5000 0 255
  , mk "antialiasing counted: the same pixels fail" aa 10000 0 5000 0 255
  , mk "antialiasing counted: within the limit passes" aa 10000 10 10 20 30
  , mk "antialiasing counted: delta over the limit fails" aa 10000 0 1 0 65
  , mk "empty canvas fails" d 0 0 0 0 0
  , mk "empty canvas with counts still fails" d 0 5 0 0 0
  , mk "unsettled and identical" d 10000 0 0 0 0 false
  , mk "unsettled and far out of tolerance" d 10000 9000 0 255 0 false
  , mk "unsettled on an empty canvas" d 0 0 0 0 0 false
  , mk "loose tolerance: 10 percent allowed" { ppm := 100000, delta := 255 } 10000 1000 0 255 0
  , mk "loose tolerance: one pixel over 10 percent" { ppm := 100000, delta := 255 } 10000 1001 0 255 0
  , mk "large canvas: 2000 ppm of 4000000 is 8000 px" d 4000000 8000 0 64 0
  , mk "large canvas: 8001 px fails" d 4000000 8001 0 64 0
  , mk "single pixel canvas changed" { ppm := 1000000, delta := 255 } 1 1 0 255 0
  ]

/-- One line of `pixel.jsonl`: `{"name", "tol", "stats", "verdict"}`.

$$\mathrm{line}(c) = \{\mathit{name}, \mathit{tol}, \mathit{stats}, \operatorname{name}(\operatorname{verdict}(c.t, c.st))\}$$
-/
def Case.line (c : Case) : String :=
  (Json.mkObj [("name", c.name), ("tol", tolJson c.tol), ("stats", statsJson c.st),
               ("verdict", (verdict c.tol c.st).name)]).compress

/-- The text of `packages/contracts/golden/gate/pixel.jsonl`, one line per case.

$$\mathrm{goldenLines} = \operatorname{map}\ \mathrm{line}\ \mathrm{cases}$$
-/
def goldenLines : List String := cases.map Case.line

-- Edge cases keep their outcome (checked when this module builds).
#guard verdict {} (mk "" {} 10000 20 0 10 0).st = .pass
#guard verdict {} (mk "" {} 10000 21 0 10 0).st = .fail
#guard verdict {} (mk "" {} 10000 0 0 0 0 false).st = .unsettled
#guard verdict {} (mk "" {} 0 0 0 0 0).st = .fail

end Fw.Gate.Pixel
