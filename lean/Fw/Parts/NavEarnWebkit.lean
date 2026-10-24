import Lean.Data.Json
import Fw.Engine.TransitionStart
/-! Part `nav`, variant `earn-logical`. Cause and candidates: research/notes/2026/10-2x-earn-webkit-parity.md; this task's
measurements: research/notes/2026/10-2x-earn-webkit-smooth.md. -/
namespace Fw.Parts.NavEarnWebkit

open Fw.Engine.TransitionStart

/-- The earn rule in the hero pill, entry: `.is-hero-pill .btn.earn`, opacity 200 ms without a delay. The faithful list. -/
def faithfulHero : List Item := earnHeroPill

/-- The earn rule outside the hero pill, exit from it: `.btn.earn`, opacity 320 ms after 120 ms. The faithful list. -/
def faithfulBase : List Item := earnBase

/-- The variant list in the hero pill: `padding-inline-start, padding-inline-end` in place of `padding-inline`. -/
def variantHero : List Item := earnItems 200 0 [.prop .paddingInlineStart, .prop .paddingInlineEnd]

/-- The variant list outside the hero pill. -/
def variantBase : List Item := earnItems 320 120 [.prop .paddingInlineStart, .prop .paddingInlineEnd]

theorem variantHero_eq_fixLogical : variantHero = fixLogical := rfl

/-- The properties that change at a hero-pill flip: max-width, opacity and both side paddings (`heroChanged`), the same
set on entry and on exit. -/
def flipChanged : CssProp → Bool := heroChanged

/-- The transition each engine runs on `p`: the last list entry that names it sets its duration and delay (the curve
`cubic-bezier(.33,0,.2,1)` is one constant for every entry of the rule). -/
def timing (e : Eng) (d : Dir) (l : List Item) (p : CssProp) : Option (Nat × Nat) :=
  ((l.filter fun it => match e with
      | .chromium => (crKeys d it.entry).contains p
      | .webkit => wkMatches d it.entry p).getLast?).map fun it => (it.dur, it.delay)

/-- **Faithful on Chromium, entry:** max-width, opacity and both paddings start. -/
theorem hero_entry_chromium_faithful (d : Dir) :
    startedSet .chromium d faithfulHero flipChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

/-- **Faithful on Chromium, exit** (review follow-up of earn-webkit-parity): the same four. -/
theorem hero_exit_chromium (d : Dir) :
    startedSet .chromium d faithfulBase flipChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

/-- **Faithful on WebKit, exit:** the padding never starts, only max-width and opacity. -/
theorem hero_exit_webkit (d : Dir) :
    startedSet .webkit d faithfulBase flipChanged = [.maxWidth, .opacity] := by
  cases d <;> decide

/-- **Variant on WebKit, entry:** all four start, so the padding eases instead of snapping. -/
theorem variant_entry_webkit (d : Dir) :
    startedSet .webkit d variantHero flipChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

/-- **Variant on WebKit, exit:** all four start. -/
theorem variant_exit_webkit (d : Dir) :
    startedSet .webkit d variantBase flipChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

/-- **For every change set:** WebKit starts a left and a right padding transition exactly when that padding changes,
on the entry list and on the exit list, left to right and right to left. -/
theorem variant_webkit_padding (d : Dir) (c : CssProp → Bool) :
    (wkStarts d (entries variantHero) c .paddingLeft = c .paddingLeft ∧
     wkStarts d (entries variantHero) c .paddingRight = c .paddingRight) ∧
    (wkStarts d (entries variantBase) c .paddingLeft = c .paddingLeft ∧
     wkStarts d (entries variantBase) c .paddingRight = c .paddingRight) := by
  cases d <;> simp [wkStarts, wkBits, wkMatches, hasWrapper, CssProp.isLogical, CssProp.phys, Entry.longhands,
    variantHero, variantBase, earnItems, entries]

/-- **First frame on WebKit, entry and exit:** the side padding keeps its value instead of jumping (24 px wide, 16 px
narrow), where the faithful list shows 0 (`firstFrame_wide`, `firstFrame_narrow`). -/
theorem variant_firstFrame (d : Dir) :
    firstFramePad .webkit d variantHero flipChanged 24 0 = 24 ∧ firstFramePad .webkit d variantBase flipChanged 24 0 = 24 ∧
    firstFramePad .webkit d variantHero flipChanged 16 0 = 16 ∧ firstFramePad .webkit d variantBase flipChanged 16 0 = 16 := by
  cases d <;> decide

/-- **Chromium: the started set is the faithful one** for every change set, on both lists. -/
theorem variant_chromium_set (d : Dir) (c : CssProp → Bool) :
    startedSet .chromium d variantHero c = startedSet .chromium d faithfulHero c ∧
    startedSet .chromium d variantBase c = startedSet .chromium d faithfulBase c := by
  constructor <;>
  · cases d <;> (unfold startedSet; apply List.filter_congr; intro p _; cases p <;>
      simp [starts, crStarts, variantHero, variantBase, faithfulHero, faithfulBase, earnHeroPill, earnBase, earnItems,
        entries, crKeys, Entry.longhands, CssProp.phys])

/-- **Chromium: the duration and delay of every property are the faithful ones.** -/
theorem variant_chromium_timing (d : Dir) (p : CssProp) :
    timing .chromium d variantHero p = timing .chromium d faithfulHero p ∧
    timing .chromium d variantBase p = timing .chromium d faithfulBase p := by
  cases d <;> cases p <;> decide

/-- **WebKit with the variant starts what Chromium starts with the faithful rule**, for every change set. -/
theorem variant_webkit_set_eq_chromium_faithful (d : Dir) (c : CssProp → Bool) :
    startedSet .webkit d variantHero c = startedSet .chromium d faithfulHero c ∧
    startedSet .webkit d variantBase c = startedSet .chromium d faithfulBase c := by
  have h := variant_chromium_set d c
  refine ⟨?_, ?_⟩
  · rw [← h.1]
    unfold startedSet
    apply List.filter_congr
    intro p _
    exact engines_agree_without_paddingInline d _ (by cases d <;> decide) c p
  · rw [← h.2]
    unfold startedSet
    apply List.filter_congr
    intro p _
    exact engines_agree_without_paddingInline d _ (by cases d <;> decide) c p

/-- **WebKit with the variant runs Chromium's faithful duration and delay on every property.** -/
theorem variant_webkit_timing_eq_chromium_faithful (d : Dir) (p : CssProp) :
    timing .webkit d variantHero p = timing .chromium d faithfulHero p ∧
    timing .webkit d variantBase p = timing .chromium d faithfulBase p := by
  cases d <;> cases p <;> decide

/-- **The padding eases on the same schedule as max-width** (680 ms, no delay) on WebKit with the variant. -/
theorem variant_webkit_padding_timing (d : Dir) :
    timing .webkit d variantHero .paddingLeft = some (680, 0) ∧ timing .webkit d variantBase .paddingRight = some (680, 0) := by
  cases d <;> decide

/-- The faithful lists start no padding transition on WebKit for any change set (the cause), shown for contrast. -/
theorem faithful_webkit_never_starts_padding (d : Dir) (c : CssProp → Bool) :
    wkStarts d (entries faithfulHero) c .paddingLeft = false ∧ wkStarts d (entries faithfulBase) c .paddingRight = false := by
  cases d <;> simp [wkStarts, wkBits, wkMatches, hasWrapper, CssProp.isLogical, CssProp.phys, Entry.longhands,
    faithfulHero, faithfulBase, earnHeroPill, earnBase, earnItems, entries]

open Lean in
private def numJ (mant : Nat) (exp : Nat) : Json := Json.num ⟨mant, exp⟩

open Lean in
/-- The curve `cubic-bezier(.33, 0, .2, 1)` of every earn entry. -/
def curveJson : Json := Json.arr #[numJ 33 2, numJ 0 0, numJ 2 1, numJ 1 0]

open Lean in
private def names (l : List CssProp) : Json := Json.arr (l.map fun p => Json.str p.css).toArray

open Lean in
private def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", Json.str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- The four lists with their golden names: arm (`faithful`, `variant`) and rule (`hero`: entry, `base`: exit). -/
def arms : List (String × String × List Item) :=
  [("faithful", "hero", faithfulHero), ("faithful", "base", faithfulBase), ("variant", "hero", variantHero),
   ("variant", "base", variantBase)]

open Lean in
/-- The golden lines `packages/contracts/golden/parts/nav.earn.webkit.jsonl`: each list entry (`list`), and for each
engine, direction and list the started set, the first-frame padding and, when the left padding starts, its timing
(`started`). -/
def lines (_ : Unit) : List String :=
  (arms.map fun (arm, rule, l) =>
    line "list" [("arm", Json.str arm), ("rule", Json.str rule)]
      (Json.arr (l.map fun it => Json.mkObj [("property", Json.str it.entry.css), ("durMs", Json.num (it.dur : Nat)),
        ("delayMs", Json.num (it.delay : Nat)), ("curve", curveJson)]).toArray))
  ++ ([Eng.chromium, .webkit].flatMap fun e => [Dir.ltr, .rtl].flatMap fun d => arms.map fun (arm, rule, l) =>
    line "started" [("engine", Json.str e.name), ("dir", Json.str d.name), ("arm", Json.str arm), ("rule", Json.str rule)]
      (Json.mkObj [("starts", names (startedSet e d l flipChanged)),
        ("firstFramePadWide", Json.num (firstFramePad e d l flipChanged 24 0 : Nat)),
        ("firstFramePadNarrow", Json.num (firstFramePad e d l flipChanged 16 0 : Nat)),
        ("paddingLeftTiming", match (if starts e d (entries l) flipChanged .paddingLeft then timing e d l .paddingLeft else none) with
          | some (du, de) => Json.arr #[Json.num du, Json.num de]
          | none => Json.null)]))

def goldenText (_ : Unit) : String := String.join ((lines ()).map (· ++ "\n"))

/-- Print the golden text, or with `--check <file>` compare it; exit 1 on a difference. -/
def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"nav.earn.webkit golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"nav.earn.webkit golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.NavEarnWebkit
