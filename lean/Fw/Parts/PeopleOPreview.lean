import Lean.Data.Json
import Fw.Engine.Core
import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Fw.Parts.PeopleO
/-!
# people.o, variant `preview-translate`: the seller preview follows its face by `translate`, not by `top`

The preview card of `Fw.Parts.PeopleO` is `position: fixed`; its `left` and `top` follow the face it hangs from, and the
original writes them in every scroll frame (JS 6190-6213, 6251). A `top` change on a fixed box is a layout change:
the movement-only shortcut `LayoutOutOfFlowMovementOnly` needs `position: absolute`
(`StyleDifference.cpp:557-565`@862f17d). The variant writes `left`, `top` and `width` when the card opens and whenever
the faithful position is not the held one moved by the scroll delta, and in every other scroll frame writes only the
`translate` property (separate from the `transform` of `previewIn`).

* The face moves with the page: its rect at scroll `y` is its rect at the last write `y0` moved up by `y - y0`.
* The card top is `bot + 12` below the face, `top - 452` above it, or `12` when the above position leaves the
  viewport (`PeopleO.cardTop`). Those three are the `Regime`s; a regime change is a flip.
* Pixels. The card layer sits at its layout position snapped to the device grid (`snapDev`), and the compositor adds the
  translate. The two agree with the faithful snapped position only if the translate is a whole number of device pixels
  (`snapDev_add`, `frac_counter`); the variant keeps the held position only for such a delta and rewrites otherwise.
  WebKit's scroll positions are integers (`ScrollTypes.h:47-49`, `LocalDOMWindow.cpp:1466`@862f17d), so on WebKit every
  scroll delta is such a delta at integer device ratios.

Premises (INFERRED): the card has its own composited layer (a fixed box with a stacking context,
`RenderLayerCompositor.cpp:4097-4150`@862f17d; Chromium composites fixed boxes of a scrolling page), and `translate` adds
no `will-change`, so the layer budget is the faithful one. Times and lengths are `Rat`.
-/
namespace Fw.Parts.PeopleOPreview

open Fw.Engine
open Lean (Json)

/-! ## Device-pixel snapping -/

/-- A CSS length `v` snapped to the device grid at ratio `d`, in device pixels: round half up. -/
def snapDev (d : Rat) (v : Rat) : Int := Rat.floor (v * d + 1 / 2)

/-- The sub-pixel phase of `v` at ratio `d`: its fractional device-pixel part. -/
def phase (d : Rat) (v : Rat) : Rat := v * d - Rat.floor (v * d)

/-- **Snapping commutes with a whole-device-pixel shift.** Moving a length by `s` CSS px with `s * d = k` device px,
`k` an integer, moves its snapped position by exactly `k`. -/
theorem snapDev_add (d t s : Rat) (k : Int) (h : s * d = k) : snapDev d (t + s) = snapDev d t + k := by
  unfold snapDev
  have : (t + s) * d + 1 / 2 = (t * d + 1 / 2) + (k : Rat) := by
    rw [← h]; grind
  rw [this, Rat.floor_add_intCast]

/-- **The phase is unchanged by a whole-device-pixel shift.** -/
theorem phase_add (d t s : Rat) (k : Int) (h : s * d = k) : phase d (t + s) = phase d t := by
  unfold phase
  have h1 : (t + s) * d = t * d + (k : Rat) := by rw [← h]; grind
  have h2 : Rat.floor ((t + s) * d) = Rat.floor (t * d) + k := by rw [h1, Rat.floor_add_intCast]
  rw [h2, h1]
  push_cast
  grind

/-- **A fractional shift breaks it.** At `d = 1`, a length `100.3` moved by `-1/2` snaps to `100`, but the held
snapped `100` plus the translate `-1/2` is `99.5`: the pixel the compositor draws is not the faithful pixel. -/
theorem frac_counter : snapDev 1 (100.3 + (-1 / 2)) = 100 ∧ (snapDev 1 100.3 : Rat) + (-1 / 2) = 99.5 := by
  constructor <;> decide +kernel

/-! ## Card position by regime -/

/-- The three ways `PeopleO.cardTop` is computed: under the face, above it, or above it clamped to the viewport top. -/
inductive Regime where
  | below | aboveFree | aboveClamped
deriving Repr, DecidableEq, BEq

def Regime.name : Regime → String
  | .below => "below"
  | .aboveFree => "aboveFree"
  | .aboveClamped => "aboveClamped"

/-- The regime of a face with rect top `t` and bottom `b` in a viewport of height `vh` (JS 6195-6197). -/
def regime (vh t b : Rat) : Regime :=
  if vh - 12 < b + 12 + PeopleO.cardHeight then
    (if 12 ≤ t - 12 - PeopleO.cardHeight then .aboveFree else .aboveClamped)
  else .below

/-- **The card top is a function of the regime.** Under the face it is `b + 12`, above it `t - 452`, clamped `12`. -/
theorem cardTop_regime (vh t b : Rat) :
    PeopleO.cardTop vh t b =
      match regime vh t b with
      | .below => b + 12
      | .aboveFree => t - 12 - PeopleO.cardHeight
      | .aboveClamped => 12 := by
  unfold PeopleO.cardTop regime
  by_cases h1 : vh - 12 < b + 12 + PeopleO.cardHeight
  · by_cases h2 : 12 ≤ t - 12 - PeopleO.cardHeight
    · simp only [h1, h2, ite_true]; grind
    · simp only [h1, h2, ite_true, ite_false]; grind
  · simp [h1]

/-- What a held write remembers: the viewport, the face rect (left, width, top, bottom) and the scroll position at the
last time `left`, `top` and `width` were written. -/
structure Held where
  vw : Rat
  vh : Rat
  x : Rat
  s : Rat
  t : Rat
  b : Rat
  y0 : Rat
deriving Repr, DecidableEq

/-- The inputs of one frame: the same fields at the current scroll position `y`. -/
abbrev Input := Held

/-- The card top the held write put on the page. -/
def Held.top (h : Held) : Rat := PeopleO.cardTop h.vh h.t h.b

/-- The card left the held write put on the page. -/
def Held.left (h : Held) : Rat := PeopleO.cardLeft h.vw h.x h.s

/-- Whether `q` is an integer. -/
def isInt (q : Rat) : Bool := decide (q = (q.floor : Rat))

/-- A passing `isInt` gives the integer. -/
theorem isInt_exists (q : Rat) (h : isInt q = true) : ∃ k : Int, q = k :=
  ⟨q.floor, by simpa [isInt] using h⟩

/-- The scroll delta the face rect has moved by since the held write. -/
def Held.delta (h : Held) (y : Rat) : Rat := h.y0 - y

/-- The translate (CSS px) the variant would apply in the held regime. -/
def shiftOf (r : Regime) (n : Rat) : Rat := if r = .aboveClamped then 0 else n

/-- **The keep test.** The held write stays when the viewport, the face's left and width are unchanged, the face rect
moved by exactly the scroll delta (nothing else moved it), the regime is the same, and the shift is a whole number of
device pixels at ratio `d`. -/
def keep (d : Rat) (h i : Input) (y : Rat) : Bool :=
  decide (h.vw = i.vw) && decide (h.vh = i.vh) && decide (h.x = i.x) && decide (h.s = i.s) &&
  decide (i.t = h.t + h.delta y) && decide (i.b = h.b + h.delta y) &&
  decide (regime h.vh h.t h.b = regime i.vh i.t i.b) &&
  (decide (regime h.vh h.t h.b = .aboveClamped) || isInt (h.delta y * d))

/-- The result of one frame: whether `left`/`top`/`width` are written, the translate, and the card top and left the
page shows (the written one, moved by the translate). -/
structure Out where
  write : Bool
  tr : Rat
  top : Rat
  left : Rat
deriving Repr, DecidableEq

/-- One frame of the variant. A kept frame writes nothing and sets the translate; a rewrite writes the faithful
position and clears the translate. -/
def step (d : Rat) (h i : Input) (y : Rat) : Out :=
  if keep d h i y then
    ⟨false, shiftOf (regime h.vh h.t h.b) (h.delta y), h.top + shiftOf (regime h.vh h.t h.b) (h.delta y), h.left⟩
  else ⟨true, 0, PeopleO.cardTop i.vh i.t i.b, PeopleO.cardLeft i.vw i.x i.s⟩

/-- The held state after a frame: unchanged when kept, the current input at scroll `y` after a rewrite. -/
def next (d : Rat) (h i : Input) (y : Rat) : Held := if keep d h i y then h else { i with y0 := y }

/-- **The page shows the faithful position, whatever the history.** In every frame, from every held state, the card
top and left shown equal `PeopleO.cardTop` and `PeopleO.cardLeft` of the current rect and viewport. So flips and the
viewport clamps are the faithful ones, in a sequence of any length (the held state of the next frame is `next`).
-/
theorem step_faithful (d : Rat) (h i : Input) (y : Rat) :
    (step d h i y).top = PeopleO.cardTop i.vh i.t i.b ∧ (step d h i y).left = PeopleO.cardLeft i.vw i.x i.s := by
  unfold step
  by_cases hk : keep d h i y = true
  · simp only [hk, ite_true]
    simp only [keep, Bool.and_eq_true, decide_eq_true_eq] at hk
    obtain ⟨⟨⟨⟨⟨⟨⟨hvw, hvh⟩, hx⟩, hs⟩, ht⟩, hb⟩, hr⟩, -⟩ := hk
    refine ⟨?_, ?_⟩
    · unfold Held.top
      rw [cardTop_regime, cardTop_regime, ← hr, ht, hb]
      cases regime h.vh h.t h.b <;> simp only [shiftOf] <;> grind
    · simp [Held.left, hvw, hx, hs]
  · simp [hk]

/-- **No write between flips.** A kept frame writes no `left`, `top` or `width`. -/
theorem keep_no_write (d : Rat) (h i : Input) (y : Rat) (hk : keep d h i y = true) : (step d h i y).write = false := by
  simp [step, hk]

/-- **A rewrite is the faithful write.** An unkept frame writes and clears the translate. -/
theorem rewrite_clears (d : Rat) (h i : Input) (y : Rat) (hk : keep d h i y = false) :
    (step d h i y).write = true ∧ (step d h i y).tr = 0 := by
  simp [step, hk]

/-- **A kept frame in the unclamped regimes translates by the scroll delta.** The translate is `y0 - y`, that is
`-(y - y0)`. -/
theorem keep_translate (d : Rat) (h i : Input) (y : Rat) (hk : keep d h i y = true)
    (hr : regime h.vh h.t h.b ≠ .aboveClamped) : (step d h i y).tr = -(y - h.y0) := by
  simp [step, hk, shiftOf, hr, Held.delta]
  grind

/-- **In the clamped regime nothing moves.** A kept frame has translate `0`. -/
theorem keep_clamped (d : Rat) (h i : Input) (y : Rat) (hk : keep d h i y = true)
    (hr : regime h.vh h.t h.b = .aboveClamped) : (step d h i y).tr = 0 := by
  simp [step, hk, shiftOf, hr]

/-! ## Pixels and phase -/

/-- A face at document offset `bb` (top) with height `ht`, seen at scroll `y`: its rect top and bottom. -/
def rectTop (bb y : Rat) : Rat := bb - y
def rectBot (bb ht y : Rat) : Rat := bb + ht - y

/-- The faithful card top at scroll `y` for a face at document offset `bb` and height `ht`. -/
def topAt (vh bb ht y : Rat) : Rat := PeopleO.cardTop vh (rectTop bb y) (rectBot bb ht y)

/-- No flip between scroll positions `y0` and `y`: the same regime, and not the clamped one. -/
def noFlip (vh bb ht y0 y : Rat) : Prop :=
  regime vh (rectTop bb y0) (rectBot bb ht y0) = regime vh (rectTop bb y) (rectBot bb ht y) ∧
  regime vh (rectTop bb y0) (rectBot bb ht y0) ≠ .aboveClamped

/-- **Position equality (the pinned statement).** For whole-number scroll positions `y y0` and an integer device ratio
`d`, without a flip, the snapped card top at `y` is the snapped card top at `y0` minus the scroll delta, in device
pixels: `snapDev(cardTop(rect y)) = snapDev(cardTop(rect y0)) - (y - y0) * d`; and the phase is the same. -/
theorem snap_noFlip (d : Nat) (vh bb ht : Rat) (y0 y : Int) (hf : noFlip vh bb ht y0 y) :
    snapDev d (topAt vh bb ht y) = snapDev d (topAt vh bb ht y0) - (y - y0) * d ∧
    phase d (topAt vh bb ht y) = phase d (topAt vh bb ht y0) := by
  obtain ⟨hr, hc⟩ := hf
  have key : topAt vh bb ht y = topAt vh bb ht y0 + ((y0 - y : Int) : Rat) := by
    unfold topAt
    rw [cardTop_regime, cardTop_regime, ← hr]
    unfold rectTop rectBot at *
    cases hreg : regime vh (bb - y0) (bb + ht - y0) <;> simp only [hreg] at hc <;> grind
  have hk : ((y0 - y : Int) : Rat) * (d : Rat) = (((y0 - y) * d : Int) : Rat) := by push_cast; rfl
  rw [key]
  refine ⟨?_, phase_add d _ _ _ hk⟩
  rw [snapDev_add d _ _ ((y0 - y) * d) hk]
  grind

/-- **Clamped: the position is the same.** Where both positions are clamped the card top is `12` at both. -/
theorem clamped_same (vh bb ht y0 y : Rat) (h0 : regime vh (rectTop bb y0) (rectBot bb ht y0) = .aboveClamped)
    (h1 : regime vh (rectTop bb y) (rectBot bb ht y) = .aboveClamped) : topAt vh bb ht y = topAt vh bb ht y0 := by
  unfold topAt
  rw [cardTop_regime, cardTop_regime, h0, h1]

/-- **The pixel the compositor draws for a kept frame is the faithful pixel.** The held card top, snapped, plus the
translate in device pixels, equals the faithful snapped top, whenever the keep test passes and the shift is a whole
number `k` of device pixels (or the regime is the clamped one, translate `0`). -/
theorem keep_snap (d : Rat) (h i : Input) (y : Rat) (k : Int) (hk : keep d h i y = true)
    (hs : (step d h i y).tr * d = k) :
    snapDev d (PeopleO.cardTop i.vh i.t i.b) = snapDev d h.top + k := by
  have f := (step_faithful d h i y).1
  have : (step d h i y).top = h.top + (step d h i y).tr := by
    simp [step, hk]
  rw [← f, this]
  exact snapDev_add d _ _ k hs

/-- **A kept frame translates by whole device pixels.** -/
theorem keep_whole (d : Rat) (h i : Input) (y : Rat) (hk : keep d h i y = true) :
    ∃ k : Int, (step d h i y).tr * d = k := by
  by_cases hr : regime h.vh h.t h.b = .aboveClamped
  · exact ⟨0, by rw [keep_clamped d h i y hk hr]; simp⟩
  · have hk0 := hk
    simp only [keep, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at hk
    rcases hk.2 with hc | hi
    · exact absurd hc hr
    · obtain ⟨k, hk'⟩ := isInt_exists _ hi
      refine ⟨k, ?_⟩
      rw [keep_translate d h i y hk0 hr]
      have : -(y - h.y0) = h.delta y := by simp only [Held.delta]; grind
      rw [this]; exact hk'

/-- **Pixels for a kept frame, whole.** In every kept frame the faithful snapped card top is the held snapped top
plus the translate in device pixels, and that translate is a whole number of them. -/
theorem keep_pixel (d : Rat) (h i : Input) (y : Rat) (hk : keep d h i y = true) :
    ∃ k : Int, (step d h i y).tr * d = k ∧ snapDev d (PeopleO.cardTop i.vh i.t i.b) = snapDev d h.top + k := by
  obtain ⟨k, hk'⟩ := keep_whole d h i y hk
  exact ⟨k, hk', keep_snap d h i y k hk hk'⟩

#guard regime 900 300 356 == .below
#guard regime 900 600 656 == .aboveFree
#guard regime 900 400 456 == .aboveClamped

/-! ## Work and layers -/

/-- The scroll frames of the open card. -/
inductive Variant where
  | faithful | translate
deriving Repr, DecidableEq

/-- The properties one engine table uses for a position write and a translate write on the card. -/
structure Props (P : Type) where
  pos : P
  tr : P

/-- Chromium: `top` and `translate`. -/
def crProps : Props Chromium.CrProp := ⟨.css .top, .css .translate⟩

/-- WebKit: the inset of a fixed box (the movement-only shortcut is absolute only) and `translate`, which the table
files under `transform`. -/
def wkProps : Props WebKit.WkProp := ⟨.inset, .transform⟩

/-- One scroll frame with the card open, in the engine's change list. `kept` says the variant's keep test passed.
The faithful variant writes `top` in every frame; the variant writes `translate` in a kept frame, and `top` and
`translate` in a rewrite. The card's layer state is `ls`. -/
def frameOf {P : Type} (pr : Props P) (ls : LayerState) (v : Variant) (kept : Bool) : FrameIn P :=
  match v with
  | .faithful => ⟨1, 0, 0, 0, [⟨0, pr.pos, ls⟩], 0⟩
  | .translate =>
    if kept then ⟨1, 0, 0, 0, [⟨0, pr.tr, ls⟩], 0⟩
    else ⟨1, 0, 0, 0, [⟨0, pr.pos, ls⟩, ⟨0, pr.tr, ls⟩], 0⟩

/-- The layout passes of a frame under engine `E`. -/
def layoutPasses {P M : Type} (E : Engine P M) (pr : Props P) (ls : LayerState) (v : Variant) (kept : Bool) : Nat :=
  (frameWork E (frameOf pr ls v kept)).passes .layout

/-- **Faithful: one layout pass in every scroll frame**, on both engines, at any layer state. -/
theorem faithful_layout :
    (∀ ls, layoutPasses Chromium.chromium crProps ls .faithful true = 1) ∧
    (∀ ls, layoutPasses WebKit.webkit wkProps ls .faithful true = 1) := by
  constructor <;> intro ls <;> cases ls <;> decide

/-- **Non-flip frames: no layout pass**, on both engines, when the card has its own layer. -/
theorem translate_layout_kept :
    layoutPasses Chromium.chromium crProps .own .translate true = 0 ∧
    layoutPasses WebKit.webkit wkProps .own .translate true = 0 := by
  decide

/-- **Flip frames: one layout pass**, the faithful one. -/
theorem translate_layout_flip :
    layoutPasses Chromium.chromium crProps .own .translate false = 1 ∧
    layoutPasses WebKit.webkit wkProps .own .translate false = 1 := by
  decide

/-- **Not below the faithful in any stage on a kept frame** (own layer): the variant's frame work is at most the
faithful frame's, and strictly less. -/
theorem translate_work_lt :
    (frameWork Chromium.chromium (frameOf crProps .own .translate true)).lt
      (frameWork Chromium.chromium (frameOf crProps .own .faithful true)) ∧
    (frameWork WebKit.webkit (frameOf wkProps .own .translate true)).lt
      (frameWork WebKit.webkit (frameOf wkProps .own .faithful true)) := by
  decide

/-- The resident cost of the card: its one composited layer, `5070` kpx of backing store (existing, MEASURED in the
layer census). The variant adds no `will-change` and no 3D transform, so it adds none. -/
def residentOf (_ : Variant) : Resident := ⟨1, 5070⟩

/-- **Layer budget 0.** The variant's resident layers and backing equal the faithful ones. -/
theorem layer_budget_zero : residentOf .translate = residentOf .faithful := rfl

/-! ## Goldens -/

def jr (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]
def jn (q : Rat) : Json :=
  match (List.range 13).find? (fun e => (10 ^ e : Nat) % q.den == 0) with
  | some e => .num ⟨q.num * ((10 ^ e : Nat) / q.den : Nat), e⟩
  | none => jr q

def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

def heldJson (h : Held) : Json :=
  Json.mkObj [("vw", jn h.vw), ("vh", jn h.vh), ("x", jn h.x), ("s", jn h.s), ("t", jn h.t), ("b", jn h.b), ("y0", jn h.y0)]

def outJson (o : Out) : Json :=
  Json.mkObj [("write", .bool o.write), ("tr", jr o.tr), ("top", jr o.top), ("left", jr o.left)]

def regimeLines (_ : Unit := ()) : List String :=
  [600, 900].flatMap fun vh => [0, 12, 100, 464, 464.5, 500, 700].flatMap fun t =>
    [t + 56, t + 100].map fun b =>
      line "regime" [("vh", jn vh), ("t", jn t), ("b", jn b)] (.str (regime vh t b).name)

def snapLines (_ : Unit := ()) : List String :=
  [1, 2, 3 / 2].flatMap fun d => [0, 100.3, 100.5, 100.7, 99.75, -3.2].map fun v =>
    line "snapDev" [("d", jn d), ("v", jn v)] (.num ⟨snapDev d v, 0⟩)

/-- Held states: below the face, above and free, above and clamped; all at scroll `1000`. -/
def helds : List Held :=
  [⟨1280, 900, 400, 56, 300, 356, 1000⟩, ⟨1280, 900, 400, 56, 600, 656, 1000⟩, ⟨1280, 900, 400, 56, 400, 456, 1000⟩]

/-- The frame inputs: a scroll to `y`, an extra shift `dt` of the face (a layout shift), and a viewport width. -/
def mkInput (h : Held) (y dt vw : Rat) : Input :=
  { h with vw := vw, t := h.t + (h.y0 - y) + dt, b := h.b + (h.y0 - y) + dt, y0 := y }

def stepLines (_ : Unit := ()) : List String :=
  helds.flatMap fun h => [1, 2].flatMap fun d => [1000, 1003, 997, 1100, 1000.5, 1002.5, 1400, 1500].flatMap fun y =>
    [0, 5].flatMap fun dt => [1280, 1000].map fun vw =>
      let i := mkInput h y dt vw
      line "step" [("d", jn d), ("held", heldJson h), ("input", heldJson i), ("y", jn y)]
        (Json.mkObj [("keep", .bool (keep d h i y)), ("out", outJson (step d h i y))])

def engineName : Bool → String
  | true => "chromium"
  | false => "webkit"

def workLines (_ : Unit := ()) : List String :=
  [true, false].flatMap fun cr => [Variant.faithful, .translate].flatMap fun v => [true, false].map fun kept =>
    let n := if cr then layoutPasses Chromium.chromium crProps .own v kept else layoutPasses WebKit.webkit wkProps .own v kept
    line "layoutPasses" [("engine", .str (engineName cr)), ("variant", .str (if v == .faithful then "faithful" else "translate")),
      ("kept", .bool kept)] (.num ⟨n, 0⟩)

/-- The golden lines `packages/contracts/golden/parts/people-o-preview.jsonl`. -/
def lines (_ : Unit := ()) : List String := regimeLines () ++ snapLines () ++ stepLines () ++ workLines ()

def goldenText (_ : Unit := ()) : String := String.join ((lines ()).map (· ++ "\n"))

/-- Print the golden text, or with `--check <file>` compare it; exit 1 on a difference. -/
def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"people-o-preview golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"people-o-preview golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.PeopleOPreview
