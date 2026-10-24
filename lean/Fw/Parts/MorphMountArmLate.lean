import Fw.Parts.MorphEnd
import Fw.Parts.MorphMount

/-!
# morph.mount:arm-late

The end-of-page morph listens to `wheel` and `touchmove` on `window` with `passive: false`, from the moment the platform
is within 200 % of the viewport (the observer `near`) or the morph is active. WebKit answers every wheel event over a
non-passive wheel listener on the main thread before it scrolls (`ScrollingTree.cpp:118-131@862f17d`: the point is in the
non-passive wheel region, so `SynchronousScrolling` and `BlockingDOMEventDispatch`; a passive listener gets
`AsyncScrolling` and `NonBlockingDOMEventDispatch`, `:133-134`), and a non-passive touchmove listener holds a touch
sequence the same way (`WebPageProxy.cpp:5049-5089,5228-5300@862f17d`, cited by `MorphListen.honored`).

`arm-late` keeps every listener the original has, but registers it passive until the platform bottom is inside a band
of scroll positions (the half line `bottom <= edge vh`). The same handler runs in both modes, so a passive listener
changes only whether `preventDefault` is honored. Theorems:

* `prevent_needs`: for every `Hooks` (so every A/B/C brick combination, `prevent_needs_cfg`) a handler call can ask for
  `preventDefault` only when the morph is active, or the read arm holds;
* `covers`: an idle call that asks for it has the platform in the band;
* `late_same`: along any event/refresh trace the late run's outputs equal the faithful run's;
* `no_blocking_out_of_band`: outside the band, and with the morph idle, no non-passive listener is attached.
-/
namespace Fw.Parts.MorphMountArmLate

open Fw.Parts Fw.Parts.MorphEnd
open Fw.Parts.MorphTween (St frame push)

/-- The part and the variant the flag `morph.mount:arm-late` names. -/
def partId : String := "morph.mount"
def variantId : String := "arm-late"

/-! ## The band -/

/-- How far past the arming edge the band reaches, in px: one viewport of pan inside a touch gesture (checked on the replay
profiles by `MorphListen.panOk`) plus a quarter viewport of scroll between two band evaluations (INFERRED, unchecked). -/
def lead (vh : Rat) : Rat := vh + vh / 4

/-- The platform bottom edge of the band. The original arms a push at `bottom <= vh + 8` (`MorphTween.armed`). -/
def edge (vh : Rat) : Rat := vh + MorphTween.bottomSlack + lead vh

/-- The band: the platform bottom is at most `edge vh`. A half line, so no upper edge needs a premise. -/
def inBand (vh bottom : Rat) : Bool := decide (bottom ≤ edge vh)

#guard edge 800 == 800 + 8 + 1000
#guard inBand 800 1808 == true && inBand 800 (3615 / 2) == true && inBand 800 1809 == false && inBand 800 (3617 / 2) == false

/-- The band holds every bottom at which the original arms a push, at any lag up to `lead`. -/
theorem armed_in_band {h vh b bEval : Rat} (ha : MorphTween.armed h b vh = true) (hl : bEval ≤ b + lead vh) :
    inBand vh bEval = true := by
  simp only [MorphTween.armed, MorphTween.bottomSlack, Bool.and_eq_true, decide_eq_true_eq] at ha
  simp only [inBand, edge, MorphTween.bottomSlack, lead] at hl ⊢
  grind

/-- `morph.mount`'s own arming test is `MorphTween.armed`. -/
theorem mount_armed_eq (h b vh : Rat) : MorphMount.armed ⟨h, b⟩ vh = MorphTween.armed h b vh := by
  have e : vh * 45 / 100 = vh * MorphTween.fillRatio := by unfold MorphTween.fillRatio; grind
  unfold MorphMount.armed MorphTween.armed MorphTween.bottomSlack
  rw [e]

/-! ## Listener modes -/

/-- What the original attaches: both listeners, non-passive, while `near` or active. -/
def attached (near act : Bool) : Bool := near || act

/-- What `arm-late` attaches non-passive: only inside the band (and `near`), or while the morph is active. -/
def blocking (near band act : Bool) : Bool := (near && band) || act

inductive Mode where
  | none | passive | blocking
  deriving DecidableEq, Repr

def mode (near band act : Bool) : Mode :=
  if blocking near band act then .blocking else if attached near act then .passive else .none

def Mode.name : Mode → String
  | .none => "none" | .passive => "passive" | .blocking => "blocking"

/-- A non-passive listener is always one the original also has. -/
theorem blocking_le (near band act : Bool) : blocking near band act = true → attached near act = true := by
  cases near <;> cases band <;> cases act <;> simp [blocking, attached]

/-- The same listeners exist: `arm-late` only changes passive against non-passive. -/
theorem mode_none_iff (near band act : Bool) : mode near band act = .none ↔ attached near act = false := by
  cases near <;> cases band <;> cases act <;> simp [mode, blocking, attached]

/-- Outside the band, with the morph idle, no non-passive listener is attached. -/
theorem no_blocking_out_of_band (near act : Bool) (hact : act = false) : mode near false act ≠ .blocking := by
  cases near <;> simp [mode, blocking, attached, hact]

/-- In the band, or while active, the mode is the original's (non-passive) whenever the original attaches. -/
theorem mode_in_band (near act : Bool) (h : attached near act = true) : mode near true act = .blocking := by
  cases near <;> cases act <;> simp_all [mode, blocking, attached]

/-! ## The lock decision asks for `preventDefault` only where the band holds -/

/-- The read a capture handler takes its arm test from. -/
def evRead : Ev → Option Read
  | .touchmove _ r => some r
  | .wheel _ r => some r
  | _ => none

/-- The events the capture listeners see. -/
def evGated : Ev → Bool
  | .touchstart _ | .touchmove .. | .wheel .. => true
  | _ => false

theorem read_gated (e : Ev) (r : Read) (h : evRead e = some r) : evGated e = true := by
  cases e <;> simp_all [evRead, evGated]

theorem moveStep_prevent (h : Hooks) (s : S) (d : Rat) (r : Read) (hp : (moveStep h s d r).2.prevent = true) :
    s.tw.isActive = true ∨ r.arm = true := by
  rcases moveStep_cases h s d r with ⟨ht, he⟩ | ⟨ht, -, -⟩ | ⟨g, ht, -, -, -⟩ <;> try (rw [he] at hp; simp at hp; done)
  all_goals
    simp only [MorphTween.taken, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at ht
    rcases ht with ht | ⟨-, ht⟩
    · exact Or.inl ht
    · exact Or.inr ht

/-- A handler call changes the tween only when its push is taken, and then through `push`. -/
theorem moveStep_tw (h : Hooks) (s : S) (d : Rat) (r : Read) :
    (moveStep h s d r).1.tw = s.tw ∨
      ((s.tw.isActive = true ∨ r.arm = true) ∧ ∃ g, (moveStep h s d r).1.tw = push s.tw g r.reduced r.now) := by
  have hk : MorphTween.taken s.tw.isActive d r.arm = true → s.tw.isActive = true ∨ r.arm = true := by
    simp only [MorphTween.taken, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq]
    intro ht; rcases ht with ht | ⟨-, ht⟩
    · exact Or.inl ht
    · exact Or.inr ht
  rcases moveStep_cases h s d r with ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, ht, -, -, he⟩
  · left; rw [he]
  · left; rw [he]; simp [kept]
  · right; exact ⟨hk ht, g, by rw [he]; simp [applied]⟩

/-- **The lock decision, every brick combination.** A handler call asks for `preventDefault` only when the morph is active
or the read arm holds, whatever `Hooks` the bricks A, B and C build. -/
theorem prevent_needs (h : Hooks) (s : S) (e : Ev) (hp : (step h s e).2.prevent = true) :
    s.tw.isActive = true ∨ ∃ r, evRead e = some r ∧ r.arm = true := by
  cases e with
  | touchstart y => simp [step] at hp
  | touchmove y r =>
    simp only [step] at hp
    rcases moveStep_prevent h _ _ r hp with ha | ha
    · exact Or.inl ha
    · exact Or.inr ⟨r, rfl, ha⟩
  | wheel d r =>
    simp only [step] at hp
    rcases moveStep_prevent h _ _ r hp with ha | ha
    · exact Or.inl ha
    · exact Or.inr ⟨r, rfl, ha⟩
  | scroll y m => simp [step, frameOut] at hp
  | resize y m => simp [step, frameOut] at hp
  | tick n => simp [step] at hp

theorem prevent_needs_cfg (c : Cfg) (s : S) (e : Ev) (hp : (step c.hooks s e).2.prevent = true) :
    c ∈ Cfg.all ∧ (s.tw.isActive = true ∨ ∃ r, evRead e = some r ∧ r.arm = true) :=
  ⟨mem_all c, prevent_needs c.hooks s e hp⟩

/-- **The band covers the lock.** An idle call that asks for `preventDefault`, with the read arm tied to the geometry, has the
band evaluation inside the band, if that evaluation is at most `lead` behind the platform bottom. -/
theorem covers (h : Hooks) (hh vh b bEval : Rat) (s : S) (e : Ev) (hidle : s.tw.isActive = false)
    (hp : (step h s e).2.prevent = true)
    (hgeo : ∀ r, evRead e = some r → r.arm = true → MorphTween.armed hh b vh = true) (hl : bEval ≤ b + lead vh) :
    inBand vh bEval = true := by
  rcases prevent_needs h s e hp with ha | ⟨r, hr, ha⟩
  · rw [hidle] at ha; exact absurd ha (by simp)
  · exact armed_in_band (hgeo r hr ha) hl

/-! ## A run: refreshes and events -/

/-- The listener layer and the morph. `near`, `actR`, `bEval` are the inputs of the last refresh; `clock` the last tick. -/
structure W where
  s : S
  near : Bool
  actR : Bool
  bEval : Rat
  clock : Rat

def W.listens (w : W) : Bool := attached w.near w.actR

def W.blocks (vh : Rat) (w : W) : Bool := blocking w.near (inBand vh w.bEval) w.actR

inductive Act where
  | ev (e : Ev) (b : Rat)
  | refresh (near : Bool) (b : Rat)

def evClock (w : W) : Ev → Rat
  | .tick n => n
  | _ => w.clock

/-- One action. A refresh stores `near`, whether the morph is active and the platform bottom. An event that the capture
listeners see runs only while the original would have them attached; the handler is the same in both modes. -/
def stepW (h : Hooks) (w : W) : Act → W × Option Out
  | .refresh near b => ({ w with near := near, actR := w.s.tw.isActive, bEval := b }, none)
  | .ev e _ =>
    if evGated e && !w.listens then (w, none)
    else ({ w with s := (step h w.s e).1, clock := evClock w e }, some (step h w.s e).2)

def honorOut (blk : Bool) (o : Out) : Out := { o with prevent := o.prevent && blk }

theorem honorOut_of (blk : Bool) (o : Out) (h : o.prevent = true → blk = true) : honorOut blk o = o := by
  cases o with | mk p g f w => cases p <;> simp_all [honorOut]

/-- The faithful outputs: every `preventDefault` honored. -/
def outsW (h : Hooks) : W → List Act → List (Option Out)
  | _, [] => []
  | w, a :: t => (stepW h w a).2 :: outsW h (stepW h w a).1 t

/-- The `arm-late` outputs: a `preventDefault` counts only while the listener is non-passive. -/
def outsL (h : Hooks) (vh : Rat) : W → List Act → List (Option Out)
  | _, [] => []
  | w, a :: t => (stepW h w a).2.map (honorOut (w.blocks vh)) :: outsL h vh (stepW h w a).1 t

/-- A tween that is not active and still pending stays inactive for every later frame time. -/
def Settled (c : Rat) (tw : St) : Prop :=
  tw.isActive = false → tw.pending = true → ∀ now, c ≤ now → (frame tw now).isActive = false

theorem settled_mono {c c' : Rat} {tw : St} (h : Settled c tw) (hc : c ≤ c') : Settled c' tw :=
  fun a b now hn => h a b now (by grind)

theorem tween_mono (f t e e' : Rat) (ht : t ≤ f) (he : e ≤ e') :
    (MorphTween.tween f t e').value ≤ (MorphTween.tween f t e).value := by
  have hm := MorphTween.ease_mem (MorphTween.clamp01 (e' / MorphTween.duration))
  have hm' := MorphTween.ease_mem (MorphTween.clamp01 (e / MorphTween.duration))
  have hi : MorphTween.clamp01 (e / MorphTween.duration) ≤ MorphTween.clamp01 (e' / MorphTween.duration) := by
    have : e / MorphTween.duration ≤ e' / MorphTween.duration := by
      rw [MorphTween.div_dur, MorphTween.div_dur]; grind
    unfold MorphTween.clamp01; grind
  have hz := MorphTween.ease_mono _ _ hi
  unfold MorphTween.tween
  by_cases h1 : 1 ≤ MorphTween.clamp01 (e' / MorphTween.duration)
  · by_cases h2 : 1 ≤ MorphTween.clamp01 (e / MorphTween.duration)
    · simp [h1, h2]
    · simp only [h1, h2, ite_true, ite_false]
      have := Rat.mul_le_mul_of_nonneg_left hm'.2 (show 0 ≤ f - t by grind)
      have := Rat.mul_nonneg (show 0 ≤ f - t by grind) hm'.1
      grind
  · have h2 : ¬ 1 ≤ MorphTween.clamp01 (e / MorphTween.duration) := by grind
    simp only [h1, h2, ite_false]
    have := Rat.mul_le_mul_of_nonneg_left hz (show 0 ≤ f - t by grind)
    grind

/-- One frame that leaves the tween inactive and pending leaves it inactive at every later time. -/
theorem settled_frame (tw : St) (now : Rat) (htt : tw.t = tw.target) : Settled now (frame tw now) := by
  intro hi hp now' hn
  have hfr : ∀ x, (frame (frame tw now) x) = { frame tw x with value := (frame tw x).value } := by
    intro x; simp [frame]
  simp only [MorphTween.St.isActive, MorphTween.active, Bool.or_eq_false_iff, decide_eq_false_iff_not] at hi ⊢
  simp only [frame] at hi ⊢
  have hb := MorphTween.tween_between tw.f tw.t (now' - tw.start)
  refine ⟨hi.1, ?_⟩
  by_cases hs : tw.t ≤ tw.f
  · have := tween_mono tw.f tw.t (now - tw.start) (now' - tw.start) hs (by grind)
    have h2 := hi.2
    unfold MorphTween.activeCut at *
    grind
  · have := hb.2
    have h3 := hi.1
    unfold MorphTween.activeCut at *
    have hm : max tw.f tw.t = tw.t := by grind
    grind

theorem settled_push (c : Rat) (tw : St) (g : Rat) (red : Bool) (now : Rat) (h0 : Settled c tw) :
    Settled c (push tw g red now) := by
  unfold push
  by_cases h1 : tw.target = g ∧ tw.t = g
  · simp only [h1, and_self, ite_true]; exact h0
  · by_cases hr : red = true
    · simp only [h1, hr, ite_true, ite_false]
      intro _ hp; simp at hp
    · simp only [h1, hr, ite_false, Bool.not_eq_true] at *
      intro hi hp now' hn
      simp only [MorphTween.St.isActive, MorphTween.active, Bool.or_eq_false_iff, decide_eq_false_iff_not] at hi ⊢
      simp only [frame] at ⊢
      have hb := MorphTween.tween_between tw.value g (now' - now)
      unfold MorphTween.activeCut at *
      refine ⟨hi.1, ?_⟩
      grind

/-- Where a tween can change in one step: nowhere, through a taken push, or through a pending tick. -/
theorem step_tw (h : Hooks) (s : S) (e : Ev) :
    (step h s e).1.tw = s.tw ∨
      (∃ r, evRead e = some r ∧ (s.tw.isActive = true ∨ r.arm = true) ∧
        ∃ g, (step h s e).1.tw = push s.tw g r.reduced r.now) ∨
      (∃ n, e = .tick n ∧ s.tw.pending = true ∧ (step h s e).1.tw = frame s.tw n) := by
  cases e with
  | touchstart y => left; simp [step]
  | touchmove y r =>
    simp only [step]
    rcases moveStep_tw h { s with touchY := y.getD s.touchY } (s.touchY - y.getD s.touchY) r with h1 | ⟨h2, g, h3⟩
    · left; exact h1
    · right; left; exact ⟨r, rfl, h2, g, h3⟩
  | wheel d r =>
    simp only [step]
    rcases moveStep_tw h s d r with h1 | ⟨h2, g, h3⟩
    · left; exact h1
    · right; left; exact ⟨r, rfl, h2, g, h3⟩
  | scroll y m => left; simp [step]
  | resize y m => left; simp [step]
  | tick n =>
    by_cases hp : s.tw.pending = true
    · right; right; exact ⟨n, rfl, hp, by simp [step, hp]⟩
    · left; simp [step, hp]

/-- A call with a read arm that holds and a listener attached has its band evaluation inside the band. -/
theorem arm_blocks (vh : Rat) (w : W) (hl : w.listens = true) {hh b : Rat} (ha : MorphTween.armed hh b vh = true)
    (hlag : w.bEval ≤ b + lead vh) : w.blocks vh = true := by
  have hb := armed_in_band ha hlag
  unfold W.listens attached at hl
  unfold W.blocks blocking
  simp only [hb, Bool.and_true, Bool.or_eq_true] at hl ⊢
  exact hl

/-- What the run carries from one action to the next. -/
def Inv' (vh : Rat) (w : W) : Prop :=
  MorphEnd.Inv w.s ∧ Settled w.clock w.s.tw ∧ (w.s.tw.isActive = true → w.blocks vh = true)

/-- What the run assumes of an action: a read arm that holds comes with the platform geometry and a band evaluation at
most `lead` behind it; ticks do not run back in time. -/
def ActOk (hh vh : Rat) (w : W) : Act → Prop
  | .ev e b => (∀ r, evRead e = some r → r.arm = true → MorphTween.armed hh b vh = true ∧ w.bEval ≤ b + lead vh) ∧
      (∀ n, e = .tick n → w.clock ≤ n)
  | .refresh _ _ => True

theorem inv'_init (vh y b : Rat) :
    Inv' vh ⟨init y, false, false, b, 0⟩ := by
  refine ⟨inv_init y, ?_, ?_⟩
  · intro _ hp; simp [init, MorphTween.rest] at hp
  · intro ha
    simp [init, MorphTween.rest, MorphTween.St.isActive, MorphTween.active, MorphTween.activeCut] at ha
    grind

theorem stepW_inv (h : Hooks) (hh vh : Rat) (w : W) (a : Act) (hi : Inv' vh w) (hok : ActOk hh vh w a) :
    Inv' vh (stepW h w a).1 := by
  obtain ⟨i1, i2, i3⟩ := hi
  cases a with
  | refresh near b =>
    simp only [stepW]
    refine ⟨i1, i2, ?_⟩
    intro ha
    simp [W.blocks, blocking, ha]
  | ev e b =>
    obtain ⟨hgeo, hclk⟩ := hok
    simp only [stepW]
    by_cases hq : (evGated e && !w.listens) = true
    · simp only [hq]; exact ⟨i1, i2, i3⟩
    · simp only [hq]
      have hl : evGated e = true → w.listens = true := by
        intro hg
        cases hw : w.listens
        · simp [hg, hw] at hq
        · rfl
      have hblk : ∀ w' : W, w'.near = w.near → w'.actR = w.actR → w'.bEval = w.bEval → w'.blocks vh = w.blocks vh := by
        intro w' a1 a2 a3; simp [W.blocks, a1, a2, a3]
      refine ⟨inv_step h w.s e i1, ?_, ?_⟩
      · rcases step_tw h w.s e with h1 | ⟨r, hr, -, g, h3⟩ | ⟨n, hn, hp, h4⟩
        · show Settled (evClock w e) (step h w.s e).1.tw
          rw [h1]
          cases e with
          | tick n => exact settled_mono i2 (hclk n rfl)
          | _ => exact i2
        · show Settled (evClock w e) (step h w.s e).1.tw
          have : evClock w e = w.clock := by cases e <;> simp_all [evRead, evClock]
          rw [this, h3]; exact settled_push _ _ _ _ _ i2
        · subst hn
          show Settled (evClock w (.tick n)) (step h w.s (.tick n)).1.tw
          rw [h4]; exact settled_frame _ _ i1.2.1
      · intro hact
        replace hact : (step h w.s e).1.tw.isActive = true := hact
        show (W.blocks vh { w with s := (step h w.s e).1, clock := evClock w e }) = true
        have hb2 : W.blocks vh { w with s := (step h w.s e).1, clock := evClock w e } = W.blocks vh w := by
          simp [W.blocks]
        rw [hb2]
        rcases step_tw h w.s e with h1 | ⟨r, hr, hor, g, h3⟩ | ⟨n, hn, hp, h4⟩
        · rw [h1] at hact; exact i3 hact
        · rcases hor with hor | hor
          · exact i3 hor
          · obtain ⟨hA, hlag⟩ := hgeo r hr hor
            exact arm_blocks vh w (hl (read_gated e r hr)) hA hlag
        · subst hn
          rw [h4] at hact
          apply i3
          cases hx : w.s.tw.isActive
          · have := i2 hx hp n (hclk n rfl)
            rw [this] at hact; exact absurd hact (by simp)
          · rfl

theorem stepW_honored (h : Hooks) (hh vh : Rat) (w : W) (a : Act) (hi : Inv' vh w) (hok : ActOk hh vh w a)
    (o : Out) (ho : (stepW h w a).2 = some o) : honorOut (w.blocks vh) o = o := by
  obtain ⟨i1, i2, i3⟩ := hi
  cases a with
  | refresh near b => simp [stepW] at ho
  | ev e b =>
    obtain ⟨hgeo, hclk⟩ := hok
    simp only [stepW] at ho
    by_cases hq : (evGated e && !w.listens) = true
    · simp [hq] at ho
    · simp [hq] at ho
      subst ho
      have hl : evGated e = true → w.listens = true := by
        intro hg
        cases hw : w.listens
        · simp [hg, hw] at hq
        · rfl
      apply honorOut_of
      intro hp
      rcases prevent_needs h w.s e hp with ha | ⟨r, hr, ha⟩
      · exact i3 ha
      · obtain ⟨hA, hlag⟩ := hgeo r hr ha
        exact arm_blocks vh w (hl (read_gated e r hr)) hA hlag

/-- The premises hold along the whole run. -/
def AllOk (h : Hooks) (hh vh : Rat) : W → List Act → Prop
  | _, [] => True
  | w, a :: t => ActOk hh vh w a ∧ AllOk h hh vh (stepW h w a).1 t

/-- **Same behaviour.** Along any run whose premises hold, the outputs with the listeners passive outside the band equal the
faithful outputs: every `preventDefault` the original would call is honored. -/
theorem late_same (h : Hooks) (hh vh : Rat) (t : List Act) :
    ∀ w : W, Inv' vh w → AllOk h hh vh w t → outsL h vh w t = outsW h w t := by
  induction t with
  | nil => intro w _ _; rfl
  | cons a t ih =>
    intro w hi hok
    obtain ⟨h1, h2⟩ := hok
    simp only [outsL, outsW]
    congr 1
    · cases ho : (stepW h w a).2 with
      | none => rfl
      | some o => simp [stepW_honored h hh vh w a hi h1 o ho]
    · exact ih _ (stepW_inv h hh vh w a hi h1) h2

theorem late_same_cfg (c : Cfg) (hh vh : Rat) (t : List Act) (w : W) (hi : Inv' vh w) (hok : AllOk c.hooks hh vh w t) :
    c ∈ Cfg.all ∧ outsL c.hooks vh w t = outsW c.hooks w t :=
  ⟨mem_all c, late_same c.hooks hh vh t w hi hok⟩

/-- Outside the band, with no non-passive listener from an earlier refresh, the morph is idle: the lock has nothing to
decide. -/
theorem out_of_band_idle (vh : Rat) (w : W) (hi : Inv' vh w) (hb : inBand vh w.bEval = false) (ha : w.actR = false) :
    w.s.tw.isActive = false := by
  obtain ⟨-, -, i3⟩ := hi
  cases hx : w.s.tw.isActive
  · rfl
  · have := i3 hx
    simp [W.blocks, blocking, hb, ha] at this

/-- No refresh outside the band, with the morph idle, leaves a non-passive listener. -/
theorem refresh_out_of_band (h : Hooks) (w : W) (near : Bool) (b vh : Rat) (hb : inBand vh b = false)
    (hidle : w.s.tw.isActive = false) :
    mode (stepW h w (.refresh near b)).1.near (inBand vh (stepW h w (.refresh near b)).1.bEval)
      (stepW h w (.refresh near b)).1.actR ≠ .blocking := by
  simp only [stepW, hb, hidle]
  exact no_blocking_out_of_band near false rfl

/-! ## Registering the listeners -/

inductive Ty where
  | wheel | touchmove
  deriving DecidableEq, Repr

/-- A listener registry: the passive `touchstart`, and each of `wheel`, `touchmove` as absent or with its passive flag. -/
structure Reg where
  start : Bool
  wheel : Option Bool
  move : Option Bool
  deriving DecidableEq, Repr

inductive Op where
  | addStart | rmStart
  | add (t : Ty) (passive : Bool)
  | rm (t : Ty)
  deriving DecidableEq, Repr

def Op.apply (r : Reg) : Op → Reg
  | .addStart => { r with start := true }
  | .rmStart => { r with start := false }
  | .add .wheel p => { r with wheel := some p }
  | .add .touchmove p => { r with move := some p }
  | .rm .wheel => { r with wheel := none }
  | .rm .touchmove => { r with move := none }

def Reg.ofMode : Mode → Reg
  | .none => ⟨false, none, none⟩
  | .passive => ⟨true, some true, some true⟩
  | .blocking => ⟨true, some false, some false⟩

/-- The registry changes that take the registry of `cur` to that of `nxt`. -/
def ops (cur nxt : Mode) : List Op :=
  if cur = nxt then []
  else
    (if cur = .none then [] else [.rm .wheel, .rm .touchmove]) ++
    (if cur = .none then [.addStart] else if nxt = .none then [.rmStart] else []) ++
    (if nxt = .none then [] else [.add .wheel (nxt == .passive), .add .touchmove (nxt == .passive)])

theorem ops_idem (m : Mode) : ops m m = [] := by simp [ops]

/-- Applying `ops cur nxt` to the registry of `cur` gives the registry of `nxt`, for every pair of modes. -/
theorem ops_reach (cur nxt : Mode) : (ops cur nxt).foldl Op.apply (Reg.ofMode cur) = Reg.ofMode nxt := by
  cases cur <;> cases nxt <;> decide

/-- Same listeners: `arm-late` registers a `wheel` and a `touchmove` exactly when the original does. -/
theorem same_listeners (near band act : Bool) :
    (Reg.ofMode (mode near band act)).wheel.isSome = attached near act := by
  cases near <;> cases band <;> cases act <;> decide

end Fw.Parts.MorphMountArmLate
