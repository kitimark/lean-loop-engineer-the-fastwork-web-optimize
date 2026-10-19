import Fw.Measure.Viewport
/-!
# When two baselines may be compared (task faithful-checks-rerun)

The PL5 verdict (`Fw.Faithful.zoneVerdict`) says whether a rewrite baseline R lies inside the bands of the original
baseline A. It says nothing about whether R and A measured the same thing. The first faithful run compared a rewrite that
had been measured at a 645 x 1398 layout viewport (run 39130842058) with an original measured at 430 x 932: every cell
was scored and the numbers meant nothing.

`comparable a r` decides it before any cell is scored. Each baseline carries a `Meta`: the profile, the preset, the zone
height, the browser, the profile viewport (width, height, device pixel ratio, mobile, touch) and the viewport the page
reported after load (`observed`, `none` when the run did not record it). The pair is comparable exactly when all of
profile, preset, zone height, browser and the profile viewport agree, the candidate `r` recorded an observed viewport,
and that viewport (and A's, when A recorded one) equals the profile viewport (`Fw.Measure.Viewport.viewportFaithful`).
Otherwise the answer names the first failing field, in the order of `fieldNames`. The same check applies to the control
(the original of the same CI run) against A.

Limit: the frozen original baseline A was measured before the observed viewport was recorded, so its `observed` is `none`
and only its declared fields are compared; the control of every run is observed.
-/
namespace Fw.Faithful
open Fw.Measure.Viewport

/-- What a baseline says about how it was measured.

$$\mathrm{Meta} = \Sigma^{*3} \times \mathbb{N} \times \mathbb{N}^2 \times \mathbb{Q} \times \mathbb{B}^2 \times (\mathbb{N}^2)_{\bot}$$
-/
structure Meta where
  profile : String
  preset : String
  browser : String
  zoneHeightPx : Nat
  width : Nat
  height : Nat
  dpr : Rat
  mobile : Bool
  touch : Bool
  observed : Option Size
deriving DecidableEq

/-- The profile viewport of a baseline as a size.

$$\mathrm{vp}(m) = (m_w, m_h)$$
-/
def Meta.size (m : Meta) : Size := ⟨m.width, m.height⟩

/-- The declared viewport tuple of two baselines agrees.

$$\mathrm{sameVp}(a, r) \iff a_w = r_w \land a_h = r_h \land a_{dpr} = r_{dpr} \land a_{mobile} = r_{mobile} \land a_{touch} = r_{touch}$$
-/
def sameViewport (a r : Meta) : Bool :=
  decide (a.width = r.width) && decide (a.height = r.height) && decide (a.dpr = r.dpr) &&
    decide (a.mobile = r.mobile) && decide (a.touch = r.touch)

/-- A baseline whose page reported its viewport reported the profile viewport; one that did not report passes (the
reference side) or fails (the candidate side, `required`).

$$\mathrm{seen}_{\mathrm{req}}(m) = \begin{cases} \mathrm{faithful}(m_{vp}, o) & m_{obs} = o \\ \lnot\,\mathrm{req} & m_{obs} = \bot \end{cases}$$
-/
def seen (required : Bool) (m : Meta) : Bool :=
  match m.observed with
  | some o => viewportFaithful m.size o
  | none => !required

/-- The viewport of the pair is usable: declared tuples agree, A's observation (if any) and R's (required) are the profile
viewport.

$$\mathrm{vpOk}(a, r) = \mathrm{sameVp}(a, r) \land \mathrm{seen}_{\mathrm{false}}(a) \land \mathrm{seen}_{\mathrm{true}}(r)$$
-/
def viewportOk (a r : Meta) : Bool :=
  sameViewport a r && seen false a && seen true r

/-- The checks in the order they are reported: field name and whether it holds.

$$\mathrm{checks}(a, r) = [(\mathtt{profile}, a_{prof} = r_{prof}), (\mathtt{preset}, \ldots), (\mathtt{zoneHeightPx}, \ldots), (\mathtt{browser}, \ldots), (\mathtt{viewport}, \mathrm{vpOk}(a, r))]$$
-/
def checks (a r : Meta) : List (String × Bool) :=
  [("profile", decide (a.profile = r.profile)), ("preset", decide (a.preset = r.preset)),
   ("zoneHeightPx", decide (a.zoneHeightPx = r.zoneHeightPx)), ("browser", decide (a.browser = r.browser)),
   ("viewport", viewportOk a r)]

/-- The field names a refusal can carry.

$$F = [\mathtt{profile}, \mathtt{preset}, \mathtt{zoneHeightPx}, \mathtt{browser}, \mathtt{viewport}]$$
-/
def fieldNames : List String := ["profile", "preset", "zoneHeightPx", "browser", "viewport"]

/-- `none` when the pair is comparable, else the first field that fails.

$$\mathrm{cmp}(a, r) = \bot \iff \text{all checks hold, else the first failing field}$$
-/
def comparable (a r : Meta) : Option String :=
  ((checks a r).find? (fun c => !c.2)).map (·.1)

/-- The pair is comparable exactly when every field agrees and the viewport is usable.

$$\mathrm{cmp}(a, r) = \bot \iff a_{prof} = r_{prof} \land a_{preset} = r_{preset} \land a_{zone} = r_{zone} \land a_{br} = r_{br} \land \mathrm{vpOk}(a, r)$$
-/
theorem comparable_iff (a r : Meta) :
    comparable a r = none ↔
      a.profile = r.profile ∧ a.preset = r.preset ∧ a.zoneHeightPx = r.zoneHeightPx ∧ a.browser = r.browser ∧
        viewportOk a r = true := by
  unfold comparable checks
  simp [List.find?_eq_none]

/-- A refusal names a field of the list and that field fails.

$$\mathrm{cmp}(a, r) = f \Rightarrow f \in \mathrm{fieldNames} \land (f, \bot) \in \mathrm{checks}(a, r)$$
-/
theorem refusal_sound (a r : Meta) (f : String) (h : comparable a r = some f) :
    f ∈ fieldNames ∧ (f, false) ∈ checks a r := by
  unfold comparable at h
  cases hf : (checks a r).find? (fun c => !c.2) with
  | none => simp [hf] at h
  | some c =>
    simp only [hf, Option.map_some, Option.some.injEq] at h
    have hm := List.mem_of_find?_eq_some hf
    have hp := List.find?_some hf
    have hc : c.2 = false := by simpa using hp
    subst h
    refine ⟨?_, ?_⟩
    · unfold checks at hm
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
      unfold fieldNames
      rcases hm with h | h | h | h | h <;> subst h <;> simp
    · rw [← hc]; exact hm

/-- A candidate whose page reported another viewport than its profile is refused, whatever else agrees.

$$o \ne \mathrm{vp}(r) \Rightarrow \mathrm{cmp}(a, r) \ne \bot \quad (r_{obs} = o)$$
-/
theorem unfaithful_refused (a r : Meta) (o : Size) (h : r.observed = some o) (hne : o ≠ r.size) :
    comparable a r ≠ none := by
  intro hc
  have := ((comparable_iff a r).1 hc).2.2.2.2
  unfold viewportOk seen at this
  rw [h] at this
  have h2 : viewportFaithful r.size o = true := (by simpa using this : _ ∧ _).2
  exact hne ((accepts_iff _ _).1 h2)

/-- A candidate that did not record its observed viewport is refused.

$$r_{obs} = \bot \Rightarrow \mathrm{cmp}(a, r) \ne \bot$$
-/
theorem unobserved_refused (a r : Meta) (h : r.observed = none) : comparable a r ≠ none := by
  intro hc
  have := ((comparable_iff a r).1 hc).2.2.2.2
  unfold viewportOk seen at this
  rw [h] at this
  simp at this

/-- A baseline is comparable with itself when its page reported the profile viewport.

$$m_{obs} = (m_w, m_h) \Rightarrow \mathrm{cmp}(m, m) = \bot$$
-/
theorem comparable_self (m : Meta) (h : m.observed = some m.size) : comparable m m = none := by
  rw [comparable_iff]
  simp [viewportOk, sameViewport, seen, h, accepts_self]

/-- The 645 x 1398 run of the first faithful check is refused as `viewport`. -/
example :
    comparable
      ⟨"swipe-v1", "original", "HeadlessChrome/156.0.8078.4", 500, 430, 932, 3, true, true, none⟩
      ⟨"swipe-v1", "original", "HeadlessChrome/156.0.8078.4", 500, 430, 932, 3, true, true, some ⟨645, 1398⟩⟩
      = some "viewport" := by decide

end Fw.Faithful
