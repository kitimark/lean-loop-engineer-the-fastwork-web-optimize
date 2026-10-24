import Lean.Data.Json
/-! Proof note: research/notes/2026/10-2x-earn-webkit-parity.md. WebKit@862f17d (`WC` = `Source/WebCore`), Chromium@f842f52 (`CA` = `third_party/blink/renderer/core/animation`). -/
namespace Fw.Engine.TransitionStart

inductive CssProp where
  | maxWidth | opacity | paddingTop | paddingRight | paddingBottom | paddingLeft
  | paddingInlineStart | paddingInlineEnd | rowGap | columnGap
  deriving DecidableEq, Repr

inductive Dir where
  | ltr | rtl
  deriving DecidableEq, Repr

inductive Entry where
  | prop (p : CssProp)
  | paddingInline
  | padding
  | gap
  | all
  deriving DecidableEq, Repr

inductive Eng where
  | chromium | webkit
  deriving DecidableEq, Repr

def CssProp.isLogical : CssProp → Bool
  | .paddingInlineStart | .paddingInlineEnd => true
  | _ => false

def CssProp.phys (d : Dir) : CssProp → CssProp
  | .paddingInlineStart => if d = .ltr then .paddingLeft else .paddingRight
  | .paddingInlineEnd => if d = .ltr then .paddingRight else .paddingLeft
  | p => p

def allProps : List CssProp :=
  [.maxWidth, .opacity, .paddingTop, .paddingRight, .paddingBottom, .paddingLeft, .rowGap, .columnGap]

def Entry.longhands : Entry → List CssProp
  | .prop p => [p]
  | .paddingInline => [.paddingInlineStart, .paddingInlineEnd]
  | .padding => [.paddingTop, .paddingRight, .paddingBottom, .paddingLeft]
  | .gap => [.rowGap, .columnGap]
  | .all => []

/-- **Chromium: the examined properties of an entry.** Each longhand of a shorthand is made physical with `ToPhysical`
(`CA/css/css_animations.cc:2993-3007`); `all` lists the physical set (`:3056-3072`). -/
def crKeys (d : Dir) : Entry → List CssProp
  | .all => allProps
  | e => e.longhands.map (CssProp.phys d)

/-- **WebKit: the property bits an entry sets** (`compileTransitionPropertiesInStyle`, `WC/style/Styleable.cpp:535-566`).
A longhand is resolved to physical (`:563-564`); the longhands of a shorthand are set as they are listed (`:560-562`),
so `padding-inline` sets the two logical bits. `all` adds the changed physical properties (`:790-815`). -/
def wkBits (d : Dir) : Entry → List CssProp
  | .prop p => [p.phys d]
  | .all => allProps
  | e => e.longhands

/-- **WebKit: whether an entry matches a property** (`transitionMatchesProperty`, `WC/style/Styleable.cpp:519-532`):
the entry's property, or a longhand of its shorthand, resolved to physical, equals the property. -/
def wkMatches (d : Dir) : Entry → CssProp → Bool
  | .all, _ => true
  | e, p => (e.longhands.map (CssProp.phys d)).contains p

/-- Whether WebKit has an interpolation wrapper for the property. The logical longhands have none: the generated map
holds `nullptr` for them, "handled via resolution to physical" (`WC/css/scripts/process-css-properties.py:5956`). -/
def hasWrapper (p : CssProp) : Bool := !p.isLogical

def crStarts (d : Dir) (l : List Entry) (changed : CssProp → Bool) (p : CssProp) : Bool :=
  (l.flatMap (crKeys d)).contains p && changed p

/-- **WebKit starts a transition on `p`:** a bit of `p` is set, an entry matches it, and the wrapper sees a difference.
Without a wrapper `Style::Interpolation::equals` answers true (`WC/style/StyleInterpolation.cpp:281-289`), so nothing starts. -/
def wkStarts (d : Dir) (l : List Entry) (changed : CssProp → Bool) (p : CssProp) : Bool :=
  (l.flatMap (wkBits d)).contains p && l.any (fun e => wkMatches d e p) && hasWrapper p && changed p

def starts : Eng → Dir → List Entry → (CssProp → Bool) → CssProp → Bool
  | .chromium => crStarts
  | .webkit => wkStarts

theorem logical_noWrapper (p : CssProp) (h : p.isLogical = true) : hasWrapper p = false := by
  simp [hasWrapper, h]

theorem wk_paddingInline_never (d : Dir) (changed : CssProp → Bool) (p : CssProp) :
    wkStarts d [.paddingInline] changed p = false := by
  cases p <;> simp [wkStarts, hasWrapper, CssProp.isLogical, wkBits, Entry.longhands]

theorem cr_paddingInline_ltr (changed : CssProp → Bool) :
    crStarts .ltr [.paddingInline] changed .paddingLeft = changed .paddingLeft ∧
    crStarts .ltr [.paddingInline] changed .paddingRight = changed .paddingRight := by
  simp [crStarts, crKeys, Entry.longhands, CssProp.phys]

theorem cr_paddingInline_rtl (changed : CssProp → Bool) :
    crStarts .rtl [.paddingInline] changed .paddingLeft = changed .paddingLeft ∧
    crStarts .rtl [.paddingInline] changed .paddingRight = changed .paddingRight := by
  simp [crStarts, crKeys, Entry.longhands, CssProp.phys]

theorem wk_inlineLonghands_ltr (changed : CssProp → Bool) :
    wkStarts .ltr [.prop .paddingInlineStart, .prop .paddingInlineEnd] changed .paddingLeft = changed .paddingLeft ∧
    wkStarts .ltr [.prop .paddingInlineStart, .prop .paddingInlineEnd] changed .paddingRight = changed .paddingRight := by
  simp [wkStarts, wkBits, wkMatches, hasWrapper, CssProp.isLogical, CssProp.phys, Entry.longhands]

theorem wk_physicalPair (d : Dir) (changed : CssProp → Bool) :
    wkStarts d [.prop .paddingLeft, .prop .paddingRight] changed .paddingLeft = changed .paddingLeft ∧
    wkStarts d [.prop .paddingLeft, .prop .paddingRight] changed .paddingRight = changed .paddingRight := by
  simp [wkStarts, wkBits, wkMatches, hasWrapper, CssProp.isLogical, CssProp.phys, Entry.longhands]

theorem wk_padding_left (d : Dir) (changed : CssProp → Bool) :
    wkStarts d [.padding] changed .paddingLeft = changed .paddingLeft := by
  simp [wkStarts, wkBits, wkMatches, hasWrapper, CssProp.isLogical, CssProp.phys, Entry.longhands]

theorem wk_all (d : Dir) (changed : CssProp → Bool) (p : CssProp) (hp : p.isLogical = false) :
    wkStarts d [.all] changed p = changed p := by
  cases p <;> simp_all [wkStarts, wkBits, wkMatches, hasWrapper, CssProp.isLogical, allProps]

theorem phys_physical (d : Dir) (p : CssProp) : (p.phys d).isLogical = false := by
  cases p <;> cases d <;> simp [CssProp.phys, CssProp.isLogical]

theorem crKeys_physical (d : Dir) (e : Entry) (p : CssProp) (h : p ∈ crKeys d e) : p.isLogical = false := by
  cases e with
  | all =>
    simp only [crKeys, allProps, List.mem_cons, List.not_mem_nil, or_false] at h
    rcases h with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> rfl
  | prop q => obtain ⟨r, _, rfl⟩ := List.mem_map.mp h; exact phys_physical d r
  | paddingInline => obtain ⟨r, _, rfl⟩ := List.mem_map.mp h; exact phys_physical d r
  | padding => obtain ⟨r, _, rfl⟩ := List.mem_map.mp h; exact phys_physical d r
  | gap => obtain ⟨r, _, rfl⟩ := List.mem_map.mp h; exact phys_physical d r

theorem cr_logical_false (d : Dir) (l : List Entry) (changed : CssProp → Bool) (p : CssProp) (h : p.isLogical = true) :
    crStarts d l changed p = false := by
  have hn : (l.flatMap (crKeys d)).contains p = false := by
    cases hc : (l.flatMap (crKeys d)).contains p
    · rfl
    · obtain ⟨e, _, he⟩ := List.mem_flatMap.mp (List.contains_iff_mem.mp hc)
      have := crKeys_physical d e p he
      rw [h] at this
      exact absurd this (by decide)
  rw [crStarts, hn]
  rfl

theorem wkBits_eq (d : Dir) (e : Entry) (h : e ≠ .paddingInline) : wkBits d e = crKeys d e := by
  cases e with
  | prop p => simp [wkBits, crKeys, Entry.longhands]
  | paddingInline => exact absurd rfl h
  | padding => simp [wkBits, crKeys, Entry.longhands, CssProp.phys]
  | gap => simp [wkBits, crKeys, Entry.longhands, CssProp.phys]
  | all => simp [wkBits, crKeys]

theorem wkMatches_eq (d : Dir) (e : Entry) (h : e ≠ .paddingInline) (p : CssProp) (hp : p.isLogical = false) :
    wkMatches d e p = (crKeys d e).contains p := by
  cases e with
  | paddingInline => exact absurd rfl h
  | all => cases p <;> simp_all [wkMatches, crKeys, allProps, CssProp.isLogical]
  | _ => simp [wkMatches, crKeys]

theorem engines_agree_without_paddingInline (d : Dir) (l : List Entry) (hl : ∀ e ∈ l, e ≠ .paddingInline)
    (changed : CssProp → Bool) (p : CssProp) : wkStarts d l changed p = crStarts d l changed p := by
  by_cases hp : p.isLogical = true
  · rw [cr_logical_false d l changed p hp]
    simp [wkStarts, hasWrapper, hp]
  · have hp' : p.isLogical = false := by simpa using hp
    have hb : l.flatMap (wkBits d) = l.flatMap (crKeys d) := by
      induction l with
      | nil => rfl
      | cons e t ih =>
        simp only [List.flatMap_cons]
        rw [wkBits_eq d e (hl e (by simp)), ih (fun x hx => hl x (by simp [hx]))]
    have hm : l.any (fun e => wkMatches d e p) = (l.flatMap (crKeys d)).contains p := by
      apply Bool.eq_iff_iff.mpr
      simp only [List.any_eq_true, List.contains_iff_mem, List.mem_flatMap]
      constructor
      · rintro ⟨e, he, hme⟩
        exact ⟨e, he, by simpa [wkMatches_eq d e (hl e he) p hp'] using hme⟩
      · rintro ⟨e, he, hme⟩
        exact ⟨e, he, by simpa [wkMatches_eq d e (hl e he) p hp'] using hme⟩
    simp [wkStarts, crStarts, hb, hm, hasWrapper, hp']

structure Item where
  entry : Entry
  dur : Nat
  delay : Nat
  deriving DecidableEq, Repr

def entries (l : List Item) : List Entry := l.map (·.entry)

def earnItems (opDur opDelay : Nat) (pad : List Entry) : List Item :=
  ⟨.prop .maxWidth, 680, 0⟩ :: ⟨.prop .opacity, opDur, opDelay⟩ :: pad.map fun e => ⟨e, 680, 0⟩

def earnBase : List Item := earnItems 320 120 [.paddingInline]

def earnHeroPill : List Item := earnItems 200 0 [.paddingInline]

def fixLogical : List Item := earnItems 200 0 [.prop .paddingInlineStart, .prop .paddingInlineEnd]

def fixPhysical : List Item := earnItems 200 0 [.prop .paddingLeft, .prop .paddingRight]

def fixPadding : List Item := earnItems 200 0 [.padding]

def heroChanged (p : CssProp) : Bool := [CssProp.maxWidth, .opacity, .paddingLeft, .paddingRight].contains p

def startedSet (e : Eng) (d : Dir) (l : List Item) (changed : CssProp → Bool) : List CssProp :=
  allProps.filter (starts e d (entries l) changed)

theorem hero_entry_chromium (d : Dir) :
    startedSet .chromium d earnHeroPill heroChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

theorem hero_entry_webkit (d : Dir) :
    startedSet .webkit d earnHeroPill heroChanged = [.maxWidth, .opacity] := by
  cases d <;> decide

theorem base_same_set (e : Eng) (d : Dir) (c : CssProp → Bool) :
    startedSet e d earnBase c = startedSet e d earnHeroPill c := by
  cases e <;> cases d <;> rfl

theorem fixLogical_webkit_eq_chromium (d : Dir) (c : CssProp → Bool) :
    startedSet .webkit d fixLogical c = startedSet .chromium d fixLogical c := by
  unfold startedSet
  apply List.filter_congr
  intro p _
  exact engines_agree_without_paddingInline d _ (by cases d <;> decide) c p

theorem fixLogical_chromium_unchanged (d : Dir) (c : CssProp → Bool) :
    startedSet .chromium d fixLogical c = startedSet .chromium d earnHeroPill c := by
  cases d <;> (unfold startedSet; apply List.filter_congr; intro p _; cases p <;>
    simp [starts, crStarts, fixLogical, earnHeroPill, earnItems, entries, crKeys, Entry.longhands, CssProp.phys])

theorem fixPhysical_webkit_eq_chromium (d : Dir) (c : CssProp → Bool) :
    startedSet .webkit d fixPhysical c = startedSet .chromium d fixPhysical c := by
  unfold startedSet
  apply List.filter_congr
  intro p _
  exact engines_agree_without_paddingInline d _ (by cases d <;> decide) c p

theorem fixPhysical_chromium_unchanged (d : Dir) (c : CssProp → Bool) :
    startedSet .chromium d fixPhysical c = startedSet .chromium d earnHeroPill c := by
  cases d <;> (unfold startedSet; apply List.filter_congr; intro p _; cases p <;>
    simp [starts, crStarts, fixPhysical, earnHeroPill, earnItems, entries, crKeys, Entry.longhands, CssProp.phys])

theorem fixPadding_webkit_eq_chromium (d : Dir) (c : CssProp → Bool) :
    startedSet .webkit d fixPadding c = startedSet .chromium d fixPadding c := by
  unfold startedSet
  apply List.filter_congr
  intro p _
  exact engines_agree_without_paddingInline d _ (by cases d <;> decide) c p

theorem fixPadding_chromium_differs :
    startedSet .chromium .ltr fixPadding (fun p => p = .paddingTop) ≠
    startedSet .chromium .ltr earnHeroPill (fun p => p = .paddingTop) := by
  decide

def firstFramePad (e : Eng) (d : Dir) (l : List Item) (changed : CssProp → Bool) (before after : Nat) : Nat :=
  if starts e d (entries l) changed .paddingLeft then before else after

theorem firstFrame_wide (d : Dir) :
    firstFramePad .webkit d earnHeroPill heroChanged 24 0 = 0 ∧
    firstFramePad .chromium d earnHeroPill heroChanged 24 0 = 24 := by
  cases d <;> decide

theorem firstFrame_narrow (d : Dir) :
    firstFramePad .webkit d earnHeroPill heroChanged 16 0 = 0 ∧
    firstFramePad .chromium d earnHeroPill heroChanged 16 0 = 16 := by
  cases d <;> decide

def earnWidth (maxW pad c : Nat) : Nat := min maxW (c + 2 * pad)

theorem padding_snap_width (maxW pad c : Nat) (h : c + 2 * pad ≤ maxW) :
    earnWidth maxW pad c = earnWidth maxW 0 c + 2 * pad := by
  unfold earnWidth
  omega

structure Input where
  listed : Bool
  durPos : Bool
  interp : Bool
  hasRunning : Bool
  runEndEqAfter : Bool
  curEqAfter : Bool
  revStartEqAfter : Bool
  completed : Bool
  deriving DecidableEq, Repr

inductive Out where
  | none | keep | cancel | start | restart | reverse
  deriving DecidableEq, Repr

/-- **WebKit's outcome** (`updateCSSTransitionsForStyleableAndProperty`, `WC/style/Styleable.cpp:584-760`): a start needs no
running transition (`:659-663`); an unlisted property cancels (`:693-699`); a running transition to the new value stays (`:701`);
a current value equal to the new one, or not interpolable, cancels (`:712`); a combined duration of 0 cancels (`:716`); a
reversing-adjusted start equal to the new value reverses (`:719`); otherwise it restarts from the current value (`:748`).
A completed transition that ended at the new value blocks the start (`:663`). -/
def wkOutcome (i : Input) : Out :=
  if !i.hasRunning then
    (if i.listed && i.durPos && !i.curEqAfter && i.interp && !i.completed then .start else .none)
  else if !i.listed then .cancel
  else if i.runEndEqAfter then .keep
  else if i.curEqAfter || !i.interp then .cancel
  else if !i.durPos then .cancel
  else if i.revStartEqAfter then .reverse
  else .restart

/-- **Chromium's outcome** (`CalculateTransitionUpdateForPropertyHandle`, `CA/css/css_animations.cc:2662-2925`): a running transition
to the new value stays (`:2709-2713`), else it is cancelled (`:2714`) and the checks for a new one follow: equal values (`:2733`),
`UnstartTransition` for a pair that cannot interpolate (`:2776`) or a combined duration of 0 (`:2858`), then reversing when the
new value is the running transition's reversing-adjusted start (`:2866-2884`), else a start from the before-change style (`:2919`). -/
def crOutcome (i : Input) : Out :=
  if !i.listed then (if i.hasRunning then .cancel else .none)
  else if i.hasRunning && i.runEndEqAfter then .keep
  else if i.curEqAfter || !i.interp || !i.durPos then (if i.hasRunning then .cancel else .none)
  else if i.hasRunning && i.revStartEqAfter then .reverse
  else if i.hasRunning then .restart
  else .start

def outcome : Eng → Input → Out
  | .chromium => crOutcome
  | .webkit => wkOutcome

theorem wk_start (i : Input) (h1 : i.hasRunning = false) (h2 : i.listed = true) (h3 : i.durPos = true)
    (h4 : i.curEqAfter = false) (h5 : i.interp = true) (h6 : i.completed = false) : wkOutcome i = .start := by
  simp [wkOutcome, h1, h2, h3, h4, h5, h6]

theorem wk_noStart (i : Input) (h1 : i.hasRunning = false)
    (h : i.listed = false ∨ i.durPos = false ∨ i.curEqAfter = true ∨ i.interp = false ∨ i.completed = true) :
    wkOutcome i = .none := by
  rcases h with h | h | h | h | h <;> simp [wkOutcome, h1, h]

theorem wk_cancel_unlisted (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = false) : wkOutcome i = .cancel := by
  simp [wkOutcome, h1, h2]

theorem wk_keep (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = true) :
    wkOutcome i = .keep := by
  simp [wkOutcome, h1, h2, h3]

theorem wk_cancel_current (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = false)
    (h : i.curEqAfter = true ∨ i.interp = false) : wkOutcome i = .cancel := by
  rcases h with h | h <;> simp [wkOutcome, h1, h2, h3, h]

theorem wk_cancel_zero (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = false)
    (h4 : i.curEqAfter = false) (h5 : i.interp = true) (h6 : i.durPos = false) : wkOutcome i = .cancel := by
  simp [wkOutcome, h1, h2, h3, h4, h5, h6]

theorem wk_reverse (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = false)
    (h4 : i.curEqAfter = false) (h5 : i.interp = true) (h6 : i.durPos = true) (h7 : i.revStartEqAfter = true) :
    wkOutcome i = .reverse := by
  simp [wkOutcome, h1, h2, h3, h4, h5, h6, h7]

theorem wk_restart (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = false)
    (h4 : i.curEqAfter = false) (h5 : i.interp = true) (h6 : i.durPos = true) (h7 : i.revStartEqAfter = false) :
    wkOutcome i = .restart := by
  simp [wkOutcome, h1, h2, h3, h4, h5, h6, h7]

theorem cr_start (i : Input) (h1 : i.hasRunning = false) (h2 : i.listed = true) (h3 : i.durPos = true)
    (h4 : i.curEqAfter = false) (h5 : i.interp = true) : crOutcome i = .start := by
  simp [crOutcome, h1, h2, h3, h4, h5]

theorem cr_noStart (i : Input) (h1 : i.hasRunning = false)
    (h : i.listed = false ∨ i.durPos = false ∨ i.curEqAfter = true ∨ i.interp = false) : crOutcome i = .none := by
  rcases h with h | h | h | h <;> simp [crOutcome, h1, h]

theorem cr_cancel_unlisted (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = false) : crOutcome i = .cancel := by
  simp [crOutcome, h1, h2]

theorem cr_keep (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = true) :
    crOutcome i = .keep := by
  simp [crOutcome, h1, h2, h3]

theorem cr_cancel (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = false)
    (h : i.curEqAfter = true ∨ i.interp = false ∨ i.durPos = false) : crOutcome i = .cancel := by
  rcases h with h | h | h <;> simp [crOutcome, h1, h2, h3, h]

theorem cr_reverse (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = false)
    (h4 : i.curEqAfter = false) (h5 : i.interp = true) (h6 : i.durPos = true) (h7 : i.revStartEqAfter = true) :
    crOutcome i = .reverse := by
  simp [crOutcome, h1, h2, h3, h4, h5, h6, h7]

theorem cr_restart (i : Input) (h1 : i.hasRunning = true) (h2 : i.listed = true) (h3 : i.runEndEqAfter = false)
    (h4 : i.curEqAfter = false) (h5 : i.interp = true) (h6 : i.durPos = true) (h7 : i.revStartEqAfter = false) :
    crOutcome i = .restart := by
  simp [crOutcome, h1, h2, h3, h4, h5, h6, h7]

theorem outcome_agree (i : Input) (h : i.completed = false) : wkOutcome i = crOutcome i := by
  obtain ⟨a, b, c, d, e, f, g, k⟩ := i
  simp only at h
  subst h
  revert a b c d e f g
  decide

theorem outcome_completed_differs :
    wkOutcome ⟨true, true, true, false, false, false, false, true⟩ = .none ∧
    crOutcome ⟨true, true, true, false, false, false, false, true⟩ = .start := by
  decide

theorem scrub_restart (e : Eng) : outcome e ⟨true, true, true, true, false, false, false, false⟩ = .restart := by
  cases e <;> decide

def CssProp.css : CssProp → String
  | .maxWidth => "max-width" | .opacity => "opacity" | .paddingTop => "padding-top" | .paddingRight => "padding-right"
  | .paddingBottom => "padding-bottom" | .paddingLeft => "padding-left" | .paddingInlineStart => "padding-inline-start"
  | .paddingInlineEnd => "padding-inline-end" | .rowGap => "row-gap" | .columnGap => "column-gap"

def Entry.css : Entry → String
  | .prop p => p.css | .paddingInline => "padding-inline" | .padding => "padding" | .gap => "gap" | .all => "all"

def Eng.name : Eng → String
  | .chromium => "chromium" | .webkit => "webkit"

def Dir.name : Dir → String
  | .ltr => "ltr" | .rtl => "rtl"

def Out.name : Out → String
  | .none => "none" | .keep => "keep" | .cancel => "cancel" | .start => "start" | .restart => "restart" | .reverse => "reverse"

def Input.code (i : Input) : String :=
  String.ofList ([i.listed, i.durPos, i.interp, i.hasRunning, i.runEndEqAfter, i.curEqAfter, i.revStartEqAfter, i.completed].map
    fun b => if b then '1' else '0')

def allInputs : List Input :=
  let bs := [false, true]
  bs.flatMap fun a => bs.flatMap fun b => bs.flatMap fun c => bs.flatMap fun d => bs.flatMap fun e => bs.flatMap fun f =>
    bs.flatMap fun g => bs.map fun h => ⟨a, b, c, d, e, f, g, h⟩

def allEntries : List Entry :=
  [.prop .maxWidth, .prop .opacity, .prop .paddingTop, .prop .paddingRight, .prop .paddingBottom, .prop .paddingLeft,
   .prop .paddingInlineStart, .prop .paddingInlineEnd, .prop .rowGap, .prop .columnGap, .paddingInline, .padding, .gap, .all]

open Lean in
private def row (e : Eng) (kv : List (String × Json)) : String :=
  (Json.mkObj ([("engine", Json.str e.name), ("stage", Json.str "style")] ++ kv)).compress

open Lean in
private def names (l : List CssProp) : Json := Json.arr (l.map fun p => Json.str p.css).toArray

def namedLists : List (String × List Item) :=
  [("earn-base", earnBase), ("earn-hero-pill", earnHeroPill), ("fix-logical-longhands", fixLogical),
   ("fix-physical-longhands", fixPhysical), ("fix-padding-shorthand", fixPadding)]

open Lean in
def goldenLines (_ : Unit) : List String :=
  let engs := [Eng.chromium, .webkit]
  let dirs := [Dir.ltr, .rtl]
  let all : CssProp → Bool := fun _ => true
  (engs.flatMap fun e => dirs.flatMap fun d =>
    allEntries.map fun en =>
      row e [("kind", "entry"), ("dir", d.name), ("entry", en.css), ("starts", names (allProps.filter (starts e d [en] all)))])
  ++ (engs.flatMap fun e => dirs.flatMap fun d =>
    namedLists.map fun (n, l) =>
      row e [("kind", "list"), ("dir", d.name), ("list", n), ("heroEntryStarts", names (startedSet e d l heroChanged)),
        ("firstFramePadWide", (firstFramePad e d l heroChanged 24 0 : Nat)),
        ("firstFramePadNarrow", (firstFramePad e d l heroChanged 16 0 : Nat))])
  ++ (engs.flatMap fun e =>
    allInputs.map fun i => row e [("kind", "outcome"), ("input", i.code), ("outcome", (outcome e i).name)])

def goldenJsonl (_ : Unit) : String := String.join ((goldenLines ()).map (· ++ "\n"))

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readFile path
    if cur == goldenJsonl () then
      IO.eprintln s!"transition-start golden: {path} is up to date ({(goldenLines ()).length} rows)"
      return 0
    IO.eprintln s!"transition-start golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenJsonl ())
    return 0

end Fw.Engine.TransitionStart
