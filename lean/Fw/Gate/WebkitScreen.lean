import Lean.Data.Json
import Fw.Gate.Exit
/-!
# The device width of a Playwright WebKit live resize (task gate-green-baseline)

A plain `page.setViewportSize` sets the page's screen to the new viewport, so a sweep stop whose device width differs from its width
reads a wrong `device-width`. The harness sets viewport and screen together (`engines.mjs`, `launchWebkit`), and no exemption covers it.
-/
namespace Fw.Gate.WebkitScreen
open Lean Fw.Gate Fw.Gate.Exit Fw.Site.Breakpoints

/-- The device-width edges of the site: the pair 500 | 501 (`edgePairs.deviceWidth`).

The only value at which a `device-width` condition changes. -/
def deviceEdges : List Rat := [500]

/-- The device-width check of the environment: the reported screen width is the requested one or on the same side of every edge.

The `deviceWidth` entry of `envChecks`. -/
def deviceWidthHolds (screen wanted : Rat) : Bool :=
  (some screen == some wanted) || sameSide (some screen) wanted deviceEdges

/-- `deviceWidthHolds` is the `deviceWidth` check of `envChecks`.

The gate calls a stop not achieved exactly when this is false. -/
theorem deviceWidthHolds_eq_check (q : Requested) (v : Viewport) (o : Observed) (s : Rat) (hs : v.screenWidth = some s) :
    (envChecks q v o deviceEdges).lookup "deviceWidth" = some (deviceWidthHolds s q.deviceWidth) := by
  simp [envChecks, deviceWidthHolds, hs, List.lookup]

/-- A screen equal to the requested width always holds.

Setting the screen to the device width meets the check. -/
theorem deviceWidthHolds_self (d : Rat) : deviceWidthHolds d d = true := by
  simp [deviceWidthHolds]

/-- The sweep stops after the first whose device width is unmet when the screen is the new viewport.

Pairs of sweep id and stop index. -/
def plainUnmet : List (String × Nat) :=
  sweeps.flatMap fun w =>
    ((List.range w.stops.length).filter fun i =>
      0 < i && match w.stops[i]? with
        | some e => !deviceWidthHolds (pxRat e.width) (pxRat e.deviceWidth)
        | none => false).map fun i => (w.id, i)

/-- Only the two landscape stops of the phone rotation are unmet by a plain resize.

The cause of the not-comparable cell `matchMedia =Lean | sweep:phone-rotation`: stops 1 and 3 (932 x 430, device width 430). -/
theorem plain_resize_unmet : plainUnmet = [("phone-rotation", 1), ("phone-rotation", 3)] := by
  decide +kernel

/-- With the screen set to the device width, every stop of every sweep meets the check.

The harness fix leaves no stop not achieved for want of the device width. -/
theorem kept_resize_met :
    sweeps.all (fun w => w.stops.all fun e => deviceWidthHolds (pxRat e.deviceWidth) (pxRat e.deviceWidth)) = true := by
  simp [deviceWidthHolds_self]

/-- No exemption covers the phone rotation sweep.

The allowlist names no column `sweep:phone-rotation`. -/
theorem no_exemption_phone_rotation : ∀ x ∈ exemptions, x.col ≠ "sweep:phone-rotation" := by
  decide +kernel

/-- No reading of the phone rotation sweep is excused, in either engine.

A not-comparable reading there is a finding, and a comparable failing one is never hidden. -/
theorem phone_rotation_never_excused (e row : String) (r : Reading) :
    excuseReading e row "sweep:phone-rotation" r = none := by
  cases h : excuseReading e row "sweep:phone-rotation" r with
  | none => rfl
  | some i =>
    obtain ⟨x, hx, -, -, -, hc, -⟩ := exemptions_enumerated e row "sweep:phone-rotation" r i h
    exact absurd hc (no_exemption_phone_rotation x hx)

/-- The stop lines of the golden: sweep, stop, requested sizes, the screen after a plain resize and after the harness resize, and
whether each meets the check. -/
def stopLines : List String :=
  sweeps.flatMap fun w =>
    ((List.range w.stops.length).filterMap fun i => match w.stops[i]? with
      | some e =>
        if 0 < i then
          let n (x : Px) : Json := toJson (pxRat x).floor
          some (Json.mkObj [("kind", "stop"), ("sweep", w.id), ("stop", i), ("width", n e.width), ("height", n e.height),
            ("deviceWidth", n e.deviceWidth), ("deviceHeight", n e.deviceHeight),
            ("plainScreen", Json.arr #[n e.width, n e.height]),
            ("plainMet", deviceWidthHolds (pxRat e.width) (pxRat e.deviceWidth)),
            ("keptScreen", Json.arr #[n e.deviceWidth, n e.deviceHeight]),
            ("keptMet", deviceWidthHolds (pxRat e.deviceWidth) (pxRat e.deviceWidth))]).compress
        else none
      | none => none)

/-- The lines of `golden/gate/webkit-screen.jsonl`: the pin of the Playwright behaviour, then one line per stop after the first. -/
def goldenLines : List String :=
  (Json.mkObj [("kind", "pin"), ("package", "playwright-core@1.64.1"), ("file", "lib/coreBundle.js"),
    ("plainResize", "screen: { ...viewportSize }"), ("keptResize", "setEmulatedSizeFromWindowOpen"),
    ("apply", "updateEmulatedViewportSize"), ("deviceEdges", toJson [500])]).compress :: stopLines

/-- The bytes of the golden. -/
def goldenText : String := String.intercalate "\n" goldenLines ++ "\n"

#guard sweeps.all fun w => w.stops.all fun e => e.width.den == 1 && e.height.den == 1 && e.deviceWidth.den == 1 && e.deviceHeight.den == 1

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match Fw.Gate.Settle.argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"webkit-screen golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"webkit-screen golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

end Fw.Gate.WebkitScreen
