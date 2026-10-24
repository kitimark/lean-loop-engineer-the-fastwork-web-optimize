import Lean.Data.Json
import Fw.Engine.TransitionStart
namespace Fw.Parts.NavEarnWebkit

open Fw.Engine.TransitionStart

def faithfulHero : List Item := earnHeroPill

def faithfulBase : List Item := earnBase

def variantHero : List Item := earnItems 200 0 [.prop .paddingInlineStart, .prop .paddingInlineEnd]

def variantBase : List Item := earnItems 320 120 [.prop .paddingInlineStart, .prop .paddingInlineEnd]

theorem variantHero_eq_fixLogical : variantHero = fixLogical := rfl

def flipChanged : CssProp → Bool := heroChanged

def timing (e : Eng) (d : Dir) (l : List Item) (p : CssProp) : Option (Nat × Nat) :=
  ((l.filter fun it => match e with
      | .chromium => (crKeys d it.entry).contains p
      | .webkit => wkMatches d it.entry p).getLast?).map fun it => (it.dur, it.delay)

theorem hero_entry_chromium_faithful (d : Dir) :
    startedSet .chromium d faithfulHero flipChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

theorem hero_exit_chromium (d : Dir) :
    startedSet .chromium d faithfulBase flipChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

theorem hero_exit_webkit (d : Dir) :
    startedSet .webkit d faithfulBase flipChanged = [.maxWidth, .opacity] := by
  cases d <;> decide

theorem variant_entry_webkit (d : Dir) :
    startedSet .webkit d variantHero flipChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

theorem variant_exit_webkit (d : Dir) :
    startedSet .webkit d variantBase flipChanged = [.maxWidth, .opacity, .paddingRight, .paddingLeft] := by
  cases d <;> decide

theorem variant_webkit_padding (d : Dir) (c : CssProp → Bool) :
    (wkStarts d (entries variantHero) c .paddingLeft = c .paddingLeft ∧
     wkStarts d (entries variantHero) c .paddingRight = c .paddingRight) ∧
    (wkStarts d (entries variantBase) c .paddingLeft = c .paddingLeft ∧
     wkStarts d (entries variantBase) c .paddingRight = c .paddingRight) := by
  cases d <;> simp [wkStarts, wkBits, wkMatches, hasWrapper, CssProp.isLogical, CssProp.phys, Entry.longhands,
    variantHero, variantBase, earnItems, entries]

theorem variant_firstFrame (d : Dir) :
    firstFramePad .webkit d variantHero flipChanged 24 0 = 24 ∧ firstFramePad .webkit d variantBase flipChanged 24 0 = 24 ∧
    firstFramePad .webkit d variantHero flipChanged 16 0 = 16 ∧ firstFramePad .webkit d variantBase flipChanged 16 0 = 16 := by
  cases d <;> decide

theorem variant_chromium_set (d : Dir) (c : CssProp → Bool) :
    startedSet .chromium d variantHero c = startedSet .chromium d faithfulHero c ∧
    startedSet .chromium d variantBase c = startedSet .chromium d faithfulBase c := by
  constructor <;>
  · cases d <;> (unfold startedSet; apply List.filter_congr; intro p _; cases p <;>
      simp [starts, crStarts, variantHero, variantBase, faithfulHero, faithfulBase, earnHeroPill, earnBase, earnItems,
        entries, crKeys, Entry.longhands, CssProp.phys])

theorem variant_chromium_timing (d : Dir) (p : CssProp) :
    timing .chromium d variantHero p = timing .chromium d faithfulHero p ∧
    timing .chromium d variantBase p = timing .chromium d faithfulBase p := by
  cases d <;> cases p <;> decide

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

theorem variant_webkit_timing_eq_chromium_faithful (d : Dir) (p : CssProp) :
    timing .webkit d variantHero p = timing .chromium d faithfulHero p ∧
    timing .webkit d variantBase p = timing .chromium d faithfulBase p := by
  cases d <;> cases p <;> decide

theorem variant_webkit_padding_timing (d : Dir) :
    timing .webkit d variantHero .paddingLeft = some (680, 0) ∧ timing .webkit d variantBase .paddingRight = some (680, 0) := by
  cases d <;> decide

theorem faithful_webkit_never_starts_padding (d : Dir) (c : CssProp → Bool) :
    wkStarts d (entries faithfulHero) c .paddingLeft = false ∧ wkStarts d (entries faithfulBase) c .paddingRight = false := by
  cases d <;> simp [wkStarts, wkBits, wkMatches, hasWrapper, CssProp.isLogical, CssProp.phys, Entry.longhands,
    faithfulHero, faithfulBase, earnHeroPill, earnBase, earnItems, entries]

def underMotion (reduced : Bool) (l : List Item) : List Item := if reduced then [] else l

def computedNone : List String := ["none", "0s", "ease", "0s", "normal"]

def computed (l : List Item) : List String := if l.isEmpty then computedNone else l.map (·.entry.css)

theorem reduced_started_empty (e : Eng) (d : Dir) (c : CssProp → Bool) (l : List Item) :
    startedSet e d (underMotion true l) c = [] := by
  simp [underMotion, startedSet, entries]
  intro p _
  cases e <;> simp [starts, crStarts, wkStarts]

theorem reduced_computed_faithful :
    computed (underMotion true variantHero) = computed (underMotion true faithfulHero) ∧
    computed (underMotion true variantBase) = computed (underMotion true faithfulBase) ∧
    computed (underMotion true variantHero) = computedNone := by
  decide

theorem motion_computed_differs :
    computed (underMotion false variantHero) ≠ computed (underMotion false faithfulHero) := by decide

open Lean in
private def numJ (mant : Nat) (exp : Nat) : Json := Json.num ⟨mant, exp⟩

open Lean in
def curveJson : Json := Json.arr #[numJ 33 2, numJ 0 0, numJ 2 1, numJ 1 0]

open Lean in
private def names (l : List CssProp) : Json := Json.arr (l.map fun p => Json.str p.css).toArray

open Lean in
private def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", Json.str fn), ("in", Json.mkObj inp), ("out", out)]).compress

def arms : List (String × String × List Item) :=
  [("faithful", "hero", faithfulHero), ("faithful", "base", faithfulBase), ("variant", "hero", variantHero),
   ("variant", "base", variantBase)]

open Lean in
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
  ++ ([Eng.chromium, .webkit].flatMap fun e => [Dir.ltr, .rtl].flatMap fun d => arms.map fun (arm, rule, l) =>
    line "reduced" [("engine", Json.str e.name), ("dir", Json.str d.name), ("arm", Json.str arm), ("rule", Json.str rule)]
      (Json.mkObj [("starts", names (startedSet e d (underMotion true l) flipChanged)),
        ("computed", Json.arr ((computed (underMotion true l)).map Json.str).toArray)]))

def goldenText (_ : Unit) : String := String.join ((lines ()).map (· ++ "\n"))

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
