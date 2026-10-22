import Fw.Engine.Visual
import Fw.Site.BreakpointMatrix
import Fw.Parts.Commission
import Fw.Parts.PeopleCardOpt
/-!
commission:band-gate: skip the two custom-property writes where the CSS pins the card.
Proof note: `research/notes/2026/10-2x-commission-band-gate.md`.
-/
namespace Fw.Parts.CommissionOpt

open Fw.Engine Fw.Site.Breakpoints Fw.Parts.Commission
open Fw.Parts.PeopleCardOpt (cascade always)

def scaleDecls (w : Rat) : List (MQ × Rat) := [(always, 1 - depth * w), (c1000, 1)]

def radiusDecls (w : Rat) : List (MQ × Rat) := [(always, radius * w), (c1000, 0)]

def look (env : Env) (p : Rat × Rat) : Rat × Rat :=
  (cascade env (scaleDecls (max p.1 p.2)) 1, cascade env (radiusDecls (max p.1 p.2)) 0)

#guard look (exEnv 430 430) (1, 1) == (1, 0)
#guard look (exEnv 1280 1280) (1, 1) == (916667/1000000, 32)
#guard look (exEnv 1000 1000) (1, 1) == (1, 0) && look (exEnv 1001 1001 .none .coarse) (1, 0) == (1, 0)
#guard look (exEnv 1001 1001) (1, 1) == (916667/1000000, 32)
#guard look (exEnv 1280 400) (1, 1) == (1, 0)

theorem look_gated (env : Env) (p : Rat × Rat) (h : c1000.eval env = true) : look env p = (1, 0) := by
  simp [look, cascade, scaleDecls, radiusDecls, h]

theorem look_ungated (env : Env) (p : Rat × Rat) (h : c1000.eval env = false) :
    look env p = (1 - depth * max p.1 p.2, radius * max p.1 p.2) := by
  have ha : always.eval env = true := rfl
  simp [look, cascade, scaleDecls, radiusDecls, h, ha]

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

structure Ev where
  gate : Bool
  rm : Bool
  top : Rat
  bottom : Rat
  vh : Rat

structure St where
  fol : Pair
  inl : Rat × Rat
  writes : Nat
  cls : Bool × Bool
deriving Repr, DecidableEq

def St.init : St := ⟨pair0, (1, 1), 0, (false, false)⟩

def Ev.frame (e : Ev) (st : St) : Frame := Fw.Parts.Commission.frame st.fol e.top e.bottom e.vh e.rm e.gate

def stepO (e : Ev) (st : St) : St :=
  let f := e.frame st
  ⟨⟨f.n, f.r⟩, (f.n, f.shrink), st.writes + 2, (f.entering, f.shrinking)⟩

def stepV (e : Ev) (st : St) : St :=
  if e.gate && (e.frame st).more then
    let f := e.frame st
    { st with fol := ⟨f.n, f.r⟩, cls := (f.entering, f.shrinking) }
  else stepO e st

def stepC (g : Bool) (st : St) : St :=
  if g then st else { st with inl := (st.fol.n, max st.fol.n st.fol.r), writes := st.writes + 2 }

def stO (ev : Nat → Ev) : Nat → St
  | 0 => St.init
  | k + 1 => stepO (ev k) (stO ev k)

def stV (ev : Nat → Ev) : Nat → St
  | 0 => St.init
  | k + 1 => stepV (ev k) (stV ev k)

theorem fol_cls_agree (ev : Nat → Ev) (k : Nat) :
    (stV ev k).fol = (stO ev k).fol ∧ (stV ev k).cls = (stO ev k).cls := by
  induction k with
  | zero => simp [stV, stO]
  | succ k ih =>
    have hf : (ev k).frame (stV ev k) = (ev k).frame (stO ev k) := by
      simp [Ev.frame, ih.1]
    simp only [stV, stO, stepV, stepO, hf]
    split <;> simp

theorem frame_agree (ev : Nat → Ev) (k : Nat) : (ev k).frame (stV ev k) = (ev k).frame (stO ev k) := by
  simp [Ev.frame, (fol_cls_agree ev k).1]

theorem inl_written (ev : Nat → Ev) (k : Nat) (h : ¬ ((ev k).gate = true ∧ ((ev k).frame (stO ev k)).more = true)) :
    (stV ev (k + 1)).inl = (stO ev (k + 1)).inl := by
  have hf := frame_agree ev k
  have hc : ((ev k).gate && ((ev k).frame (stO ev k)).more) = false := by
    cases hg : (ev k).gate <;> cases hm : ((ev k).frame (stO ev k)).more <;> simp_all
  simp [stV, stO, stepV, stepO, hf, hc]

theorem inl_ungated (ev : Nat → Ev) (k : Nat) (h : (ev k).gate = false) :
    (stV ev (k + 1)).inl = (stO ev (k + 1)).inl :=
  inl_written ev k (by simp [h])

theorem inl_settled (ev : Nat → Ev) (k : Nat) (h : ((ev k).frame (stO ev k)).more = false) :
    (stV ev (k + 1)).inl = (stO ev (k + 1)).inl :=
  inl_written ev k (by simp [h])

theorem exit_catchup (ev : Nat → Ev) (k : Nat) (h : (ev k).gate = false) :
    (stV ev (k + 1)).inl = (((ev k).frame (stO ev k)).n, ((ev k).frame (stO ev k)).shrink) := by
  rw [inl_ungated ev k h]
  simp [stO, stepO]

theorem inl_orig (ev : Nat → Ev) (k : Nat) :
    (stO ev k).inl = ((stO ev k).fol.n, max (stO ev k).fol.n (stO ev k).fol.r) := by
  cases k with
  | zero =>
    have h10 : max (1 : Rat) 0 = 1 := by decide +kernel
    simp [stO, St.init, pair0, h10]
  | succ k => simp [stO, stepO, Frame.shrink]

theorem media_catchup (ev : Nat → Ev) (k : Nat) : (stepC false (stV ev k)).inl = (stO ev k).inl := by
  rw [inl_orig ev k]
  simp [stepC, (fol_cls_agree ev k).1]

theorem look_agree (envs : Nat → Env) (ev : Nat → Ev) (hg : ∀ k, (ev k).gate = c1000.eval (envs k)) (k : Nat) :
    look (envs k) (stV ev (k + 1)).inl = look (envs k) (stO ev (k + 1)).inl := by
  have h := hg k
  cases hc : c1000.eval (envs k)
  · rw [inl_ungated ev k (by rw [h, hc])]
  · rw [look_gated _ _ hc, look_gated _ _ hc]

theorem media_look_agree (env : Env) (ev : Nat → Ev) (k : Nat) :
    look env (stepC (c1000.eval env) (stV ev k)).inl = look env (stO ev k).inl := by
  cases hc : c1000.eval env
  · rw [media_catchup ev k]
  · rw [look_gated _ _ hc, look_gated _ _ hc]

theorem commission_visSame (vp : (Nat → Env) → Rect)
    (scn : (Nat → Env) → Nat → Rat × Rat → Bool × Bool → Scene)
    (ev : (Nat → Env) → Nat → Ev) (hg : ∀ envs k, (ev envs k).gate = c1000.eval (envs k)) :
    VisSame E vp
      (fun envs k => scn envs k (look (envs k) (stO (ev envs) (k + 1)).inl) (stO (ev envs) (k + 1)).cls)
      (fun envs k => scn envs k (look (envs k) (stV (ev envs) (k + 1)).inl) (stV (ev envs) (k + 1)).cls) := by
  apply visSame_of_eq
  intro envs k
  rw [look_agree envs (ev envs) (hg envs) k, (fol_cls_agree (ev envs) (k + 1)).2]

theorem writes_orig (ev : Nat → Ev) (k : Nat) : (stO ev k).writes = 2 * k := by
  induction k with
  | zero => simp [stO, St.init]
  | succ k ih => simp [stO, stepO, ih]; omega

theorem writes_step (ev : Nat → Ev) (k : Nat) :
    (stV ev (k + 1)).writes =
      (stV ev k).writes + (if (ev k).gate = true ∧ ((ev k).frame (stO ev k)).more = true then 0 else 2) := by
  have hf := frame_agree ev k
  simp only [stV, stepV, hf]
  split <;> simp_all [stepO]

theorem writes_le (ev : Nat → Ev) (k : Nat) : (stV ev k).writes ≤ (stO ev k).writes := by
  induction k with
  | zero => simp [stV, stO]
  | succ k ih =>
    rw [writes_step]
    have := writes_orig ev (k + 1)
    have := writes_orig ev k
    split <;> omega

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

theorem moving_run_lt (ev : Nat → Ev) (k : Nat) (hk : 0 < k)
    (h : ∀ j, j < k → (ev j).gate = true ∧ ((ev j).frame (stO ev j)).more = true) :
    (stV ev k).writes < (stO ev k).writes := by
  rw [(moving_run ev k h).1, writes_orig]; omega

def writeNow (gate more : Bool) : Bool := !(gate && more)

def catchupNow (gate : Bool) : Bool := !gate

#guard writeNow false true && writeNow false false && writeNow true false && !writeNow true true
#guard catchupNow false && !catchupNow true

theorem stepV_writes (e : Ev) (st : St) :
    (stepV e st).writes = st.writes + (if writeNow e.gate (e.frame st).more then 2 else 0) := by
  cases hg : e.gate <;> cases hm : (e.frame st).more <;> simp [stepV, stepO, writeNow, hg, hm]

theorem stepC_writes (g : Bool) (st : St) :
    (stepC g st).writes = st.writes + (if catchupNow g then 2 else 0) := by
  cases g <;> simp [stepC, catchupNow]

end Fw.Parts.CommissionOpt
