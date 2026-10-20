import Lean.Data.Json
import Fw.Parts.HiddenPause
import Fw.Parts.HeroExit
import Fw.Engine.Compose
/-!
# hero.countdown `hidden-pause`: hold the face writes while the hero clock paints nothing

The hero clock sits in `.copy` (opacity `calc(var(--copy-in) * var(--exit-opacity))`, `opacity: var(--exit-opacity)`
at `width<=600px`; `apps/site/src/parts/hero/hero.module.css`), inside the sticky stage that hero.exit writes
`--exit-opacity` on, inside the 200vh track. The spring keeps integrating; the gate holds the face `transform` writes
while the clock is hidden and writes the latest value per face when it shows again.

Hidden is `exitOpacity = 0` (the zone past `T + n`) and nothing else. A distance branch (track more than one viewport
away) adds nothing: far above already lies in the exit zone (`farAbove_implies_exitZero`), and far below cannot happen
for the first section (`farBelow_unreachable`). The pointer-off sentinel (`e < 1/20`) is not a hidden condition: at
`e = 1/25` the copy still paints (`sentinel_not_hidden`).
-/
namespace Fw.Parts.HeroCountdownHidden

open Fw.Engine
open Fw.Parts.HiddenPause (Tmpl inst Hidden HiddenOrStill hiddenPause_visSame cdFrame skipWrites unhideFrame
  cr_countdown_style wk_countdown_style unhide_le)
open Fw.Parts.HeroExit (exitOpacity exitOpacityAt exitRange exitClamp exitFrame pointerOff copyOpacity
  exitRange_pos div_mul_pos exitOpacity_before exitOpacity_after exitOpacity_linear)

/-! ## 1. The exit branch: the clamp reaches exactly 0 -/

/-- **The exit opacity is exactly 0 on one closed zone.**

The hero is fully transparent exactly once the track top has moved at least the whole exit range above the viewport. -/
theorem exitOpacity_eq_zero_iff (t h v : Rat) : exitOpacity t h v = 0 ↔ exitRange h v ≤ -t := by
  constructor
  · intro h0
    refine Classical.byContradiction fun hlt => ?_
    have hlt' : -t < exitRange h v := by grind
    by_cases ht : 0 ≤ t
    · rw [exitOpacity_before t h v ht] at h0; exact absurd h0 (by decide)
    · have hl := exitOpacity_linear t h v (by grind) (by grind)
      rw [h0] at hl
      grind
  · exact exitOpacity_after t h v

/-- **The zone in scroll terms.** For a track whose top sits at document offset `T`, the exit opacity at scroll `y`
is 0 exactly from `y = T + n` on, with `n = max(1, h - v)` (for the 200vh track, `n = max(1, v)`).

The clock is hidden by the exit from one scroll position on, one exit range below the track top. -/
theorem exitZeroAt_iff (T h v y : Rat) : exitOpacityAt T h v y = 0 ↔ T + exitRange h v ≤ y := by
  unfold exitOpacityAt
  rw [exitOpacity_eq_zero_iff]
  grind

/-- **The frame's written opacity is 0 exactly in the zone, and never under reduced motion.**

Reduced motion writes 1, so only the scrolled-out zone without reduced motion writes 0. -/
theorem exitFrame_zero_iff (r : Bool) (t h v : Rat) :
    (exitFrame r t h v).opacity = 0 ↔ r = false ∧ exitRange h v ≤ -t := by
  cases r
  · simp only [exitFrame, Bool.false_eq_true, ↓reduceIte, true_and]
    exact exitOpacity_eq_zero_iff t h v
  · simp only [exitFrame, ↓reduceIte, Bool.true_eq_false, false_and, iff_false]
    decide

/-- **The sentinel does not decide.** There is a track geometry where pointer events are off (the sentinel fires)
while the exit opacity is `1/25 ≠ 0`, so the copy still paints.

Witness `t = -768`, `h = 1600`, `v = 800`: the exit opacity is `1/25`, below the `1/20` sentinel and above 0. -/
theorem sentinel_not_hidden :
    ∃ t h v : Rat, pointerOff (exitOpacity t h v) = true ∧ exitOpacity t h v ≠ 0 :=
  ⟨-768, 1600, 800, by decide +kernel, by decide +kernel⟩

/-- **Off the top implies the exit zone.** A track of height `h ≥ 1` whose bottom is at or
above the viewport top (`t + h ≤ 0`) and a viewport height `v ≥ 0` give exit opacity 0.

A track scrolled fully above the viewport is already in the exit zone. -/
theorem exitZero_of_above (t h v : Rat) (h1 : 1 ≤ h) (hv : 0 ≤ v) (ht : t + h ≤ 0) : exitOpacity t h v = 0 :=
  (exitOpacity_eq_zero_iff t h v).mpr (by unfold exitRange; grind)

/-! ## 2. No distance branch: far above is already the exit zone, far below never happens -/

/-- **Far above implies exit 0.** A track of height `h ≥ 1` whose bottom is more than one viewport height above the
viewport top (`t + h < -v`), with `v ≥ 0`, has exit opacity 0.

An IntersectionObserver with one viewport of margin would report such a track as far, but the exit branch already
closes the gate there, so a far branch saves nothing. -/
theorem farAbove_implies_exitZero (t h v : Rat) (h1 : 1 ≤ h) (hv : 0 ≤ v) (ht : t + h < -v) :
    exitOpacity t h v = 0 :=
  exitZero_of_above t h v h1 hv (by grind)

/-- **Far below never happens for the first section.** A track at document offset `T < 2v`, seen at scroll `y ≥ 0`,
has its top at `T - y < 2v`, so it never lies wholly below the viewport grown by one viewport height.

The hero track is the first section, so its document offset is below two viewport heights. -/
theorem farBelow_unreachable (T y v : Rat) (hT : T < 2 * v) (hy : 0 ≤ y) : T - y < 2 * v := by
  grind

/-! ## 3. The gate decision -/

/-- The stage's effective `--exit-opacity`: the written value, or the CSS default 1 before the first write.

What the copy's opacity multiplies by. -/
def exitVal (ex : Option Rat) : Rat := ex.getD 1

/-- **The gate's hidden decision**: the written exit opacity is exactly 0.

Here `x = 0` means a written 0 (`⊥ ≠ 0`). Hold the face writes while the copy is transparent; before hero.exit
writes, the gate stays open. -/
def gateHidden (ex : Option Rat) : Bool := decide (ex = some 0)

/-- **The decision.**

The gate is closed exactly when hero.exit has written opacity 0. -/
theorem hidden_iff (ex : Option Rat) : gateHidden ex = true ↔ ex = some 0 := by
  simp [gateHidden]

/-- **In scroll terms.** The gate is closed on the frame's written opacity exactly in the exit zone without reduced
motion.

Only the scrolled-out zone closes the gate, and reduced motion never does. -/
theorem hidden_iff_exit (r : Bool) (t h v : Rat) :
    gateHidden (some (exitFrame r t h v).opacity) = true ↔ r = false ∧ exitRange h v ≤ -t := by
  rw [hidden_iff, ← exitFrame_zero_iff]
  simp

#guard gateHidden (some 0)
#guard !gateHidden (some (1/25))
#guard !gateHidden none
#guard !gateHidden (some 1)

/-- **Which instance gets the gate.** Only the hero instance with variant `hidden-pause` is gated; morph.countdown
keeps its own gate.

Any other variant or anchor id writes the faces directly. -/
def gatedInstance (variant fwId : String) : Bool := variant == "hidden-pause" && fwId == "hero-countdown"

#guard gatedInstance "hidden-pause" "hero-countdown"
#guard !gatedInstance "hidden-pause" "morph-countdown"
#guard !gatedInstance "faithful" "hero-countdown"

/-! ## 4. The clock's scene is empty while the gate is closed -/

/-- Every box of the clock sits in the copy: its effective opacity is the copy's opacity times a factor.

Each clock box carries the copy's opacity as a factor. -/
def ClockUnder {A : Type} (copyIn : Rat) (ex : Option Rat) (tm : Tmpl A) : Prop :=
  ∀ e ∈ tm, ∃ k : A → Rat, ∀ a, (e.2 a).alpha = copyOpacity copyIn (exitVal ex) * k a

/-- A template whose every box is hidden shows nothing.

Dropped boxes leave an empty scene for every face value. -/
private theorem visible_nil {A : Type} (vp : Rect) (a : A) :
    ∀ tm : Tmpl A, (∀ e ∈ tm, Hidden vp e.2) → visible vp (inst tm a) = []
  | [], _ => rfl
  | e :: tm, h => by
    have ih := visible_nil vp a tm (fun x hx => h x (List.mem_cons_of_mem _ hx))
    simp only [visible, inst, List.map_cons, List.filter_cons] at ih ⊢
    simp [h e List.mem_cons_self a, ih]

/-- **Exit branch, scene.** With the written exit opacity 0, every clock box is dropped in every viewport.

A transparent copy shows no clock, whatever the faces hold. -/
theorem scene_empty_of_exit {A : Type} (copyIn : Rat) (tm : Tmpl A) (vp : Rect) (a : A)
    (hU : ClockUnder copyIn (some 0) tm) : visible vp (inst tm a) = [] := by
  refine visible_nil vp a tm fun e he b => ?_
  obtain ⟨k, hk⟩ := hU e he
  have : (e.2 b).alpha ≤ 0 := by
    rw [hk b]; simp [copyOpacity, exitVal]
  simp [BoxVis.drop, this]

/-- **Closed gate, empty scene.** Whenever the decision holds, the clock's visible scene is empty.

Every clock box is dropped for every face value while the gate is closed. -/
theorem hidden_scene_empty {A : Type} (copyIn : Rat) (ex : Option Rat) (vp : Rect) (tm : Tmpl A)
    (hg : gateHidden ex = true) (hU : ClockUnder copyIn ex tm) :
    HiddenOrStill vp tm ∧ ∀ a, visible vp (inst tm a) = [] := by
  have hx := (hidden_iff ex).mp hg
  subst hx
  refine ⟨fun e he => Or.inr fun b => ?_, fun a => scene_empty_of_exit copyIn tm vp a hU⟩
  obtain ⟨k, hk⟩ := hU e he
  have : (e.2 b).alpha ≤ 0 := by
    rw [hk b]; simp [copyOpacity, exitVal]
  simp [BoxVis.drop, this]

/-! ## 5. The write gate (`createWriteGate`) -/

/-- One event the clock's faces see: a face write, or a gate signal. -/
inductive Ev (K V : Type) where
  | write (k : K) (v : V)
  | hide (b : Bool)

/-- The write gate's state: whether it is closed, the held latest value per face, and the faces as shown. -/
structure Gate (K V : Type) where
  hidden : Bool
  pend : K → Option V
  shown : K → V

variable {K V : Type} [DecidableEq K]

/-- Point update of a face map. -/
def upd (f : K → V) (k : K) (v : V) : K → V := fun j => if j = k then v else f j

/-- The faithful clock: every write lands, signals do nothing. -/
def fStep (D : K → V) : Ev K V → (K → V)
  | .write k v => upd D k v
  | .hide _ => D

/-- **The gate step** (`createWriteGate`, `apps/site/src/parts/engine.scene/logic.ts`): an open gate writes through, a
closed one holds the latest value per face; a signal equal to the state does nothing; closing only sets the flag;
opening writes every held value and clears them.

Writes pass while open; on opening, every held face gets its latest value. -/
def gStep (g : Gate K V) : Ev K V → Gate K V
  | .write k v => if g.hidden then { g with pend := upd g.pend k (some v) } else { g with shown := upd g.shown k v }
  | .hide b =>
    if b = g.hidden then g
    else if b then { g with hidden := true }
    else ⟨false, fun _ => none, fun j => (g.pend j).getD (g.shown j)⟩

/-- The open gate with nothing held, showing `D`. -/
def gInit (D : K → V) : Gate K V := ⟨false, fun _ => none, D⟩

/-- The gate's invariant against the faithful faces `D`: open, it shows `D` and holds nothing; closed, each face's held
value (or, if none, its shown value) is `D`'s. -/
def Inv (g : Gate K V) (D : K → V) : Prop :=
  if g.hidden then ∀ k, (g.pend k).getD (g.shown k) = D k else g.shown = D ∧ ∀ k, g.pend k = none

/-- **The first open frame rewrites every face to the faithful value.** Opening a closed gate whose invariant holds
shows exactly the faithful faces.

On unhide, the held latest values make the clock equal to the original's. -/
theorem first_visible_rewrites (g : Gate K V) (D : K → V) (hh : g.hidden = true) (hi : Inv g D) :
    (gStep g (.hide false)).shown = D ∧ (gStep g (.hide false)).hidden = false := by
  simp only [Inv, hh, ↓reduceIte] at hi
  simp only [gStep, hh, Bool.false_eq_true, ↓reduceIte]
  exact ⟨funext hi, trivial⟩

/-- **A closed gate shows nothing new.** A write while closed leaves the shown faces unchanged (the skipped DOM write).

Held writes never reach the DOM. -/
theorem closed_write_skipped (g : Gate K V) (k : K) (v : V) (hh : g.hidden = true) :
    (gStep g (.write k v)).shown = g.shown := by
  simp [gStep, hh]

/-- One step keeps the invariant. -/
theorem inv_step (g : Gate K V) (D : K → V) (ev : Ev K V) (hi : Inv g D) : Inv (gStep g ev) (fStep D ev) := by
  cases ev with
  | write k v =>
    cases hh : g.hidden
    · simp only [Inv, hh, Bool.false_eq_true, ↓reduceIte] at hi
      simp only [Inv, gStep, fStep, hh, Bool.false_eq_true, ↓reduceIte]
      exact ⟨by rw [hi.1], hi.2⟩
    · simp only [Inv, hh, ↓reduceIte] at hi
      simp only [Inv, gStep, fStep, hh, ↓reduceIte]
      intro j
      by_cases hj : j = k
      · simp [upd, hj]
      · simp [upd, hj, hi j]
  | hide b =>
    cases hh : g.hidden <;> cases b
    · simpa [gStep, fStep, hh] using hi
    · simp only [Inv, hh, Bool.false_eq_true, ↓reduceIte] at hi
      simp only [Inv, gStep, fStep, hh, ↓reduceIte, Bool.true_eq_false]
      intro j; simp [hi.2 j, hi.1]
    · have := first_visible_rewrites g D hh hi
      simp only [Inv, fStep, this.2, Bool.false_eq_true, ↓reduceIte]
      exact ⟨this.1, fun _ => by simp [gStep, hh]⟩
    · simpa [gStep, fStep, hh] using hi

/-- Replaying events from a state keeps the invariant. -/
theorem inv_run : ∀ (evs : List (Ev K V)) (g : Gate K V) (D : K → V), Inv g D →
    Inv (evs.foldl gStep g) (evs.foldl fStep D)
  | [], _, _, hi => hi
  | ev :: evs, g, D, hi => inv_run evs _ _ (inv_step g D ev hi)

/-- **Open gate, faithful faces.** After any event list from the open initial gate, whenever the gate is open the
shown faces equal the faithful faces.

Whenever the clock is shown, it shows the original's faces. -/
theorem gate_sync (D0 : K → V) (evs : List (Ev K V)) (ho : (evs.foldl gStep (gInit D0)).hidden = false) :
    (evs.foldl gStep (gInit D0)).shown = evs.foldl fStep D0 := by
  have hi := inv_run evs (gInit D0) D0 (by simp [Inv, gInit])
  simp only [Inv, ho, Bool.false_eq_true, ↓reduceIte] at hi
  exact hi.1

#guard ((([.hide true, .write 1 7, .write 1 8, .hide false] : List (Ev Nat Nat)).foldl gStep (gInit fun _ => 0)).shown 1) == 8
#guard ((([.hide true, .write 1 7] : List (Ev Nat Nat)).foldl gStep (gInit fun _ => 0)).shown 1) == 0
#guard ((([.write 2 5, .hide false] : List (Ev Nat Nat)).foldl gStep (gInit fun _ => 0)).shown 2) == 5

/-! ## 6. Vision: the variant's clock looks like the original's at every instant -/

/-- **visSame (class E).** For every environment and paint instant `t` with events `ε(env, t)` so
far: if each clock box sits in the copy at the written exit value, and the gate is closed at a paint only when the
decision holds there, the variant's clock (shown faces) and the original's (all writes landed) give the same visible
scene.

Holding the face writes only while the copy is transparent gives the original's picture at every width and every
instant. -/
theorem visSame {Env T : Type} (vp : Env → Rect) (tm : Env → T → Tmpl (K → V)) (D0 : K → V)
    (evs : Env → T → List (Ev K V)) (copyIn : Env → T → Rat) (ex : Env → T → Option Rat)
    (hU : ∀ env t, ClockUnder (copyIn env t) (ex env t) (tm env t))
    (hSig : ∀ env t, ((evs env t).foldl gStep (gInit D0)).hidden = true → gateHidden (ex env t) = true) :
    VisSame E vp (fun env t => inst (tm env t) ((evs env t).foldl fStep D0))
      (fun env t => inst (tm env t) ((evs env t).foldl gStep (gInit D0)).shown) :=
  hiddenPause_visSame vp tm (fun env t => (evs env t).foldl fStep D0)
    (fun env t => ((evs env t).foldl gStep (gInit D0)).shown)
    (fun env t => ((evs env t).foldl gStep (gInit D0)).hidden = true)
    (fun env t h => (hidden_scene_empty (copyIn env t) (ex env t) (vp env) (tm env t) (hSig env t h) (hU env t)).1)
    (fun env t h => gate_sync D0 (evs env t) (by simpa using h))

/-! ## 7. Work: a closed frame drops the style pass, the reopening frame is `≤` -/

open Fw.Engine.Chromium Fw.Engine.WebKit in
/-- **Work, both engines.** For `d > 0` springing digits in any layer state: a closed frame (callbacks kept, face writes
held) is strictly below the original's frame in the Chromium lane and in WebKit, and the reopening frame (any subset
of the face writes) costs at most the original's frame in every engine.

Here `κ` is any filter on the frame's changes (the held writes the reopening frame replays). The hidden clock saves the style pass per springing frame in both engines and its re-sync never costs more than an
original frame (`cr_countdown_style`, `wk_countdown_style`, `unhide_le`). -/
theorem hidden_work (d : Nat) (l : LayerState) (hd : 0 < d) :
    (frameWork chromium (skipWrites (cdFrame (.css .transform) d l))).lt
        (frameWork chromium (cdFrame (.css .transform) d l)) ∧
      (frameWork webkit (skipWrites (cdFrame WkProp.transform d l))).lt
        (frameWork webkit (cdFrame WkProp.transform d l)) ∧
      ∀ {P M : Type} (E : Engine P M) (p : P) (keep : Change P → Bool),
        (frameWork E (unhideFrame p d l keep)).le (frameWork E (cdFrame p d l)) :=
  ⟨(cr_countdown_style d l hd).2.2, (wk_countdown_style d l hd).2.2, fun E p keep => unhide_le E p d l keep⟩

theorem hidden_work_idle {P M : Type} (E : Engine P M) (p : P) (l : LayerState) :
    skipWrites (cdFrame p 0 l) = cdFrame p 0 l ∧
      frameWork E (skipWrites (cdFrame p 0 l)) = frameWork E (cdFrame p 0 l) :=
  ⟨rfl, rfl⟩

theorem hidden_pass_absorbed {P M : Type} (E : Engine P M) (p : P) (d : Nat) (l : LayerState) (g : FrameIn P)
    (s : Stage) (hs : s ∈ touched E g) :
    (frameWork E (skipWrites (cdFrame p d l) ++ g)).passes s = (frameWork E (cdFrame p d l ++ g)).passes s :=
  passes_absorb_part E (cdFrame p d l) (skipWrites (cdFrame p d l)) g s hs (by cases s <;> rfl)

#guard (skipWrites (cdFrame (0 : Nat) 0 .none)).changes.isEmpty
#guard (cdFrame (0 : Nat) 2 .none).changes.length == 32

/-! ## 8. Golden rows: gate open or closed per zone -/

/-- One zone: name, reduced motion, track top, track height and viewport height (viewport `(0, 0, 1280, v)`, track
`(0, t, 1280, h)`), and whether hero.exit has written yet. -/
abbrev Zone := String × Bool × Rat × Rat × Rat × Bool

/-- The zones the golden covers (`v = 800`; the 200vh track has `h = 1600`; under reduced motion the track is `auto`
and `h = 900` stands for its content height). -/
def zones : List Zone :=
  [("unwritten", false, 0, 1600, 800, false), ("below-top", false, 100, 1600, 800, true),
   ("rest", false, 0, 1600, 800, true), ("fade", false, -400, 1600, 800, true),
   ("pointer-off", false, -768, 1600, 800, true), ("edge", false, -800, 1600, 800, true),
   ("past", false, -1200, 1600, 800, true), ("far-above", false, -2600, 1600, 800, true),
   ("reduced-past", true, -1200, 900, 800, true), ("reduced-near", true, -1600, 900, 800, true),
   ("reduced-far", true, -1800, 900, 800, true), ("far-below", false, 1600, 1600, 800, true),
   ("short-track", false, -1, 100, 800, true)]

/-- The written exit value of a zone: hero.exit's frame opacity, or none before its first write. -/
def written (z : Zone) : Option Rat :=
  let (_, r, t, h, v, w) := z
  if w then some (exitFrame r t h v).opacity else none

/-- The decision of a zone. -/
def zoneHidden (z : Zone) : Bool := gateHidden (written z)

/-- A rational as the wire object `{"num", "den"}`. -/
def ratWire (q : Rat) : Lean.Json := Lean.Json.mkObj [("num", toString q.num), ("den", toString q.den)]

/-- One golden row: the zone's inputs, the written exit value (`null` if none), the sentinel and the decision. -/
def row (z : Zone) : Lean.Json :=
  let (n, r, t, h, v, _) := z
  Lean.Json.mkObj
    [("zone", n), ("reduced", r), ("trackTop", ratWire t), ("trackHeight", ratWire h), ("vh", ratWire v),
     ("exit", match written z with | some e => ratWire e | none => Lean.Json.null),
     ("pointerOff", pointerOff (exitVal (written z))), ("hidden", zoneHidden z)]

/-- The contents of `packages/contracts/golden/parts/hero.countdown.hidden.jsonl`: one compact row per zone. -/
def goldenText : String := String.join (zones.map fun z => (row z).compress ++ "\n")

#guard (zones.map zoneHidden) ==
  [false, false, false, false, false, true, true, true, false, false, false, false, true]
#guard (zones.map fun z => pointerOff (exitVal (written z))) ==
  [false, false, false, false, true, true, true, true, false, false, false, false, true]

/-- Print the golden, or with `--check <file>` compare it byte for byte (exit 1 on a difference).

Any other argument list prints goldenText and returns 0; an unreadable `f` raises an IO error instead of a code. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readFile path
    if cur == goldenText then
      IO.eprintln s!"countdown hidden golden: {path} is up to date ({zones.length} lines)"
      return 0
    IO.eprintln s!"countdown hidden golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Parts.HeroCountdownHidden
