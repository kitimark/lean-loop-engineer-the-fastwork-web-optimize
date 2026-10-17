import Fw.Measure.Zones
/-!
# Containment splits of trace slices and the N1 net rule (task n1-lean)

The Chromium counts lane (`packages/measure-chromium/src/trace.mjs`) counts main-thread trace slices
per frame. Two slice names are **split by containment**: a complete slice (`ph = "X"`) that lies
inside a complete slice of a given outer name is counted under its own type instead of the usual one
(research note 2026-10-17 "hittest-and-spk-q", sections 1.2 and 2.2):

| slice | inside | usual type | split type |
|---|---|---|---|
| `HitTest` | `OverlayInterstitialAdDetector::MaybeFireDetection` | `trace.HitTest` | `trace.HitTest.overlayAdDetector` |
| `StyleEngine::updateActiveStyleSheets` | `IsolatedSVGDocumentHost::IsolatedSVGDocumentHost` | `trace.N1.updateActiveStyleSheets` | `trace.N1.svgImageDocument` |

The first is Chromium's overlay-ad detector, which runs on a wall-clock cap (browser work, not page
work); the second is the first style-sheet update of each isolated SVG-image document (image
decoding, not a change to the page's sheets).

**N1 net rule.** The N1 read of a frame is made of the N1 types other than the SVG-image type:
`n1Gated = n1Keys \ n1Excluded`, where `n1Excluded` are the split types whose usual type is an N1 type.

Proved: the split only moves slices between the two types and loses or adds none
(`splitCounts_sum`); only complete slices move (`inside_ph`); without an outer slice nothing moves
(`splitCounts_no_outer`); the net N1 count is the gross count minus the SVG-image documents
(`n1_net`); the gated N1 keys exclude the SVG-image type and their counts do not see it
(`svg_not_gated`, `countIn_gated_svg`).

The container has no Lean, so `trace.mjs` keeps its own copy of the table and the containment test;
`packages/measure-chromium/test/pure.test.mjs` checks both against the `measure.splits` golden vectors.
-/
namespace Fw.Measure.Splits
open Fw.Measure

/-- One containment split: slices named `name` inside a complete slice named `within` count as
`key`, the others as `base`.

$$\mathrm{Split} = \Sigma^{*} \times \Sigma^{*} \times \Sigma^{*} \times \Sigma^{*}\ \ (\mathrm{name}, \mathrm{within}, \mathrm{base}, \mathrm{key})$$
-/
structure Split where
  name : String
  within : String
  base : String
  key : String
deriving Repr, DecidableEq

/-- The outer slice of the overlay-ad detector (`overlay_interstitial_ad_detector.cc:93@f842f52`).

$$\mathrm{detector} = \texttt{"OverlayInterstitialAdDetector::MaybeFireDetection"}$$
-/
def detector : String := "OverlayInterstitialAdDetector::MaybeFireDetection"

/-- The outer slice of an isolated SVG-image document.

$$\mathrm{svgHost} = \texttt{"IsolatedSVGDocumentHost::IsolatedSVGDocumentHost"}$$
-/
def svgHost : String := "IsolatedSVGDocumentHost::IsolatedSVGDocumentHost"

/-- The type of a style-sheet update inside an SVG-image document.

$$\mathrm{svgKey} = \texttt{"trace.N1.svgImageDocument"}$$
-/
def svgKey : String := "trace.N1.svgImageDocument"

/-- **The split table** (the TS `SPLITS` of `trace.mjs` must equal it).

$$\mathrm{splits} = [(\texttt{HitTest}, \mathrm{detector}, \texttt{trace.HitTest}, \texttt{trace.HitTest.overlayAdDetector}),\ (\texttt{StyleEngine::updateActiveStyleSheets}, \mathrm{svgHost}, \texttt{trace.N1.updateActiveStyleSheets}, \mathrm{svgKey})]$$
-/
def splits : List Split :=
  [⟨"HitTest", detector, "trace.HitTest", "trace.HitTest.overlayAdDetector"⟩,
   ⟨"StyleEngine::updateActiveStyleSheets", svgHost, "trace.N1.updateActiveStyleSheets", svgKey⟩]

/-- One main-thread trace slice: name, phase, start time and duration (µs; a missing duration is 0).

$$\mathrm{Slice} = \Sigma^{*} \times \Sigma^{*} \times \mathbb{Z} \times \mathbb{Z}\ \ (\mathrm{name}, \mathrm{ph}, \mathrm{ts}, \mathrm{dur})$$
-/
structure Slice where
  name : String
  ph : String
  ts : Int
  dur : Int
deriving Repr, DecidableEq

/-- The phases a main-thread slice is counted in (begin, complete, the instants and `R`).

$$\operatorname{counted}(\mathit{ph}) \iff \mathit{ph} \in \{\texttt{B}, \texttt{X}, \texttt{I}, \texttt{i}, \texttt{R}\}$$
-/
def counted (ph : String) : Bool := ["B", "X", "I", "i", "R"].contains ph

/-- The intervals `[ts, ts + dur]` of the complete slices named `w`.

$$\operatorname{outers}(w, E) = [\, (s.\mathrm{ts},\ s.\mathrm{ts} + s.\mathrm{dur}) \,]_{s \in E,\ s.\mathrm{name} = w,\ s.\mathrm{ph} = \texttt{X}}$$
-/
def outers (w : String) (evs : List Slice) : List (Int × Int) :=
  (evs.filter fun e => e.name == w && e.ph == "X").map fun e => (e.ts, e.ts + e.dur)

/-- A slice is inside one of the intervals: it is complete and lies within the interval, ends
included.

$$\operatorname{inside}(O, s) \iff s.\mathrm{ph} = \texttt{X} \ \land\ \exists (a, b) \in O:\ a \le s.\mathrm{ts} \ \land\ s.\mathrm{ts} + s.\mathrm{dur} \le b$$
-/
def inside (os : List (Int × Int)) (s : Slice) : Bool :=
  s.ph == "X" && os.any fun o => decide (o.1 ≤ s.ts) && decide (s.ts + s.dur ≤ o.2)

/-- The type a slice of the split's name is counted under.

$$\operatorname{typeOf}(\sigma, E, s) = \begin{cases} \sigma.\mathrm{key} & \operatorname{inside}(\operatorname{outers}(\sigma.\mathrm{within}, E), s) \\ \sigma.\mathrm{base} & \text{otherwise} \end{cases}$$
-/
def typeOf (sp : Split) (evs : List Slice) (s : Slice) : String :=
  if inside (outers sp.within evs) s then sp.key else sp.base

/-- The counted slices of the split's name.

$$\operatorname{mine}(\sigma, E) = [\, s \in E \mid s.\mathrm{name} = \sigma.\mathrm{name} \land \operatorname{counted}(s.\mathrm{ph}) \,]$$
-/
def mine (sp : Split) (evs : List Slice) : List Slice :=
  evs.filter fun s => s.name == sp.name && counted s.ph

/-- **The split counts** of one split over a list of slices: (usual type, split type).

$$\operatorname{split}(\sigma, E) = \Big(\big|[\, s \in \operatorname{mine}(\sigma, E) \mid \lnot \operatorname{inside}(O, s) \,]\big|,\ \big|[\, s \in \operatorname{mine}(\sigma, E) \mid \operatorname{inside}(O, s) \,]\big|\Big),\quad O = \operatorname{outers}(\sigma.\mathrm{within}, E)$$
-/
def splitCounts (sp : Split) (evs : List Slice) : Nat × Nat :=
  (((mine sp evs).filter fun s => !inside (outers sp.within evs) s).length,
   ((mine sp evs).filter fun s => inside (outers sp.within evs) s).length)

/-- The split counts of every split as count entries (usual type, then split type).

$$\operatorname{splitTable}(E) = [\, (\sigma.\mathrm{base}, \operatorname{split}(\sigma, E)_1),\ (\sigma.\mathrm{key}, \operatorname{split}(\sigma, E)_2) \,]_{\sigma \in \mathrm{splits}}$$
-/
def splitTable (evs : List Slice) : Counts :=
  splits.flatMap fun sp =>
    let c := splitCounts sp evs
    [(sp.base, (c.1 : Int)), (sp.key, (c.2 : Int))]

/-! ## The N1 keys and the net rule -/

/-- The N1 types the lane records (zero-filled in every frame), in the order of `trace.mjs` `N1_KEYS`.

$$\mathrm{n1Keys} = [\texttt{updateActiveStyleSheets}, \texttt{scheduleInvalidationsForRuleSets}, \texttt{fontUpdateInvalidation}, \texttt{svgImageDocument}]\ \ (\text{each prefixed } \texttt{trace.N1.})$$
-/
def n1Keys : List String :=
  ["trace.N1.updateActiveStyleSheets", "trace.N1.scheduleInvalidationsForRuleSets",
   "trace.N1.fontUpdateInvalidation", svgKey]

/-- The N1 types that do not count toward N1: the split types whose usual type is an N1 type.

$$\mathrm{n1Excluded} = [\, \sigma.\mathrm{key} \,]_{\sigma \in \mathrm{splits},\ \sigma.\mathrm{base} \in \mathrm{n1Keys}}$$
-/
def n1Excluded : List String := (splits.filter fun sp => n1Keys.contains sp.base).map (·.key)

/-- **The gated N1 types**: the N1 types that are not excluded.

$$\mathrm{n1Gated} = [\, k \in \mathrm{n1Keys} \mid k \notin \mathrm{n1Excluded} \,]$$
-/
def n1Gated : List String := n1Keys.filter fun k => !n1Excluded.contains k

#guard n1Excluded == [svgKey]
#guard n1Gated == ["trace.N1.updateActiveStyleSheets", "trace.N1.scheduleInvalidationsForRuleSets",
  "trace.N1.fontUpdateInvalidation"]
#guard counted "X" && counted "B" && !counted "E" && !counted "M"
#guard splitCounts ⟨"h", "o", "b", "k"⟩
    [⟨"o", "X", 100, 50⟩, ⟨"h", "X", 110, 10⟩, ⟨"h", "X", 140, 20⟩, ⟨"h", "B", 120, 0⟩, ⟨"h", "E", 125, 0⟩,
     ⟨"h", "X", 150, 0⟩] == (2, 2)
#guard splitCounts ⟨"h", "o", "b", "k"⟩ [⟨"o", "B", 100, 50⟩, ⟨"h", "X", 110, 10⟩] == (1, 0)
#guard splitTable [⟨detector, "X", 0, 30⟩, ⟨"HitTest", "X", 5, 20⟩, ⟨"HitTest", "X", 40, 1⟩] ==
  [("trace.HitTest", 1), ("trace.HitTest.overlayAdDetector", 1), ("trace.N1.updateActiveStyleSheets", 0),
   (svgKey, 0)]

/-! ## Proofs -/

/-- Only complete slices are inside an interval.

$$\forall O, s:\ \operatorname{inside}(O, s) \;\Rightarrow\; s.\mathrm{ph} = \texttt{X}$$
-/
theorem inside_ph {os : List (Int × Int)} {s : Slice} (h : inside os s = true) : s.ph = "X" := by
  simp only [inside, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1

/-- Nothing is inside an empty list of intervals.

$$\forall s:\ \lnot \operatorname{inside}([\,], s)$$
-/
theorem inside_nil (s : Slice) : inside [] s = false := by simp [inside]

/-- **Conservation.** The split moves slices between the two types and loses or adds none.

$$\forall \sigma, E:\ \operatorname{split}(\sigma, E)_1 + \operatorname{split}(\sigma, E)_2 = |\operatorname{mine}(\sigma, E)|$$
-/
theorem splitCounts_sum (sp : Split) (evs : List Slice) :
    (splitCounts sp evs).1 + (splitCounts sp evs).2 = (mine sp evs).length := by
  simp only [splitCounts]
  generalize mine sp evs = l
  induction l with
  | nil => rfl
  | cons s l ih =>
    by_cases h : inside (outers sp.within evs) s = true
    · simp [h]; omega
    · simp [h]; omega

/-- Without a complete outer slice nothing is split off.

$$\forall \sigma, E:\ \operatorname{outers}(\sigma.\mathrm{within}, E) = [\,] \;\Rightarrow\; \operatorname{split}(\sigma, E)_2 = 0 \ \land\ \operatorname{split}(\sigma, E)_1 = |\operatorname{mine}(\sigma, E)|$$
-/
theorem splitCounts_no_outer (sp : Split) (evs : List Slice) (h : outers sp.within evs = []) :
    (splitCounts sp evs).2 = 0 ∧ (splitCounts sp evs).1 = (mine sp evs).length := by
  have hs := splitCounts_sum sp evs
  have h2 : (splitCounts sp evs).2 = 0 := by
    simp [splitCounts, h, inside_nil]
  exact ⟨h2, by omega⟩

/-- The split type of a split slice: a slice counted under `key` is complete and inside an outer
slice.

$$\forall \sigma, E, s:\ \sigma.\mathrm{key} \ne \sigma.\mathrm{base} \land \operatorname{typeOf}(\sigma, E, s) = \sigma.\mathrm{key} \;\Rightarrow\; s.\mathrm{ph} = \texttt{X} \ \land\ \operatorname{inside}(\operatorname{outers}(\sigma.\mathrm{within}, E), s)$$
-/
theorem typeOf_key {sp : Split} {evs : List Slice} {s : Slice} (hne : sp.key ≠ sp.base)
    (h : typeOf sp evs s = sp.key) : s.ph = "X" ∧ inside (outers sp.within evs) s = true := by
  unfold typeOf at h
  by_cases hi : inside (outers sp.within evs) s = true
  · exact ⟨inside_ph hi, hi⟩
  · simp [hi] at h; exact absurd h.symm hne

/-- The usual and split types of the table are pairwise different (no two splits share a type).

$$[\, \sigma.\mathrm{base}, \sigma.\mathrm{key} \,]_{\sigma \in \mathrm{splits}} \text{ has no duplicates}$$
-/
theorem splits_types_nodup : (splits.flatMap fun sp => [sp.base, sp.key]).Nodup := by
  simp [splits, detector, svgHost, svgKey]

/-- The SVG-image split is the only split of an N1 type.

$$\mathrm{n1Excluded} = [\mathrm{svgKey}]$$
-/
theorem n1Excluded_eq : n1Excluded = [svgKey] := by
  simp [n1Excluded, splits, n1Keys, svgKey]

/-- The SVG-image type is not gated.

$$\mathrm{svgKey} \notin \mathrm{n1Gated}$$
-/
theorem svg_not_gated : svgKey ∉ n1Gated := by
  simp [n1Gated, n1Excluded_eq]

/-- **The N1 net rule.** For the style-sheet split, the gated count (usual type) is the gross count of
`updateActiveStyleSheets` slices minus those inside SVG-image documents.

$$\forall E:\ \operatorname{split}(\sigma_{\mathrm{svg}}, E)_1 = |\operatorname{mine}(\sigma_{\mathrm{svg}}, E)| \mathbin{\dot-} \operatorname{split}(\sigma_{\mathrm{svg}}, E)_2,\quad \sigma_{\mathrm{svg}} = (\texttt{StyleEngine::updateActiveStyleSheets}, \mathrm{svgHost}, \texttt{trace.N1.updateActiveStyleSheets}, \mathrm{svgKey})$$
-/
theorem n1_net (evs : List Slice) :
    let sp : Split := ⟨"StyleEngine::updateActiveStyleSheets", svgHost, "trace.N1.updateActiveStyleSheets", svgKey⟩
    (splitCounts sp evs).1 = (mine sp evs).length - (splitCounts sp evs).2 := by
  intro sp
  have := splitCounts_sum sp evs
  omega

/-- A gated N1 count does not see an SVG-image entry.

$$\forall C, v, k:\ k \in \mathrm{n1Gated} \;\Rightarrow\; \operatorname{countIn}((\mathrm{svgKey}, v) :: C, k) = \operatorname{countIn}(C, k)$$
-/
theorem countIn_gated_svg (C : Counts) (v : Int) {k : String} (hk : k ∈ n1Gated) :
    countIn ((svgKey, v) :: C) k = countIn C k := by
  have hne : svgKey ≠ k := fun h => svg_not_gated (h ▸ hk)
  simp [countIn, hne]

end Fw.Measure.Splits
