import Fw.Engine.Visual
import Fw.Site.BreakpointMatrix
import Fw.Parts.PlatformSection
import Fw.Parts.PeopleCardOpt
/-!
# platform:mq, skip the `--platform-shrink` write where the CSS pins the card (`platform.module.css` 7-9, 31-32, 303-315)
Proof note and premises: `research/notes/2026/10-2x-platform-shrink-mq.md`.
-/
namespace Fw.Parts.PlatformShrinkOpt

open Fw.Engine Fw.Site.Breakpoints
open Fw.Parts.PeopleCardOpt (cascade always)

/-! ## The card's look -/

/-- The card's scale at inline shrink `v`: `.card { transform: scale(var(--platform-shrink-scale)) }` (line 32), the
section's scale `1 - 0.083333 v` (line 8), then the band's `1` (`transform: none`, line 311).

Source order, last matching condition wins. -/
def scaleDecls (v : Rat) : List (MQ × Rat) := [(always, 1 - 83333 / 1000000 * v), (c860, 1)]

/-- The card's border radius in px at inline shrink `v`: `calc(var(--platform-shrink-radius) * v)` (line 31) with the
radius 32px, 24px at `(width<=720px)` (line 288), then the band's `0` (`border-radius: 0`, line 310).

Source order, last matching condition wins. -/
def radiusDecls (v : Rat) : List (MQ × Rat) := [(always, 32 * v), (wLe720, 24 * v), (c860, 0)]

/-- **The card's look** at inline `--platform-shrink` value `v`: scale and radius.

The two values the shrink feeds. -/
def look (env : Env) (v : Rat) : Rat × Rat := (cascade env (scaleDecls v) 1, cascade env (radiusDecls v) 0)

#guard look (exEnv 430 430) (1/2) == (1, 0)
#guard look (exEnv 1280 1280) 1 == (916667/1000000, 32)
#guard look (exEnv 800 800) 1 == (1, 0) && look (exEnv 1000 1000 .none .coarse) 1 == (1, 0)
#guard look (exEnv 1000 1000) 1 == (916667/1000000, 32)

/-- **The gated look.** In the c860 band the card's scale is 1 and its radius 0, whatever the value.

Where the gate is on, the written value never shows. -/
theorem look_gated (env : Env) (v : Rat) (h : c860.eval env = true) : look env v = (1, 0) := by
  simp [look, cascade, scaleDecls, radiusDecls, h]

/-- **The ungated scale.** Outside the band the scale is `1 - 83333/1000000 v`.

Where the gate is off, the card follows the value. -/
theorem scale_ungated (env : Env) (v : Rat) (h : c860.eval env = false) :
    (look env v).1 = 1 - 83333 / 1000000 * v := by
  have ha : always.eval env = true := rfl
  simp [look, cascade, scaleDecls, h, ha]

/-- **The gate is exact.** The look does not depend on the inline value exactly in the c860 band.

The variant skips the write precisely where it is invisible, and nowhere else. -/
theorem look_const_iff (env : Env) : (∀ v, look env v = look env 0) ↔ c860.eval env = true := by
  constructor
  · intro h
    cases hc : c860.eval env
    · have h1 := congrArg Prod.fst (h 1)
      rw [scale_ungated env 1 hc, scale_ungated env 0 hc] at h1
      exact absurd h1 (by decide +kernel)
    · rfl
  · intro hc v
    rw [look_gated env v hc, look_gated env 0 hc]

/-! ## The event sequence -/

/-- One event of the frame function: the gate (is `c860` matching now), reduced motion, the card's bottom edge and the
viewport height. A scroll callback and the media-change handler are both events.

What the frame reads. -/
structure Ev where
  gate : Bool
  rm : Bool
  bottom : Rat
  vh : Rat

/-- The state after an event: the inline `--platform-shrink` value, the number of writes so far, the class bit.

What the DOM holds. -/
structure St where
  inl : Rat
  writes : Nat
  cls : Bool
deriving Repr, DecidableEq

/-- The state at load: the CSS `0`, no write, class off.

Before the first event. -/
def St.init : St := ⟨0, 0, false⟩

/-- The value the frame computes.

`PlatformSection.shrink`, the one the TS part already mirrors. -/
def Ev.val (e : Ev) : Rat := PlatformSection.shrink e.rm e.bottom e.vh

/-- The original's event: write the computed value if it differs from the held one, set the class.

What `createShrink`'s frame does today. -/
def stepO (e : Ev) (st : St) : St :=
  ⟨e.val, st.writes + (if e.val = st.inl then 0 else 1), PlatformSection.shrinking e.bottom e.vh⟩

/-- The variant's event: with the gate on, no write; the class is set as before; with the gate off it is the original's
event on the variant's own held value.

What `createShrink`'s frame does under `mq`. -/
def stepV (e : Ev) (st : St) : St :=
  if e.gate then { st with cls := PlatformSection.shrinking e.bottom e.vh } else stepO e st

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

/-- **A leaving event writes the original's value.** After an event whose gate is off, the variant holds the value the
original holds.

Leaving the band (or being outside it) repairs the one stale value at once. -/
theorem inl_ungated (ev : Nat → Ev) (k : Nat) (h : (ev k).gate = false) :
    (stV ev (k + 1)).inl = (stO ev (k + 1)).inl := by
  simp [stV, stO, stepV, stepO, h]

/-- **The class sequences agree.** After every event the class bits are equal.

The `is-platform-shrinking` background switch is untouched by the gate. -/
theorem cls_agree (ev : Nat → Ev) (k : Nat) : (stV ev (k + 1)).cls = (stO ev (k + 1)).cls := by
  simp only [stV, stO, stepV, stepO]
  split <;> rfl

/-- **The look agrees after every event.** With the gate read from the environment in force at the event, the card's
look under the variant equals the original's, in the band (nothing shows) and outside it (same value).

The gated card looks the same in every frame, also across a band change. -/
theorem look_agree (envs : Nat → Env) (ev : Nat → Ev) (hg : ∀ k, (ev k).gate = c860.eval (envs k)) (k : Nat) :
    look (envs k) (stV ev (k + 1)).inl = look (envs k) (stO ev (k + 1)).inl := by
  have h := hg k
  cases hc : c860.eval (envs k)
  · rw [inl_ungated ev k (by rw [h, hc])]
  · rw [look_gated _ _ hc, look_gated _ _ hc]

/-- **Vision, class E (platform).** For every environment trajectory and event, the original's and the variant's
visible scenes are equal, for any scene built from the event, the card's look at the held value and the class.

Premise P1 (the gate each event reads is the one in force) is the hypothesis `hg`. -/
theorem platformShrink_visSame (vp : (Nat → Env) → Rect) (scn : (Nat → Env) → Nat → Rat × Rat → Bool → Scene)
    (ev : (Nat → Env) → Nat → Ev) (hg : ∀ envs k, (ev envs k).gate = c860.eval (envs k)) :
    VisSame E vp
      (fun envs k => scn envs k (look (envs k) (stO (ev envs) (k + 1)).inl) (stO (ev envs) (k + 1)).cls)
      (fun envs k => scn envs k (look (envs k) (stV (ev envs) (k + 1)).inl) (stV (ev envs) (k + 1)).cls) := by
  apply visSame_of_eq
  intro envs k
  rw [look_agree envs (ev envs) (hg envs) k, cls_agree]

/-! ## Work -/

/-- The count step with the gate on, as arithmetic on the held values and counts.

Skipping a write keeps the invariant. -/
theorem writes_step_gated (vw ow : Nat) (vi oi x : Rat) (ih : vw + (if vi = oi then 0 else 1) ≤ ow) :
    vw + (if vi = x then 0 else 1) ≤ ow + (if x = oi then 0 else 1) := by
  grind

/-- The count step with the gate off.

A write on both sides keeps the invariant. -/
theorem writes_step_open (vw ow : Nat) (vi oi x : Rat) (ih : vw + (if vi = oi then 0 else 1) ≤ ow) :
    vw + (if x = vi then 0 else 1) + (if x = x then 0 else 1) ≤ ow + (if x = oi then 0 else 1) := by
  grind

/-- **Writes, every prefix.** The variant's writes plus one if its held value is stale are at most the original's.

The invariant behind `writes_le`. -/
theorem writes_inv (ev : Nat → Ev) (k : Nat) :
    (stV ev k).writes + (if (stV ev k).inl = (stO ev k).inl then 0 else 1) ≤ (stO ev k).writes := by
  induction k with
  | zero => simp [stV, stO, St.init]
  | succ k ih =>
    by_cases hg : (ev k).gate = true
    · simp only [stV, stO, stepV, stepO, hg, ↓reduceIte]
      exact writes_step_gated _ _ _ _ _ ih
    · simp only [stV, stO, stepV, stepO, hg]
      exact writes_step_open _ _ _ _ _ ih

/-- **The variant never writes more.** After every event the variant has written at most as often as the original.

The saving is never repaid with interest, also across band exits. -/
theorem writes_le (ev : Nat → Ev) (k : Nat) : (stV ev k).writes ≤ (stO ev k).writes :=
  Nat.le_trans (Nat.le_add_right _ _) (writes_inv ev k)

/-- **A run in the band writes nothing.** While every event is gated the variant holds the CSS `0` and has written
nothing.

The whole saving, in the phone band. -/
theorem gated_run (ev : Nat → Ev) (k : Nat) (h : ∀ j, j < k → (ev j).gate = true) :
    (stV ev k).writes = 0 ∧ (stV ev k).inl = 0 := by
  induction k with
  | zero => simp [stV, St.init]
  | succ k ih =>
    have := ih (fun j hj => h j (Nat.lt_succ_of_lt hj))
    have hk := h k (Nat.lt_succ_self k)
    simp [stV, stepV, hk, this]

/-- **Strictly less in the band.** If the original writes at least once during a run that stays in the band, the
variant writes strictly less.

The saving exists whenever the card moves while the page is in the phone band. -/
theorem gated_run_lt (ev : Nat → Ev) (k : Nat) (h : ∀ j, j < k → (ev j).gate = true) (hw : 0 < (stO ev k).writes) :
    (stV ev k).writes < (stO ev k).writes := by
  rw [(gated_run ev k h).1]; exact hw

/-- **No shrink, no write.** While the card's bottom edge is at or below `0.85` of the viewport height at every event,
the computed value is 0, so the original writes nothing either and the variant saves nothing.

The rewrite's last section ends the page, so a plain scroll never lifts the bottom above that line. -/
theorem unshrunk_run (ev : Nat → Ev) (k : Nat)
    (h : ∀ j, j < k → 0 < (ev j).vh ∧ 17 * (ev j).vh / 20 ≤ (ev j).bottom) :
    (stO ev k).writes = 0 ∧ (stO ev k).inl = 0 := by
  induction k with
  | zero => simp [stO, St.init]
  | succ k ih =>
    have ih' := ih (fun j hj => h j (Nat.lt_succ_of_lt hj))
    obtain ⟨hv, hb⟩ := h k (Nat.lt_succ_self k)
    have hs : (ev k).val = 0 := (PlatformSection.shrink_ends (ev k).rm (ev k).bottom (ev k).vh hv).1 hb
    simp [stO, stepO, hs, ih']

/-! ## Decision and goldens -/

/-- **The write decision** the TS driver mirrors: whether to write, given the gate, the computed value and the last
written one.

No write in the band, a write outside it exactly when the value differs. -/
def writeNow (gate : Bool) (s last : Rat) : Bool := !gate && s != last

/-- The last written value after the decision.

Held while the write is skipped. -/
def lastAfter (gate : Bool) (s last : Rat) : Rat := if writeNow gate s last then s else last

#guard writeNow false (1/2) 0 && !writeNow false 0 0 && !writeNow true (1/2) 0
#guard lastAfter true 1 0 == 0 && lastAfter false 1 0 == 1

/-- The decision agrees with the model: the variant's event writes exactly when `writeNow` says so.

The TS decision is the model's event. -/
theorem stepV_writes (e : Ev) (st : St) :
    (stepV e st).writes = st.writes + (if writeNow e.gate e.val st.inl then 1 else 0) ∧
    (stepV e st).inl = lastAfter e.gate e.val st.inl := by
  cases hg : e.gate <;> by_cases hv : e.val = st.inl <;> simp [stepV, stepO, writeNow, lastAfter, hg, hv]

end Fw.Parts.PlatformShrinkOpt
