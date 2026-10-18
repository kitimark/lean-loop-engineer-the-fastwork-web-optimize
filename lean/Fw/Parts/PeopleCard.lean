import Fw.Engine
import Fw.Site.BreakpointMatrix
import Fw.Parts.MorphMountOpt
import Fw.Parts.EndFlags
/-!
# people.card: gate the scroll-shrink lerp by the band where CSS already pins the card (PLAN rev 10)

**The original** (snapshot, pretty-printed copies of `nodes/2.DyWL8TcE.js` and `assets/2.gBuqKVzi.css`; the
unformatted `snapshot/site/` files carry the same text on one line each):

* JS, `2.DyWL8TcE.js` pretty 11278-11290: `C(e) = min(1, max(0, e))`, `w(e) = t·t·(3 − 2t)` with `t = C(e)`, and
  the progress `T(rect, ih)` of the card's bottom edge through the band from 85 % to 35 % of the viewport height.
* JS, pretty 11295-11329, the frame callback `l` and its scheduler `u`: `l` reads the card's rect, takes the target
  `n = rm ? +(t ≥ .5) : w(t)`, moves `o += (n − o)·(rm ? 1 : .22)`, snaps `o = n` when `|n − o| < 8e-4` (11316),
  writes `h.style.setProperty('--future-shrink', String(o))` on the section (11317), sets the class
  `is-future-shrinking` to `t > .04` (11318), and requests itself again while `|n − o| ≥ 8e-4` (11319). `u`
  requests `l` once per frame (`i ||= rAF(l)`, 11327-11329); the section scroll engine calls `u` (11359).
* CSS, `2.gBuqKVzi.css` pretty 2358-2361: `.start-selling-future { --future-shrink: 0;
  --future-shrink-scale: calc(1 - 0.083333 * var(--future-shrink)); --future-shrink-radius: 32px }`; 2378: the card's
  `border-radius: calc(var(--future-shrink-radius) * var(--future-shrink))`; 2389-2392 and 2415-2418: with the class,
  `transform: scale(var(--future-shrink-scale))`. Then three `@media` rules on the section, in source order:
  3384-3388 the c860 query sets scale 1 and radius 0px, 3586-3589 `(width<=640px)` sets radius 24px, 3650-3654 the
  c860 query again sets scale 1 and radius 0px. `--future-shrink` is read nowhere else.

**The variant** `rewrite+?fw=people.card:mq`: while `c860` (the generated `mq.c860`,
`Fw.Site.Breakpoints.c860`) matches, `l` skips the `--future-shrink` write and the self re-request; everything
else in `l` (the class, the other reads and toggles) runs as before. Outside `c860` the variant runs the original.

**What is proved.**
* Vision, class E: in the c860 band the card's look does not depend on `--future-shrink` (`look_gated`), and
  exactly there (`look_const_iff`); the class sequences agree (`cls_agree`); so the visible scenes are equal for
  every environment and frame (`peopleCard_visSame`).
* Work, every engine: frame by frame the variant is `⪯` the original (`gate_le`, `run_le`); a tail frame (a
  re-request with no scroll call) is strictly less (`gate_lt_tail`); a value-changing write is strictly less on
  Chromium (`cr_write_lt`, one style unit of the custom-property write) and, when a rect read follows the write
  (width ≤ 860), on every engine through the forced style pass (`gate_lt_forced`). Run forms: `run_dominates_of_lt`,
  `cr_dominates`, `wk_dominates`. Outside the band the frames are identical (`frames_ungated_eq`).
* Golden rows for `engine-check` (`goldenLines`, `packages/contracts/golden/engine/people-card.jsonl`).

**Premises** (hypotheses or model choices, named in the handoff):
* P1 (band per load): the environment is fixed during a run; a resize across the c860 edge is not covered.
* P2 (progress moves with calls): in the band, a frame with no scroll call sees the same progress `t` as the frame
  before it (the card only moves under a scroll, and every scroll calls `u`).
* P3 (exact numbers): JS doubles are modelled by `Rat`; `.22`, `.85`, `.35`, `.04`, `8e-4` are taken exactly.
* P4 (other work): the rest of each frame (`oth`) is the same in both arms; the lerp's own forced style pass is
  the one rect read after its write.
* P5 (engine rows): a same-value inline write is a no-op in both engines (Chromium
  `B/core/css/css_property_value_set.cc:606-608` (`SetLonghandProperty` returns `kUnchanged`) and
  `B/core/css/abstract_property_set_css_style_declaration.cc:278-281` (`DidMutate(kNoChanges)`)@f842f52; WebKit
  `Source/WebCore/css/MutableStyleProperties.cpp:221-223`, `css/CSSStyleProperties.cpp:441`@862f17d), so only a
  changed value is a change. On Chromium the write is a custom property with no reader whose computed value moves
  in the band (`styleOnly`); WebKit's table has no custom-property row, so its restyle is not counted (open).
-/
namespace Fw.Parts.PeopleCard

open Fw.Engine Fw.Site.Breakpoints
open Fw.Parts.MorphMountOpt (CountType series predict crTypes wkTypes stageName)

/-! ## The original lerp, restated -/

/-- `C(e)` of the snapshot (`2.DyWL8TcE.js` pretty 11278-11280): clamp to $[0, 1]$.

$$\forall x \in \mathbb{Q}:\ \operatorname{clamp01}(x) =\begin{cases} 0 & x < 0 \\ 1 & 0 \le x \land 1 < x \\ x & 0 \le x \le 1 \end{cases} = \min(1, \max(0, x))$$

The value cut to the unit interval. -/
def clamp01 (x : Rat) : Rat := if x < 0 then 0 else if 1 < x then 1 else x

#guard clamp01 (-1/2) == 0 && clamp01 (3/2) == 1 && clamp01 (1/4) == 1/4 && clamp01 0 == 0 && clamp01 1 == 1

/-- `w(e)` of the snapshot (pretty 11281-11284): the smoothstep of the clamped value.

$$\forall x \in \mathbb{Q}:\ \operatorname{smooth}(x) = c^2 (3 - 2c),\quad c = \operatorname{clamp01}(x)$$

The eased progress the lerp aims at. -/
def smooth (x : Rat) : Rat := let c := clamp01 x; c * c * (3 - 2 * c)

#guard smooth 0 == 0 && smooth 1 == 1 && smooth (1/2) == 1/2 && smooth 2 == 1 && smooth (1/10) == 7/250

/-- `T(rect, ih)` of the snapshot (pretty 11285-11290): the progress of the card's bottom edge `b` through the band
from 85 % down to 35 % of the viewport height `ih` (first match).

$$\forall b, h \in \mathbb{Q}:\ \operatorname{progress}(b, h) = \begin{cases} 0 & h \le 0 \\ 0 & h > 0 \land b \ge \tfrac{85}{100} h \\ 1 & h > 0 \land b < \tfrac{85}{100} h \land b \le \tfrac{35}{100} h \\ \operatorname{clamp}\!\Big(\dfrac{\frac{85}{100} h - b}{\frac{85}{100} h - \frac{35}{100} h}\Big) & \text{otherwise} \end{cases}$$

How far the card has risen into the shrink band, from 0 to 1. -/
def progress (b ih : Rat) : Rat :=
  if ih ≤ 0 then 0
  else
    let n := ih * (85 / 100)
    let r := ih * (35 / 100)
    if n ≤ b then 0 else if b ≤ r then 1 else clamp01 ((n - b) / (n - r))

#guard progress 900 1000 == 0 && progress 850 1000 == 0 && progress 350 1000 == 1 && progress 600 1000 == 1/2
#guard progress 10 0 == 0

/-- The lerp target `n` (pretty 11314): a step at $\tfrac12$ under reduced motion, the smoothstep otherwise.

$$\forall \mathit{rm} \in \mathbb{B},\ \forall t \in \mathbb{Q}:\ \operatorname{target}(\mathit{rm}, t) = \begin{cases} 1 & \mathit{rm} \land t \ge \tfrac12 \\ 0 & \mathit{rm} \land t < \tfrac12 \\ \operatorname{smooth}(t) & \lnot \mathit{rm} \end{cases}$$

Where `--future-shrink` is heading. -/
def target (rm : Bool) (t : Rat) : Rat := if rm then (if 1 / 2 ≤ t then 1 else 0) else smooth t

#guard target true (1/2) == 1 && target true (2/5) == 0 && target false (1/2) == 1/2

/-- The settle test `|d| < 8e-4` (pretty 11316, 11319), with $8 \cdot 10^{-4} = \tfrac{1}{1250}$.

$$\forall d \in \mathbb{Q}:\ \operatorname{near8}(d) \iff -\tfrac{1}{1250} < d < \tfrac{1}{1250}$$

The lerp counts as arrived. -/
def near8 (d : Rat) : Bool := decide (-(1 / 1250) < d) && decide (d < 1 / 1250)

#guard near8 0 && near8 (1/2000) && !near8 (1/1250) && !near8 (-1/1250)

/-- One lerp move before the snap (pretty 11315): factor 1 under reduced motion, $\tfrac{22}{100}$ otherwise.

$$\forall \mathit{rm} \in \mathbb{B},\ \forall o, n \in \mathbb{Q}:\ \operatorname{raw}(\mathit{rm}, o, n) = o + (n - o) \cdot \begin{cases} 1 & \mathit{rm} \\ \tfrac{22}{100} & \lnot \mathit{rm} \end{cases}$$

The value moved part of the way to the target. -/
def lerpRaw (rm : Bool) (o n : Rat) : Rat := o + (n - o) * (if rm then 1 else 22 / 100)

/-- One lerp step with the snap (pretty 11315-11316): the new `o`.

$$\forall \mathit{rm} \in \mathbb{B},\ \forall o, n \in \mathbb{Q}:\ \operatorname{step}(\mathit{rm}, o, n) = \begin{cases} n & \operatorname{near8}(n - \operatorname{raw}(\mathit{rm}, o, n)) \\ \operatorname{raw}(\mathit{rm}, o, n) & \text{otherwise} \end{cases}$$

The value `l` writes to `--future-shrink`. -/
def lerpStep (rm : Bool) (o n : Rat) : Rat :=
  let o' := lerpRaw rm o n
  if near8 (n - o') then n else o'

#guard lerpStep false 0 1 == 11/50 && lerpStep true 0 1 == 1 && lerpStep false (9995/10000) 1 == 1

/-- The self re-request (pretty 11319): `l` asks for another frame while the new value is not near the target.

$$\forall \mathit{rm} \in \mathbb{B},\ \forall o, n \in \mathbb{Q}:\ \operatorname{again}(\mathit{rm}, o, n) \iff \lnot\operatorname{near8}(n - \operatorname{step}(\mathit{rm}, o, n))$$

Whether the lerp keeps running without a scroll. -/
def again (rm : Bool) (o n : Rat) : Bool := !near8 (n - lerpStep rm o n)

#guard again false 0 1 && !again true 0 1 && !again false (9995/10000) 1 && !again false 1 1

/-- The class `is-future-shrinking` (pretty 11318, class map 11469): on when the progress passes $\tfrac{1}{25}$.

$$\forall t \in \mathbb{Q}:\ \operatorname{shrinking}(t) \iff t > \tfrac{1}{25}$$

Whether the card takes the scale transform rule. -/
def shrinking (t : Rat) : Bool := decide (1 / 25 < t)

#guard shrinking (1/10) && !shrinking (1/25) && !shrinking 0

/-- The lerp state between frames: the last written value `val` (the section's `--future-shrink`, initially the
CSS `0`, pretty CSS 2359 and JS `o = 0`, 11301), whether a self re-request is pending, and the class.

$$\mathrm{St} = \underbrace{\mathbb{Q}}_{\mathrm{val}} \times \underbrace{\mathbb{B}}_{\mathrm{pend}} \times \underbrace{\mathbb{B}}_{\mathrm{cls}}$$

What the component remembers from one frame to the next. -/
structure St where
  val : Rat
  pend : Bool
  cls : Bool
deriving Repr, DecidableEq

/-- The state at load: value 0, nothing pending, class off.

$$\mathrm{init} = (0, \bot, \bot)$$

Before the first frame. -/
def St.init : St := ⟨0, false, false⟩

/-- One run of `l` at progress `t` (pretty 11312-11319).

$$\forall \mathit{rm},\ t,\ s:\ \operatorname{runL}(\mathit{rm}, t, s) = \big(\operatorname{step}(\mathit{rm}, s.\mathrm{val}, n),\ \operatorname{again}(\mathit{rm}, s.\mathrm{val}, n),\ \operatorname{shrinking}(t)\big),\quad n = \operatorname{target}(\mathit{rm}, t)$$

The state after the callback runs once. -/
def runL (rm : Bool) (t : Rat) (s : St) : St :=
  let n := target rm t
  ⟨lerpStep rm s.val n, again rm s.val n, shrinking t⟩

/-- **The original's frame step**: `l` runs when the scroll engine called `u` before this frame or a re-request is
pending (one `rAF` per frame, `i ||= rAF(l)`, pretty 11327-11329); otherwise nothing changes and nothing is pending.

$$\forall \mathit{rm}, c \in \mathbb{B},\ t \in \mathbb{Q},\ s \in \mathrm{St}:\ \operatorname{stepO}(\mathit{rm}, c, t, s) = \begin{cases} \operatorname{runL}(\mathit{rm}, t, s) & c \lor s.\mathrm{pend} \\ (s.\mathrm{val}, \bot, s.\mathrm{cls}) & \text{otherwise} \end{cases}$$

What one frame does to the original's state. -/
def stepO (rm call : Bool) (t : Rat) (s : St) : St :=
  if call || s.pend then runL rm t s else { s with pend := false }

/-- **The variant's frame step**: with the gate on, `l` runs only on a scroll call and only sets the class (no
write, no re-request); with the gate off it is the original's step.

$$\forall g, \mathit{rm}, c,\ t,\ s:\ \operatorname{stepV}(g, \mathit{rm}, c, t, s) = \begin{cases} (s.\mathrm{val}, \bot, \operatorname{shrinking}(t)) & g \land c \\ (s.\mathrm{val}, \bot, s.\mathrm{cls}) & g \land \lnot c \\ \operatorname{stepO}(\mathit{rm}, c, t, s) & \lnot g \end{cases}$$

What one frame does to the variant's state. -/
def stepV (gate rm call : Bool) (t : Rat) (s : St) : St :=
  if gate then (if call then ⟨s.val, false, shrinking t⟩ else { s with pend := false }) else stepO rm call t s

/-- The original's state after `k` frames, frame `j` having scroll call `call j` and progress `t j`.

$$\forall \mathit{rm}, c, t:\ \operatorname{stO}(0) = \mathrm{init},\quad \operatorname{stO}(k+1) = \operatorname{stepO}(\mathit{rm}, c_k, t_k, \operatorname{stO}(k))$$

The original's lerp state frame by frame. -/
def stO (rm : Bool) (call : Nat → Bool) (t : Nat → Rat) : Nat → St
  | 0 => St.init
  | k + 1 => stepO rm (call k) (t k) (stO rm call t k)

/-- The variant's state after `k` frames.

$$\forall g, \mathit{rm}, c, t:\ \operatorname{stV}(0) = \mathrm{init},\quad \operatorname{stV}(k+1) = \operatorname{stepV}(g, \mathit{rm}, c_k, t_k, \operatorname{stV}(k))$$

The variant's lerp state frame by frame. -/
def stV (gate rm : Bool) (call : Nat → Bool) (t : Nat → Rat) : Nat → St
  | 0 => St.init
  | k + 1 => stepV gate rm (call k) (t k) (stV gate rm call t k)

/-- A sample input: rest, four scroll frames, two gap frames, two scroll frames, three tail frames. -/
private def exCall : Nat → Bool := fun k => [false, true, true, true, true, false, false, true, true, false, false,
  false].getD k false
private def exT : Nat → Rat := fun k => [0, 1/10, 1/5, 3/10, 2/5, 2/5, 2/5, 1/2, 3/5, 3/5, 3/5, 3/5].getD k (3/5)

#guard (stO false exCall exT 1) == St.init
#guard (stO false exCall exT 2).val == 77/12500 && (stO false exCall exT 2).pend && (stO false exCall exT 2).cls
#guard (stO false exCall exT 7).pend && (stV true false exCall exT 7).val == 0
#guard (List.range 13).all fun k => (stO false exCall exT k).cls == (stV true false exCall exT k).cls
#guard (List.range 13).all fun k => stV false false exCall exT k == stO false exCall exT k

/-! ## The cascade and the card's look -/

/-- The condition that always matches: one arm with no feature.

$$\forall e \in \mathrm{Env}:\ e \models \mathrm{always}$$

The base rule's condition. -/
def always : MQ := ⟨[[]]⟩

/-- **The cascade of one custom property** on the section: declarations `(q, x)` in source order, the last one
whose condition matches wins, `d` when none matches.

$$\forall e,\ d,\ D:\ \operatorname{cascade}(e, D, d) = \operatorname{foldl}\big((a, (q, x)) \mapsto (x \text{ if } e \models q \text{ else } a),\ d,\ D\big)$$

The value the section computes for that property. -/
def cascade (env : Env) (ds : List (MQ × Rat)) (d : Rat) : Rat :=
  ds.foldl (fun acc qx => if qx.1.eval env then qx.2 else acc) d

/-- `--future-shrink-scale` on the section at shrink `s`: pretty CSS 2360, 3386, 3652.

$$\forall s:\ \mathrm{scaleDecls}(s) = [(\mathrm{always},\ 1 - \tfrac{83333}{1000000} s),\ (\mathrm{c860}, 1),\ (\mathrm{c860}, 1)]$$

The scale declarations in source order. -/
def scaleDecls (s : Rat) : List (MQ × Rat) := [(always, 1 - 83333 / 1000000 * s), (c860, 1), (c860, 1)]

/-- `--future-shrink-radius` on the section, in px: pretty CSS 2361, 3387, 3588, 3653.

$$\mathrm{radiusDecls} = [(\mathrm{always}, 32),\ (\mathrm{c860}, 0),\ (\mathrm{wLe640}, 24),\ (\mathrm{c860}, 0)]$$

The radius declarations in source order. -/
def radiusDecls : List (MQ × Rat) := [(always, 32), (c860, 0), (wLe640, 24), (c860, 0)]

/-- **The card's look** at shrink `s`: the scale its transform uses when the class is on (pretty CSS 2389-2392,
2415-2418) and its border radius `radius · s` (2378).

$$\forall e \in \mathrm{Env},\ \forall s \in \mathbb{Q}:\ \operatorname{look}(e, s) = \big(\operatorname{cascade}(e, \mathrm{scaleDecls}(s), 0),\ \operatorname{cascade}(e, \mathrm{radiusDecls}, 0) \cdot s\big)$$

The two values of the card that `--future-shrink` feeds. -/
def look (env : Env) (s : Rat) : Rat × Rat := (cascade env (scaleDecls s) 0, cascade env radiusDecls 0 * s)

#guard c860.css == "(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)"
#guard look (exEnv 430 430) (1/2) == (1, 0)
#guard look (exEnv 1280 1280) 1 == (916667/1000000, 32)
#guard look (exEnv 1000 1000 .none .coarse) 1 == (1, 0)

/-- The 640 band lies inside the c860 band.

$$\forall e \in \mathrm{Env}:\ e \models \mathrm{wLe640} \Rightarrow e \models \mathrm{c860}$$

Every viewport at most 640 px wide is gated. -/
theorem wLe640_c860 (env : Env) (h : wLe640.eval env = true) : c860.eval env = true := by
  apply (c860_iff env).2
  left
  simp [MQ.eval, wLe640, Feature.holds] at h
  simp only [Px.LeNat] at h ⊢
  omega

/-- **The gated look.** In the c860 band the card's scale is 1 and its radius 0, whatever the shrink.

$$\forall e \in \mathrm{Env},\ \forall s \in \mathbb{Q}:\ e \models \mathrm{c860} \Rightarrow \operatorname{look}(e, s) = (1, 0)$$

Where the gate is on, the lerp's output never shows. -/
theorem look_gated (env : Env) (s : Rat) (h : c860.eval env = true) : look env s = (1, 0) := by
  simp [look, cascade, scaleDecls, radiusDecls, h]

/-- **The ungated look.** Outside the c860 band the scale is $1 - \tfrac{83333}{1000000} s$ and the radius $32 s$.

$$\forall e \in \mathrm{Env},\ \forall s \in \mathbb{Q}:\ e \not\models \mathrm{c860} \Rightarrow \operatorname{look}(e, s) = \big(1 - \tfrac{83333}{1000000} s,\ 32 s\big)$$

Where the gate is off, the card follows the lerp. -/
theorem look_ungated (env : Env) (s : Rat) (h : c860.eval env = false) :
    look env s = (1 - 83333 / 1000000 * s, 32 * s) := by
  have h640 : wLe640.eval env = false := by
    cases h' : wLe640.eval env
    · rfl
    · have := wLe640_c860 env h'; rw [h] at this; exact absurd this (by decide)
  have ha : always.eval env = true := rfl
  simp [look, cascade, scaleDecls, radiusDecls, h, h640, ha]

/-- **The gate is exact.** The look does not depend on the shrink exactly in the c860 band.

$$\forall e \in \mathrm{Env}:\ \big(\forall s \in \mathbb{Q}:\ \operatorname{look}(e, s) = \operatorname{look}(e, 0)\big) \iff e \models \mathrm{c860}$$

The variant skips the lerp precisely where it is invisible, and nowhere else. -/
theorem look_const_iff (env : Env) : (∀ s, look env s = look env 0) ↔ c860.eval env = true := by
  constructor
  · intro h
    cases hc : c860.eval env
    · have h1 := h 1
      rw [look_ungated env 1 hc, look_ungated env 0 hc] at h1
      exact absurd (congrArg Prod.snd h1) (by decide +kernel)
    · rfl
  · intro hc s
    rw [look_gated env s hc, look_gated env 0 hc]

/-! ## Vision, class E -/

/-- With the gate off the variant's state is the original's.

$$\forall \mathit{rm}, c, t,\ \forall k \in \mathbb{N}:\ \operatorname{stV}(\bot, \mathit{rm}, c, t, k) = \operatorname{stO}(\mathit{rm}, c, t, k)$$

Outside the band the variant is the original. -/
theorem stV_ungated (rm : Bool) (call : Nat → Bool) (t : Nat → Rat) :
    ∀ k, stV false rm call t k = stO rm call t k
  | 0 => rfl
  | k + 1 => by simp only [stV, stO, stepV, stV_ungated rm call t k]; rfl

/-- **The class sequences agree in the band** (premise P2). If a frame without a scroll call sees the progress of
the frame before it, then after every frame the original's and the variant's class are equal, the variant has
nothing pending, and an original re-request comes from a frame whose progress set the class.

$$\forall \mathit{rm}, c, t:\ \big(\forall j:\ c_{j+1} = \bot \Rightarrow t_{j+1} = t_j\big) \Rightarrow \forall k \in \mathbb{N}:\ \operatorname{stO}(\mathit{rm}, c, t, k).\mathrm{cls} = \operatorname{stV}(\top, \mathit{rm}, c, t, k).\mathrm{cls} \land \operatorname{stV}(\top, \mathit{rm}, c, t, k).\mathrm{pend} = \bot \land \big(\operatorname{stO}(\mathit{rm}, c, t, k).\mathrm{pend} \Rightarrow \exists j:\ k = j + 1 \land \operatorname{stO}(\mathit{rm}, c, t, k).\mathrm{cls} = \operatorname{shrinking}(t_j)\big)$$

A tail frame re-sets the class to the value the last scroll call set. -/
theorem cls_agree (rm : Bool) (call : Nat → Bool) (t : Nat → Rat)
    (hp : ∀ j, call (j + 1) = false → t (j + 1) = t j) :
    ∀ k, (stO rm call t k).cls = (stV true rm call t k).cls ∧ (stV true rm call t k).pend = false ∧
      ((stO rm call t k).pend = true → ∃ j, k = j + 1 ∧ (stO rm call t k).cls = shrinking (t j))
  | 0 => by simp [stO, stV, St.init]
  | k + 1 => by
    obtain ⟨hc, _, hpend⟩ := cls_agree rm call t hp k
    simp only [stO, stV, stepO, stepV, ↓reduceIte]
    cases hk : call k
    · cases hpk : (stO rm call t k).pend
      · simp [hc]
      · obtain ⟨j, rfl, hj⟩ := hpend hpk
        have ht : t (j + 1) = t j := hp j hk
        simp [runL, ht, ← hj, hc]
    · simp [runL]

/-- **Vision, class E (people.card).** For every environment and frame, the original's and the variant's visible
scenes are equal, for any scene built from the frame, the card's look at the current `--future-shrink` and the
class (premise P2 in the band; P1: the environment is fixed per run).

$$\forall \mathit{vp},\ \forall S,\ \forall c, t:\ \Big(\forall e, j:\ e \models \mathrm{c860} \Rightarrow c_e(j+1) = \bot \Rightarrow t_e(j+1) = t_e(j)\Big) \Rightarrow \operatorname{VisSame}_{\mathrm{E}}\Big(\mathit{vp},\ (e, k) \mapsto S\big(e, k, \operatorname{look}(e, \operatorname{stO}([e \models \mathrm{rmReduce}], c_e, t_e, k).\mathrm{val}), \operatorname{stO}([e \models \mathrm{rmReduce}], c_e, t_e, k).\mathrm{cls}\big),\ (e, k) \mapsto S\big(e, k, \operatorname{look}(e, \operatorname{stV}([e \models \mathrm{c860}], [e \models \mathrm{rmReduce}], c_e, t_e, k).\mathrm{val}), \operatorname{stV}([e \models \mathrm{c860}], [e \models \mathrm{rmReduce}], c_e, t_e, k).\mathrm{cls}\big)\Big)$$

The gated card looks the same in every frame at every width. -/
theorem peopleCard_visSame (vp : Env → Rect) (scn : Env → Nat → Rat × Rat → Bool → Scene)
    (call : Env → Nat → Bool) (t : Env → Nat → Rat)
    (hp : ∀ env j, c860.eval env = true → call env (j + 1) = false → t env (j + 1) = t env j) :
    VisSame E vp
      (fun env k => scn env k (look env (stO (rmReduce.eval env) (call env) (t env) k).val)
        (stO (rmReduce.eval env) (call env) (t env) k).cls)
      (fun env k => scn env k (look env (stV (c860.eval env) (rmReduce.eval env) (call env) (t env) k).val)
        (stV (c860.eval env) (rmReduce.eval env) (call env) (t env) k).cls) := by
  apply visSame_of_eq
  intro env k
  cases hg : c860.eval env
  · simp [stV_ungated]
  · have hc := (cls_agree (rmReduce.eval env) (call env) (t env) (fun j => hp env j hg) k).1
    rw [look_gated env _ hg, look_gated env _ hg, hc]

/-! ## Work -/

/-- Two frame inputs side by side: callbacks, forced passes, hit tests and animations add, changes append.

$$\forall a, b \in \mathrm{FrameIn}(P):\ a \oplus b = (a.\mathrm{script} + b.\mathrm{script},\ a.\mathrm{fS} + b.\mathrm{fS},\ a.\mathrm{fL} + b.\mathrm{fL},\ a.\mathrm{hits} + b.\mathrm{hits},\ a.\mathrm{changes} \mathbin{+\!\!+} b.\mathrm{changes},\ a.\mathrm{compAnims} + b.\mathrm{compAnims})$$

One frame made of the rest of the page and the lerp. -/
def addF {P : Type} (a b : FrameIn P) : FrameIn P :=
  ⟨a.script + b.script, a.forcedStyle + b.forcedStyle, a.forcedLayout + b.forcedLayout, a.hits + b.hits,
    a.changes ++ b.changes, a.compAnims + b.compAnims⟩

/-- The lerp's own part of a frame: one callback when `l` runs, the write's changes `W`, and `f` forced style passes.

$$\forall r \in \mathbb{B},\ W,\ f \in \mathbb{N}:\ \operatorname{lerp}(r, W, f) = ([r],\ f,\ 0,\ 0,\ W,\ 0)$$

What `l` adds to a frame. -/
def lerpFrame {P : Type} (run : Bool) (wr : List (Change P)) (fs : Nat) : FrameIn P :=
  ⟨if run then 1 else 0, fs, 0, 0, wr, 0⟩

/-- A list of changes covers itself.

$$\forall E,\ \forall L \in \mathrm{Change}(P)^{*}:\ \operatorname{cover}_E(L, L) = \mathrm{true}$$

Every change dirties its own stages. -/
theorem coverB_refl {P M : Type} (E : Engine P M) : ∀ l : List (Change P), coverB E l l = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_refl E cs]

/-- **Frame dominance of the gate**, every engine: the variant's frame (the rest plus at most the callback) is `⪯`
the original's (the rest plus the callback whenever the variant has one, its write and its forced passes).

$$\forall E,\ \forall X \in \mathrm{FrameIn}(P),\ \forall c, r \in \mathbb{B},\ \forall W,\ \forall f \in \mathbb{N}:\ (c \Rightarrow r) \Rightarrow \operatorname{frameWork}_E(X \oplus \operatorname{lerp}(c, [\,], 0)) \preceq \operatorname{frameWork}_E(X \oplus \operatorname{lerp}(r, W, f))$$

Dropping the write and the re-request never adds work. -/
theorem gate_le {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool) (h : cv = true → ro = true)
    (wr : List (Change P)) (fs : Nat) :
    (frameWork E (addF oth (lerpFrame cv [] 0))).le (frameWork E (addF oth (lerpFrame ro wr fs))) := by
  apply frame_le_of_cover E oth.changes wr
  · exact List.Perm.refl _
  · simpa [addF, lerpFrame] using coverB_refl E oth.changes
  · simp only [addF, lerpFrame]; cases cv <;> cases ro <;> simp_all
  · simp [addF, lerpFrame]
  · simp [addF, lerpFrame]
  · simp [addF, lerpFrame]
  · simp [addF, lerpFrame]

/-- **A tail frame is strictly less**, every engine: where the original runs `l` only because it re-requested
itself, the variant runs nothing, one `script` unit fewer.

$$\forall E,\ \forall X,\ \forall W,\ \forall f:\ \operatorname{frameWork}_E(X \oplus \operatorname{lerp}(\bot, [\,], 0)) \prec \operatorname{frameWork}_E(X \oplus \operatorname{lerp}(\top, W, f))$$

No lerp frame after the scroll stops. -/
theorem gate_lt_tail {P M : Type} (E : Engine P M) (oth : FrameIn P) (wr : List (Change P)) (fs : Nat) :
    (frameWork E (addF oth (lerpFrame false [] 0))).lt (frameWork E (addF oth (lerpFrame true wr fs))) := by
  refine ⟨gate_le E oth false true (by simp) wr fs, Or.inl ⟨.script, Or.inr ?_⟩⟩
  simp only [frameWork, stageUnits, addF, lerpFrame, List.countP_append, List.append_nil, ↓reduceIte,
    Bool.false_eq_true]
  split <;> omega

/-- **A written stage is strictly less**, every engine: when the write's changes dirty stage `s`, the variant has
fewer `s` units.

$$\forall E,\ \forall X,\ \forall c, r \in \mathbb{B},\ \forall W,\ \forall f \in \mathbb{N},\ \forall s \in \mathrm{Stage},\ \forall w:\ (c \Rightarrow r) \land w \in W \land s \in E.\mathrm{stagesOf}(w) \Rightarrow \operatorname{frameWork}_E(X \oplus \operatorname{lerp}(c, [\,], 0)) \prec \operatorname{frameWork}_E(X \oplus \operatorname{lerp}(r, W, f))$$

A skipped write that would have cost work saves it. -/
theorem gate_lt_stage {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool) (h : cv = true → ro = true)
    (wr : List (Change P)) (fs : Nat) (s : Stage) (c : Change P) (hc : c ∈ wr) (hs : s ∈ E.stagesOf c) :
    (frameWork E (addF oth (lerpFrame cv [] 0))).lt (frameWork E (addF oth (lerpFrame ro wr fs))) := by
  refine ⟨gate_le E oth cv ro h wr fs, Or.inl ⟨s, Or.inr ?_⟩⟩
  have hpos : 0 < wr.countP (fun c => decide (s ∈ E.stagesOf c)) :=
    List.countP_pos_iff.mpr ⟨c, hc, by simp [hs]⟩
  simp only [frameWork, stageUnits, addF, lerpFrame, List.countP_append, List.countP_nil]
  split <;> split <;> cases cv <;> cases ro <;> simp_all <;> omega

/-- **A forced style pass is strictly less**, every engine: when the original's write is followed by a rect read
(`f > 0` forced style passes), the variant has fewer `style` passes.

$$\forall E,\ \forall X,\ \forall c, r,\ \forall W,\ \forall f \in \mathbb{N}:\ (c \Rightarrow r) \land 0 < f \Rightarrow \operatorname{frameWork}_E(X \oplus \operatorname{lerp}(c, [\,], 0)) \prec \operatorname{frameWork}_E(X \oplus \operatorname{lerp}(r, W, f))$$

No restyle forced by a write that is not made. -/
theorem gate_lt_forced {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool) (h : cv = true → ro = true)
    (wr : List (Change P)) (fs : Nat) (hf : 0 < fs) :
    (frameWork E (addF oth (lerpFrame cv [] 0))).lt (frameWork E (addF oth (lerpFrame ro wr fs))) := by
  refine ⟨gate_le E oth cv ro h wr fs, Or.inl ⟨.style, Or.inl ?_⟩⟩
  have h0 := ((gate_le E oth cv ro h wr 0).1 .style).1
  have ht : touched E (addF oth (lerpFrame ro wr fs)) = touched E (addF oth (lerpFrame ro wr 0)) := rfl
  simp only [frameWork, forcedPasses] at h0 ⊢
  rw [ht]
  simp only [addF, lerpFrame] at h0 ⊢
  omega

/-! ### Frames of a run -/

/-- **The original's frame** `k` in the lerp's terms: `l` runs on a call or a pending re-request; its write is a
change (the changes `W`) only when the value moves (premise P5), and is followed by a forced style pass when `ra`
(a rect read after the write, pretty 11321-11323, at width ≤ 860).

$$\forall X, W, \mathit{ra}, \mathit{rm}, c, t, s:\ \operatorname{frO}(X, W, \mathit{ra}, \mathit{rm}, c, t, s) = X \oplus \operatorname{lerp}\big(r,\ [w]\cdot W,\ [w \land \mathit{ra}]\big),\quad r = c \lor s.\mathrm{pend},\ w = r \land \operatorname{runL}(\mathit{rm}, t, s).\mathrm{val} \ne s.\mathrm{val}$$

($[w] \cdot W$ is $W$ when $w$, else $[\,]$.) What the original asks of the engine in one frame. -/
def frameO {P : Type} (oth : FrameIn P) (wr : List (Change P)) (ra rm call : Bool) (t : Rat) (s : St) : FrameIn P :=
  let run := call || s.pend
  let w := run && decide ((runL rm t s).val ≠ s.val)
  addF oth (lerpFrame run (if w then wr else []) (if w && ra then 1 else 0))

/-- **The variant's frame**: gated, the rest plus one callback on a call; ungated, the original's frame.

$$\forall g, X, W, \mathit{ra}, \mathit{rm}, c, t, s:\ \operatorname{frV}(g, X, W, \mathit{ra}, \mathit{rm}, c, t, s) = \begin{cases} X \oplus \operatorname{lerp}(c, [\,], 0) & g \\ \operatorname{frO}(X, W, \mathit{ra}, \mathit{rm}, c, t, s) & \lnot g \end{cases}$$

What the variant asks of the engine in one frame. -/
def frameV {P : Type} (gate : Bool) (oth : FrameIn P) (wr : List (Change P)) (ra rm call : Bool) (t : Rat)
    (s : St) : FrameIn P :=
  if gate then addF oth (lerpFrame call [] 0) else frameO oth wr ra rm call t s

/-- The original's works over the frames `ks`.

$$\forall E, X, W, \mathit{ra}, \mathit{rm}, c, t, K:\ \operatorname{WO} = [\,\operatorname{frameWork}_E(\operatorname{frO}(X_k, W, \mathit{ra}, \mathit{rm}, c_k, t_k, \operatorname{stO}(\mathit{rm}, c, t, k)))\,]_{k \in K}$$

The original's run. -/
def worksO {P M : Type} (E : Engine P M) (oth : Nat → FrameIn P) (wr : List (Change P)) (ra rm : Bool)
    (call : Nat → Bool) (t : Nat → Rat) (ks : List Nat) : List Work :=
  ks.map fun k => frameWork E (frameO (oth k) wr ra rm (call k) (t k) (stO rm call t k))

/-- The variant's works over the frames `ks`.

$$\forall E, g, X, W, \mathit{ra}, \mathit{rm}, c, t, K:\ \operatorname{WV} = [\,\operatorname{frameWork}_E(\operatorname{frV}(g, X_k, W, \mathit{ra}, \mathit{rm}, c_k, t_k, \operatorname{stV}(g, \mathit{rm}, c, t, k)))\,]_{k \in K}$$

The variant's run. -/
def worksV {P M : Type} (E : Engine P M) (gate : Bool) (oth : Nat → FrameIn P) (wr : List (Change P))
    (ra rm : Bool) (call : Nat → Bool) (t : Nat → Rat) (ks : List Nat) : List Work :=
  ks.map fun k => frameWork E (frameV gate (oth k) wr ra rm (call k) (t k) (stV gate rm call t k))

/-- **Ungated, the frames are the original's.**

$$\forall E, X, W, \mathit{ra}, \mathit{rm}, c, t, K:\ \operatorname{WV}(\bot) = \operatorname{WO}$$

Outside the band the variant does exactly the original's work. -/
theorem frames_ungated_eq {P M : Type} (E : Engine P M) (oth : Nat → FrameIn P) (wr : List (Change P))
    (ra rm : Bool) (call : Nat → Bool) (t : Nat → Rat) (ks : List Nat) :
    worksV E false oth wr ra rm call t ks = worksO E oth wr ra rm call t ks := by
  simp [worksV, worksO, frameV, stV_ungated]

/-- Pointwise `⪯` over a list gives `leAll`.

$$\forall f, g,\ \forall K:\ (\forall k \in K:\ f(k) \preceq g(k)) \Rightarrow \operatorname{leAll}([f(k)]_{k \in K}, [g(k)]_{k \in K}) = \mathrm{true}$$

Frame by frame at most is run-wise at most. -/
theorem leAll_map {α : Type} (f g : α → Work) :
    ∀ ks : List α, (∀ k ∈ ks, (f k).le (g k)) → leAll (ks.map f) (ks.map g) = true
  | [], _ => rfl
  | k :: ks, h => by
    simp only [List.map_cons, leAll, Bool.and_eq_true]
    exact ⟨(Work.leb_iff _ _).2 (h k (by simp)), leAll_map f g ks (fun j hj => h j (by simp [hj]))⟩

/-- One strictly smaller frame gives `someLt`.

$$\forall f, g,\ \forall K:\ (\exists k \in K:\ f(k) \prec g(k)) \Rightarrow \operatorname{someLt}([f(k)]_{k \in K}, [g(k)]_{k \in K}) = \mathrm{true}$$

A strict frame shows in the run. -/
theorem someLt_map {α : Type} (f g : α → Work) :
    ∀ ks : List α, (∃ k ∈ ks, (f k).lt (g k)) → someLt (ks.map f) (ks.map g) = true
  | [], ⟨_, hk, _⟩ => by simp at hk
  | k :: ks, ⟨j, hj, hlt⟩ => by
    simp only [List.map_cons, someLt, List.zip_cons_cons, List.any_cons, Bool.or_eq_true]
    rcases List.mem_cons.mp hj with rfl | hj
    · exact .inl ((Work.ltb_iff _ _).2 hlt)
    · exact .inr (someLt_map f g ks ⟨j, hj, hlt⟩)

/-- **Work, every engine, every band.** Frame by frame the variant's run is `⪯` the original's.

$$\forall E, g, X, W, \mathit{ra}, \mathit{rm}, c, t, K:\ \operatorname{leAll}(\operatorname{WV}(g), \operatorname{WO}) = \mathrm{true}$$

The gate never costs a frame anything. -/
theorem run_le {P M : Type} (E : Engine P M) (gate : Bool) (oth : Nat → FrameIn P) (wr : List (Change P))
    (ra rm : Bool) (call : Nat → Bool) (t : Nat → Rat) (ks : List Nat) :
    leAll (worksV E gate oth wr ra rm call t ks) (worksO E oth wr ra rm call t ks) = true := by
  cases gate
  · rw [frames_ungated_eq]
    exact leAll_map _ _ ks (fun _ _ => Work.le_refl _)
  · apply leAll_map
    intro k _
    simp only [frameV, frameO, ↓reduceIte]
    exact gate_le E (oth k) _ _ (by simp_all) _ _

/-- **Run dominance from one strict frame**, every engine: in the band, if some frame of the variant is strictly
below the original's, the screen says "dominates".

$$\forall E, X, W, \mathit{ra}, \mathit{rm}, c, t, K:\ \big(\exists k \in K:\ \operatorname{WV}(\top)_k \prec \operatorname{WO}_k\big) \Rightarrow \operatorname{screen}(\operatorname{toRun}(\operatorname{WO}), \operatorname{toRun}(\operatorname{WV}(\top))) = \mathrm{ok}(\mathrm{dominates})$$

($\operatorname{WV}(\top)_k$ and $\operatorname{WO}_k$ are the frame works at $k$.) Once a lerp frame is saved, the gated run wins. -/
theorem run_dominates_of_lt {P M : Type} (E : Engine P M) (oth : Nat → FrameIn P) (wr : List (Change P))
    (ra rm : Bool) (call : Nat → Bool) (t : Nat → Rat) (ks : List Nat)
    (h : ∃ k ∈ ks, (frameWork E (frameV true (oth k) wr ra rm (call k) (t k) (stV true rm call t k))).lt
      (frameWork E (frameO (oth k) wr ra rm (call k) (t k) (stO rm call t k)))) :
    Screen.screen (toRun (worksO E oth wr ra rm call t ks)) (toRun (worksV E true oth wr ra rm call t ks)) =
      .ok .dominates :=
  run_dominates (run_le E true oth wr ra rm call t ks) (someLt_map _ _ ks h)

/-- A value-changing lerp frame of the original: `l` runs (a call or a pending re-request) and moves the value.

$$\forall \mathit{rm}, c, t, s:\ \operatorname{moves}(\mathit{rm}, c, t, s) \iff (c \lor s.\mathrm{pend}) \land \operatorname{runL}(\mathit{rm}, t, s).\mathrm{val} \ne s.\mathrm{val}$$

Which original frames the gate saves. -/
def moves (rm call : Bool) (t : Rat) (s : St) : Bool := (call || s.pend) && decide ((runL rm t s).val ≠ s.val)

/-- **A gated tail frame is strictly less**, every engine.

$$\forall E, X, W, \mathit{ra}, \mathit{rm}, c, t, s, s':\ \lnot c \land s.\mathrm{pend} \Rightarrow \operatorname{frameWork}_E(\operatorname{frV}(\top, X, W, \mathit{ra}, \mathit{rm}, c, t, s')) \prec \operatorname{frameWork}_E(\operatorname{frO}(X, W, \mathit{ra}, \mathit{rm}, c, t, s))$$

The original's re-requested frame costs more than the variant's idle one. -/
theorem frame_lt_tail {P M : Type} (E : Engine P M) (oth : FrameIn P) (wr : List (Change P)) (ra rm call : Bool)
    (t : Rat) (s s' : St) (hc : call = false) (hp : s.pend = true) :
    (frameWork E (frameV true oth wr ra rm call t s')).lt (frameWork E (frameO oth wr ra rm call t s)) := by
  subst hc
  simp only [frameV, frameO, hp, ↓reduceIte, Bool.false_or, Bool.true_and]
  exact gate_lt_tail E oth _ _

/-- **A gated moving write with a following rect read is strictly less**, every engine (the forced style pass).

$$\forall E, X, W, \mathit{rm}, c, t, s, s':\ \operatorname{moves}(\mathit{rm}, c, t, s) \Rightarrow \operatorname{frameWork}_E(\operatorname{frV}(\top, X, W, \top, \mathit{rm}, c, t, s')) \prec \operatorname{frameWork}_E(\operatorname{frO}(X, W, \top, \mathit{rm}, c, t, s))$$

At width ≤ 860 each skipped write also skips a forced restyle. -/
theorem frame_lt_read {P M : Type} (E : Engine P M) (oth : FrameIn P) (wr : List (Change P)) (rm call : Bool)
    (t : Rat) (s s' : St) (hm : moves rm call t s = true) :
    (frameWork E (frameV true oth wr true rm call t s')).lt (frameWork E (frameO oth wr true rm call t s)) := by
  simp only [moves] at hm
  simp only [frameV, frameO, hm, ↓reduceIte, Bool.and_true]
  exact gate_lt_forced E oth _ _ (by simp_all) _ _ (by decide)

/-! ### Chromium -/

open Fw.Engine.Chromium in
/-- The Chromium write in the band: `--future-shrink` on the section `e`, a custom property with no reader whose
computed value moves (the scale reads the band's `1`, the radius `0 · s = 0`), so `styleOnly`.

$$\forall e \in \mathbb{N}:\ \operatorname{crWrite}(e) = (e,\ \mathrm{custom}(0, [\,]),\ \mathrm{none})$$

The one change the original's write makes on Chromium. -/
def crWrite (e : Nat) : Change CrProp := ⟨e, .custom 0 [], .none⟩

open Fw.Engine.Chromium in
/-- The Chromium write dirties style only.

$$\forall e \in \mathbb{N}:\ \operatorname{stagesOf}_{\mathrm{cr}}(\operatorname{crWrite}(e)) = [\mathrm{style}]$$

A restyle and nothing after it. -/
theorem cr_write_stages (e : Nat) : chromium.stagesOf (crWrite e) = [.style] := rfl

open Fw.Engine.Chromium in
/-- **Chromium: a gated moving write is strictly less** (one style unit), with or without a following read.

$$\forall X, \mathit{ra}, \mathit{rm}, c, t, s, s', e:\ \operatorname{moves}(\mathit{rm}, c, t, s) \Rightarrow \operatorname{frameWork}_{\mathrm{cr}}(\operatorname{frV}(\top, X, [\operatorname{crWrite}(e)], \mathit{ra}, \mathit{rm}, c, t, s')) \prec \operatorname{frameWork}_{\mathrm{cr}}(\operatorname{frO}(X, [\operatorname{crWrite}(e)], \mathit{ra}, \mathit{rm}, c, t, s))$$

No restyle per scroll frame on Chromium. -/
theorem cr_write_lt (oth : FrameIn CrProp) (ra rm call : Bool) (t : Rat) (s s' : St) (e : Nat)
    (hm : moves rm call t s = true) :
    (frameWork chromium (frameV true oth [crWrite e] ra rm call t s')).lt
      (frameWork chromium (frameO oth [crWrite e] ra rm call t s)) := by
  simp only [moves] at hm
  simp only [frameV, frameO, hm, ↓reduceIte]
  exact gate_lt_stage chromium oth _ _ (by simp_all) _ _ .style (crWrite e) (by simp) (by simp [cr_write_stages])

open Fw.Engine.Chromium in
/-- **Work, Chromium (people.card).** In the band, with the write `crWrite(e)`: if the original has a tail frame or
a value-changing write in the run, the screen says "dominates".

$$\forall X, \mathit{ra}, \mathit{rm}, c, t, K, e:\ \big(\exists k \in K:\ (\lnot c_k \land \operatorname{stO}(\mathit{rm}, c, t, k).\mathrm{pend}) \lor \operatorname{moves}(\mathit{rm}, c_k, t_k, \operatorname{stO}(\mathit{rm}, c, t, k))\big) \Rightarrow \operatorname{screen}\big(\operatorname{toRun}(\operatorname{WO}_{\mathrm{cr}}(X, [\operatorname{crWrite}(e)], \mathit{ra}, \mathit{rm}, c, t, K)), \operatorname{toRun}(\operatorname{WV}_{\mathrm{cr}}(\top, X, [\operatorname{crWrite}(e)], \mathit{ra}, \mathit{rm}, c, t, K))\big) = \mathrm{ok}(\mathrm{dominates})$$

One saved lerp frame makes the gated run dominate on Chromium. -/
theorem cr_dominates (oth : Nat → FrameIn CrProp) (ra rm : Bool) (call : Nat → Bool) (t : Nat → Rat)
    (ks : List Nat) (e : Nat)
    (h : ∃ k ∈ ks, (call k = false ∧ (stO rm call t k).pend = true) ∨ moves rm (call k) (t k) (stO rm call t k) = true) :
    Screen.screen (toRun (worksO chromium oth [crWrite e] ra rm call t ks))
      (toRun (worksV chromium true oth [crWrite e] ra rm call t ks)) = .ok .dominates := by
  apply run_dominates_of_lt
  obtain ⟨k, hk, h⟩ := h
  refine ⟨k, hk, ?_⟩
  rcases h with ⟨hc, hp⟩ | hm
  · exact frame_lt_tail chromium (oth k) _ ra rm _ (t k) _ _ hc hp
  · exact cr_write_lt (oth k) ra rm (call k) (t k) _ _ e hm

/-! ### WebKit -/

open Fw.Engine.WebKit in
/-- **Work, WebKit (people.card).** In the band, with no change counted for the write (no custom-property row): if
the original has a tail frame, or a value-changing write followed by a rect read (`ra`), the screen says
"dominates".

$$\forall X, \mathit{ra}, \mathit{rm}, c, t, K:\ \big(\exists k \in K:\ (\lnot c_k \land \operatorname{stO}(\mathit{rm}, c, t, k).\mathrm{pend}) \lor (\mathit{ra} \land \operatorname{moves}(\mathit{rm}, c_k, t_k, \operatorname{stO}(\mathit{rm}, c, t, k)))\big) \Rightarrow \operatorname{screen}\big(\operatorname{toRun}(\operatorname{WO}_{\mathrm{wk}}(X, [\,], \mathit{ra}, \mathit{rm}, c, t, K)), \operatorname{toRun}(\operatorname{WV}_{\mathrm{wk}}(\top, X, [\,], \mathit{ra}, \mathit{rm}, c, t, K))\big) = \mathrm{ok}(\mathrm{dominates})$$

The saved re-requests and forced restyles make the gated run dominate on WebKit. -/
theorem wk_dominates (oth : Nat → FrameIn WkProp) (ra rm : Bool) (call : Nat → Bool) (t : Nat → Rat)
    (ks : List Nat)
    (h : ∃ k ∈ ks, (call k = false ∧ (stO rm call t k).pend = true) ∨
      (ra = true ∧ moves rm (call k) (t k) (stO rm call t k) = true)) :
    Screen.screen (toRun (worksO webkit oth [] ra rm call t ks))
      (toRun (worksV webkit true oth [] ra rm call t ks)) = .ok .dominates := by
  apply run_dominates_of_lt
  obtain ⟨k, hk, h⟩ := h
  refine ⟨k, hk, ?_⟩
  rcases h with ⟨hc, hp⟩ | ⟨hr, hm⟩
  · exact frame_lt_tail webkit (oth k) _ ra rm _ (t k) _ _ hc hp
  · subst hr; exact frame_lt_read webkit (oth k) _ rm (call k) (t k) _ _ hm

/-! ## Golden rows for `engine-check`

The swipe profiles load at 430 × 932, touch (`packages/measure-chromium/profiles/swipe-v1.json`,
`swipe-touch-v1.json`), so the gate is on and `ra` holds (430 ≤ 860). The schematic run: one rest frame, a stroke of
four scroll frames, a gap of two, a stroke of two, a tail of three (the touch profile's 2-frame gaps). The rest of
the page (`oth`) is the same in both arms: a scroll change on every scroll frame and one layout-affecting change of
another part in the rest frame, so the counts the gate does not touch read `=o`, not `=0`. -/

/-- The swipe env: 430 × 932, DPR 3, touch, no reduced motion.

$$\mathrm{swipeEnv} = \operatorname{touch}(430, 932, 3, \text{no-preference})$$

The profile's viewport as a breakpoint environment. -/
def swipeEnv : Env := touchEnv (.ofNat 430) (.ofNat 932) (.ofNat 3) .noPreference

#guard c860.eval swipeEnv && wLe860.eval swipeEnv && !rmReduce.eval swipeEnv

/-- The schematic run's frames.

$$\mathrm{ks} = [0, 1, \dots, 11]$$

Twelve frames. -/
def ks : List Nat := List.range 12

open Fw.Engine.Chromium in
/-- The Chromium rest of frame `k`: a scroll change on scroll frames, a `width` change of another part in frame 0.

$$\forall k:\ X^{\mathrm{cr}}_k = \begin{cases} \operatorname{jsWrite}(0, [(1, \mathrm{css}(\mathrm{width}), \mathrm{none})]) & k = 0 \\ \operatorname{jsWrite}(0, [(0, \mathrm{scroll}(\bot), \mathrm{own})]) & k \ne 0 \land c_k \\ \operatorname{jsWrite}(0, [\,]) & \text{otherwise} \end{cases}$$

The page's other work, the same in both arms. -/
def crOth (k : Nat) : FrameIn CrProp :=
  if k = 0 then jsWrite 0 [⟨1, .css .width, .none⟩]
  else if exCall k then jsWrite 0 [⟨0, .scroll false, .own⟩] else jsWrite 0 []

open Fw.Engine.WebKit in
/-- The WebKit rest of frame `k`: a scroll position on scroll frames, a `size` change of another part in frame 0.

$$\forall k:\ X^{\mathrm{wk}}_k = \begin{cases} (0,0,0,0,[(1, \mathrm{size}, \mathrm{none})],0) & k = 0 \\ (0,0,0,0,[(0, \mathrm{scrollPos}, \mathrm{none})],0) & k \ne 0 \land c_k \\ (0,0,0,0,[\,],0) & \text{otherwise} \end{cases}$$

The page's other work, the same in both arms. -/
def wkOth (k : Nat) : FrameIn WkProp :=
  if k = 0 then ⟨0, 0, 0, 0, [⟨1, .size, .none⟩], 0⟩
  else if exCall k then ⟨0, 0, 0, 0, [⟨0, .scrollPos, .none⟩], 0⟩ else ⟨0, 0, 0, 0, [], 0⟩

/-- The Chromium works of the schematic run, original and variant.

$$\mathrm{crO} = \operatorname{WO}_{\mathrm{cr}},\quad \mathrm{crV} = \operatorname{WV}_{\mathrm{cr}}(\top)\quad \text{at } X^{\mathrm{cr}}, W = [\operatorname{crWrite}(2)], \mathit{ra} = \top, \mathit{rm} = \bot, c, t, \mathrm{ks}$$

Model counts for the golden rows. -/
def crO : List Work := worksO Fw.Engine.Chromium.chromium crOth [crWrite 2] true false exCall exT ks
/-- See `crO`. $$\mathrm{crV} = \operatorname{WV}_{\mathrm{cr}}(\top)$$ The variant's model counts. -/
def crV : List Work := worksV Fw.Engine.Chromium.chromium true crOth [crWrite 2] true false exCall exT ks

/-- The WebKit works of the schematic run.

$$\mathrm{wkO} = \operatorname{WO}_{\mathrm{wk}},\quad \mathrm{wkV} = \operatorname{WV}_{\mathrm{wk}}(\top)\quad \text{at } X^{\mathrm{wk}}, W = [\,], \mathit{ra} = \top, \mathit{rm} = \bot, c, t, \mathrm{ks}$$

Model counts for the golden rows. -/
def wkO : List Work := worksO Fw.Engine.WebKit.webkit wkOth [] true false exCall exT ks
/-- See `wkO`. $$\mathrm{wkV} = \operatorname{WV}_{\mathrm{wk}}(\top)$$ The variant's model counts. -/
def wkV : List Work := worksV Fw.Engine.WebKit.webkit true wkOth [] true false exCall exT ks

#guard leAll crV crO && someLt crV crO && leAll wkV wkO && someLt wkV wkO

/-- The emitted prediction: the model's, with a strict `<o` weakened to `≤o`.

$$\forall p:\ \operatorname{soften}(p) = \begin{cases} \text{"≤o"} & p = \text{"<o"} \\ p & p \ne \text{"<o"} \end{cases}$$

The model's strict drop needs a tail frame (no scroll, lerp unsettled) or a frame where the card is the only style
writer; the swipe profiles guarantee neither (`swipe-v1` scrolls on every frame, other parts write style on scroll),
so the golden claims only the pointwise `≤` that `run_le` gives. -/
def soften (p : String) : String := if p = "<o" then "≤o" else p

#guard soften "<o" == "≤o" && soften "=o" == "=o" && soften "≤o" == "≤o" && soften "any" == "any"

/-- One JSON row, keys sorted.

$$\operatorname{row}(e, sc, \tau, V, O) = \{\mathrm{base} = \text{rewrite}, \mathrm{countType} = \tau.\mathrm{name}, \mathrm{engine} = e, \mathrm{prediction} = \operatorname{soften}(\operatorname{predict}(\tau.\mathrm{exact}, \operatorname{series}(V, \tau), \operatorname{series}(O, \tau))),\mathrm{scenario} = sc, \mathrm{stage} = \operatorname{stageName}(\tau.\mathrm{stage}), \mathrm{variant} = \text{rewrite+?fw=people.card:mq}\}$$

The variant flag is `?fw=people.card:mq`; the base is the faithful rewrite. -/
def row (engine scenario : String) (t : CountType) (vs os : List Work) : String :=
  "{\"base\":\"rewrite\",\"countType\":\"" ++ t.name ++ "\",\"engine\":\"" ++ engine ++ "\",\"prediction\":\"" ++
    soften (predict t.exact (series vs t) (series os t)) ++ "\",\"scenario\":\"" ++ scenario ++ "\",\"stage\":\"" ++
    stageName t.stage ++ "\",\"variant\":\"rewrite+?fw=people.card:mq\"}"

/-- All golden rows: Chromium on `swipe-v1` and `swipe-touch-v1`, WebKit on `swipe-v1` (all in the c860 band).

$$|\mathrm{goldenLines}| = 2 \cdot |\mathrm{crTypes}| + |\mathrm{wkTypes}| = 20$$

The file `packages/contracts/golden/engine/people-card.jsonl`, line by line. -/
def goldenLines : List String :=
  (["swipe-v1", "swipe-touch-v1"].flatMap fun sc => crTypes.map fun t => row "chromium" sc t crV crO) ++
    wkTypes.map fun t => row "webkit" "swipe-v1" t wkV wkO

/-- The golden file text: one row per line, trailing newline.

$$\mathrm{goldenText} = \operatorname{concat}[\, \ell \mathbin{+\!\!+} \text{"\textbackslash n"} \,]_{\ell \in \mathrm{goldenLines}}$$

What the driver writes. -/
def goldenText : String := String.join (goldenLines.map (· ++ "\n"))

#guard goldenLines.length == 20
#guard (crTypes.map fun t => predict t.exact (series crV t) (series crO t)) ==
  ["<o", "<o", "=o", "=o", "=o", "=o", "=o", "=o"]
#guard (wkTypes.map fun t => predict t.exact (series wkV t) (series wkO t)) == ["≤o", "=o", "=o", "≤o"]
#guard goldenLines.all fun l => (l.splitOn "\"<o\"").length == 1

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1, 17)

The original's write is followed by a rect read, which pays $f$ forced style passes and leaves the style flag clean.
`frameWork` also charged the write's lifecycle style pass, so it saw a saving of $f + 1$ style passes (2 for the one
read, `gate_forced_margin_old`). With the frame-end pass counted, the saving is the $f$ forced passes only
(`gate_forced_marginE`): the margin halves. When the rest of the frame also dirties style, the variant pays that
style pass at frame end while the original's read already covered it, so with one read the style passes tie
(`gate_forced_tieE`) and the strict win rests on the skipped units (`gate_lt_stageE`). The `⪯` verdict holds for
every flag assignment where the variant's end-dirty stages are end-dirty in the original too, or are the style stage
that the original's forced read pays for (`gate_leE`). -/

section EndPass

open Fw.Parts.EndFlags

/-- The style passes of a frame under `frameWorkE`: the end pass, if style is touched and ends dirty, plus the
forced style passes.

$$\forall E, F, e:\ \operatorname{frameWork}^{e}_E(F).\mathrm{passes}(\mathrm{style}) = [\mathrm{style} \in \operatorname{touched}_E(F) \land e(\mathrm{style})] + F.\mathrm{forcedStyle}$$

The definition read at the style stage. -/
theorem passesE_style {P M : Type} (E : Engine P M) (F : FrameIn P) (e : Stage → Bool) :
    (frameWorkE E F e).passes .style =
      (if Stage.style ∈ touched E F ∧ e .style = true then 1 else 0) + F.forcedStyle := rfl

/-- **Gate frame under `frameWorkE`: `⪯`.** If every stage the variant touches and ends dirty also ends dirty in the
original, or is the style stage and the original forces $f > 0$ style passes, the gated frame costs at most the
original's.

$$\forall E, X, c, r, W, f,\ \forall e_v, e_o:\ (c \Rightarrow r) \land \big(\forall s \in \operatorname{touched}_E(V):\ e_v(s) = \top \Rightarrow e_o(s) = \top \lor (s = \mathrm{style} \land f > 0)\big) \Rightarrow \operatorname{frameWork}^{e_v}_E(V) \preceq \operatorname{frameWork}^{e_o}_E(O)$$
$$\text{where } V = X \oplus \operatorname{lerp}(c, [\,], 0),\ O = X \oplus \operatorname{lerp}(r, W, f)$$

Skipping the write and its read never leaves more to do at frame end. -/
theorem gate_leE {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool) (h : cv = true → ro = true)
    (wr : List (Change P)) (fs : Nat) (ev eo : Stage → Bool)
    (hm : ∀ s, s ∈ touched E (addF oth (lerpFrame cv [] 0)) → ev s = true →
      eo s = true ∨ (s = .style ∧ 0 < fs)) :
    (frameWorkE E (addF oth (lerpFrame cv [] 0)) ev).le (frameWorkE E (addF oth (lerpFrame ro wr fs)) eo) := by
  have ht := touched_of_le_same_forced E (fun s => by cases s <;> rfl) (gate_le E oth cv ro h wr 0)
  refine frameE_le_of_total E ev eo (fun s hs => ht s hs) (fun s => ((gate_le E oth cv ro h wr fs).1 s).2)
    (gate_le E oth cv ro h wr fs).2 (fun s => ?_) (fun s hs => ?_)
  · cases s <;> simp [forcedPasses, addF, lerpFrame]
  · have := hm s hs
    cases s <;> simp only [forcedPasses, addF, lerpFrame] <;> revert this <;> cases ev _ <;> cases eo _ <;>
      simp <;> omega

/-- **Gate frame with a forced read under `frameWorkE`: still `≺`.** If the original forces $f > 0$ style passes and
the variant's end-dirty stages are end-dirty in the original, the gated frame is strictly cheaper on style passes.

$$\forall E, X, c, r, W,\ \forall f > 0,\ \forall e_v, e_o:\ (c \Rightarrow r) \land \big(\forall s \in \operatorname{touched}_E(V):\ e_v(s) = \top \Rightarrow e_o(s) = \top\big) \Rightarrow \operatorname{frameWork}^{e_v}_E(V) \prec \operatorname{frameWork}^{e_o}_E(O)$$
$$\text{where } V = X \oplus \operatorname{lerp}(c, [\,], 0),\ O = X \oplus \operatorname{lerp}(r, W, f)$$

The forced restyle is saved and not paid back at frame end. -/
theorem gate_lt_forcedE {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool) (h : cv = true → ro = true)
    (wr : List (Change P)) (fs : Nat) (hf : 0 < fs) (ev eo : Stage → Bool)
    (hm : ∀ s, s ∈ touched E (addF oth (lerpFrame cv [] 0)) → ev s = true → eo s = true) :
    (frameWorkE E (addF oth (lerpFrame cv [] 0)) ev).lt (frameWorkE E (addF oth (lerpFrame ro wr fs)) eo) := by
  refine ⟨gate_leE E oth cv ro h wr fs ev eo (fun s hs he => Or.inl (hm s hs he)), Or.inl ⟨.style, Or.inl ?_⟩⟩
  have ht := touched_of_le_same_forced E (fun s => by cases s <;> rfl) (gate_le E oth cv ro h wr 0) .style
  have hto : touched E (addF oth (lerpFrame ro wr fs)) = touched E (addF oth (lerpFrame ro wr 0)) := rfl
  rw [passesE_style, passesE_style, hto]
  show _ + (oth.forcedStyle + 0) < _ + (oth.forcedStyle + fs)
  by_cases hv : Stage.style ∈ touched E (addF oth (lerpFrame cv [] 0))
  · have h1 := ht hv
    have h2 := hm .style hv
    revert h2; cases ev .style <;> cases eo .style <;> simp [hv, h1] <;> omega
  · simp only [hv, false_and, ↓reduceIte]
    omega

/-- **Gate frame under `frameWorkE`: strict by units.** If some change of the write dirties a stage $s$, the gated
frame is strictly cheaper, under the flag condition of `gate_leE`.

$$\forall E, X, c, r, W, f,\ \forall e_v, e_o,\ \forall s,\ \forall w \in W:\ (c \Rightarrow r) \land s \in E.\mathrm{stagesOf}(w) \land \big(\forall t \in \operatorname{touched}_E(V):\ e_v(t) = \top \Rightarrow e_o(t) = \top \lor (t = \mathrm{style} \land f > 0)\big) \Rightarrow \operatorname{frameWork}^{e_v}_E(V) \prec \operatorname{frameWork}^{e_o}_E(O)$$
$$\text{where } V = X \oplus \operatorname{lerp}(c, [\,], 0),\ O = X \oplus \operatorname{lerp}(r, W, f)$$

The skipped write's units stay saved whatever the end flags. -/
theorem gate_lt_stageE {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool) (h : cv = true → ro = true)
    (wr : List (Change P)) (fs : Nat) (s : Stage) (c : Change P) (hc : c ∈ wr) (hs : s ∈ E.stagesOf c)
    (ev eo : Stage → Bool)
    (hm : ∀ t, t ∈ touched E (addF oth (lerpFrame cv [] 0)) → ev t = true →
      eo t = true ∨ (t = .style ∧ 0 < fs)) :
    (frameWorkE E (addF oth (lerpFrame cv [] 0)) ev).lt (frameWorkE E (addF oth (lerpFrame ro wr fs)) eo) := by
  refine ⟨gate_leE E oth cv ro h wr fs ev eo hm, Or.inl ⟨s, Or.inr ?_⟩⟩
  have hpos : 0 < wr.countP (fun c => decide (s ∈ E.stagesOf c)) :=
    List.countP_pos_iff.mpr ⟨c, hc, by simp [hs]⟩
  show stageUnits E _ s < stageUnits E _ s
  simp only [stageUnits, addF, lerpFrame, List.countP_append, List.countP_nil]
  split <;> split <;> cases cv <;> cases ro <;> simp_all <;> omega

/-- **The margin under `frameWorkE` (ledger n=17).** If the variant does not touch style and the original's read
leaves the style flag clean, the original pays exactly $f$ more style passes.

$$\forall E, X, c, r, W, f,\ \forall e_v, e_o:\ \mathrm{style} \notin \operatorname{touched}_E(V) \land e_o(\mathrm{style}) = \bot \Rightarrow \operatorname{frameWork}^{e_o}_E(O).\mathrm{passes}(\mathrm{style}) = \operatorname{frameWork}^{e_v}_E(V).\mathrm{passes}(\mathrm{style}) + f$$
$$\text{where } V = X \oplus \operatorname{lerp}(c, [\,], 0),\ O = X \oplus \operatorname{lerp}(r, W, f)$$

The saving is the forced passes, not one more. -/
theorem gate_forced_marginE {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool)
    (wr : List (Change P)) (fs : Nat) (ev eo : Stage → Bool)
    (hv : Stage.style ∉ touched E (addF oth (lerpFrame cv [] 0))) (heo : eo .style = false) :
    (frameWorkE E (addF oth (lerpFrame ro wr fs)) eo).passes .style =
      (frameWorkE E (addF oth (lerpFrame cv [] 0)) ev).passes .style + fs := by
  rw [passesE_style, passesE_style]
  show _ + (oth.forcedStyle + fs) = _ + (oth.forcedStyle + 0) + fs
  simp only [heo, hv, false_and, and_false, Bool.false_eq_true, ↓reduceIte]
  omega

/-- **The tie under `frameWorkE`.** If the variant touches style and ends it dirty while the original's single
forced read ($f = 1$) leaves it clean, both pay the same style passes.

$$\forall E, X, c, r, W,\ \forall e_v, e_o:\ \mathrm{style} \in \operatorname{touched}_E(V) \land e_v(\mathrm{style}) = \top \land e_o(\mathrm{style}) = \bot \Rightarrow \operatorname{frameWork}^{e_o}_E(O).\mathrm{passes}(\mathrm{style}) = \operatorname{frameWork}^{e_v}_E(V).\mathrm{passes}(\mathrm{style})$$
$$\text{where } V = X \oplus \operatorname{lerp}(c, [\,], 0),\ O = X \oplus \operatorname{lerp}(r, W, 1)$$

The read's forced restyle is the pass the variant pays at frame end. -/
theorem gate_forced_tieE {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool)
    (wr : List (Change P)) (ev eo : Stage → Bool)
    (hv : Stage.style ∈ touched E (addF oth (lerpFrame cv [] 0))) (hev : ev .style = true)
    (heo : eo .style = false) :
    (frameWorkE E (addF oth (lerpFrame ro wr 1)) eo).passes .style =
      (frameWorkE E (addF oth (lerpFrame cv [] 0)) ev).passes .style := by
  rw [passesE_style, passesE_style]
  show _ + (oth.forcedStyle + 1) = _ + (oth.forcedStyle + 0)
  simp only [heo, hev, hv, and_false, and_true, Bool.false_eq_true, ↓reduceIte]
  omega

/-- **The old margin (`frameWork`, over-counted).** If the variant does not touch style and some change of the write
dirties style, `frameWork` charges the original $f + 1$ more style passes.

$$\forall E, X, c, r, W, f,\ \forall w \in W:\ \mathrm{style} \notin \operatorname{touched}_E(V) \land \mathrm{style} \in E.\mathrm{stagesOf}(w) \Rightarrow \operatorname{frameWork}_E(O).\mathrm{passes}(\mathrm{style}) = \operatorname{frameWork}_E(V).\mathrm{passes}(\mathrm{style}) + f + 1$$
$$\text{where } V = X \oplus \operatorname{lerp}(c, [\,], 0),\ O = X \oplus \operatorname{lerp}(r, W, f)$$

The extra one is the lifecycle pass the read already paid. -/
theorem gate_forced_margin_old {P M : Type} (E : Engine P M) (oth : FrameIn P) (cv ro : Bool)
    (wr : List (Change P)) (fs : Nat) (c : Change P) (hc : c ∈ wr) (hs : Stage.style ∈ E.stagesOf c)
    (hv : Stage.style ∉ touched E (addF oth (lerpFrame cv [] 0))) :
    (frameWork E (addF oth (lerpFrame ro wr fs))).passes .style =
      (frameWork E (addF oth (lerpFrame cv [] 0))).passes .style + fs + 1 := by
  have ho : Stage.style ∈ touched E (addF oth (lerpFrame ro wr fs)) := by
    simp only [touched, List.mem_append]
    exact Or.inl (Or.inl (Or.inl (List.mem_flatMap.mpr ⟨c, by simp [addF, lerpFrame, hc], hs⟩)))
  show (if Stage.style ∈ touched E (addF oth (lerpFrame ro wr fs)) then 1 else 0) + (oth.forcedStyle + fs) =
    (if Stage.style ∈ touched E (addF oth (lerpFrame cv [] 0)) then 1 else 0) + (oth.forcedStyle + 0) + fs + 1
  simp only [ho, hv, ↓reduceIte]
  omega

end EndPass

end Fw.Parts.PeopleCard
