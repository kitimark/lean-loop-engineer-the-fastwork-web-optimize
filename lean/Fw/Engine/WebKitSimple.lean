import Fw.Engine.WebKit
/-!
# WebKit simple container: when a composited box holds no backing store (task nav-fixed-size)
`RenderLayerBacking::isSimpleContainerCompositingLayer` at WebKit@862f17d, `WC` = `Source/WebCore`; extends `simple_layer` of `Fw.Engine.WebKit`.
-/
namespace Fw.Engine.WebKitSimple
open Fw.Engine.WebKit

/-- The style facts that make a box paint decorations (`RenderLayerBacking.cpp:3235-3243`); `backdrop-filter`, `clip-path`, `overflow` and a plain background colour are not among them. -/
structure Decor where
  border : Bool
  radius : Bool
  outline : Bool
  appearance : Bool
  shadow : Bool
  filter : Bool
  clip : Bool
deriving Repr, DecidableEq

/-- Whether any decoration is painted into the box's own layer (`RenderLayerBacking.cpp:3235-3243, 3426-3455`). -/
def paintsDecor (d : Decor) : Bool := d.border || d.radius || d.outline || d.appearance || d.shadow || d.filter || d.clip

/-- A composited box seen by the simple-container rule. -/
structure Box where
  decor : Decor
  barComposited : Bool
  otherPaint : Bool
deriving Repr, DecidableEq

/-- Whether descendants paint into the box's layer: a descendant that has no layer of its own does (`RenderLayerBacking.cpp:3465-3496`). -/
def descendantsPaint (b : Box) : Bool := !b.barComposited || b.otherPaint

/-- `drawsContent` of the box's layer. -/
def drawsContent (b : Box) : Bool := paintsDecor b.decor || descendantsPaint b

/-- The nav box of the original: rounded, with a composited bar assumed. -/
def navOrig : Box := ⟨⟨false, true, false, false, false, false, false⟩, true, false⟩

/-- The nav box under `nav:clip-box`: radius 0, the pill drawn by `clip-path`. -/
def navClip : Box := ⟨⟨false, false, false, false, false, false, false⟩, true, false⟩

/-- A box with no decoration and no painting descendant is a simple container with no backing store and no resize paint. -/
theorem simpleContainer_backing (b : Box) (hd : paintsDecor b.decor = false) (hbar : b.barComposited = true)
    (ho : b.otherPaint = false) (t : Bool) (a : Nat) :
    drawsContent b = false ∧ residentKpx (drawsContent b) false a = 0 ∧ resizePaint (drawsContent b) false t a = 0 := by
  have h : drawsContent b = false := by simp [drawsContent, descendantsPaint, hd, hbar, ho]
  simp [h, residentKpx, resizePaint, usesBacking]

/-- Without the composited bar the box draws: the premise `barComposited` is load-bearing. -/
theorem bar_premise_needed (b : Box) (hbar : b.barComposited = false) : drawsContent b = true := by
  simp [drawsContent, descendantsPaint, hbar]

/-- A rounded box draws its decoration, so the original nav keeps its backing store whatever its descendants do. -/
theorem navOrig_draws : drawsContent navOrig = true := by decide

/-- The nav under the flag draws nothing, given a composited bar and no other painting descendant. -/
theorem navClip_simple : drawsContent navClip = false := by decide

/-- Backing resident and resize paint of the two nav boxes: the original holds and repaints its area, the clipped box neither. -/
theorem navClip_vs_orig (t : Bool) (a : Nat) :
    residentKpx (drawsContent navClip) false a = 0 ∧ resizePaint (drawsContent navClip) false t a = 0 ∧
      residentKpx (drawsContent navOrig) false a = a ∧ resizePaint (drawsContent navOrig) false true a = a := by
  simp [navClip_simple, navOrig_draws, residentKpx, resizePaint, usesBacking]

end Fw.Engine.WebKitSimple
