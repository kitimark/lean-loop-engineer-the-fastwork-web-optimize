import Fw.Engine.Visual
import Fw.Site.BreakpointMatrix
import Fw.Parts.Commission
import Fw.Parts.PeopleCardOpt
/-!
# commission:band-gate, skip the two custom-property writes where the CSS pins the card (`commission.module.css` 7-10, 48, 51, 436-452)
Proof note and premises: `research/notes/2026/10-2x-commission-band-gate.md`.

In the c1000 band the section sets `--commission-shrink-scale: 1` and `--commission-shrink-radius: 0px`, and the card sets
`border-radius: 0` and `transform: none`, so the two values the driver writes every follower frame
(`--commission-enter-shrink`, `--commission-shrink`) are read by nothing that shows. The variant skips both writes while
the gate (`mq.c1000`) holds, runs the follower and the class toggles as before, and writes the current pair on the first
frame that reads the gate off.
-/
namespace Fw.Parts.CommissionOpt

open Fw.Engine Fw.Site.Breakpoints Fw.Parts.Commission
open Fw.Parts.PeopleCardOpt (cascade always)

/-! ## The card's look -/

/-- The card's scale at `max(e, s) = w`: `--commission-shrink-scale` is `1 - 0.083333 w` (line 9), then the band's `1`
(line 438).

Source order, last matching condition wins. -/
def scaleDecls (w : Rat) : List (MQ × Rat) := [(always, 1 - depth * w), (c1000, 1)]

/-- The card's border radius in px at `max(e, s) = w`: `calc(32px * w)` (lines 10, 48), then the band's `0` (lines 439, 446).

Source order, last matching condition wins. -/
def radiusDecls (w : Rat) : List (MQ × Rat) := [(always, radius * w), (c1000, 0)]

/-- **The card's look** at the inline pair `(e, s)`: scale and radius, the two values the pair feeds.

The CSS reads the pair only through `max e s`. -/
def look (env : Env) (p : Rat × Rat) : Rat × Rat :=
  (cascade env (scaleDecls (max p.1 p.2)) 1, cascade env (radiusDecls (max p.1 p.2)) 0)

#guard look (exEnv 430 430) (1, 1) == (1, 0)
#guard look (exEnv 1280 1280) (1, 1) == (916667/1000000, 32)
#guard look (exEnv 1000 1000) (1, 1) == (1, 0) && look (exEnv 1001 1001 .none .coarse) (1, 0) == (1, 0)
#guard look (exEnv 1001 1001) (1, 1) == (916667/1000000, 32)
#guard look (exEnv 1280 400) (1, 1) == (1, 0)

/-- **The gated look.** In the c1000 band the card's scale is 1 and its radius 0, whatever the pair.

Where the gate is on, the written pair never shows. -/
theorem look_gated (env : Env) (p : Rat × Rat) (h : c1000.eval env = true) : look env p = (1, 0) := by
  simp [look, cascade, scaleDecls, radiusDecls, h]

/-- **The ungated look.** Outside the band the scale is `1 - 83333/1000000 max(e, s)` and the radius `32 max(e, s)`.

Where the gate is off, the card follows the pair. -/
theorem look_ungated (env : Env) (p : Rat × Rat) (h : c1000.eval env = false) :
    look env p = (1 - depth * max p.1 p.2, radius * max p.1 p.2) := by
  have ha : always.eval env = true := rfl
  simp [look, cascade, scaleDecls, radiusDecls, h, ha]

/-- **The gate is exact.** The look does not depend on the inline pair exactly in the c1000 band.

The variant skips the writes precisely where they are invisible, and nowhere else. -/
theorem look_const_iff (env : Env) : (∀ p, look env p = look env (1, 1)) ↔ c1000.eval env = true := by
  constructor
  · intro h
    cases hc : c1000.eval env
    · have h1 := congrArg Prod.fst (h (0, 0))
      rw [look_ungated env _ hc, look_ungated env _ hc] at h1
      exact absurd h1 (by decide +kernel)
    · rfl
  · intro hc p
    rw [look_gated env p hc, look_gated env (1, 1) hc]

/-! ## The event sequence -/

/-- One event of the frame body: the gate (is `c1000` matching now, the driver's `compact`), reduced motion, the card's top
edge, the section's bottom edge and the viewport height.

What the frame reads. -/
structure Ev where
  gate : Bool
  rm : Bool
  top : Rat
  bottom : Rat
  vh : Rat

/-- The state after an event: the follower pair, the inline pair on the section, the number of property writes so far, and
the two class bits.

What the driver and the DOM hold. -/
structure St where
  fol : Pair
  inl : Rat × Rat
  writes : Nat
  cls : Bool × Bool
deriving Repr, DecidableEq

/-- The state at load: the follower at `(1, 0)`, the CSS `1` for both properties, no write, classes off.

Before the first event. -/
def St.init : St := ⟨pair0, (1, 1), 0, (false, false)⟩

/-- The frame an event runs.

`Commission.frame` on the follower, the one the TS part already mirrors. -/
def Ev.frame (e : Ev) (st : St) : Frame := Fw.Parts.Commission.frame st.fol e.top e.bottom e.vh e.rm e.gate

/-- The original's event: advance the follower, write both properties, set the classes.

What the driver's body does today (`driver.ts` `body`): two `setProperty` calls every event. -/
def stepO (e : Ev) (st : St) : St :=
  let f := e.frame st
  ⟨⟨f.n, f.r⟩, (f.n, f.shrink), st.writes + 2, (f.entering, f.shrinking)⟩

/-- The variant's event: with the gate on and the follower still moving, the follower and the classes advance and nothing is
written; with the gate off, or with the follower settled, it is the original's event.

What the driver's body does under `commission:band-gate`. The settled write keeps the section's pair equal to the
original's at rest, which the breakpoint gate compares. -/
def stepV (e : Ev) (st : St) : St :=
  if e.gate && (e.frame st).more then
    let f := e.frame st
    { st with fol := ⟨f.n, f.r⟩, cls := (f.entering, f.shrinking) }
  else stepO e st

/-- The media-change event: with the gate off, write the follower's current pair (the one the original wrote last); with the
gate on, nothing. It does not run the frame body.

What the driver does on a `mq.c1000` change under the variant, so that a change without a resize repairs the stale pair. -/
def stepC (g : Bool) (st : St) : St :=
  if g then st else { st with inl := (st.fol.n, max st.fol.n st.fol.r), writes := st.writes + 2 }

/-- The original's state after `k` events.

The original, event by event. -/
def stO (ev : Nat → Ev) : Nat → St
  | 0 => St.init
  | k + 1 => stepO (ev k) (stO ev k)

/-- The variant's state after `k` events.

The variant, event by event. -/
def stV (ev : Nat → Ev) : Nat → St
  | 0 => St.init
  | k + 1 => stepV (ev k) (stV ev k)

/-- **The follower and the classes agree.** After every event the variant's follower pair and class bits equal the original's.

The gate changes no decision the frame takes; only the writes. -/
theorem fol_cls_agree (ev : Nat → Ev) (k : Nat) :
    (stV ev k).fol = (stO ev k).fol ∧ (stV ev k).cls = (stO ev k).cls := by
  induction k with
  | zero => simp [stV, stO]
  | succ k ih =>
    have hf : (ev k).frame (stV ev k) = (ev k).frame (stO ev k) := by
      simp [Ev.frame, ih.1]
    simp only [stV, stO, stepV, stepO, hf]
    split <;> simp

/-- The frames of the two arms are equal at every event.

The one fact the other proofs rewrite with. -/
theorem frame_agree (ev : Nat → Ev) (k : Nat) : (ev k).frame (stV ev k) = (ev k).frame (stO ev k) := by
  simp [Ev.frame, (fol_cls_agree ev k).1]

/-- **A writing event writes the original's pair.** After an event that is not (gated and moving), the variant holds the
pair the original holds.

The stale pair is repaired by any event the variant writes in. -/
theorem inl_written (ev : Nat → Ev) (k : Nat) (h : ¬ ((ev k).gate = true ∧ ((ev k).frame (stO ev k)).more = true)) :
    (stV ev (k + 1)).inl = (stO ev (k + 1)).inl := by
  have hf := frame_agree ev k
  have hc : ((ev k).gate && ((ev k).frame (stO ev k)).more) = false := by
    cases hg : (ev k).gate <;> cases hm : ((ev k).frame (stO ev k)).more <;> simp_all
  simp [stV, stO, stepV, stepO, hf, hc]

/-- **A leaving event writes the original's pair.** After an event whose gate is off, the variant holds the pair the original
holds.

Leaving the band (or being outside it) repairs the stale pair at once, in the frame that reads the gate off, before paint. -/
theorem inl_ungated (ev : Nat → Ev) (k : Nat) (h : (ev k).gate = false) :
    (stV ev (k + 1)).inl = (stO ev (k + 1)).inl :=
  inl_written ev k (by simp [h])

/-- **A settled event writes the original's pair.** In the band, an event whose follower has settled leaves the variant
holding the pair the original holds.

At rest in the band the section carries the faithful pair, which is what the breakpoint gate reads. -/
theorem inl_settled (ev : Nat → Ev) (k : Nat) (h : ((ev k).frame (stO ev k)).more = false) :
    (stV ev (k + 1)).inl = (stO ev (k + 1)).inl :=
  inl_written ev k (by simp [h])

/-- **The exit catch-up.** An event with the gate off leaves the variant holding exactly the faithful pair
`(n, max n r)` of that frame, whatever the events before it.

The band exit restores the faithful state in one frame. -/
theorem exit_catchup (ev : Nat → Ev) (k : Nat) (h : (ev k).gate = false) :
    (stV ev (k + 1)).inl = (((ev k).frame (stO ev k)).n, ((ev k).frame (stO ev k)).shrink) := by
  rw [inl_ungated ev k h]
  simp [stO, stepO]

/-- **The original's pair is always the follower's.** The section holds `(n, max n r)` of the follower after every event.

The invariant behind the media-change catch-up. -/
theorem inl_orig (ev : Nat → Ev) (k : Nat) :
    (stO ev k).inl = ((stO ev k).fol.n, max (stO ev k).fol.n (stO ev k).fol.r) := by
  cases k with
  | zero =>
    have h10 : max (1 : Rat) 0 = 1 := by decide +kernel
    simp [stO, St.init, pair0, h10]
  | succ k => simp [stO, stepO, Frame.shrink]

/-- **The media-change catch-up.** With the gate off, the catch-up leaves the variant holding the original's pair.

A change of `mq.c1000` without a resize still repairs the pair before paint. -/
theorem media_catchup (ev : Nat → Ev) (k : Nat) : (stepC false (stV ev k)).inl = (stO ev k).inl := by
  rw [inl_orig ev k]
  simp [stepC, (fol_cls_agree ev k).1]

/-- **The look agrees after every event.** With the gate read from the environment in force at the event, the card's look
under the variant equals the original's, in the band (nothing shows) and outside it (same pair).

The gated card looks the same in every frame, also across a band change. -/
theorem look_agree (envs : Nat → Env) (ev : Nat → Ev) (hg : ∀ k, (ev k).gate = c1000.eval (envs k)) (k : Nat) :
    look (envs k) (stV ev (k + 1)).inl = look (envs k) (stO ev (k + 1)).inl := by
  have h := hg k
  cases hc : c1000.eval (envs k)
  · rw [inl_ungated ev k (by rw [h, hc])]
  · rw [look_gated _ _ hc, look_gated _ _ hc]

/-- **The look agrees after a media-change catch-up.** With the gate the environment gives, the card's look under the variant
after the catch-up equals the original's.

A change without a resize shows no stale pair. -/
theorem media_look_agree (env : Env) (ev : Nat → Ev) (k : Nat) :
    look env (stepC (c1000.eval env) (stV ev k)).inl = look env (stO ev k).inl := by
  cases hc : c1000.eval env
  · rw [media_catchup ev k]
  · rw [look_gated _ _ hc, look_gated _ _ hc]

/-- **Vision, class E (commission).** For every environment trajectory and event, the original's and the variant's visible
scenes are equal, for any scene built from the event, the card's look at the held pair and the class bits.

Premise P1 (the gate each event reads is the one in force) is the hypothesis `hg`. -/
theorem commission_visSame (vp : (Nat → Env) → Rect)
    (scn : (Nat → Env) → Nat → Rat × Rat → Bool × Bool → Scene)
    (ev : (Nat → Env) → Nat → Ev) (hg : ∀ envs k, (ev envs k).gate = c1000.eval (envs k)) :
    VisSame E vp
      (fun envs k => scn envs k (look (envs k) (stO (ev envs) (k + 1)).inl) (stO (ev envs) (k + 1)).cls)
      (fun envs k => scn envs k (look (envs k) (stV (ev envs) (k + 1)).inl) (stV (ev envs) (k + 1)).cls) := by
  apply visSame_of_eq
  intro envs k
  rw [look_agree envs (ev envs) (hg envs) k, (fol_cls_agree (ev envs) (k + 1)).2]

/-! ## Work -/

/-- **The original writes twice per event.** After `k` events it has made `2k` writes.

The cost today. -/
theorem writes_orig (ev : Nat → Ev) (k : Nat) : (stO ev k).writes = 2 * k := by
  induction k with
  | zero => simp [stO, St.init]
  | succ k ih => simp [stO, stepO, ih]; omega

/-- **The variant writes only on events that are not (gated and moving).** Its count grows by two on those and by nothing on
the others.

The count step. -/
theorem writes_step (ev : Nat → Ev) (k : Nat) :
    (stV ev (k + 1)).writes =
      (stV ev k).writes + (if (ev k).gate = true ∧ ((ev k).frame (stO ev k)).more = true then 0 else 2) := by
  have hf := frame_agree ev k
  simp only [stV, stepV, hf]
  split <;> simp_all [stepO]

/-- **The variant never writes more.** After every event the variant has written at most as often as the original.

The saving is never repaid with interest, also across band exits. -/
theorem writes_le (ev : Nat → Ev) (k : Nat) : (stV ev k).writes ≤ (stO ev k).writes := by
  induction k with
  | zero => simp [stV, stO]
  | succ k ih =>
    rw [writes_step]
    have := writes_orig ev (k + 1)
    have := writes_orig ev k
    split <;> omega

/-- **A moving run in the band writes nothing.** While every event is gated and its follower still moves, the variant has
written nothing and holds the CSS `1, 1`.

The whole saving, in the compact band, while the card follows the scroll. -/
theorem moving_run (ev : Nat → Ev) (k : Nat)
    (h : ∀ j, j < k → (ev j).gate = true ∧ ((ev j).frame (stO ev j)).more = true) :
    (stV ev k).writes = 0 ∧ (stV ev k).inl = (1, 1) := by
  induction k with
  | zero => simp [stV, St.init]
  | succ k ih =>
    have := ih (fun j hj => h j (Nat.lt_succ_of_lt hj))
    have hk := h k (Nat.lt_succ_self k)
    have hf := frame_agree ev k
    simp [stV, stepV, hk.1, hf, hk.2, this]

/-- **Strictly less in the band.** If a run stays in the band with a moving follower for at least one event, the variant
writes strictly less.

Unlike a platform shrink value, the follower frame writes on every event, so the saving exists for every moving frame. -/
theorem moving_run_lt (ev : Nat → Ev) (k : Nat) (hk : 0 < k)
    (h : ∀ j, j < k → (ev j).gate = true ∧ ((ev j).frame (stO ev j)).more = true) :
    (stV ev k).writes < (stO ev k).writes := by
  rw [(moving_run ev k h).1, writes_orig]; omega

/-! ## Decision and goldens -/

/-- **The write decision** the TS driver mirrors: write both properties unless the gate is on and the follower still moves.

No write in the band while the card follows the scroll, a write outside it (which includes the first frame after the band is
left) and a write when the follower settles in the band. -/
def writeNow (gate more : Bool) : Bool := !(gate && more)

/-- The media-change decision: write the follower's pair exactly when the gate is off.

A change out of the band repairs the pair before paint. -/
def catchupNow (gate : Bool) : Bool := !gate

#guard writeNow false true && writeNow false false && writeNow true false && !writeNow true true
#guard catchupNow false && !catchupNow true

/-- The decision agrees with the model: the variant's event adds `2` writes exactly when `writeNow` says so.

The TS decision is the model's event. -/
theorem stepV_writes (e : Ev) (st : St) :
    (stepV e st).writes = st.writes + (if writeNow e.gate (e.frame st).more then 2 else 0) := by
  cases hg : e.gate <;> cases hm : (e.frame st).more <;> simp [stepV, stepO, writeNow, hg, hm]

/-- The media-change decision agrees with the model.

The TS catch-up is the model's event. -/
theorem stepC_writes (g : Bool) (st : St) :
    (stepC g st).writes = st.writes + (if catchupNow g then 2 else 0) := by
  cases g <;> simp [stepC, catchupNow]

end Fw.Parts.CommissionOpt
