import Lean.Data.Json
/-!
# Pixel verdict of the visual diff (tasks `visual-diff`, `visual-diff-2`)

The breakpoint gate compares computed styles; it cannot see a fallback font drawing other glyphs, a stacking order or
paint. The visual diff screenshots each part's box in the original and in the rewrite, compares the two images, and
reduces the comparison to a few counts (`Stats`). This module is the pure part: from the counts, the capture's premises
and a per-part tolerance (`Tol`) it decides `pass`, `fail`, `unsettled`, `invalid` or `nc`. The TS side
(`packages/visual-diff/src/verdict.mjs`, `assets.mjs`) is checked against the golden vectors
`packages/contracts/golden/gate/pixel.jsonl` and `pixel-assets.jsonl`, which `goldenLines` and `assetFileLines` write.

Inputs, for one crop of one part at one probe on one engine ($\mathbb N$ throughout, no floats):
* $n$ = `total`, the pixels of the compared canvas (the larger of the two crops; pixels outside the smaller crop count as
  changed with delta 255, so a size mismatch is a change and never hidden);
* $c$ = `changed`, the pixels that differ and are not antialiasing;
* $a$ = `aa`, the pixels that differ and are classified as antialiasing only (the antialias-only mask);
* $\delta$ = `maxDelta`, the largest channel difference ($0..255$) over the $c$ pixels; $\delta_a$ = `aaMaxDelta`, the same
  over the $a$ pixels;
* $s$ = `settled`, whether both arms were settled (an input: the capture decides it, from the gate's settled-sample
  predicate `Fw.Gate.Settle.settled` on each arm and from two shots that agree within the part's tolerance; a page
  still animating is not a stable picture, so it is not judged);
* $p$ = `present`, whether at least one arm had a box to shoot (neither arm drew the part: nothing to compare, `nc`);
* $\phi$ = `fontsLoaded` and $\iota$ = `imagesLoaded`, the premise on both arms: every declared font the crop's text uses
  is loaded and no font is loading or failed (`fontsLoaded` below), and every image in the crop is complete with a
  non-zero natural size (`imagesLoaded` below). Both are decided in the page from `document.fonts` and the `img`
  elements; a sample without them is a picture of a missing asset (serif fallback glyphs, grey placeholder boxes), not
  of the port, so it is `invalid`, never `fail` (first run, 39077035869: 0 of 240 cells passed for that reason).

Tolerance (per part): $\rho$ = `ppm`, the largest allowed changed fraction in parts per million; $\tau$ = `delta`, the
largest allowed channel delta; `countAA`, whether antialiasing-only pixels count as changes (default no).

Rules (proved below):
* `pixel_verdict_total`, `verdict_nc_iff`, `verdict_invalid_iff`, `verdict_unsettled_iff`, `verdict_pass_iff`,
  `verdict_fail_iff`: exactly one of the five outcomes holds, and each is characterised;
* `no_verdict_without_assets`: a pass or a fail exists only when fonts and images are loaded; `unloaded_never_fail`: an
  unloaded sample is `invalid`;
* `unsettled_never_pass`: an unsettled capture is never `pass`;
* `tolerance_monotone`: a looser tolerance never turns `pass` into `fail`;
* `identical_pass`: identical settled images with loaded assets pass under every tolerance;
* `aa_mask_ignores_aa`: with `countAA = false` the antialiasing pixels never change the verdict;
* the asset predicates (`Img.loaded`, `imagesLoaded`, `fontsLoaded`) and their characterising theorems.
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

/-- The counts one image comparison produces, with the capture's premises.

$$\mathrm{st} = (n, c, a, \delta, \delta_a, s, p, \phi, \iota) \in \mathbb N^{5} \times \mathbb B^{4}$$
-/
structure Stats where
  total : Nat
  changed : Nat
  aa : Nat
  maxDelta : Nat
  aaMaxDelta : Nat
  settled : Bool
  present : Bool
  fontsLoaded : Bool
  imagesLoaded : Bool
  deriving DecidableEq, Repr, Inhabited

/-- The outcome. `pass` and `fail` are the verdicts; the other three say why there is none.

$$\mathcal V = \{\mathrm{pass}, \mathrm{fail}, \mathrm{unsettled}, \mathrm{invalid}, \mathrm{nc}\}$$
-/
inductive Verdict where
  | pass
  | fail
  | unsettled
  | invalid
  | nc
  deriving DecidableEq, Repr, Inhabited

/-- Fonts and images were loaded on both arms.

$$\operatorname{assets}(st) \iff \phi \wedge \iota$$
-/
def assetsOk (st : Stats) : Bool := st.fontsLoaded && st.imagesLoaded

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

/-- **The verdict.** Order of the premises: nothing captured is `nc`; missing assets are `invalid`; an unstable picture is
`unsettled` (not judged); an empty canvas (nothing was captured) fails; otherwise pass exactly when `within`.

$$\operatorname{verdict}(t, st) = \begin{cases} \mathrm{nc} & \neg p \\ \mathrm{invalid} & p \wedge \neg(\phi \wedge \iota) \\ \mathrm{unsettled} & p \wedge \phi \wedge \iota \wedge \neg s \\ \mathrm{fail} & p \wedge \phi \wedge \iota \wedge s \wedge n = 0 \\ \mathrm{pass} & p \wedge \phi \wedge \iota \wedge s \wedge n > 0 \wedge \operatorname{within}(t, st) \\ \mathrm{fail} & p \wedge \phi \wedge \iota \wedge s \wedge n > 0 \wedge \neg \operatorname{within}(t, st) \end{cases}$$
-/
def verdict (t : Tol) (st : Stats) : Verdict :=
  if st.present = false then .nc
  else if assetsOk st = false then .invalid
  else if st.settled = false then .unsettled
  else if st.total = 0 then .fail
  else if within t st then .pass
  else .fail

/-- Tolerance order: $t_1 \preceq t_2$ ($t_2$ is at least as loose as $t_1$).

$$t_1 \preceq t_2 \iff \rho_1 \le \rho_2 \ \wedge\ \tau_1 \le \tau_2 \ \wedge\ (\mathit{countAA}_2 \Rightarrow \mathit{countAA}_1)$$
-/
def Tol.le (t1 t2 : Tol) : Prop := t1.ppm ≤ t2.ppm ∧ t1.delta ≤ t2.delta ∧ (t2.countAA = true → t1.countAA = true)

/-- Every outcome is one of the five (the function is total), and they exclude each other.

$$\forall t, st:\ \operatorname{verdict}(t, st) \in \{\mathrm{pass}, \mathrm{fail}, \mathrm{unsettled}, \mathrm{invalid}, \mathrm{nc}\}, \text{ exactly one}$$
-/
theorem pixel_verdict_total (t : Tol) (st : Stats) :
    (verdict t st = .pass ∧ verdict t st ≠ .fail ∧ verdict t st ≠ .unsettled ∧ verdict t st ≠ .invalid ∧ verdict t st ≠ .nc) ∨
    (verdict t st = .fail ∧ verdict t st ≠ .pass ∧ verdict t st ≠ .unsettled ∧ verdict t st ≠ .invalid ∧ verdict t st ≠ .nc) ∨
    (verdict t st = .unsettled ∧ verdict t st ≠ .pass ∧ verdict t st ≠ .fail ∧ verdict t st ≠ .invalid ∧ verdict t st ≠ .nc) ∨
    (verdict t st = .invalid ∧ verdict t st ≠ .pass ∧ verdict t st ≠ .fail ∧ verdict t st ≠ .unsettled ∧ verdict t st ≠ .nc) ∨
    (verdict t st = .nc ∧ verdict t st ≠ .pass ∧ verdict t st ≠ .fail ∧ verdict t st ≠ .unsettled ∧ verdict t st ≠ .invalid) := by
  cases h : verdict t st <;> simp

/-- The verdict is `nc` exactly when no arm had a box.

$$\forall t, st:\ \operatorname{verdict}(t, st) = \mathrm{nc} \iff p = \mathrm{false}$$
-/
theorem verdict_nc_iff (t : Tol) (st : Stats) :
    verdict t st = .nc ↔ st.present = false := by
  unfold verdict assetsOk
  cases hp : st.present <;> cases hf : st.fontsLoaded <;> cases hi : st.imagesLoaded <;> cases hs : st.settled <;>
    by_cases h0 : st.total = 0 <;> by_cases hw : within t st = true <;> simp [h0, hw]

/-- The verdict is `invalid` exactly when something was captured and fonts or images were not loaded.

$$\forall t, st:\ \operatorname{verdict}(t, st) = \mathrm{invalid} \iff p \wedge \neg(\phi \wedge \iota)$$
-/
theorem verdict_invalid_iff (t : Tol) (st : Stats) :
    verdict t st = .invalid ↔ st.present = true ∧ assetsOk st = false := by
  unfold verdict assetsOk
  cases hp : st.present <;> cases hf : st.fontsLoaded <;> cases hi : st.imagesLoaded <;> cases hs : st.settled <;>
    by_cases h0 : st.total = 0 <;> by_cases hw : within t st = true <;> simp [h0, hw]

/-- The verdict is `unsettled` exactly when the capture is present, its assets are loaded, and it was not settled.

$$\forall t, st:\ \operatorname{verdict}(t, st) = \mathrm{unsettled} \iff p \wedge \phi \wedge \iota \wedge s = \mathrm{false}$$
-/
theorem verdict_unsettled_iff (t : Tol) (st : Stats) :
    verdict t st = .unsettled ↔ st.present = true ∧ assetsOk st = true ∧ st.settled = false := by
  unfold verdict assetsOk
  cases hp : st.present <;> cases hf : st.fontsLoaded <;> cases hi : st.imagesLoaded <;> cases hs : st.settled <;>
    by_cases h0 : st.total = 0 <;> by_cases hw : within t st = true <;> simp [h0, hw]

/-- The verdict is `pass` exactly when the capture is present, loaded, settled, non-empty and within tolerance.

$$\forall t, st:\ \operatorname{verdict}(t, st) = \mathrm{pass} \iff p \wedge \phi \wedge \iota \wedge s \wedge n > 0 \wedge \operatorname{within}(t, st)$$
-/
theorem verdict_pass_iff (t : Tol) (st : Stats) :
    verdict t st = .pass ↔
      st.present = true ∧ assetsOk st = true ∧ st.settled = true ∧ 0 < st.total ∧ within t st = true := by
  unfold verdict assetsOk
  cases hp : st.present <;> cases hf : st.fontsLoaded <;> cases hi : st.imagesLoaded <;> cases hs : st.settled <;>
    by_cases h0 : st.total = 0 <;> by_cases hw : within t st = true <;> simp [h0, hw] <;> omega

/-- The verdict is `fail` exactly when the capture is present, loaded, settled and empty or out of tolerance.

$$\forall t, st:\ \operatorname{verdict}(t, st) = \mathrm{fail} \iff p \wedge \phi \wedge \iota \wedge s \wedge (n = 0 \vee \neg \operatorname{within}(t, st))$$
-/
theorem verdict_fail_iff (t : Tol) (st : Stats) :
    verdict t st = .fail ↔
      st.present = true ∧ assetsOk st = true ∧ st.settled = true ∧ (st.total = 0 ∨ within t st = false) := by
  unfold verdict assetsOk
  cases hp : st.present <;> cases hf : st.fontsLoaded <;> cases hi : st.imagesLoaded <;> cases hs : st.settled <;>
    by_cases h0 : st.total = 0 <;> by_cases hw : within t st = true <;> simp [h0, hw]

/-- **No pixel verdict without assets.** A `pass` or a `fail` exists only when the fonts and the images were loaded.

$$\forall t, st:\ \operatorname{verdict}(t, st) \in \{\mathrm{pass}, \mathrm{fail}\} \implies \phi \wedge \iota$$
-/
theorem no_verdict_without_assets (t : Tol) (st : Stats)
    (h : verdict t st = .pass ∨ verdict t st = .fail) :
    st.fontsLoaded = true ∧ st.imagesLoaded = true := by
  have : assetsOk st = true := by
    rcases h with h | h
    · exact ((verdict_pass_iff t st).1 h).2.1
    · exact ((verdict_fail_iff t st).1 h).2.1
  simpa [assetsOk] using this

/-- An unloaded sample that was captured is `invalid`, so it is never a `fail` (nor a `pass`).

$$\forall t, st:\ p \wedge \neg(\phi \wedge \iota) \implies \operatorname{verdict}(t, st) = \mathrm{invalid}$$
-/
theorem unloaded_is_invalid (t : Tol) (st : Stats) (hp : st.present = true) (h : assetsOk st = false) :
    verdict t st = .invalid :=
  (verdict_invalid_iff t st).2 ⟨hp, h⟩

/-- An unloaded sample is never a failure, whatever the counts.

$$\forall t, st:\ \neg(\phi \wedge \iota) \implies \operatorname{verdict}(t, st) \ne \mathrm{fail}$$
-/
theorem unloaded_never_fail (t : Tol) (st : Stats) (h : assetsOk st = false) :
    verdict t st ≠ .fail := by
  intro hf
  have := ((verdict_fail_iff t st).1 hf).2.1
  rw [h] at this
  exact absurd this (by simp)

/-- An unsettled capture is never `pass`, whatever the tolerance and whatever the counts.

$$\forall t, st:\ s = \mathrm{false} \implies \operatorname{verdict}(t, st) \ne \mathrm{pass}$$
-/
theorem unsettled_never_pass (t : Tol) (st : Stats) (h : st.settled = false) :
    verdict t st ≠ .pass := by
  intro hp
  have := (verdict_pass_iff t st).1 hp
  rw [h] at this
  exact absurd this.2.2.1 (by simp)

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
  obtain ⟨hpr, ha, hs, hn, hw⟩ := hp
  refine ⟨hpr, ha, hs, hn, ?_⟩
  obtain ⟨e1, e2⟩ := eff_antitone h st
  obtain ⟨p, d, _⟩ := h
  simp only [within, Bool.and_eq_true, decide_eq_true_eq] at hw ⊢
  obtain ⟨w1, w2⟩ := hw
  refine ⟨?_, Nat.le_trans e2 (Nat.le_trans w2 d)⟩
  have hm : t1.ppm * st.total ≤ t2.ppm * st.total := Nat.mul_le_mul_right _ p
  have hm2 : effChanged t2 st * 1000000 ≤ effChanged t1 st * 1000000 := Nat.mul_le_mul_right _ e1
  exact Nat.le_trans hm2 (Nat.le_trans w1 hm)

/-- Identical, present, loaded, settled, non-empty images pass under every tolerance.

$$\forall t, st:\ p \wedge \phi \wedge \iota \wedge s \wedge n > 0 \wedge c = a = \delta = \delta_a = 0 \implies \operatorname{verdict}(t, st) = \mathrm{pass}$$
-/
theorem identical_pass (t : Tol) (st : Stats) (hp : st.present = true) (hf : st.fontsLoaded = true)
    (hi : st.imagesLoaded = true) (hs : st.settled = true) (hn : 0 < st.total)
    (hc : st.changed = 0) (ha : st.aa = 0) (hd : st.maxDelta = 0) (hda : st.aaMaxDelta = 0) :
    verdict t st = .pass := by
  rw [verdict_pass_iff]
  refine ⟨hp, by simp [assetsOk, hf, hi], hs, hn, ?_⟩
  simp [within, effChanged, effDelta, hc, ha, hd, hda]

/-- With antialiasing off the mask, antialiasing-only pixels never change the verdict: two captures that differ only in
$a$ and $\delta_a$ get the same verdict.

$$\forall t, st, a', d':\ \mathit{countAA}_t = \mathrm{false} \implies \operatorname{verdict}(t, st) = \operatorname{verdict}(t, st[a := a', \delta_a := d'])$$
-/
theorem aa_mask_ignores_aa (t : Tol) (ht : t.countAA = false) (st : Stats) (a' d' : Nat) :
    verdict t st = verdict t { st with aa := a', aaMaxDelta := d' } := by
  simp [verdict, assetsOk, within, effChanged, effDelta, ht]

/-! ## The asset premise

What the page reports, reduced to two booleans. The page lists the images that touch the crop and the font faces of
`document.fonts`, with the first family of every element in the crop that carries text. The decision is made here.
-/

/-- One `img` element that touches the crop, as the page sees it: `complete` and the natural size.

$$\mathrm{img} = (\mathit{complete}, w, h) \in \mathbb B \times \mathbb N \times \mathbb N$$
-/
structure Img where
  complete : Bool
  w : Nat
  h : Nat
  deriving DecidableEq, Repr

/-- An image is loaded when it is complete and has a non-zero natural size (a failed load is `complete` with size 0).

$$\operatorname{loaded}(i) \iff \mathit{complete}_i \wedge w_i > 0 \wedge h_i > 0$$
-/
def Img.loaded (i : Img) : Bool := i.complete && decide (0 < i.w) && decide (0 < i.h)

/-- All images that touch the crop are loaded (no image: true).

$$\iota(\mathit{is}) \iff \forall i \in \mathit{is}:\ \operatorname{loaded}(i)$$
-/
def imagesLoaded (is : List Img) : Bool := is.all Img.loaded

/-- The status of one font face of `document.fonts`.

$$\mathrm{FaceStatus} = \{\mathrm{unloaded}, \mathrm{loading}, \mathrm{loaded}, \mathrm{error}\}$$
-/
inductive FaceStatus where
  | unloaded
  | loading
  | loaded
  | error
  deriving DecidableEq, Repr

/-- One font face: its family and status.

$$\mathrm{face} = (\mathit{family}, \mathit{status}) \in \Sigma^{*} \times \mathrm{FaceStatus}$$
-/
structure Face where
  family : String
  status : FaceStatus
  deriving DecidableEq, Repr

/-- The families the crop needs: the first family of every text element in the crop that the page declares a face for.
A family nobody declared (a system font, a generic) is not a font the page loads, so it is not needed.

$$\operatorname{needed}(F, \mathit{fs}) = \{\, f \in F \mid \exists x \in \mathit{fs}:\ \mathit{family}_x = f \,\}$$
-/
def needed (fams : List String) (faces : List Face) : List String :=
  fams.filter (fun f => faces.any (fun x => x.family == f))

/-- **Fonts loaded.** No face is loading or failed, and every needed family has a loaded face.

$$\phi(F, \mathit{fs}) \iff (\forall x \in \mathit{fs}:\ \mathit{status}_x \notin \{\mathrm{loading}, \mathrm{error}\}) \ \wedge\ \forall f \in \operatorname{needed}(F, \mathit{fs}):\ \exists x \in \mathit{fs}:\ \mathit{family}_x = f \wedge \mathit{status}_x = \mathrm{loaded}$$
-/
def fontsLoaded (fams : List String) (faces : List Face) : Bool :=
  faces.all (fun x => x.status != .loading && x.status != .error) &&
  (needed fams faces).all (fun f => faces.any (fun x => x.family == f && x.status == .loaded))

/-- An image list is loaded exactly when every image is complete with a non-zero size.

$$\iota(\mathit{is}) \iff \forall i \in \mathit{is}:\ \mathit{complete}_i \wedge w_i > 0 \wedge h_i > 0$$
-/
theorem imagesLoaded_iff (is : List Img) :
    imagesLoaded is = true ↔ ∀ i ∈ is, i.complete = true ∧ 0 < i.w ∧ 0 < i.h := by
  simp [imagesLoaded, Img.loaded, List.all_eq_true, and_assoc]

/-- A broken image (complete, natural size 0) is never loaded, so a placeholder box cannot produce a verdict.

$$\forall \mathit{is}, i \in \mathit{is}:\ w_i = 0 \implies \neg\, \iota(\mathit{is})$$
-/
theorem broken_image_blocks (is : List Img) (i : Img) (hi : i ∈ is) (h0 : i.w = 0) :
    imagesLoaded is = false := by
  cases hl : imagesLoaded is
  · rfl
  · have := (imagesLoaded_iff is).1 hl i hi
    omega

/-- A face still loading blocks the font premise.

$$\forall F, \mathit{fs}, x \in \mathit{fs}:\ \mathit{status}_x = \mathrm{loading} \implies \neg\, \phi(F, \mathit{fs})$$
-/
theorem loading_font_blocks (fams : List String) (faces : List Face) (x : Face) (hx : x ∈ faces)
    (h : x.status = .loading) : fontsLoaded fams faces = false := by
  cases hl : fontsLoaded fams faces
  · rfl
  · simp only [fontsLoaded, Bool.and_eq_true, List.all_eq_true] at hl
    have := hl.1 x hx
    simp [h] at this

/-- Fonts are loaded only if every needed family has a loaded face.

$$\phi(F, \mathit{fs}) \implies \forall f \in \operatorname{needed}(F, \mathit{fs}):\ \exists x \in \mathit{fs}:\ \mathit{family}_x = f \wedge \mathit{status}_x = \mathrm{loaded}$$
-/
theorem fontsLoaded_needed_loaded (fams : List String) (faces : List Face) (h : fontsLoaded fams faces = true) :
    ∀ f ∈ needed fams faces, ∃ x ∈ faces, x.family = f ∧ x.status = .loaded := by
  intro f hf
  simp only [fontsLoaded, Bool.and_eq_true, List.all_eq_true] at h
  have := h.2 f hf
  simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at this
  obtain ⟨x, hx, h1, h2⟩ := this
  exact ⟨x, hx, h1, h2⟩

/-- An arm that declares no face at all makes the font premise vacuous: its text is drawn in a fallback font and the
pixel comparison fails on it (a port difference), it is not `invalid`. The harness therefore gives the rewrite arm the
original's faces (see `docs/team/tools/visual-diff.md`), so that the premise has something to check.

$$\phi(F, \varnothing)$$
-/
theorem fontsLoaded_no_faces (fams : List String) : fontsLoaded fams [] = true := by
  simp [fontsLoaded, needed]

/-! ## What the capture feeds `Stats.settled` and `Stats.present`

Each arm either has no box (`none`: the part is absent in that arm) or was shot (`some`) with two facts: `gate`, the
gate's settled-sample predicate `Fw.Gate.Settle.settled` held for the crop's subtree (nothing animates, enough real frames,
enough quiet frames, the pointer not inside), and `calm`, the arm's two shots 200 ms apart agree within the part's
tolerance (the gate predicate sees boxes, transforms and opacity, not paint; the pair sees paint).
-/

/-- One shot arm's facts: the two settle facts and the two asset facts (`fonts` is `fontsLoaded` of the arm's page, `images`
is `imagesLoaded`; both decided from the page's report by the rules above).

$$\mathrm{arm} = (\mathit{gate}, \mathit{calm}, \mathit{fonts}, \mathit{images}) \in \mathbb B^{4}$$
-/
structure Arm where
  gate : Bool
  calm : Bool
  fonts : Bool
  images : Bool
  deriving DecidableEq, Repr

/-- The fonts premise of the capture: every shot arm has its fonts loaded (an absent arm has none to load).

$$\phi = \forall X \in \{A, B\}:\ X = \mathrm{some}(\cdot) \implies \mathit{fonts}_X$$
-/
def fontsBoth (a b : Option Arm) : Bool := (a.all Arm.fonts) && (b.all Arm.fonts)

/-- The images premise of the capture: every shot arm has its images loaded.

$$\iota = \forall X \in \{A, B\}:\ X = \mathrm{some}(\cdot) \implies \mathit{images}_X$$
-/
def imagesBoth (a b : Option Arm) : Bool := (a.all Arm.images) && (b.all Arm.images)

/-- An arm is settled when both facts hold; an absent arm does not block (it draws nothing that could move).

$$\operatorname{ok}(\mathrm{none}) = \top, \quad \operatorname{ok}(\mathrm{some}(g, c)) = g \wedge c$$
-/
def Arm.ok : Option Arm → Bool
  | none => true
  | some a => a.gate && a.calm

/-- `Stats.settled`: both arms are settled.

$$s = \operatorname{ok}(A) \wedge \operatorname{ok}(B)$$
-/
def settledBoth (a b : Option Arm) : Bool := Arm.ok a && Arm.ok b

/-- `Stats.present`: at least one arm had a box.

$$p = A \ne \mathrm{none} \vee B \ne \mathrm{none}$$
-/
def presentAny (a b : Option Arm) : Bool := a.isSome || b.isSome

/-- Settled exactly when no shot arm failed a fact.

$$s \iff \forall X \in \{A, B\}:\ X = \mathrm{some}(g, c) \implies g \wedge c$$
-/
theorem settledBoth_iff (a b : Option Arm) :
    settledBoth a b = true ↔ ∀ x ∈ [a, b], ∀ y, x = some y → y.gate = true ∧ y.calm = true := by
  cases a <;> cases b <;> simp [settledBoth, Arm.ok, Bool.and_eq_true]

/-- A shot arm that the gate predicate rejects makes the capture unsettled, so never a pass (`unsettled_never_pass`).

$$g = \mathrm{false} \implies s = \mathrm{false}$$
-/
theorem gate_unsettled_blocks (a b : Option Arm) (c f i : Bool) (h : a = some ⟨false, c, f, i⟩) :
    settledBoth a b = false := by
  subst h
  simp [settledBoth, Arm.ok]

/-- A shot arm whose fonts are not loaded makes the capture's font premise false, so its verdict is `invalid` (given the
box was captured).

$$\mathit{fonts}_A = \mathrm{false} \implies \phi = \mathrm{false}$$
-/
theorem unloaded_arm_blocks_fonts (a b : Option Arm) (g c i : Bool) (h : a = some ⟨g, c, false, i⟩) :
    fontsBoth a b = false := by
  subst h
  simp [fontsBoth]

/-- Likewise for images.

$$\mathit{images}_A = \mathrm{false} \implies \iota = \mathrm{false}$$
-/
theorem unloaded_arm_blocks_images (a b : Option Arm) (g c f : Bool) (h : a = some ⟨g, c, f, false⟩) :
    imagesBoth a b = false := by
  subst h
  simp [imagesBoth]

/-! ## Golden vectors -/

/-- A golden case: a name, the tolerance and the counts.

$$\mathrm{case} = (\mathit{name}, t, st) \in \Sigma^{*} \times \mathrm{Tol} \times \mathrm{Stats}$$
-/
structure Case where
  name : String
  tol : Tol
  st : Stats

/-- The wire name of a verdict.

$$\mathrm{name}: \mathcal V \to \{\text{pass}, \text{fail}, \text{unsettled}, \text{invalid}, \text{nc}\}$$
-/
def Verdict.name : Verdict → String
  | .pass => "pass"
  | .fail => "fail"
  | .unsettled => "unsettled"
  | .invalid => "invalid"
  | .nc => "nc"

private def tolJson (t : Tol) : Json :=
  Json.mkObj [("ppm", t.ppm), ("delta", t.delta), ("countAA", t.countAA)]

private def statsJson (s : Stats) : Json :=
  Json.mkObj [("total", s.total), ("changed", s.changed), ("aa", s.aa), ("maxDelta", s.maxDelta),
              ("aaMaxDelta", s.aaMaxDelta), ("settled", s.settled), ("present", s.present),
              ("fontsLoaded", s.fontsLoaded), ("imagesLoaded", s.imagesLoaded)]

private def mk (name : String) (t : Tol) (total changed aa md amd : Nat) (settled : Bool := true)
    (present : Bool := true) (fonts : Bool := true) (images : Bool := true) : Case :=
  { name, tol := t, st := { total, changed, aa, maxDelta := md, aaMaxDelta := amd, settled, present,
                            fontsLoaded := fonts, imagesLoaded := images } }

/-- The cases: both sides of every threshold edge, the antialiasing switch, the empty canvas, the unsettled flag, and
each premise (absent, fonts not loaded, images not loaded) alone and with the others.

$$\mathrm{cases} \in \mathrm{Case}^{*}, \quad |\mathrm{cases}| = 34$$
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
  , mk "fonts not loaded, identical counts: invalid" d 10000 0 0 0 0 true true false true
  , mk "fonts not loaded, far out of tolerance: invalid, not fail" d 10000 9000 0 255 0 true true false true
  , mk "images not loaded, identical counts: invalid" d 10000 0 0 0 0 true true true false
  , mk "images not loaded, far out of tolerance: invalid, not fail" d 10000 9000 0 255 0 true true true false
  , mk "neither loaded: invalid" d 10000 5 0 5 0 true true false false
  , mk "fonts not loaded and unsettled: invalid first" d 10000 5 0 5 0 false true false true
  , mk "images not loaded on an empty canvas: invalid, not fail" d 0 0 0 0 0 true true true false
  , mk "absent in both arms: nc" d 0 0 0 0 0 true false true true
  , mk "absent in both arms, assets flagged unloaded: nc first" d 0 0 0 0 0 false false false false
  , mk "loaded and present, one pixel over: fail" d 10000 21 0 10 0 true true true true
  , mk "loaded, present, unsettled: unsettled" d 10000 0 0 0 0 false true true true
  , mk "loaded, present, within: pass" d 10000 20 0 10 0 true true true true
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

/-- The wire name of a face status.

$$\mathrm{name}(\mathrm{unloaded}) = \text{unloaded},\ \dots$$
-/
def FaceStatus.name : FaceStatus → String
  | .unloaded => "unloaded"
  | .loading => "loading"
  | .loaded => "loaded"
  | .error => "error"

private def imgJson (i : Img) : Json := Json.mkObj [("complete", i.complete), ("w", i.w), ("h", i.h)]
private def faceJson (f : Face) : Json := Json.mkObj [("family", f.family), ("status", f.status.name)]
private def img (c : Bool) (w h : Nat) : Img := { complete := c, w, h }
private def face (f : String) (s : FaceStatus) : Face := { family := f, status := s }

/-- One line of `pixel-assets.jsonl` for the image rule.

$$\{\text{kind}: \text{images}, \mathit{name}, \mathit{images}, \iota(\mathit{images})\}$$
-/
def imageLine (name : String) (is : List Img) : String :=
  (Json.mkObj [("kind", "images"), ("name", name), ("images", Json.arr (is.map imgJson).toArray),
               ("loaded", imagesLoaded is)]).compress

/-- One line of `pixel-assets.jsonl` for the font rule.

$$\{\text{kind}: \text{fonts}, \mathit{name}, F, \mathit{fs}, \phi(F, \mathit{fs})\}$$
-/
def fontLine (name : String) (fams : List String) (faces : List Face) : String :=
  (Json.mkObj [("kind", "fonts"), ("name", name), ("families", Json.arr (fams.map Json.str).toArray),
               ("faces", Json.arr (faces.map faceJson).toArray), ("loaded", fontsLoaded fams faces)]).compress

/-- The asset golden lines: both sides of every clause of both rules.

$$|\mathrm{assetLines}| = 20$$
-/
def assetLines : List String :=
  [ imageLine "no image" []
  , imageLine "one loaded image" [img true 100 50]
  , imageLine "image still loading" [img false 0 0]
  , imageLine "broken image: complete with natural size 0" [img true 0 0]
  , imageLine "zero width" [img true 0 50]
  , imageLine "zero height" [img true 100 0]
  , imageLine "one broken among loaded" [img true 10 10, img true 0 0, img true 5 5]
  , imageLine "incomplete with a size (decoding)" [img false 10 10]
  , fontLine "no faces declared (nothing to wait for)" ["Google Sans"] []
  , fontLine "needed face loaded" ["Google Sans"] [face "Google Sans" .loaded]
  , fontLine "needed face unloaded (never used)" ["Google Sans"] [face "Google Sans" .unloaded]
  , fontLine "needed face loading" ["Google Sans"] [face "Google Sans" .loading]
  , fontLine "needed face failed" ["Google Sans"] [face "Google Sans" .error]
  , fontLine "an unrelated face is loading" ["Google Sans"] [face "Google Sans" .loaded, face "Other" .loading]
  , fontLine "an unrelated face failed" [] [face "Other" .error]
  , fontLine "an unrelated unloaded face is fine" ["Google Sans"] [face "Google Sans" .loaded, face "Playpen" .unloaded]
  , fontLine "family used but not declared is not needed" ["Times New Roman"] [face "Google Sans" .loaded]
  , fontLine "two needed, one unloaded" ["Google Sans", "Playpen"] [face "Google Sans" .loaded, face "Playpen" .unloaded]
  , fontLine "two faces of one family, one loaded" ["Google Sans"] [face "Google Sans" .unloaded, face "Google Sans" .loaded]
  , fontLine "nothing used, nothing declared" [] []
  ]

private def armJson : Option Arm → Json
  | none => Json.null
  | some a => Json.mkObj [("gate", a.gate), ("calm", a.calm), ("fonts", a.fonts), ("images", a.images)]

/-- One line of `pixel-assets.jsonl` for the arm rules.

$$\{\text{kind}: \text{settle}, \mathit{name}, A, B, s, p, \phi, \iota\}$$
-/
def settleLine (name : String) (a b : Option Arm) : String :=
  (Json.mkObj [("kind", "settle"), ("name", name), ("a", armJson a), ("b", armJson b),
               ("settled", settledBoth a b), ("present", presentAny a b),
               ("fontsLoaded", fontsBoth a b), ("imagesLoaded", imagesBoth a b)]).compress

private def arm (g c : Bool) (f i : Bool := true) : Option Arm := some { gate := g, calm := c, fonts := f, images := i }

/-- The arm golden lines.

$$|\mathrm{settleLines}| = 12$$
-/
def settleLines : List String :=
  [ settleLine "both shot, all facts" (arm true true) (arm true true)
  , settleLine "gate predicate fails on the original" (arm false true) (arm true true)
  , settleLine "gate predicate fails on the rewrite" (arm true true) (arm false true)
  , settleLine "shots disagree on the original" (arm true false) (arm true true)
  , settleLine "shots disagree on the rewrite" (arm true true) (arm true false)
  , settleLine "original absent, rewrite settled" none (arm true true)
  , settleLine "rewrite absent, original unsettled" (arm false false) none
  , settleLine "both absent" none none
  , settleLine "fonts not loaded on the rewrite" (arm true true) (arm true true false true)
  , settleLine "images not loaded on the original" (arm true true true false) (arm true true)
  , settleLine "unloaded arm absent: nothing to load" none (arm true true)
  , settleLine "unloaded but the other arm absent" (arm true true false false) none
  ]

/-- The text of `packages/contracts/golden/gate/pixel-assets.jsonl`: the asset lines, then the arm lines.

$$\mathrm{assetFileLines} = \mathrm{assetLines} \mathbin{+\!+} \mathrm{settleLines}$$
-/
def assetFileLines : List String := assetLines ++ settleLines

-- Edge cases keep their outcome (checked when this module builds).
#guard verdict {} (mk "" {} 10000 20 0 10 0).st = .pass
#guard verdict {} (mk "" {} 10000 21 0 10 0).st = .fail
#guard verdict {} (mk "" {} 10000 0 0 0 0 false).st = .unsettled
#guard verdict {} (mk "" {} 0 0 0 0 0).st = .fail
#guard verdict {} (mk "" {} 10000 9000 0 255 0 true true false true).st = .invalid
#guard verdict {} (mk "" {} 0 0 0 0 0 true false true true).st = .nc
#guard cases.length = 34
#guard assetLines.length = 20
#guard settleLines.length = 12
#guard settledBoth none none = true
#guard presentAny none none = false
#guard fontsLoaded ["Google Sans"] [face "Google Sans" .loading] = false
#guard imagesLoaded [img true 0 0] = false

end Fw.Gate.Pixel
