import Fw.Parts.MorphTween
import Fw.Parts.MorphGeomVerify
/-! Lifecycle of the `geom-timed` flip tracks: prewarmed (held at progress 0) versus created on the push. -/
namespace Fw.Parts.MorphGeomPrewarm
open Fw.Parts.MorphTween

structure St where
  live : Option (Rat × Rat)
  tree : Bool
  base : Rat
  held : Bool
  deriving DecidableEq, Repr

structure Act where
  creates : Nat
  enters : Nat
  leaves : Nat
  deriving DecidableEq, Repr

inductive Ev where
  | warm
  | cool
  | push (f t : Rat) (allowed stale : Bool)
  | settle (m : Rat)
  | dispose
  deriving DecidableEq, Repr

def clean : St := ⟨none, false, 0, false⟩

def Act.add (a b : Act) : Act := ⟨a.creates + b.creates, a.enters + b.enters, a.leaves + b.leaves⟩

/-- The driver of the landed `geom-timed` flip: every push builds its tracks, every settle or dispose drops them. -/
def refStep (n : Nat) (s : St) : Ev → St × Act
  | .warm => (s, ⟨0, 0, 0⟩)
  | .cool => (s, ⟨0, 0, 0⟩)
  | .push f t a _ =>
    if s.live = none ∧ s.tree = false ∧ a = false then (s, ⟨0, 0, 0⟩)
    else ({ s with live := some (f, t), tree := true }, ⟨n, if s.tree then 0 else 1, 0⟩)
  | .settle m =>
    if s.tree = true ∧ 0 < m then ({ s with live := none, base := m }, ⟨0, 0, 0⟩)
    else if s.tree = true then ({ s with live := none, tree := false, base := m }, ⟨0, 0, 1⟩)
    else ({ s with base := m }, ⟨0, 0, 0⟩)
  | .dispose => ({ s with live := none, tree := false }, ⟨0, 0, if s.tree then 1 else 0⟩)

/-- A held set is cancelled and the flip tree restored. -/
def coolSt (s : St) : St := if s.held then { s with live := none, tree := false, held := false } else s

def proj (s : St) : St := coolSt s

def coolAct (s : St) : Act := ⟨0, 0, if s.held then 1 else 0⟩

/-- The prewarm driver: a clean idle page may hold the end-state tracks of the 0 to 1 push at progress 0. -/
def newStep (n : Nat) (s : St) : Ev → St × Act
  | .warm =>
    if s.tree = false ∧ s.live = none ∧ s.base = 0 ∧ s.held = false
    then ({ live := some (0, 1), tree := true, base := 0, held := true }, ⟨n, 1, 0⟩)
    else (s, ⟨0, 0, 0⟩)
  | .cool => (coolSt s, coolAct s)
  | .push f t a stale =>
    if s.held = true ∧ a = true ∧ stale = false then
      if (f, t) = ((0 : Rat), (1 : Rat)) then ({ s with held := false }, ⟨0, 0, 0⟩)
      else ({ s with live := some (f, t), held := false }, ⟨n, 0, 0⟩)
    else
      let r := refStep n (coolSt s) (.push f t a stale)
      (r.1, (coolAct s).add r.2)
  | .settle m =>
    let r := refStep n (coolSt s) (.settle m)
    (r.1, (coolAct s).add r.2)
  | .dispose =>
    let r := refStep n (coolSt s) .dispose
    (r.1, (coolAct s).add r.2)

/-- The tracks held at progress 0 show the tween's start value. -/
def look (s : St) (e : Rat) : Rat :=
  if s.held then (tween 0 1 0).value else
  match s.live with
  | some (f, t) => (tween f t e).value
  | none => s.base

def Inv (s : St) : Prop := s.held = true → s.live = some (0, 1) ∧ s.tree = true ∧ s.base = 0

def runWith (step : St → Ev → St × Act) : St → List Ev → St
  | s, [] => s
  | s, e :: es => runWith step (step s e).1 es

def runN (n : Nat) := runWith (newStep n)
def runR (n : Nat) := runWith (refStep n)

theorem clean_inv : Inv clean := by simp [Inv, clean]

theorem coolSt_inv (s : St) : Inv (coolSt s) := by
  unfold coolSt Inv
  split <;> simp_all

theorem coolSt_idem (s : St) : coolSt (coolSt s) = coolSt s := by
  unfold coolSt
  split <;> simp_all

theorem proj_nh (x : St) (hx : x.held = false) : proj x = x := by simp [proj, coolSt, hx]

theorem coolSt_clean (s : St) (h : Inv s) : coolSt s = clean ∨ s.held = false := by
  unfold coolSt
  by_cases hh : s.held = true
  · left; obtain ⟨a, b, c⟩ := h hh; simp [hh, clean, c]
  · right; simpa using hh

theorem refStep_held (n : Nat) (s : St) (ev : Ev) (h : s.held = false) : (refStep n s ev).1.held = false := by
  cases ev <;> simp only [refStep] <;> (repeat' split) <;> simp_all

theorem newStep_inv (n : Nat) (s : St) (ev : Ev) (h : Inv s) : Inv (newStep n s ev).1 := by
  have hc := coolSt_inv s
  have hr : ∀ e, Inv (refStep n (coolSt s) e).1 := by
    intro e
    have : (coolSt s).held = false := by unfold coolSt; split <;> simp_all
    exact fun hh => by simp [refStep_held n _ e this] at hh
  cases ev with
  | warm => simp only [newStep]; split <;> simp_all [Inv]
  | cool => exact hc
  | push f t a st =>
    simp only [newStep]
    split
    · split <;> simp_all [Inv]
    · exact hr _
  | settle m => exact hr _
  | dispose => exact hr _

theorem look_proj (s : St) (e : Rat) (h : Inv s) : look s e = look (proj s) e := by
  unfold proj coolSt look
  by_cases hh : s.held = true
  · obtain ⟨a, _, c⟩ := h hh
    have : (tween 0 1 0).value = 0 := tween_start 0 1 0 (by decide)
    simp [hh, this, c]
  · simp [hh]

/-- One step of the prewarm driver equals one step of the landed driver on the page it would show without the held set. -/
theorem sim_step (n : Nat) (s : St) (ev : Ev) (h : Inv s) :
    proj (newStep n s ev).1 = (refStep n (proj s) ev).1 := by
  have hp : proj s = coolSt s := rfl
  have hnh : ∀ x : St, x.held = false → coolSt x = x := fun x hx => by simp [coolSt, hx]
  have hr : ∀ e, (refStep n (coolSt s) e).1.held = false := by
    intro e
    exact refStep_held n _ e (by unfold coolSt; split <;> simp_all)
  cases ev with
  | warm =>
    simp only [newStep, hp, refStep]
    split
    · rename_i hw
      have : coolSt s = s := hnh s hw.2.2.2
      obtain ⟨a, b, c, d⟩ := hw
      cases s
      simp_all [proj, coolSt]
    · rfl
  | cool => simp [newStep, refStep, proj, coolSt_idem]
  | push f t a st =>
    simp only [newStep, hp]
    split
    · rename_i hw
      have hs : s.live = some (0, 1) ∧ s.tree = true ∧ s.base = 0 := h hw.1
      split
      · rename_i hk
        simp only [Prod.mk.injEq] at hk
        obtain ⟨hf, ht⟩ := hk
        subst hf; subst ht
        simp [proj, coolSt, refStep, hw, hs]
      · simp [proj, coolSt, refStep, hw, hs]
    · simp [proj_nh _ (hr _)]
  | settle m => simp [newStep, hp, proj_nh _ (hr _)]
  | dispose => simp [newStep, hp, proj_nh _ (hr _)]

theorem run_sim (n : Nat) (t : List Ev) : ∀ s, Inv s → proj (runN n s t) = runR n (proj s) t := by
  induction t with
  | nil => intro s _; rfl
  | cons ev es ih =>
    intro s h
    simp only [runN, runR, runWith]
    have := ih (newStep n s ev).1 (newStep_inv n s ev h)
    rw [sim_step n s ev h] at this
    exact this

/-- Same look: from a clean page, after any events, the prewarm driver shows the same value at every tween time as the landed driver. -/
theorem same_look (n : Nat) (t : List Ev) (e : Rat) : look (runN n clean t) e = look (runR n clean t) e := by
  have hi : ∀ s, Inv s → ∀ t, Inv (runN n s t) := by
    intro s h t
    induction t generalizing s with
    | nil => exact h
    | cons ev es ih => exact ih _ (newStep_inv n s ev h)
  have h1 := hi clean clean_inv t
  have h2 := run_sim n t clean clean_inv
  have h3 : proj clean = clean := by simp [proj, coolSt, clean]
  rw [h3] at h2
  have hr : (runR n clean t).held = false := by
    have : ∀ s : St, s.held = false → ∀ t, (runR n s t).held = false := by
      intro s hs t
      induction t generalizing s with
      | nil => exact hs
      | cons ev es ih => exact ih _ (refStep_held n s ev hs)
    exact this clean rfl t
  rw [look_proj _ e h1, h2]

/-- A push of the prewarmed 0 to 1 flip creates no track and enters no tree. -/
theorem held_push_no_create (n : Nat) (s : St) (h : s.held = true) :
    (newStep n s (.push 0 1 true false)).2 = ⟨0, 0, 0⟩ := by
  simp [newStep, h]

/-- After a warm of a clean page, the next 0 to 1 push creates nothing. -/
theorem warm_then_push (n : Nat) :
    (newStep n (newStep n clean .warm).1 (.push 0 1 true false)).2 = ⟨0, 0, 0⟩ := by
  apply held_push_no_create
  simp [newStep, clean]

/-- A stale layout or a refused push falls back to the landed path: the held set is cancelled first. -/
theorem held_stale_falls_back (n : Nat) (s : St) (h : s.held = true) (f t : Rat) (a : Bool) :
    (newStep n s (.push f t a true)).1 = (refStep n (coolSt s) (.push f t a true)).1 := by
  simp [newStep, h]

theorem held_refused_leaves (n : Nat) (s : St) (h : s.held = true) (f t : Rat) :
    (newStep n s (.push f t false false)).1 = (refStep n (coolSt s) (.push f t false false)).1 := by
  simp [newStep, h]

/-- Every way out of a held set ends at the base page. -/
theorem cool_base (s : St) (h : Inv s) : coolSt s = clean ∨ s.held = false := coolSt_clean s h

def Live (s : St) : Prop := s.tree = false → s.live = none

theorem clean_live : Live clean := by simp [Live, clean]

theorem newStep_live (n : Nat) (s : St) (ev : Ev) (h : Inv s) (hl : Live s) : Live (newStep n s ev).1 := by
  have hc : Live (coolSt s) := by
    unfold coolSt Live; split <;> simp_all [Live]
  have hr : ∀ x : St, Live x → ∀ e, Live (refStep n x e).1 := by
    intro x hx e
    cases e <;> simp only [refStep] <;> (repeat' split) <;> simp_all [Live]
  cases ev with
  | warm => simp only [newStep]; split <;> simp_all [Live]
  | cool => exact hc
  | push f t a st =>
    simp only [newStep]
    split
    · rename_i hw
      have := (h hw.1).2.1
      split <;> simp_all [Live]
    · exact hr _ hc _
  | settle m => exact hr _ hc _
  | dispose => exact hr _ hc _

theorem settle_zero_base (n : Nat) (s : St) (hl : Live s) :
    let s' := (newStep n s (.settle 0)).1
    s'.live = none ∧ s'.tree = false ∧ s'.held = false ∧ s'.base = 0 := by
  have hh : (coolSt s).held = false := by unfold coolSt; split <;> simp_all
  have h00 : ¬ ((0 : Rat) < 0) := by decide
  have hl2 : Live (coolSt s) := by
    unfold coolSt Live; split <;> simp_all [Live]
  simp only [newStep, refStep, h00, and_false, ite_false]
  split <;> simp_all [Live]

theorem dispose_base (n : Nat) (s : St) :
    let s' := (newStep n s .dispose).1
    s'.live = none ∧ s'.tree = false ∧ s'.held = false := by
  have hh : (coolSt s).held = false := by unfold coolSt; split <;> simp_all
  simp only [newStep, refStep]
  simp_all

/-- Without a warm event the prewarm driver is the landed driver. -/
theorem no_warm_same (n : Nat) (t : List Ev) (h : ∀ x ∈ t, x ≠ Ev.warm) :
    ∀ s : St, s.held = false → runN n s t = runR n s t := by
  induction t with
  | nil => intro s _; rfl
  | cons ev es ih =>
    intro s hs
    have hev : ev ≠ .warm := h ev (by simp)
    have hes : ∀ x ∈ es, x ≠ Ev.warm := fun x hx => h x (by simp [hx])
    have hc : coolSt s = s := by simp [coolSt, hs]
    have hstep : (newStep n s ev).1 = (refStep n s ev).1 := by
      cases ev with
      | warm => exact absurd rfl hev
      | cool => simp [newStep, refStep, hc]
      | push f t a st => simp [newStep, hs, hc]
      | settle m => simp [newStep, hc]
      | dispose => simp [newStep, hc]
    simp only [runN, runR, runWith]
    rw [hstep]
    exact ih hes _ (refStep_held n s ev hs)

/-- The delay from the end of a flip back to 0 until the tree is entered and the tracks are held again. -/
def rewarmMs : Nat := 1000

/-- The flip tree stays out for the whole quiet-leave window (A4) before a rewarm. -/
theorem rewarm_after_quiet_window : Fw.Parts.MorphGeom.verifyWindowMs < rewarmMs := by decide

end Fw.Parts.MorphGeomPrewarm
