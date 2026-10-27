import Fw.Parts.MorphGeomEarn
import Fw.Engine.ResourceFlags
/-! `morph.geom:on`: the flip layers, their Web Animations, the WebKit acceleration rules they meet, end states and
the backing bytes they add. -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav Fw.Parts.MorphTween Fw.Engine.TransitionStart
open Fw.Parts.NavEarnOpt (frameMs frames)

/-- Animated properties: the accelerated set of `GraphicsLayerCA.cpp:1183-1215@862f17d`, nothing else. -/
inductive AnimProp where
  | translate | scale | transformList | opacity | blur | backdropBlur
  deriving DecidableEq, Repr

def AnimProp.css : AnimProp → String
  | .translate => "translate" | .scale => "scale" | .transformList => "transform" | .opacity => "opacity"
  | .blur => "filter" | .backdropBlur => "backdrop-filter"

def AnimProp.arity : AnimProp → Nat
  | .translate => 2 | .scale => 2 | .transformList => 4 | .opacity => 1 | .blur => 1 | .backdropBlur => 1

inductive Easing where
  | linear
  | cubic (x1 y1 x2 y2 : Rat)
  deriving DecidableEq, Repr

inductive Composite where
  | replace | add | accumulate
  deriving DecidableEq, Repr

inductive PlayDir where
  | normal | reverse | alternate
  deriving DecidableEq, Repr

inductive Ks where
  | grid | unit | earn | panel | fade | time
  deriving DecidableEq, Repr

def Ks.list (v : Vp) : Ks → List Rat
  | .grid => knots v | .unit => [0, 1] | .earn => earnKnots | .panel => panelKnots | .fade => fadeKnots
  | .time => gridFrom 0 frameMs frames

def timeEnd : Rat := (frames : Rat) * frameMs

def Ks.offsets (v : Vp) (k : Ks) : List Rat := if k = .time then (k.list v).map (· / timeEnd) else k.list v

structure Anim where
  el : String
  key : Nat × Nat
  prop : AnimProp
  ks : Ks
  fns : List (Rat → Rat)
  kfEasing : Easing
  easing : Easing
  composite : Composite
  rate : Rat
  dir : PlayDir

def anim (el : String) (prop : AnimProp) (ks : Ks) (fns : List (Rat → Rat)) (key : Nat × Nat := (0, 0)) : Anim :=
  ⟨el, key, prop, ks, fns, .linear, .linear, .replace, 1, .normal⟩

def Anim.tracks (v : Vp) (a : Anim) : List Track := a.fns.map fun f => MorphGeom.mk f (a.ks.list v)

structure Ctx where
  eng : Eng
  a : Rat
  b : Rat
  inset : Rat
  logoW : Rat
  logoH : Rat
  langW : Rat
  lw : Rat
  w0 : Rat
  gL : Rat
  centreH : Rat
  footH : Rat
  platH : Rat
  imgs : List (List (Rat × Rat))


structure Lyr where
  name : String
  parent : String
  w : Rat
  h : Rat
  backed : Bool
  deriving Repr

def imgRows (c : Ctx) : List ((Nat × Nat) × Rat × Rat) :=
  (c.imgs.zipIdx).flatMap fun (col, i) => (col.zipIdx).map fun ((y, h), j) => ((i, j), y, h)

-- clippers, counters, solid fills, the panel and directly composited images paint nothing: `RenderLayerBacking.cpp:3509-3535,3687-3690@862f17d`
-- the veil is its own layer: it paints above the backdrop pictures while D paints below them, so it cannot be folded into D
def layers (v : Vp) (c : Ctx) : List Lyr :=
  let W := wp v; let H := hp v
  [⟨"nav", "", W, H, false⟩, ⟨"K0", "nav", 2 * W, 2 * H, false⟩, ⟨"K1", "K0", 2 * W, 2 * H, false⟩,
    ⟨"K2", "K1", 2 * W, 2 * H, false⟩, ⟨"K3", "K2", 2 * W, 2 * H, false⟩, ⟨"U", "K3", W, H, false⟩,
    ⟨"G", "U", W, H + (if phone v.w then 0 else 4), false⟩, ⟨"D", "U", W, H, false⟩,
    ⟨"bar", "U", W, pillH v, false⟩, ⟨"logo", "bar", c.logoW, c.logoH, true⟩, ⟨"actions", "bar", W, 48, false⟩,
    ⟨"lang", "actions", c.langW, 48, true⟩, ⟨"earn", "actions", c.w0, 48, true⟩,
    ⟨"earnClip", "earn", c.w0, 48, false⟩, ⟨"earnLabel", "earnClip", c.w0, 48, true⟩,
    ⟨"panel", "U", W, H, false⟩, ⟨"backdropClip", "panel", 53 / 50 * W, H, false⟩,
    ⟨"Kb", "backdropClip", 53 / 50 * W, H, false⟩, ⟨"Ub", "Kb", 53 / 50 * W, H, false⟩] ++
  ((List.range (nCols v).floor.toNat).map fun i => ⟨s!"column{i}", "Ub", cw v 1, H, false⟩) ++
  ((imgRows c).map fun ((i, j), _, h) => ⟨s!"image{i}.{j}", s!"column{i}", cw v 1, h, false⟩) ++
  [⟨"veil", "panel", W, H, true⟩, ⟨"centre", "panel", W, c.centreH, true⟩, ⟨"footer", "panel", W, c.footH, true⟩,
    ⟨"footerGrad", "footer", W, c.footH, true⟩, ⟨"footerEnd", "footer", W, c.footH, true⟩,
    ⟨"platform", "", v.w, c.platH, true⟩]

def anims (v : Vp) (c : Ctx) : List Anim :=
  [anim "K0" .transformList .grid [x0 v, y0 v, kk v, kk v],
    anim "K1" .translate .grid [tauX v, fun _ => 0],
    anim "K2" .translate .grid [fun x => -tauX v x, tauY v],
    anim "K3" .translate .grid [tauX v, fun _ => 0],
    anim "U" .transformList .grid [tUx v, tUy v, sU v, sU v],
    anim "G" .backdropBlur .unit [navBlur],
    anim "D" .opacity .unit [fun x => x],
    anim "bar" .translate .unit [fun _ => 0, y0 v],
    anim "logo" .translate .grid [logoT v c.inset c.logoW, fun _ => 0],
    anim "actions" .translate .unit [fun x => -x0 v x, fun _ => 0],
    anim "lang" .translate .earn [fun x => c.gL - actionsGap v false x, fun _ => 0],
    anim "lang" .transformList .time [fun t => c.w0 - earnWF c.eng v c.lw c.a c.b (idx t), fun _ => 0,
      fun _ => 1, fun _ => 1],
    anim "earn" .opacity .time [fun t => opF c.a c.b (idx t)],
    anim "earn" .blur .earn [earnBlur],
    anim "earn" .translate .earn [fun _ => 0, earnShift],
    anim "earnClip" .translate .time [fun t => c.w0 - earnWF c.eng v c.lw c.a c.b (idx t), fun _ => 0],
    if padRuns c.eng then
      anim "earnLabel" .translate .time [fun t => padF c.eng v c.a c.b (idx t) - earnPad v false 0, fun _ => 0]
    else anim "earnLabel" .translate .earn [fun x => earnPad v false x - earnPad v false 0, fun _ => 0],
    anim "panel" .translate .unit [fun _ => 0, dP v],
    anim "panel" .scale .unit [pS, pS],
    anim "panel" .transformList .unit [fun _ => 0, fun x => -dP v x, fun _ => 1, fun _ => 1],
    anim "panel" .opacity .panel [panelO]] ++
  (if v.w ≤ 720 then [] else [anim "panel" .blur .panel [panelBlur v]]) ++
  [anim "backdropClip" .translate .unit [fun x => 53 / 50 * x0 v x, y0 v],
    anim "Kb" .translate .unit [fun x => -(106 / 50) * x0 v x, fun x => ht v x - hp v],
    anim "Ub" .translate .unit [fun x => 106 / 50 * x0 v x, fun x => hp v - ht v x]] ++
  ((List.range (nCols v).floor.toNat).map fun i => anim "column" .translate .unit [colTx v i, fun _ => 0] (i, 0)) ++
  ((imgRows c).map fun ((i, j), y, _) =>
    anim "image" .transformList .unit [fun _ => 0, imgTy v j y 0, sImg v, sImg v] (i, j)) ++
  [anim "veil" .transformList .unit [x0 v, y0 v, fun x => wd v x / wp v, fun x => ht v x / hp v],
    anim "centre" .translate .unit [fun _ => 0, dP v],
    anim "footer" .translate .unit [x0 v, fun x => y0 v x + ht v x - hp v],
    anim "footerGrad" .scale .unit [fun x => wd v x / wp v, fun _ => 1],
    anim "footerEnd" .translate .unit [fun x => -2 * x0 v x, fun _ => 0],
    anim "platform" .opacity .fade [fade],
    anim "platform" .blur .fade [fadeBlur]]


def sortedB : List Rat → Bool
  | p :: q :: rest => decide (p < q) && sortedB (q :: rest)
  | _ => true

def offsetsOk (os : List Rat) : Bool := sortedB os && os.head? == some 0 && os.getLast? == some 1

def easingOk : Easing → Bool
  | .linear => true
  | .cubic x1 y1 x2 y2 => decide (0 ≤ x1 ∧ x1 ≤ 1 ∧ 0 ≤ x2 ∧ x2 ≤ 1 ∧ 0 ≤ y1 ∧ y1 ≤ 1 ∧ 0 ≤ y2 ∧ y2 ≤ 1)

/-- One effect meets `animationCanBeAccelerated` and `KeyframeEffect.cpp:1987-2017@862f17d`. -/
def accelOne (a : Anim) : Bool :=
  a.fns.length == a.prop.arity && a.kfEasing == .linear && easingOk a.easing && a.composite == .replace &&
    a.rate == 1 && a.dir == .normal

def keysOf (as : List Anim) : List (String × (Nat × Nat) × AnimProp) := as.map fun a => (a.el, a.key, a.prop)

def accelerable (v : Vp) (as : List Anim) : Bool :=
  as.all accelOne && (keysOf as).Nodup && [Ks.grid, .unit, .earn, .panel, .fade, .time].all (offsetsOk ∘ Ks.offsets v)

def flipEls : List String :=
  ["nav", "K0", "K1", "K2", "K3", "U", "G", "D", "bar", "logo", "actions", "lang", "earn", "earnClip", "earnLabel",
    "panel", "backdropClip", "Kb", "Ub", "column", "image", "veil", "centre", "footer", "footerGrad", "footerEnd",
    "platform"]

def noTransition (as : List Anim) : Bool := as.all fun a => flipEls.contains a.el

def Ctx.sample (v : Vp) (e : Eng) : Ctx :=
  let ph := phone v.w
  ⟨e, 0, 1, if ph then 16 else 24, if ph then 120 else 160, if ph then 32 else 40, 100,
    if ph then 120 else 144, earnMaxW v false 0, actionsGap v false 1, if ph then 360 else 420,
    if ph then 160 else 68, v.h, List.replicate (nCols v).floor.toNat [(0, 200), (200, 200), (400, 200)]⟩

theorem accelerable_bands :
    bandVps.all (fun v => [Eng.webkit, .chromium].all fun e => accelerable v (anims v (Ctx.sample v e))) = true := by
  decide +kernel

theorem noTransition_bands :
    bandVps.all (fun v => [Eng.webkit, .chromium].all fun e => noTransition (anims v (Ctx.sample v e))) = true := by
  decide +kernel

theorem timed_easing_ok : easingOk (.cubic (1 / 3) 1 (2 / 3) 1) = true := by decide +kernel

theorem layers_cover_anims :
    bandVps.all (fun v => (anims v (Ctx.sample v .webkit)).all fun a =>
      (layers v (Ctx.sample v .webkit)).any fun l => l.name = a.el ∨ l.name.startsWith a.el) = true := by
  decide +kernel

#guard sortedB [0, 1 / 5, 1] && !sortedB [0, 0, 1]
#guard offsetsOk [0, 1 / 2, 1] && !offsetsOk [0, 1 / 2] && !offsetsOk [1 / 10, 1]
#guard easingOk (.cubic (1 / 3) 1 (2 / 3) 1) && !easingOk (.cubic (1 / 3) (-1 / 10) (2 / 3) 1)
#guard accelOne (anim "D" .opacity .unit [fun x => x]) && !accelOne (anim "D" .translate .unit [fun x => x])
#guard noTransition [anim "veil" .opacity .unit [fun x => x]] && !noTransition [anim "title" .opacity .unit [fun x => x]]


def dprOf (v : Vp) : Nat := if phone v.w then 3 else 2

def Lyr.toLayer (l : Lyr) : Fw.Engine.Resource.Layer := ⟨l.w.ceil.toNat, l.h.ceil.toNat, l.backed, true⟩

def memBytes (v : Vp) (c : Ctx) : Nat := Fw.Engine.Resource.gpuBytes (dprOf v) ((layers v c).map Lyr.toLayer)

def memBudget : Nat := Fw.Engine.Resource.budgetB - Fw.Engine.Resource.Flags.basePeak

def memOk (v : Vp) (c : Ctx) : Bool := decide (memBytes v c ≤ memBudget)

theorem memBudget_eq : memBudget = 23055555 := by decide

theorem mem_bands :
    bandVps.map (fun v => memOk v (Ctx.sample v .webkit)) =
      [true, false, false, false, false, false, true, false, false, false, false, false] := by
  decide +kernel

theorem mem_phone_390 : memBytes ⟨390, 844⟩ (Ctx.sample ⟨390, 844⟩ .webkit) = 34558272 := by decide +kernel

#guard dprOf ⟨390, 844⟩ == 3 && dprOf ⟨1280, 800⟩ == 2
#guard memOk ⟨320, 568⟩ (Ctx.sample ⟨320, 568⟩ .webkit) && !memOk ⟨390, 844⟩ (Ctx.sample ⟨390, 844⟩ .webkit)


theorem eval_start (f : Rat → Rat) (p : Rat) (ks : List Rat) (h : sortedB (p :: ks) = true) :
    Track.eval (mk f (p :: ks)) p = f p := by
  cases ks with
  | nil => simp [mk, Track.eval]
  | cons q r =>
    rw [eval_mk_cons]
    simp only [sortedB, Bool.and_eq_true, decide_eq_true_eq] at h
    simp [show p ≤ q by grind, chord, Rat.sub_self, Rat.div_def, Rat.add_zero]

theorem div_one_of (x : Rat) (h : x ≠ 0) : x / x = 1 := by rw [Rat.div_def, Rat.mul_inv_cancel _ h]

theorem lt_lastL (rest : List Rat) : ∀ q r : Rat, sortedB (q :: r :: rest) = true → q < lastL (r :: rest) := by
  induction rest with
  | nil => intro q r h; simp only [sortedB, Bool.and_eq_true, decide_eq_true_eq] at h; simp [lastL]; grind
  | cons s rest ih =>
    intro q r h
    simp only [sortedB, Bool.and_eq_true, decide_eq_true_eq] at h
    have := ih r s (by simp only [sortedB, Bool.and_eq_true, decide_eq_true_eq]; exact h.2)
    simp only [lastL]; grind

theorem eval_end (f : Rat → Rat) (ks : List Rat) : ∀ p : Rat, sortedB (p :: ks) = true →
    Track.eval (mk f (p :: ks)) (lastL (p :: ks)) = f (lastL (p :: ks)) := by
  induction ks with
  | nil => intro p _; simp [mk, Track.eval, lastL]
  | cons q r ih =>
    intro p h
    rw [eval_mk_cons]
    have hs := h
    simp only [sortedB, Bool.and_eq_true, decide_eq_true_eq] at hs
    cases r with
    | nil =>
      simp only [lastL, Rat.le_refl, ite_true, chord]
      have : (f q - f p) * (q - p) / (q - p) = f q - f p := by
        rw [Rat.div_def, Rat.mul_assoc, Rat.mul_inv_cancel _ (by grind), Rat.mul_one]
      grind
    | cons s r' =>
      have hlt := lt_lastL r' q s hs.2
      simp only [lastL] at hlt ⊢
      simp only [Rat.not_le.mpr hlt, ite_false]
      exact ih q hs.2

def Ks.last (k : Ks) : Rat := if k = .time then timeEnd else 1

def allKs : List Ks := [.grid, .unit, .earn, .panel, .fade, .time]

def endsOk (v : Vp) (k : Ks) : Bool := sortedB (k.list v) && (k.list v).head? == some 0 && lastL (k.list v) == k.last

theorem ends_bands : bandVps.all (fun v => allKs.all (endsOk v)) = true := by decide +kernel

theorem valid_bands : bandVps.all (fun v => decide (320 ≤ v.w ∧ 300 ≤ v.h)) = true := by decide +kernel

theorem track_ends (v : Vp) (hv : v ∈ bandVps) (k : Ks) (f : Rat → Rat) :
    Track.eval (mk f (k.list v)) 0 = f 0 ∧ Track.eval (mk f (k.list v)) k.last = f k.last := by
  have h := List.all_eq_true.mp (List.all_eq_true.mp ends_bands v hv) k (by cases k <;> simp [allKs])
  unfold endsOk at h
  generalize k.list v = ks at h ⊢
  cases ks with
  | nil => simp at h
  | cons p ps =>
    simp only [Bool.and_eq_true, beq_iff_eq, List.head?_cons, Option.some.injEq] at h
    obtain ⟨⟨hs, rfl⟩, hl⟩ := h
    exact ⟨eval_start f 0 ps hs, hl ▸ eval_end f ps 0 hs⟩

theorem nav_ends (v : Vp) (hv : v ∈ bandVps) (m u : Rat) (hm : m = 0 ∨ m = 1) :
    navX v m u = u ∧ navY v m u = u := by
  have hV : 320 ≤ v.w ∧ 300 ≤ v.h := of_decide_eq_true (List.all_eq_true.mp valid_bands v hv)
  have h0 : 0 ≤ m := by grind
  have h1 : m ≤ 1 := by grind
  have ev : ∀ f, Track.eval (mk f (knots v)) m = f m := fun f => by
    rcases hm with rfl | rfl
    · exact (track_ends v hv .grid f).1
    · exact (track_ends v hv .grid f).2
  have hs := sU_exact v hV m h0 h1
  have hx := tUx_exact v hV m h0 h1
  have hy := tUy_exact v hV m h0 h1
  unfold navX navY
  simp only [ev]
  constructor <;> grind

theorem content_end (v : Vp) (hv : Valid v) (i j : Nat) (Y inset lw : Rat) :
    x0 v 1 = 0 ∧ y0 v 1 = 0 ∧ dP v 1 = 0 ∧ pS 1 = 1 ∧ sImg v 1 = 1 ∧ colTx v i 1 = 0 ∧ imgTy v j Y 0 1 = 0 ∧
      wd v 1 / wp v = 1 ∧ ht v 1 / hp v = 1 ∧ ht v 1 - hp v = 0 ∧ logoT v inset lw 1 = 0 ∧ panelO 1 = 1 ∧
      panelBlur v 1 = 0 := by
  have hw := wd_eq v 1; have hh := ht_eq v 1
  have := wp_pos v hv; have := hp_pos v hv; have := cw1_pos v hv
  have hx : x0 v 1 = 0 := by unfold x0; grind
  have hy : y0 v 1 = 0 := by unfold y0; grind
  have hsI : sImg v 1 = 1 := by unfold sImg; exact div_one_of _ (by grind)
  refine ⟨hx, hy, by unfold dP; grind, by unfold pS; grind, hsI, by unfold colTx; grind, by unfold imgTy; grind,
    by rw [show wd v 1 = wp v by grind]; exact div_one_of _ (by grind),
    by rw [show ht v 1 = hp v by grind]; exact div_one_of _ (by grind), by grind,
    by unfold logoT logoLeft; grind, by decide +kernel, ?_⟩
  have : panelO 1 = 1 := by decide +kernel
  unfold panelBlur; split <;> grind

theorem end_eq (v : Vp) (hv : v ∈ bandVps) :
    (∀ a ∈ anims v (Ctx.sample v .webkit) ++ anims v (Ctx.sample v .chromium), ∀ f ∈ a.fns,
      Track.eval (mk f (a.ks.list v)) 0 = f 0 ∧ Track.eval (mk f (a.ks.list v)) a.ks.last = f a.ks.last) ∧
    (∀ m u, (m = 0 ∨ m = 1) → navX v m u = u ∧ navY v m u = u) ∧
    (∀ i j Y inset lw, x0 v 1 = 0 ∧ y0 v 1 = 0 ∧ dP v 1 = 0 ∧ pS 1 = 1 ∧ sImg v 1 = 1 ∧ colTx v i 1 = 0 ∧
      imgTy v j Y 0 1 = 0 ∧ wd v 1 / wp v = 1 ∧ ht v 1 / hp v = 1 ∧ ht v 1 - hp v = 0 ∧ logoT v inset lw 1 = 0 ∧
      panelO 1 = 1 ∧ panelBlur v 1 = 0) := by
  have hV : 320 ≤ v.w ∧ 300 ≤ v.h := of_decide_eq_true (List.all_eq_true.mp valid_bands v hv)
  exact ⟨fun a _ f _ => track_ends v hv a.ks f, fun m u hm => nav_ends v hv m u hm,
    fun i j Y inset lw => content_end v hV i j Y inset lw⟩

#guard endsOk ⟨390, 844⟩ .grid && endsOk ⟨390, 844⟩ .time && Ks.last .time == 1500

end Fw.Parts.MorphGeom
