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

structure Tick where
  media : Option Bool
  body : Option Ev

def Tick.skips (t : Tick) (st : St) : Bool :=
  match t.body with
  | some e => e.gate && (e.frame st).more
  | none => false

def Tick.pre (t : Tick) (st : St) : St :=
  match t.media with
  | some g => stepC g st
  | none => st

def tickV (t : Tick) (st : St) : St :=
  match t.body with
  | some e => stepV e (t.pre st)
  | none => t.pre st

def tickO (t : Tick) (st : St) : St :=
  match t.body with
  | some e => stepO e st
  | none => st

def mV (ts : Nat → Tick) : Nat → St
  | 0 => St.init
  | k + 1 => tickV (ts k) (mV ts k)

def mO (ts : Nat → Tick) : Nat → St
  | 0 => St.init
  | k + 1 => tickO (ts k) (mO ts k)

def Reads (envs : Nat → Env) (ts : Nat → Tick) : Prop :=
  ∀ k, (∀ g, (ts k).media = some g → g = c1000.eval (envs k)) ∧
    (∀ e, (ts k).body = some e → e.gate = c1000.eval (envs k))

def MediaOnFlip (envs : Nat → Env) (ts : Nat → Tick) : Prop :=
  ∀ k, c1000.eval (envs (k + 1)) ≠ c1000.eval (envs k) → (ts (k + 1)).media ≠ none

def BodyAfterSkip (ts : Nat → Tick) : Prop :=
  ∀ k, (ts k).skips (mO ts k) = true → (ts (k + 1)).body ≠ none

def Canon (st : St) : Prop := st.inl = (st.fol.n, max st.fol.n st.fol.r)

theorem canon_init : Canon St.init := by
  have h10 : max (1 : Rat) 0 = 1 := by decide +kernel
  simp [Canon, St.init, pair0, h10]

theorem canon_stepO (e : Ev) (st : St) : Canon (stepO e st) := by
  simp [Canon, stepO, Frame.shrink]

theorem canon_mO (ts : Nat → Tick) (k : Nat) : Canon (mO ts k) := by
  induction k with
  | zero => exact canon_init
  | succ k ih =>
    simp only [mO, tickO]
    split
    · exact canon_stepO _ _
    · exact ih

theorem pre_fol_cls (t : Tick) (st : St) : (t.pre st).fol = st.fol ∧ (t.pre st).cls = st.cls := by
  unfold Tick.pre
  split
  · rename_i g _
    cases g <;> simp [stepC]
  · exact ⟨rfl, rfl⟩

theorem tick_fol_cls (t : Tick) (sV sO : St) (hf : sV.fol = sO.fol) (hc : sV.cls = sO.cls) :
    (tickV t sV).fol = (tickO t sO).fol ∧ (tickV t sV).cls = (tickO t sO).cls := by
  have hp := pre_fol_cls t sV
  simp only [tickV, tickO]
  cases t.body with
  | none => exact ⟨hp.1.trans hf, hp.2.trans hc⟩
  | some e =>
    have hfr : e.frame (t.pre sV) = e.frame sO := by simp [Ev.frame, hp.1, hf]
    simp only [stepV, stepO, hfr]
    split <;> simp

theorem m_fol_cls (ts : Nat → Tick) (k : Nat) :
    (mV ts k).fol = (mO ts k).fol ∧ (mV ts k).cls = (mO ts k).cls := by
  induction k with
  | zero => simp [mV, mO]
  | succ k ih => exact tick_fol_cls (ts k) _ _ ih.1 ih.2

theorem tick_inl_body (t : Tick) (sV sO : St) (e : Ev) (hf : sV.fol = sO.fol) (hb : t.body = some e)
    (hs : t.skips sO = false) : (tickV t sV).inl = (tickO t sO).inl := by
  have hfr : e.frame (t.pre sV) = e.frame sO := by simp [Ev.frame, (pre_fol_cls t sV).1, hf]
  have hs' : (e.gate && (e.frame sO).more) = false := by simpa [Tick.skips, hb] using hs
  simp only [tickV, tickO, hb, stepV, hfr, hs', Bool.false_eq_true, ite_false]
  simp [stepO, hfr]

theorem tick_inl_media_off (t : Tick) (sV sO : St) (hf : sV.fol = sO.fol) (hc : Canon sO)
    (hb : t.body = none) (hm : t.media = some false) : (tickV t sV).inl = (tickO t sO).inl := by
  simp only [tickV, tickO, hb, Tick.pre, hm]
  rw [hc]
  simp [stepC, hf]

theorem tick_inl_keep (t : Tick) (sV sO : St) (hb : t.body = none) (hm : t.media ≠ some false) :
    (tickV t sV).inl = sV.inl ∧ (tickO t sO).inl = sO.inl := by
  refine ⟨?_, by simp [tickO, hb]⟩
  simp only [tickV, hb, Tick.pre]
  cases h : t.media with
  | none => rfl
  | some g =>
    cases g
    · exact absurd h hm
    · rfl

theorem tick_inl_keep_agree (t : Tick) (sV sO : St) (hb : t.body = none) (hm : t.media ≠ some false)
    (h : sV.inl = sO.inl) : (tickV t sV).inl = (tickO t sO).inl := by
  have hk := tick_inl_keep t sV sO hb hm
  rw [hk.1, hk.2, h]

theorem inl_agree_p1 (envs : Nat → Env) (ts : Nat → Tick) (hr : Reads envs ts) (hp : MediaOnFlip envs ts)
    (k : Nat) (hk : c1000.eval (envs k) = false) : (mV ts (k + 1)).inl = (mO ts (k + 1)).inl := by
  induction k with
  | zero =>
    have hf := (m_fol_cls ts 0).1
    show (tickV (ts 0) (mV ts 0)).inl = (tickO (ts 0) (mO ts 0)).inl
    cases hb : (ts 0).body with
    | some e =>
      have hg : e.gate = false := by rw [(hr 0).2 e hb, hk]
      exact tick_inl_body (ts 0) _ _ e hf hb (by simp [Tick.skips, hb, hg])
    | none =>
      cases hm : (ts 0).media with
      | some g =>
        have hg : g = false := by rw [(hr 0).1 g hm, hk]
        subst hg
        exact tick_inl_media_off (ts 0) _ _ hf (canon_mO ts 0) hb hm
      | none => exact tick_inl_keep_agree (ts 0) _ _ hb (by simp [hm]) rfl
  | succ k ih =>
    have hf := (m_fol_cls ts (k + 1)).1
    show (tickV (ts (k + 1)) (mV ts (k + 1))).inl = (tickO (ts (k + 1)) (mO ts (k + 1))).inl
    cases hb : (ts (k + 1)).body with
    | some e =>
      have hg : e.gate = false := by rw [(hr (k + 1)).2 e hb, hk]
      exact tick_inl_body (ts (k + 1)) _ _ e hf hb (by simp [Tick.skips, hb, hg])
    | none =>
      cases hm : (ts (k + 1)).media with
      | some g =>
        have hg : g = false := by rw [(hr (k + 1)).1 g hm, hk]
        subst hg
        exact tick_inl_media_off (ts (k + 1)) _ _ hf (canon_mO ts (k + 1)) hb hm
      | none =>
        have hsame : c1000.eval (envs k) = false := by
          cases hc : c1000.eval (envs k)
          · rfl
          · exact absurd hm (hp k (by rw [hk, hc]; decide))
        exact tick_inl_keep_agree (ts (k + 1)) _ _ hb (by simp [hm]) (ih hsame)

theorem inl_agree_p2 (ts : Nat → Tick) (hb : BodyAfterSkip ts) (k : Nat)
    (hs : (ts k).skips (mO ts k) = false) : (mV ts (k + 1)).inl = (mO ts (k + 1)).inl := by
  induction k with
  | zero =>
    have hf := (m_fol_cls ts 0).1
    show (tickV (ts 0) (mV ts 0)).inl = (tickO (ts 0) (mO ts 0)).inl
    cases hbd : (ts 0).body with
    | some e => exact tick_inl_body (ts 0) _ _ e hf hbd hs
    | none =>
      cases hm : (ts 0).media with
      | some g =>
        cases g
        · exact tick_inl_media_off (ts 0) _ _ hf (canon_mO ts 0) hbd hm
        · exact tick_inl_keep_agree (ts 0) _ _ hbd (by simp [hm]) rfl
      | none => exact tick_inl_keep_agree (ts 0) _ _ hbd (by simp [hm]) rfl
  | succ k ih =>
    have hf := (m_fol_cls ts (k + 1)).1
    show (tickV (ts (k + 1)) (mV ts (k + 1))).inl = (tickO (ts (k + 1)) (mO ts (k + 1))).inl
    cases hbd : (ts (k + 1)).body with
    | some e => exact tick_inl_body (ts (k + 1)) _ _ e hf hbd hs
    | none =>
      have hprev : (ts k).skips (mO ts k) = false := by
        cases hp : (ts k).skips (mO ts k)
        · rfl
        · exact absurd hbd (hb k hp)
      cases hm : (ts (k + 1)).media with
      | some g =>
        cases g
        · exact tick_inl_media_off (ts (k + 1)) _ _ hf (canon_mO ts (k + 1)) hbd hm
        · exact tick_inl_keep_agree (ts (k + 1)) _ _ hbd (by simp [hm]) (ih hprev)
      | none => exact tick_inl_keep_agree (ts (k + 1)) _ _ hbd (by simp [hm]) (ih hprev)

theorem skip_gated (envs : Nat → Env) (ts : Nat → Tick) (hr : Reads envs ts) (k : Nat)
    (hs : (ts k).skips (mO ts k) = true) : c1000.eval (envs k) = true := by
  cases hb : (ts k).body with
  | none => simp [Tick.skips, hb] at hs
  | some e =>
    have hg : e.gate = true := by
      simp only [Tick.skips, hb, Bool.and_eq_true] at hs
      exact hs.1
    rw [← (hr k).2 e hb, hg]

theorem look_agree_p1 (envs : Nat → Env) (ts : Nat → Tick) (hr : Reads envs ts) (hp : MediaOnFlip envs ts)
    (k : Nat) : look (envs k) (mV ts (k + 1)).inl = look (envs k) (mO ts (k + 1)).inl := by
  cases hc : c1000.eval (envs k)
  · rw [inl_agree_p1 envs ts hr hp k hc]
  · rw [look_gated _ _ hc, look_gated _ _ hc]

theorem look_agree_p2 (envs : Nat → Env) (ts : Nat → Tick) (hr : Reads envs ts) (hb : BodyAfterSkip ts)
    (k : Nat) : look (envs k) (mV ts (k + 1)).inl = look (envs k) (mO ts (k + 1)).inl := by
  cases hs : (ts k).skips (mO ts k)
  · rw [inl_agree_p2 ts hb k hs]
  · have hc := skip_gated envs ts hr k hs
    rw [look_gated _ _ hc, look_gated _ _ hc]

theorem look_agree_merged (envs : Nat → Env) (ts : Nat → Tick) (hr : Reads envs ts)
    (h : MediaOnFlip envs ts ∨ BodyAfterSkip ts) (k : Nat) :
    look (envs k) (mV ts (k + 1)).inl = look (envs k) (mO ts (k + 1)).inl := by
  rcases h with hp | hb
  · exact look_agree_p1 envs ts hr hp k
  · exact look_agree_p2 envs ts hr hb k

theorem commission_visSame_merged (vp : (Nat → Env) → Rect)
    (scn : (Nat → Env) → Nat → Rat × Rat → Bool × Bool → Scene)
    (ts : (Nat → Env) → Nat → Tick) (hr : ∀ envs, Reads envs (ts envs))
    (h : ∀ envs, MediaOnFlip envs (ts envs) ∨ BodyAfterSkip (ts envs)) :
    VisSame E vp
      (fun envs k => scn envs k (look (envs k) (mO (ts envs) (k + 1)).inl) (mO (ts envs) (k + 1)).cls)
      (fun envs k => scn envs k (look (envs k) (mV (ts envs) (k + 1)).inl) (mV (ts envs) (k + 1)).cls) := by
  apply visSame_of_eq
  intro envs k
  rw [look_agree_merged envs (ts envs) (hr envs) (h envs) k, (m_fol_cls (ts envs) (k + 1)).2]

def exTick (m : Option Bool) (b : Option (Bool × Rat)) : Tick :=
  ⟨m, b.map fun (g, bot) => ⟨g, false, 0, bot, 1000⟩⟩

def exRun (ts : List Tick) (n : Nat) : (Rat × Rat) × (Rat × Rat) :=
  let f : Nat → Tick := fun k => ts.getD k ⟨none, none⟩
  ((mV f n).inl, (mO f n).inl)

#guard (exTick none (some (true, 600))).skips St.init
#guard !(exTick none (some (false, 600))).skips St.init
#guard !(exTick (some false) none).skips St.init
#guard (exRun [exTick none (some (true, 850)), exTick none (some (true, 600))] 2).1 == (1, 1)
#guard (exRun [exTick none (some (true, 850)), exTick none (some (true, 600))] 2).2 != (1, 1)
#guard let r := exRun [exTick none (some (true, 850)), exTick none (some (true, 600)), exTick (some false) none] 3
  r.1 == r.2
#guard let r := exRun [exTick none (some (true, 850)), exTick none (some (true, 600)),
  exTick none (some (false, 600))] 3
  r.1 == r.2
#guard let r := exRun [exTick none (some (true, 850)), exTick none (some (true, 600)), exTick none none] 3
  r.1 != r.2

end Fw.Parts.CommissionOpt
