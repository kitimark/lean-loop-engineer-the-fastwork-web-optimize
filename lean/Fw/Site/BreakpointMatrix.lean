import Fw.Site.BreakpointFacts

/-!
# The breakpoint gate's test matrix, and the MUI-internal neutral queries

The inventory's §4 matrix (`matrix.featureCombos`, `matrix.estimate`): 124 loads per engine. Every probe is an
`Env`; the generator emits each probe with the expected truth value of all 30 conditions (golden vectors).

Proved here:
* `matrix_length`, `matrix_blocks`: 124 loads, split per block exactly as `matrix.estimate.breakdown`;
* `matrix_edge_pairs`: both sides `N` and `N+1` of every width edge in the profiles `desk`, `desk-rm`, `touch`, and
  of the five `touch-rm` edges; both sides of device-width 500 at viewports 1001, 1031, 1201;
* `matrix_observes_every_edge`: for every condition and every edge of it, the matrix has two probes of one block,
  agreeing on all discrete features, at `N` and `N+1` on that axis, where the condition **does** flip. With
  `MQ.eval_congr` this means the matrix sees every change of every condition, and every listed edge is real;
* `matrix_width_dpr_whole`: every probe asks for a whole number of device pixels across (width x DPR whole; the
  fractional probes run at DPR 2), and `fractional_dpr_indep`: the move from DPR 5/4 changed no expected value;
* the neutral set (MUI-internal media): `print` and `(forced-colors: active)` are false on every gate load;
  `(hover: hover)` / `(hover: none)` are the inventory's hover conditions and take both values in the
  hover × pointer crossing.
-/

namespace Fw.Site.Breakpoints

/-- The blocks of `matrix.estimate.breakdown`.

$$ b \in \{\text{desk}, \text{desk-rm}, \text{touch}, \text{touch-rm}, \text{phone-landscape}, \text{dw-arm-isolate}, \text{hover-pointer-cross}, \text{dark}, \text{fractional-gaps}, \text{height-probes}\} $$ -/
inductive Block
  | desk | deskRm | touch | touchRm | phoneLandscape | dwArmIsolate | hoverPointerCross | dark | fractionalGaps
  | heightProbes
deriving DecidableEq, Repr

/-- The inventory's block id.

$$ \mathrm{str}(b) \in \{\texttt{desk}, \texttt{desk-rm}, \dots, \texttt{height-probes}\} $$ -/
def Block.str : Block → String
  | .desk => "desk" | .deskRm => "desk-rm" | .touch => "touch" | .touchRm => "touch-rm"
  | .phoneLandscape => "phone-landscape" | .dwArmIsolate => "dw-arm-isolate"
  | .hoverPointerCross => "hover-pointer-cross" | .dark => "dark" | .fractionalGaps => "fractional-gaps"
  | .heightProbes => "height-probes"

/-- One page load of the gate: the matrix block it belongs to, an id suffix, and its environment.

$$ p = (b, t, e) \in \mathrm{Block} \times \Sigma^* \times \mathrm{Env} $$ -/
structure Probe where
  /-- block from `matrix.estimate.breakdown` -/
  block : Block
  /-- id suffix, unique inside the block, e.g. `600` -/
  tag : String
  /-- the environment of the load -/
  env : Env
deriving Repr

/-- Probe id: `<block>-<tag>`, e.g. `desk-600`.

$$ \mathrm{id}(b, t, e) = \mathrm{str}(b) \mathbin{+\!\!+} \texttt{-} \mathbin{+\!\!+} t $$ -/
def Probe.id (p : Probe) : String := s!"{p.block.str}-{p.tag}"

/-- The 15 width edges of `matrix.edgePairs` (edge `N` = the pair `N | N+1`).

$$ E_{15} = (319, 400, 461, 480, 600, 640, 720, 860, 960, 1000, 1030, 1100, 1200, 1279, 1511) $$ -/
def widthEdgePairs : List Nat := [319, 400, 461, 480, 600, 640, 720, 860, 960, 1000, 1030, 1100, 1200, 1279, 1511]

/-- The edges at which the `touch-rm` profile runs.

$$ E_t = (600, 860, 1000, 1030, 1200) $$ -/
def touchRmEdges : List Nat := [600, 860, 1000, 1030, 1200]

/-- A desktop load: hover, fine pointer, screen = viewport, light, screen media, no forced colors.

$$ \mathrm{desk}(w, h, r, \mu) = (w, h, d_w{=}w, d_h{=}h, r, \text{hover}, \text{fine}, \mu, \text{light}, \text{screen}, \text{none}) $$ -/
def deskEnv (w h : Px) (dpr : Px) (m : Motion) : Env :=
  { width := w, height := h, deviceWidth := w, deviceHeight := h, dpr := dpr,
    hover := .hover, pointer := .fine, motion := m, scheme := .light }

/-- A touch load: no hover, coarse pointer, screen = viewport, light, screen media, no forced colors.

$$ \mathrm{touch}(w, h, r, \mu) = (w, h, d_w{=}w, d_h{=}h, r, \text{none}, \text{coarse}, \mu, \text{light}, \text{screen}, \text{none}) $$ -/
def touchEnv (w h : Px) (dpr : Px) (m : Motion) : Env :=
  { width := w, height := h, deviceWidth := w, deviceHeight := h, dpr := dpr,
    hover := .none, pointer := .coarse, motion := m, scheme := .light }

/-- DPR of the `touch` profile: 3 at or below 500 px, else 2.

$$ r(w) = \begin{cases} 3 & w \le 500 \\ 2 & w > 500 \end{cases} $$ -/
def touchDpr (w : Nat) : Px := if w ≤ 500 then .ofNat 3 else .ofNat 2

/-- The probes at both sides of each edge for one profile.

$$ \mathrm{pairs}(b, E, f) = [(b, \mathrm{str}(w), f(w)) \mid N \leftarrow E,\ w \leftarrow [N, N{+}1]] $$

(list comprehension in order: for each edge, first the probe at $N$, then the probe at $N+1$; the tag is the
decimal text of $w$). -/
def pairProbes (block : Block) (edges : List Nat) (mk : Nat → Env) : List Probe :=
  edges.flatMap fun n => [n, n + 1].map fun w => ⟨block, toString w, mk w⟩

/-- The gate matrix (one engine), block by block as in the inventory's §4.

$$ M = M_{\text{desk}} \mathbin{+\!\!+} M_{\text{desk-rm}} \mathbin{+\!\!+} M_{\text{touch}} \mathbin{+\!\!+} \dots \mathbin{+\!\!+} M_{\text{height}} $$ -/
def matrix : List Probe :=
  pairProbes .desk widthEdgePairs (fun w => deskEnv (.ofNat w) (.ofNat 900) (.ofNat 1) .noPreference) ++
  pairProbes .deskRm widthEdgePairs (fun w => deskEnv (.ofNat w) (.ofNat 900) (.ofNat 1) .reduce) ++
  pairProbes .touch widthEdgePairs (fun w => touchEnv (.ofNat w) (.ofNat 900) (touchDpr w) .noPreference) ++
  pairProbes .touchRm touchRmEdges (fun w => touchEnv (.ofNat w) (.ofNat 900) (.ofNat 2) .reduce) ++
  ([Motion.noPreference, .reduce].map fun m =>
    ⟨.phoneLandscape, Feature.motionKw m,
     { width := .ofNat 932, height := .ofNat 430, deviceWidth := .ofNat 430, deviceHeight := .ofNat 932,
       dpr := .ofNat 3, hover := .none, pointer := .coarse, motion := m, scheme := .light }⟩) ++
  ([1001, 1031, 1201].flatMap fun w => [500, 501].map fun s =>
    ⟨.dwArmIsolate, s!"{w}-screen{s}",
     { deskEnv (.ofNat w) (.ofNat 900) (.ofNat 1) .noPreference with deviceWidth := .ofNat s }⟩) ++
  ([(1024, 768), (1200, 900)].flatMap fun (w, h) =>
    [(Hover.none, Pointer.fine), (Hover.hover, Pointer.coarse)].map fun (hv, pt) =>
      ⟨.hoverPointerCross, s!"{w}x{h}-{Feature.hoverKw hv}-{Feature.pointerKw pt}",
       { deskEnv (.ofNat w) (.ofNat h) (.ofNat 2) .noPreference with hover := hv, pointer := pt }⟩) ++
  [⟨.dark, "1440x900",
     { deskEnv (.ofNat 1440) (.ofNat 900) (.ofNat 1) .noPreference with scheme := .dark }⟩,
   ⟨.dark, "430x932",
     { touchEnv (.ofNat 430) (.ofNat 932) (.ofNat 3) .noPreference with scheme := .dark }⟩] ++
  ([600, 640, 860, 1000].map fun n =>
    ⟨.fractionalGaps, s!"{n}.5",
     deskEnv (.half n) (.ofNat 900) (.ofNat 2) .noPreference⟩) ++
  ([(1440, 822), (1440, 823), (1440, 900), (1440, 901)].map fun (w, h) =>
    ⟨.heightProbes, s!"{w}x{h}", deskEnv (.ofNat w) (.ofNat h) (.ofNat 1) .noPreference⟩) ++
  ([775, 815].map fun h =>
    ⟨.heightProbes, s!"430x{h}",
     { touchEnv (.ofNat 430) (.ofNat h) (.ofNat 3) .noPreference with deviceHeight := .ofNat 932 }⟩)

/-- The inventory's `matrix.estimate.breakdown`.

$$ (30, 30, 30, 10, 2, 6, 4, 2, 4, 6),\ \textstyle\sum = 124 $$ -/
def blockBreakdown : List (Block × Nat) := [
  (.desk, 30), (.deskRm, 30), (.touch, 30), (.touchRm, 10), (.phoneLandscape, 2),
  (.dwArmIsolate, 6), (.hoverPointerCross, 4), (.dark, 2), (.fractionalGaps, 4), (.heightProbes, 6)]

/-- The matrix has 124 loads per engine.

$$ |M| = 124 $$

One engine runs 124 page loads. -/
theorem matrix_length : matrix.length = 124 := by decide +kernel

/-- Each block has exactly the inventory's number of loads, and there are no other blocks.

$$ \big(\forall (b, n) \in \mathrm{breakdown}.\ |[\, p \in M \mid \mathrm{blk}(p) = b \,]| = n\big) \land \textstyle\sum_{(b, n) \in \mathrm{breakdown}} n = |M| $$

The matrix matches `matrix.estimate.breakdown` block by block. -/
theorem matrix_blocks :
    (blockBreakdown.all fun (b, n) => (matrix.filter (·.block == b)).length == n) = true ∧
      (blockBreakdown.map (·.2)).sum = matrix.length := by decide +kernel

/-- Probe ids are unique.

$$ \forall i, j < |M|,\quad i \ne j \Rightarrow \mathrm{id}(M_i) \ne \mathrm{id}(M_j) $$

where $M_i$ is the $i$-th probe of the list $M$ (from 0).

Every load has its own name. -/
theorem matrix_ids_nodup : (matrix.map (·.id)).Nodup := by decide +kernel

/-- Does block `b` contain a probe at whole-pixel width `w`?

$$ \mathrm{hasWidth}(b, w) \iff \exists p \in M.\ \mathrm{blk}(p) = b \land w(p) = w $$ -/
def hasWidth (b : Block) (w : Nat) : Bool := matrix.any fun p => p.block == b && p.env.width == .ofNat w

/-- **Both sides of every edge, per required profile.** For the profiles `desk`, `desk-rm`, `touch` every one of the
15 width edges has probes at `N` and `N+1`; `touch-rm` has them at 600, 860, 1000, 1030, 1200; and
`dw-arm-isolate` has screens 500 and 501 at each of the viewports 1001, 1031, 1201.

$$ \forall b \in \{\text{desk}, \text{desk-rm}, \text{touch}\}\ \forall N \in E_{15}.\ \exists p, p' \in M_b.\ w(p) = N \land w(p') = N{+}1,
   \quad \forall N \in E_{t}.\ \exists p, p' \in M_{\text{touch-rm}}.\ w(p) = N \land w(p') = N{+}1,
   \quad \forall v \in \{1001, 1031, 1201\}\ \forall s \in \{500, 501\}.\ \exists p \in M_{\text{dw}}.\ (w, d_w)(p) = (v, s) $$

The matrix hits both sides of every edge in every input mode the inventory requires. -/
theorem matrix_edge_pairs :
    ([Block.desk, .deskRm, .touch].all fun b => widthEdgePairs.all fun n => hasWidth b n && hasWidth b (n + 1)) &&
    (touchRmEdges.all fun n => hasWidth .touchRm n && hasWidth .touchRm (n + 1)) &&
    ([1001, 1031, 1201].all fun v => [500, 501].all fun s => matrix.any fun p =>
      p.block == .dwArmIsolate && p.env.width == .ofNat v && p.env.deviceWidth == .ofNat s) = true := by
  decide +kernel

/-- The coordinate of an edge's axis: device width for `device-width`, viewport width otherwise.

$$ \mathrm{axis}(\text{device-width}, e) = d_w,\quad \mathrm{axis}(a, e) = w \text{ otherwise} $$ -/
def axisOf : Axis → Env → Px
  | .deviceWidth, e => e.deviceWidth
  | _, e => e.width

/-- The matrix observes a flip of `q` at edge `(tag, N)`: two probes of one block, agreeing on every discrete
feature, at `N` and `N+1` on the edge's axis, on which `q` differs.

$$ \mathrm{obs}(q, a, N) \iff \exists p, p' \in M.\ a(p) = N \land a(p') = N{+}1 \land \mathrm{blk}(p) = \mathrm{blk}(p') \land p \sim p' \land \llbracket q \rrbracket_p \ne \llbracket q \rrbracket_{p'} $$ -/
def observesFlip (q : MQ) (tag : Axis) (n : Nat) : Bool :=
  (matrix.filter fun p => axisOf tag p.env == .ofNat n).any fun p =>
    (matrix.filter fun p' => axisOf tag p'.env == .ofNat (n + 1)).any fun p' =>
      p.block == p'.block && decide (Agree p.env p'.env) && q.eval p.env != q.eval p'.env

/-- **The matrix sees every edge flip.** For every one of the 30 conditions and every edge `(axis, N)` it lists,
the matrix contains two probes of one block that agree on all discrete features, sit at `N` and `N+1` on that
axis, and give the condition different values.

$$ \forall i < 30\ \forall (a, N) \in E(q_i)\ \exists p, p' \in M.\ \mathrm{blk}(p) = \mathrm{blk}(p') \land p \sim p' \land
   a(p) = N \land a(p') = N{+}1 \land \llbracket q_i \rrbracket_p \ne \llbracket q_i \rrbracket_{p'} $$

Every listed edge is a real flip, and the matrix catches it; with `MQ.eval_congr` no other flip exists. -/
theorem matrix_observes_every_edge :
    (catalogue.all fun c => c.query.taggedEdges.all fun (tag, n) => observesFlip c.query tag n) = true := by
  decide +kernel

/-- **Desktop-profile pairs differ only in size.** In the desk, desk-rm, touch and touch-rm blocks, the probes at
`N` and `N+1` agree on every discrete feature.

$$ \forall b \in \{\text{desk}, \text{desk-rm}, \text{touch}, \text{touch-rm}\}\ \forall N \in E_{15}\ \forall p, p' \in M_b.\ w(p) = N \land w(p') = N{+}1 \Rightarrow p \sim p' $$

An edge pair varies the width (and the screen width that tracks it), nothing else a query reads. -/
theorem matrix_pairs_agree :
    ([Block.desk, .deskRm, .touch, .touchRm].all fun b => widthEdgePairs.all fun n =>
      (matrix.filter fun p => p.block == b && p.env.width == .ofNat n).all fun p =>
        (matrix.filter fun p' => p'.block == b && p'.env.width == .ofNat (n + 1)).all fun p' =>
          decide (Agree p.env p'.env)) = true := by
  decide +kernel

/-- **Fractional probes land in the gaps, one per gap.** Listing, for each `fractional-gaps` probe in matrix
order, the edges `N` among 600, 640, 860, 1000 with `N < w < N+1` gives exactly `[600], [640], [860], [1000]`:
there are four probes, each lies strictly inside exactly one gap, and the four gaps are distinct.

$$ \big(\,[N \leftarrow (600, 640, 860, 1000) \mid N < w(p) < N{+}1]\,\big)_{p \in M_{\text{frac}}} = ([600], [640], [860], [1000]) $$

The four fractional loads cover the four gaps at 600, 640, 860 and 1000, one load strictly inside each. -/
theorem matrix_fractional_in_gaps :
    (matrix.filter (·.block == .fractionalGaps)).map (fun p => [600, 640, 860, 1000].filter fun n =>
      decide (p.env.width.GtNat n) && !decide (p.env.width.GeNat (n + 1))) = [[600], [640], [860], [1000]] := by
  decide +kernel

/-! ## Realizability: whole widths and whole device pixels -/

/-- A length is a whole number of CSS px: $q \mid p$ for $x = p/q$.

$$ \forall x,\quad \mathrm{Whole}(x) \iff x.\mathrm{num} \bmod x.\mathrm{den} = 0 $$

The value is an integer, whatever the representation. -/
def Px.Whole (x : Px) : Prop := x.num % x.den = 0

instance (x : Px) : Decidable x.Whole := inferInstanceAs (Decidable (_ = _))

/-- A length times a ratio is a whole number: $x \cdot r \in \mathbb N$ for $x = p/q$, $r = c/d$.

$$ \forall x, r,\quad \mathrm{MulWhole}(x, r) \iff (x.\mathrm{num} \cdot r.\mathrm{num}) \bmod (x.\mathrm{den} \cdot r.\mathrm{den}) = 0 $$

Width times device pixel ratio is a whole number of device pixels. -/
def Px.MulWhole (x r : Px) : Prop := (x.num * r.num) % (x.den * r.den) = 0

instance (x r : Px) : Decidable (x.MulWhole r) := inferInstanceAs (Decidable (_ = _))

/-- A width that is a whole number $P$ of device pixels divided by the ratio $r$ has a whole product
with $r$.

$$ \forall x, r \in \mathrm{Px},\ \forall P \in \mathbb N,\quad x.\mathrm{num} \cdot r.\mathrm{num} = P \cdot (x.\mathrm{den} \cdot r.\mathrm{den}) \implies \mathrm{MulWhole}(x, r) $$

A Chromium media width $P / r$ (with $P$ whole physical px) always satisfies the realizability test. -/
theorem Px.mulWhole_of_device_px (x r : Px) (P : Nat) (h : x.num * r.num = P * (x.den * r.den)) :
    x.MulWhole r := by
  unfold Px.MulWhole; rw [h]; exact Nat.mul_mod_left _ _

/-- **Realizability.** Every probe of the matrix asks for a whole number of device pixels across.

$$ \forall p \in M,\quad \mathrm{MulWhole}(w(p),\ r(p)) $$

Every probe width times its DPR is whole; the fractional gaps run at DPR 2, $(N + \tfrac12) \cdot 2 = 2N + 1$. -/
theorem matrix_width_dpr_whole : ∀ p ∈ matrix, p.env.width.MulWhole p.env.dpr := by decide +kernel

/-- The probe widths are whole exactly outside the fractional-gaps block.

$$ \forall p \in M,\quad \mathrm{Whole}(w(p)) \iff b(p) \ne \text{fractional-gaps} $$

Only the four fractional loads ask for a non-integer width. -/
theorem matrix_whole_iff : ∀ p ∈ matrix, (p.env.width.Whole ↔ p.block ≠ .fractionalGaps) := by
  decide +kernel

/-- Moving a fractional probe from DPR $\tfrac54$ to DPR 2 changes no condition, so no expected vector
changes.

$$ \forall N \in \mathbb N,\ \forall q \in \mathrm{MQ},\quad \llbracket q \rrbracket_{\mathrm{desk}(N + \frac12,\ 900,\ 2,\ \text{no-preference})} = \llbracket q \rrbracket_{\mathrm{desk}(N + \frac12,\ 900,\ \frac54,\ \text{no-preference})} $$

The DPR change is invisible to every media condition (`MQ.eval_indep_height_dpr`). -/
theorem fractional_dpr_indep (N : Nat) (q : MQ) :
    q.eval (deskEnv (.half N) (.ofNat 900) (.ofNat 2) .noPreference) =
      q.eval (deskEnv (.half N) (.ofNat 900) ⟨5, 4, by decide⟩ .noPreference) :=
  MQ.eval_indep_height_dpr q (deskEnv (.half N) (.ofNat 900) ⟨5, 4, by decide⟩ .noPreference)
    (.ofNat 900) (.ofNat 900) (.ofNat 2)

/-! ## Neutral queries emitted by MUI internals -/

/-- One neutral query: media an MUI component emits that no theme option removes, with the reason it is allowed.

$$ n = (\mathrm{ts}, q, \mathrm{reason}) $$ -/
structure NeutralEntry where
  /-- TS-ready identifier -/
  tsId : String
  /-- the query -/
  query : MQ
  /-- why it is allowed without changing what the site shows under the gate -/
  reason : String
deriving Repr

/-- `print` (media type).

$$ e \models \texttt{print} \iff \tau = \text{print} $$ -/
def printQ : MQ := ⟨[[.mediaType .print]]⟩
/-- `(forced-colors: active)`.

$$ e \models \texttt{(forced-colors: active)} \iff \phi = \text{active} $$ -/
def forcedColorsActive : MQ := ⟨[[.forcedColors .active]]⟩

/-- The neutral set: the four MUI-internal media of `apps/site/src/mui-internal-media.json`.

$$ N = (\texttt{(hover: hover)}, \texttt{(hover: none)}, \texttt{(forced-colors: active)}, \texttt{print}) $$ -/
def neutral : List NeutralEntry := [
  ⟨"hoverHover", hoverHover,
   "Equals the inventory's mq.hover-hover; covered by the hover-pointer-cross block, which runs both sides (matrix_neutral_hover_both_sides)."⟩,
  ⟨"hoverNone", hoverNone,
   "Equals the inventory's mq.hover-none; covered by the hover-pointer-cross block, which runs both sides (matrix_neutral_hover_both_sides)."⟩,
  ⟨"forcedColorsActive", forcedColorsActive,
   "False on every gate load (forced colors off in every matrix environment; matrix_neutral_inert), so it cannot change a gated pixel."⟩,
  ⟨"print", printQ,
   "Media type print never matches a screen load; false on every gate load (matrix_neutral_inert)."⟩
]

/-- The neutral set prints exactly as `apps/site/src/mui-internal-media.json` lists it.

$$ (\mathrm{css}(n_i))_i = (\texttt{(hover: hover)}, \texttt{(hover: none)}, \texttt{(forced-colors: active)}, \texttt{print}) $$

The four MUI media strings, byte for byte. -/
theorem neutral_css :
    neutral.map (fun n => n.query.css) = ["(hover: hover)", "(hover: none)", "(forced-colors: active)", "print"] := by
  decide

/-- `print` and `(forced-colors: active)` are false in every environment that is a screen load without forced
colors.

$$ \tau = \text{screen} \land \phi = \text{none} \Rightarrow e \not\models \texttt{print} \land e \not\models \texttt{(forced-colors: active)} $$

Neither query can match on screen with forced colors off. -/
theorem neutral_inert (e : Env) (ht : e.mediaType = .screen) (hf : e.forcedColors = .none) :
    ¬ printQ.Holds e ∧ ¬ forcedColorsActive.Holds e := by
  simp [MQ.Holds, MQ.eval, Feature.holds, printQ, forcedColorsActive, ht, hf]

/-- **(a)** `print` and `(forced-colors: active)` are false in every environment of the gate matrix.

$$ \forall p \in M.\ p \not\models \texttt{print} \land p \not\models \texttt{(forced-colors: active)} $$

No gate load can see these two MUI queries match. -/
theorem matrix_neutral_inert :
    ∀ p ∈ matrix, ¬ printQ.Holds p.env ∧ ¬ forcedColorsActive.Holds p.env := by
  intro p hp
  have hall : (matrix.all fun p => p.env.mediaType == .screen && p.env.forcedColors == .none) = true := by decide +kernel
  have := List.all_eq_true.mp hall p hp
  simp only [Bool.and_eq_true, beq_iff_eq] at this
  exact neutral_inert p.env this.1 this.2

/-- **(b)** The two hover queries of the neutral set are exactly the inventory's hover conditions
(`mq.hover-hover`, `mq.hover-none`), and inside the `hover-pointer-cross` block each takes both values at one
viewport size.

$$ n_{hh} = q_{\text{mq.hover-hover}} \land n_{hn} = q_{\text{mq.hover-none}} \land
   \forall q \in \{n_{hh}, n_{hn}\}\ \exists p, p' \in M_{\text{cross}}.\ (w,h)(p) = (w,h)(p') \land
   p \models q \land p' \not\models q $$

The gate already runs both sides of both hover queries, crossed with the pointer. -/
theorem matrix_neutral_hover_both_sides :
    (neutral.take 2).map (·.query) = [hoverHover, hoverNone] ∧
    (catalogue.find? (·.id == "mq.hover-hover")).map (·.query) = some hoverHover ∧
    (catalogue.find? (·.id == "mq.hover-none")).map (·.query) = some hoverNone ∧
    ([hoverHover, hoverNone].all fun q =>
      let cross := matrix.filter (·.block == .hoverPointerCross)
      cross.any fun p => cross.any fun p' =>
        p.env.width == p'.env.width && p.env.height == p'.env.height && q.eval p.env && !q.eval p'.env) = true :=
  ⟨rfl, by decide, by decide, by decide +kernel⟩

/-- The hover × pointer crossing: in the `hover-pointer-cross` block (only one of hover:none and pointer:coarse)
no combo's touch arm matches, so at 1200 px (screen 1200) no combo matches at all, while at 1024 px only
`c1030` matches, through its width arm.

$$ \forall p \in M_{\text{cross}}.\ \neg\mathrm{touch}(p) \land
   (w(p) = 1200 \Rightarrow \textstyle\bigwedge_{C \in \{C_{860}, C_{1000}, C_{1030}, C^{nodw}_{1000}\}} p \not\models C) \land
   (w(p) = 1024 \Rightarrow p \models C_{1030} \land p \not\models C_{860} \land p \not\models C_{1000} \land p \not\models C^{nodw}_{1000}) $$

Half a touch device is not a touch device; note that `c1030` still matches at 1024 px by width. -/
theorem matrix_cross_no_touch_arm :
    ((matrix.filter (·.block == .hoverPointerCross)).all fun p =>
      !(p.env.hover == .none && p.env.pointer == .coarse) &&
      (p.env.width != .ofNat 1200 || [c860, c1000, c1030, c1000Nodw].all (fun q => !q.eval p.env)) &&
      (p.env.width != .ofNat 1024 ||
        (c1030.eval p.env && !c860.eval p.env && !c1000.eval p.env && !c1000Nodw.eval p.env))) = true := by
  decide +kernel

/-- The device-width arm alone: at viewports 1031 and 1201 with a fine pointer, screen 500 vs 501 flips
`c860`, `c1000`, `c1030` and never `c1000Nodw`; at viewport 1001 it flips `c860` and `c1000` while `c1030`
already holds by width.

$$ \forall p \in M_{\text{dw}}.\ p \not\models C^{nodw}_{1000} \land \big(d_w(p) = 500 \Rightarrow p \models C_{860} \land p \models C_{1000} \land p \models C_{1030}\big)
   \land \big(d_w(p) \ne 500 \Rightarrow p \not\models C_{860} \land p \not\models C_{1000} \land (p \models C_{1030} \iff w(p) = 1001)\big) $$

(structural equality of `Px` values, as in the Lean; the block's probes are the viewports 1001, 1031, 1201 at
screens 500 and 501.)

Only the device-width arm separates the combos from the countdown combo. -/
theorem matrix_dw_arm :
    ((matrix.filter (·.block == .dwArmIsolate)).all fun p =>
      !c1000Nodw.eval p.env &&
      (if p.env.deviceWidth == .ofNat 500 then c860.eval p.env && c1000.eval p.env && c1030.eval p.env
       else !c860.eval p.env && !c1000.eval p.env &&
         (c1030.eval p.env == (p.env.width == .ofNat 1001)))) = true := by
  decide +kernel

/-- Phone landscape (932×430 on a 430×932 screen, touch) is in the C860 / `>=861` overlap for both motion
settings, but **not** in the C1000 / `>=1001` overlap: 932 < 1001, so only C1000 matches there. (As the
inventory's `phone-landscape.why` states, the C1000 / `>=1001` overlap needs a viewport of at least 1001 px with a
small screen or touch; the `touch` probes at 1031 and 1200 and the `dw-arm-isolate` probes with screen 500 provide
it.)

$$ \forall p \in M_{\text{landscape}}.\ p \models C_{860} \land p \models (w \ge 861) \land p \models C_{1000} \land p \not\models (w \ge 1001) $$

The landscape loads exercise the 860 overlap only. -/
theorem matrix_landscape_overlaps :
    ((matrix.filter (·.block == .phoneLandscape)).all fun p =>
      c860.eval p.env && wGe861.eval p.env && c1000.eval p.env && !wGe1001.eval p.env) = true := by
  decide +kernel

/-! ## Examples (`#guard`) -/

#guard hasWidth .desk 860 && hasWidth .desk 861 && !hasWidth .desk 862
#guard hasWidth .touchRm 1200 && !hasWidth .touchRm 400
#guard observesFlip c860 .width 860 && observesFlip c860 .deviceWidth 500 && observesFlip c860 .widthTouch 1200
#guard !observesFlip c860 .width 640
#guard !observesFlip c1000Nodw .deviceWidth 500
#guard (matrix.map Probe.id).take 3 == ["desk-319", "desk-320", "desk-400"]

end Fw.Site.Breakpoints
