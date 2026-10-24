import Lean.Data.Json
import Fw.Parts.EngineScroll
import Fw.Parts.NavHitTest
import Fw.Parts.HeroCountdown
import Fw.Parts.HeroExit
import Fw.Parts.MorphTween
import Fw.Parts.MorphPanel
import Fw.Parts.NavGolden
import Fw.Parts.CommissionGolden
import Fw.Parts.CommissionOptGolden
import Fw.Parts.OverlayGolden
import Fw.Parts.HeroGolden
import Fw.Parts.PeopleGolden
import Fw.Parts.PainNotesGolden
import Fw.Parts.PlatformGolden
/-!
# Golden vectors for the M2 pilot parts

`lake exe fwcore partsgolden <outDir>` writes, per part id:

* `<outDir>/<part-id>.jsonl` — only functions the TS part exports, with its `GOLDEN_ARGS` names
  (`{"fn": name, "in": {...}, "out": ...}`);
* `<outDir>/<part-id>.spec.jsonl` — Lean-only functions (no TS counterpart yet).

Encoding: `Int`/`Nat` as JSON integers, `Bool`, strings; `Rat` **inputs** as exact JSON decimals (every input is
chosen with a terminating decimal expansion); `Rat` **outputs** always in the wire form
`{"num":"<int>","den":"<positive int>"}` (PLAN §3.2), to be compared with a tolerance on the TS side.
-/
namespace Fw.Parts.Golden
open Lean

/-! ## Encoders -/

/-- Exact decimal of a rational whose reduced denominator is `2^a 5^b` with `a, b ≤ 40` (i.e. divides
`10^40`), with the fewest digits; none otherwise.

The JSON number for a rational input, when one exists. -/
def decimal? (q : Rat) : Option JsonNumber :=
  (List.range 41).findSome? fun e =>
    if (10 ^ e : Nat) % q.den == 0 then some ⟨q.num * ((10 ^ e : Nat) / q.den : Nat), e⟩ else none

/-- The `Rat` wire form. An exact fraction for JSON. -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- A rational input: an exact JSON decimal, else the wire form.

(so a terminating `q` whose denominator does not divide `10^40`, e.g. `2^(-41)`, goes to the wire form).

How a rational argument is written into a golden line. -/
def rin (q : Rat) : Json := match decimal? q with
  | some n => .num n
  | none => ratWire q

/-- An integer as JSON. A JSON integer. -/
def jint (z : Int) : Json := .num ⟨z, 0⟩

/-- A natural number as JSON. A JSON integer. -/
def jnat (n : Nat) : Json := jint n

/-- One golden line. A single compressed JSON line. -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-! ## engine.scroll -/

section Engine
open Fw.Parts.EngineScroll

/-- JSON of an entry. One registered callback. -/
def entryJ (e : Entry) : Json := Json.mkObj [("id", .str e.id), ("order", jint e.order), ("seq", jint e.seq)]

/-- JSON of a step. One frame-plan step. -/
def stepJ (s : Step) : Json :=
  Json.mkObj [("op", .str (match s.op with | .read => "read" | .write => "write")), ("i", jnat s.i)]

/-- Variant name. The variant's wire name. -/
def variantName : Variant → String
  | .faithful => "faithful"
  | .batched => "batched"

/-- Access name. The access's wire name. -/
def accessName : Access → String
  | .readStyle => "RS" | .readLayout => "RL" | .writeStyle => "WS" | .writeLayout => "WL"

/-- Writer patterns used for the frame plans (every pattern up to length 3, plus longer ones).

The callback write patterns the golden lines cover. -/
def writerPatterns : List (List Bool) :=
  [[], [false], [true], [false, false], [false, true], [true, false], [true, true],
   [false, false, false], [false, false, true], [false, true, false], [false, true, true],
   [true, false, false], [true, false, true], [true, true, false], [true, true, true],
   [false, true, false, true, true], [true, true, true, true, true, true]]

/-- engine.scroll lines (TS functions). The conformance vectors for the TS engine. -/
def engineLines : List String :=
  let orders : List (List Entry) :=
    [[], [⟨"a", 0, 0⟩], [⟨"b", 2, 0⟩, ⟨"a", 1, 1⟩, ⟨"c", 1, 2⟩], [⟨"x", 0, 2⟩, ⟨"y", 0, 1⟩, ⟨"z", 0, 0⟩],
     [⟨"nav", 100, 0⟩, ⟨"hero", 0, 1⟩, ⟨"pain", 0, 2⟩, ⟨"people", -5, 3⟩],
     [⟨"a", 0, 0⟩, ⟨"b", 0, 1⟩, ⟨"c", 0, 2⟩, ⟨"d", 0, 3⟩], [⟨"p", 1, 5⟩, ⟨"q", 1, 5⟩]]
  orders.map (fun es => line "orderCallbacks" [("entries", .arr (es.map entryJ).toArray)]
      (.arr ((orderCallbacks es).map Json.str).toArray)) ++
  ([Variant.faithful, .batched].flatMap fun v => writerPatterns.map fun ws =>
      line "framePlan" [("variant", .str (variantName v)), ("writers", .arr (ws.map Json.bool).toArray)]
        (.arr ((framePlan v ws).map stepJ).toArray)) ++
  ([false, true].map fun p => line "shouldSchedule" [("pending", .bool p)] (.bool (shouldSchedule p))) ++
  ([(false, 0), (false, 1), (false, 5), (true, 0), (true, 1), (true, 2)].map fun (a, n) =>
      line "listenerAction" [("attached", .bool a), ("size", jnat n)] (.str (listenerAction a n)))

/-- engine.scroll Lean-only lines: forced counts, plan layouts, runs.

The `forcedCounts` and `forcedCountsBatched` rows carry **forced passes only** (`forced_ρ`), not the
stage's trace total: they omit the frame-end lifecycle pass. The trace total is
`total_ρ = forced_ρ + [fE]` (`EngineScroll.total_eq`). For the
pilot frame the batched rows read style `1/0` (dirty/clean start) while the batched total is `2/1`, against a faithful
total of `4/3`: batching saves 2 style passes in the trace, not 3 (`pilot_batched_rows_forced_only`).

Each line is labelled with its inputs (left of `↦`) and carries its value (right of `↦`); the batched rows
are labelled with `as`, not with `bat(as)`, and `W` is `writerPatterns`.

Vectors for the cost model, labelled as forced counts rather than totals. -/
def engineSpecLines : List String :=
  let seqs : List (List Access) :=
    [[], [.readLayout], [.writeStyle, .readLayout], [.readLayout, .writeLayout, .readLayout],
     [.readStyle, .writeStyle, .readStyle, .writeLayout, .readLayout], heroExitAccesses, navAccesses, pilotFrame]
  let counts (d : Bool) (as : List Access) : Json :=
    Json.mkObj [("style", jnat (forced styleRole d as)), ("layout", jnat (forced layoutRole d as))]
  (seqs.flatMap fun as => [false, true].flatMap fun d =>
      let bat := as.filter Access.isRead ++ as.filter (fun a => !a.isRead)
      [line "forcedCounts" [("accesses", .arr (as.map (Json.str ∘ accessName)).toArray), ("dirty", .bool d)]
         (counts d as),
       line "forcedCountsBatched" [("accesses", .arr (as.map (Json.str ∘ accessName)).toArray), ("dirty", .bool d)]
         (counts d bat)]) ++
  ([Variant.faithful, .batched].flatMap fun v => writerPatterns.flatMap fun ws => [false, true].map fun d =>
      line "planLayouts" [("variant", .str (variantName v)), ("writers", .arr (ws.map Json.bool).toArray),
        ("dirty", .bool d)] (jnat (planLayouts d (framePlan v ws)))) ++
  ([[], [Ev.frame], [.scroll, .frame], [.scroll, .scroll, .scroll, .frame, .frame, .scroll, .frame],
    [.frame, .scroll, .frame, .scroll, .scroll]].flatMap fun es => [false, true].map fun p =>
      line "engineRuns" [("pending", .bool p),
        ("events", .arr (es.map (fun e => Json.str (match e with | .scroll => "scroll" | .frame => "frame"))).toArray)]
        (jnat (runs p es)))

/-- The read-first reordering the `forcedCountsBatched` rows use. All reads, then all writes, each in order. -/
def batchedOrder (as : List Access) : List Access := as.filter Access.isRead ++ as.filter (fun a => !a.isRead)

#guard batchedOrder [.writeStyle, .readLayout] == [.readLayout, .writeStyle]
#guard forced styleRole true (batchedOrder pilotFrame) == 1
#guard total styleRole true (batchedOrder pilotFrame) == 2

/-- **The batched golden rows are forced counts, not totals.** For the pilot frame and either start flag, the
`forcedCountsBatched` style value is `[d]` while the batched trace total is `1 + [d]`; the faithful forced count and
total are both `3 + [d]`; layout is `[d]` in all four.

Read as totals the pilot's batched row is 2/1, not 1/0, so batching saves two style passes, not three. -/
theorem pilot_batched_rows_forced_only (d : Bool) :
    forced styleRole d (batchedOrder pilotFrame) = d.toNat ∧
      total styleRole d (batchedOrder pilotFrame) = 1 + d.toNat ∧
      forced styleRole d pilotFrame = 3 + d.toNat ∧ total styleRole d pilotFrame = 3 + d.toNat ∧
      forced layoutRole d (batchedOrder pilotFrame) = d.toNat ∧
      total layoutRole d (batchedOrder pilotFrame) = d.toNat ∧
      forced layoutRole d pilotFrame = d.toNat ∧ total layoutRole d pilotFrame = d.toNat := by
  cases d <;> decide

end Engine

/-! ## nav.hitTest -/

section Nav
open Fw.Parts.NavHitTest

/-- nav.hitTest lines (TS functions). The conformance vectors for the TS hit test. -/
def navLines : List String :=
  let rects : List Rect :=
    [⟨0, 0, 390, 64⟩, ⟨0, 0, 393, 56⟩, ⟨12, 8, 361, 100⟩, ⟨16.5, 12.25, 1200, 64⟩, ⟨0, -10, 0, 0⟩,
     ⟨100, 4, 640.5, 63.5⟩, ⟨-20, 0, 80, 65⟩]
  (rects.map fun r =>
    let (x, y) := hitPoint r
    line "hitPoint" [("rect", Json.mkObj [("left", rin r.left), ("top", rin r.top), ("width", rin r.width),
      ("height", rin r.height)])] (Json.mkObj [("x", ratWire x), ("y", ratWire y)])) ++
  ([false, true].flatMap fun a => [false, true].flatMap fun b => [false, true].flatMap fun c =>
    [false, true].map fun d =>
      line "classifyHit" [("hasElement", .bool a), ("inExclude", .bool b), ("inInclude", .bool c),
        ("inShrinking", .bool d)] (.bool (classifyHit ⟨a, b, c, d⟩))) ++
  ([[], [false], [true], [true, false], [true, true, false, false], [true, true], [false, true]].map fun bs =>
    line "firstOutside" [("insideNav", .arr (bs.map Json.bool).toArray)] (jint (firstOutside bs))) ++
  ([false, true].flatMap fun p => [false, true].map fun n =>
    line "changed" [("prev", .bool p), ("next", .bool n)] (.bool (changed p n)))

/-- nav.hitTest Lean-only lines: faithful hit and `is-on-dark`. Vectors for the faithful reading. -/
def navSpecLines : List String :=
  let hitJ (h : Hit) : Json := Json.mkObj [("insideNav", .bool h.insideNav), ("reEnabled", .bool h.reEnabled)]
  ([[], [⟨false, false⟩], [⟨true, false⟩, ⟨false, false⟩], [⟨true, true⟩, ⟨false, false⟩],
    [⟨true, false⟩, ⟨true, true⟩, ⟨false, false⟩], [⟨true, false⟩, ⟨true, false⟩]].map fun (bs : List Hit) =>
    line "faithfulHit" [("stack", .arr (bs.map hitJ).toArray)]
      (Json.mkObj [("faithful", jint (faithfulHit bs)), ("firstOutside", jint (firstOutside (bs.map (·.insideNav))))])) ++
  ([false, true].flatMap fun g => ([0, 0.2, 0.2001, 0.5, 0.92, 1] : List Rat).map fun m =>
    line "isOnDark" [("hit", .bool g), ("morph", rin m)] (.bool (isOnDark g m)))

end Nav

/-! ## hero.countdown -/

section Countdown
open Fw.Parts.HeroCountdown

/-- JSON of a spring state, in the wire form or as `rin` inputs.

A spring as JSON. -/
def springJ (wire : Bool) (s : Spring) : Json :=
  if wire then Json.mkObj [("value", ratWire s.value), ("velocity", ratWire s.velocity)]
  else Json.mkObj [("value", rin s.value), ("velocity", rin s.velocity)]

/-- The capture pin `t_0` = 2026-10-01T00:00:00+07:00 in epoch ms. The pinned clock. -/
def t0Ms : Int := 1790787600000

/-- hero.countdown lines (TS functions). The conformance vectors for the TS countdown. -/
def countdownLines (_ : Unit := ()) : List String :=
  let rs : List (Int × Int) :=
    [(0, 1), (0, 999), (0, 1000), (0, 1001), (5000, 1000), (1000, 1000), (1001, 1000), (999, 1000),
     (0, 86400000), (0, 86400001), (0, 86399999), (t0Ms, targetMs), (targetMs - 1, targetMs),
     (targetMs, targetMs), (targetMs + 1, targetMs), (targetMs + 3600000, targetMs), (t0Ms + 500, targetMs)]
  (rs.map fun (n, t) => line "remainingSeconds" [("nowMs", jint n), ("targetMs", jint t)]
      (jnat (remainingSeconds n t))) ++
  ([0, 1, 59, 60, 61, 3599, 3600, 3601, 86399, 86400, 86401, 90061, 2808000,
     remainingSeconds t0Ms targetMs, 8640000].map fun n =>
      line "unitsFromSeconds" [("total", jnat n)] (.arr ((unitsFromSeconds n).map jnat).toArray)) ++
  (([0, 9, 10, 16, 99, 100, 123, -7.9, 5.5, 1000] : List Rat).flatMap fun v => [false, true].map fun p =>
      line "digitPlaces" [("value", rin v), ("padStart", .bool p)] (.arr ((digitPlaces v p).map jnat).toArray)) ++
  (([(1234, 1000), (1234, 100), (1234, 10), (1234, 1), (5, 10), (-1234.9, 1), (16, 10), (16, 1), (0, 1), (9.75, 1)]
      : List (Rat × Nat)).map fun (v, p) =>
      line "digitAt" [("value", rin v), ("place", jnat p)] (jnat (digitAt v p))) ++
  (([0, 3, 9, 9.5, 4.25, -0.5, 27.5, -13.25, 0.03125] : List Rat).flatMap fun a =>
      (List.range 10).map fun k =>
      line "faceDelta" [("face", jnat k), ("current", rin a)] (ratWire (faceDelta k a))) ++
  (([(⟨4, 0⟩, 3, 16), (⟨4, 0⟩, 3, 8), (⟨4, 0⟩, 3, 33), (⟨4, 0⟩, 3, 0), (⟨4, 0⟩, 3, -5), (⟨3, 0⟩, 3, 16),
     (⟨3.0005, 0⟩, 3, 0), (⟨9, 0⟩, 0, 16), (⟨0, 0⟩, 9, 48), (⟨2.5, -1.25⟩, 2, 16), (⟨5, 0⟩, 6, 64)]
      : List (Spring × Rat × Rat)).map fun (s, t, dt) =>
      let r := springStep s t dt
      line "springStep" [("state", springJ false s), ("target", rin t), ("dtMs", rin dt)]
        (Json.mkObj [("state", springJ true r.state), ("done", .bool r.done)])) ++
  (([(0, 0, 52), (9, 0, 52), (5, 0, 36), (6, 0, 31), (3, 4.25, 52), (0, 9.5, 36)] : List (Int × Rat × Rat)).map
      fun (k, a, c) =>
      line "faceOffsetPx" [("face", jint k), ("spring", rin a), ("cellPx", rin c)] (ratWire (faceOffsetPx k a c))) ++
  ([([16, 4, 5, 9], labelsEn), ([0, 0, 0, 0], labelsEn), ([], labelsEn), ([1, 2], ["d"]),
    ([32, 10, 0, 0], ["วัน", "ชม.", "นาที", "วินาที"])].map fun (u, l) =>
      line "ariaLabel" [("units", .arr (u.map jnat).toArray), ("labels", .arr (l.map Json.str).toArray)]
        (.str (ariaLabel u l))) ++
  (([24, 28, 40, 16, 20, 32, 48, 13] : List Rat).map fun f =>
      line "cellHeight" [("fontPx", rin f)] (jint (cellHeight f))) ++
  ([false, true].flatMap fun a => [false, true].map fun b =>
      let m := countdownMetrics a b
      line "countdownMetrics" [("le400", .bool a), ("c1000nodw", .bool b)]
        (Json.mkObj [("fontPx", jnat m.fontPx), ("cellPx", jnat m.cellPx), ("unitPx", jnat m.unitPx),
          ("unitRadiusPx", jnat m.unitRadiusPx), ("unitGapPx", jnat m.unitGapPx), ("rowGapPx", jnat m.rowGapPx),
          ("labelPx", jnat m.labelPx)])) ++
  (([0, 1, 9, 9.5, 4.25, -0.5, 10, 27.5] : List Rat).map fun a =>
      line "stripOffsetCells" [("spring", rin a)] (ratWire (stripOffsetCells a))) ++
  ((List.range 12).map fun j => line "stripEntryDigit" [("j", jnat j)] (jint (stripEntryDigit j))) ++
  (([(t0Ms, t0Ms), (t0Ms, t0Ms + 1000), (t0Ms, t0Ms + 3600000), (t0Ms, targetMs - 1), (t0Ms, targetMs),
     (t0Ms, targetMs + 5000), (0, t0Ms)] : List (Int × Int)).map fun (r, n) =>
      line "refreshShown" [("readMs", jint r), ("nowMs", jint n)]
        (.arr ((shown (refreshNow ⟨r⟩ n)).map jnat).toArray))

end Countdown

/-! ## hero.exit -/

section Exit
open Fw.Parts.HeroExit

/-- hero.exit lines (TS functions). The conformance vectors for the TS hero exit. -/
def exitLines (_ : Unit := ()) : List String :=
  let geoms : List (Rat × Rat × Rat) :=
    -- (trackTop, trackHeight, viewportHeight): desktop vh 800 (n = 800), 700-range, degenerate, phone vh 844
    ([100, 0, -0.5, -1, -400, -560, -576, -760, -761, -799, -800, -801, -5000].map fun t => (t, 1600, 800)) ++
    ([-100, -350, -700].map fun t => (t, 1500, 800)) ++
    ([0, -0.5, -1, -3].map fun t => (t, 100, 800)) ++
    ([-1, -422, -844, -845.5].map fun t => (t, 1688, 844))
  ([(1600, 800), (100, 800), (800, 800), (801, 800), (1600.5, 800), (1688, 844)] : List (Rat × Rat)).map
      (fun (h, v) => line "exitRange" [("trackHeight", rin h), ("viewportHeight", rin v)] (ratWire (exitRange h v))) ++
  (geoms.map fun (t, h, v) => line "exitOpacity" [("trackTop", rin t), ("trackHeight", rin h), ("viewportHeight", rin v)]
      (ratWire (exitOpacity t h v))) ++
  (([0, 0.25, 1, 0.05, 0.5] : List Rat).map fun e => line "exitScatter" [("opacity", rin e)] (ratWire (exitScatter e))) ++
  (([0, 0.0499, 0.05, 0.0501, 0.28, 1] : List Rat).map fun e =>
      line "pointerOff" [("opacity", rin e)] (.bool (pointerOff e))) ++
  ([false, true].flatMap fun r => geoms.map fun (t, h, v) =>
      let f := exitFrame r t h v
      line "exitFrame" [("reduced", .bool r), ("trackTop", rin t), ("trackHeight", rin h), ("viewportHeight", rin v)]
        (Json.mkObj [("opacity", ratWire f.opacity), ("pointerNone", .bool f.pointerNone)])) ++
  ([false, true].flatMap fun r => ([800, 844, 667.5] : List Rat).map fun v =>
      line "trackHeightPx" [("viewportHeight", rin v), ("reduced", .bool r)]
        (match trackHeightPx v r with | some x => ratWire x | none => .null)) ++
  ([false, true].flatMap fun l => ([600, 680, 900, 844, 679.5] : List Rat).map fun s =>
      line "heroHeightPx" [("svh", rin s), ("le600", .bool l)] (ratWire (heroHeightPx s l))) ++
  (([(1, 0.4), (0.5, 0.5), (0, 1), (1, 1), (1, 0)] : List (Rat × Rat)).map fun (c, e) =>
      line "copyOpacity" [("copyIn", rin c), ("exitOpacityValue", rin e)] (ratWire (copyOpacity c e))) ++
  ([false, true].flatMap fun l => ([(1, 0), (1, 0.5), (1, 1), (0, 0), (0.5, 0.25), (0, 1)] : List (Rat × Rat)).flatMap
      fun (c, s) =>
      [line "copyBlurPx" [("copyIn", rin c), ("scatter", rin s), ("le600", .bool l)] (ratWire (copyBlurPx c s l)),
       line "copyTranslateYPx" [("copyIn", rin c), ("scatter", rin s), ("le600", .bool l)]
         (ratWire (copyTranslateYPx c s l))]) ++
  (([0, 0.5, 1, 0.25] : List Rat).map fun s => line "cueBlurPx" [("scatter", rin s)] (ratWire (cueBlurPx s))) ++
  ([false, true].flatMap fun l => ([0, 0.5, 1] : List Rat).map fun s =>
      line "cueTranslateYPx" [("scatter", rin s), ("le600", .bool l)] (ratWire (cueTranslateYPx s l))) ++
  (([0, 0.5, 1, 0.25, 0.625] : List Rat).map fun s => line "cardOpacity" [("scatter", rin s)] (ratWire (cardOpacity s))) ++
  (([(1, 120, 0, -400), (0, 120, 0, -400), (0.5, -64, 0.5, 300), (1, 0, 1, -167.5)] : List (Rat × Rat × Rat × Rat)).map
      fun (n, x, s, o) =>
      line "cardTranslate" [("entered", rin n), ("enter", rin x), ("scatter", rin s), ("scatterOffset", rin o)]
        (ratWire (cardTranslate n x s o)))

/-- hero.exit Lean-only lines: band, full cue reading, nav progress. Vectors for the extra readings. -/
def exitSpecLines : List String :=
  (([599.5, 600, 600.5, 601, 320, 1512] : List Rat).map fun w => line "le600" [("width", rin w)] (.bool (le600 w))) ++
  ([false, true].flatMap fun l => [false, true].flatMap fun d => ([(0, 0), (0.5, 0.5), (1, 0.5), (1, 1)] : List (Rat × Rat)).flatMap
      fun (c, s) =>
      [line "cueBlurPxFull" [("copyIn", rin c), ("scatter", rin s), ("le600", .bool l), ("splashDone", .bool d)]
         (ratWire (cueBlurPxFull c s l d)),
       line "cueTranslateYPxFull" [("copyIn", rin c), ("scatter", rin s), ("le600", .bool l), ("splashDone", .bool d)]
         (ratWire (cueTranslateYPxFull c s l d))]) ++
  (([100, 0, -400, -575, -576, -577, -800, -900] : List Rat).map fun t =>
      let p := navHeroProgress t 1600 800
      line "navHeroProgress" [("trackTop", rin t), ("trackHeight", rin 1600), ("viewportHeight", rin 800)]
        (Json.mkObj [("progress", ratWire p), ("pillPassed", .bool (decide (p ≥ 18 / 25)))]))

end Exit

section Tween
open Fw.Parts.MorphTween

/-- A tween state as JSON. The wire form of `St`. -/
def stJson (s : St) : Json :=
  Json.mkObj [("value", ratWire s.value), ("target", ratWire s.target), ("from", ratWire s.f), ("to", ratWire s.t),
    ("start", ratWire s.start), ("pending", .bool s.pending)]

/-- A tween state as the input of a golden line. -/
def stIn (s : St) : Json :=
  Json.mkObj [("value", rin s.value), ("target", rin s.target), ("from", rin s.f), ("to", rin s.t),
    ("start", rin s.start), ("pending", .bool s.pending)]

/-- morph.tween lines (TS functions): the conformance vectors for the TS tween. Comprehensions run their generators
left to right, outer to inner; `line`, `rin`, `ratWire` as in `PlatformGolden`. -/
def tweenLines (_ : Unit := ()) : List String :=
  let xs : List Rat := [-1, 0, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 1.5]
  let els : List Rat := [-16, 0, 16.667, 100, 340, 500, 679, 679.9, 680, 680.1, 1000]
  let ends : List (Rat × Rat) := [(0, 1), (1, 0), (0.3, 1), (0.8, 0), (0.5, 0.5)]
  (xs.map fun x => line "ease" [("x", rin x)] (ratWire (ease x))) ++
  (ends.flatMap fun (f, t) => els.map fun e =>
    let z := tween f t e
    line "tween" [("from", rin f), ("to", rin t), ("elapsed", rin e)]
      (Json.mkObj [("value", ratWire z.value), ("done", .bool z.done)])) ++
  (([0, 0.5, 0.99, 1, -1, 1.5, -0.5, 120, -120, 0.0] : List Rat).map fun d =>
    line "dir" [("delta", rin d)] (match dir d with | some g => ratWire g | none => .null)) ++
  (([(360, 800, 800), (359.9, 800, 800), (800, 808, 800), (800, 808.5, 800), (0, 0, 800), (380.25, 844, 844),
     (379.8, 844, 844), (900, 852, 844), (900, 852.01, 844)] : List (Rat × Rat × Rat)).map fun (h, b, v) =>
    line "armed" [("rectHeight", rin h), ("rectBottom", rin b), ("viewportHeight", rin v)] (.bool (armed h b v))) ++
  ([false, true].flatMap fun a => ([-5, 0, 0.5, 5] : List Rat).flatMap fun d => [false, true].map fun r =>
    line "taken" [("active", .bool a), ("delta", rin d), ("armed", .bool r)] (.bool (taken a d r))) ++
  (([(0, 0), (0.001, 0), (0, 0.001), (0.0011, 0), (0, 0.0011), (1, 0), (0, 1), (1, 1)] : List (Rat × Rat)).map fun (w, r) =>
    line "active" [("target", rin w), ("value", rin r)] (.bool (active w r))) ++
  (([0, 0.1, 0.275, 0.5, 0.5225, 0.5226, 0.55, 0.9, 1] : List Rat).flatMap fun m =>
    [line "fade" [("m", rin m)] (ratWire (fade m)), line "pointerNone" [("m", rin m)] (.bool (pointerNone m))]) ++
  (let states : List St := [rest, push rest 1 false 100, frame (push rest 1 false 100) 440,
      frame (push rest 1 false 100) 780, push rest 1 true 100, frame (push (frame (push rest 1 false 100) 440) 0 false 450) 450]
   states.flatMap fun s => ([0, 1] : List Rat).flatMap fun g => [false, true].map fun rm =>
     line "push" [("state", stIn s), ("goal", rin g), ("reduced", .bool rm), ("now", rin 1000)] (stJson (push s g rm 1000))) ++
  (let states : List St := [rest, push rest 1 false 100, frame (push rest 1 false 100) 440, push rest 1 true 100]
   states.flatMap fun s => ([100, 116.667, 440, 780, 781, 90] : List Rat).map fun n =>
     line "frame" [("state", stIn s), ("now", rin n)] (stJson (frame s n)))

end Tween

/-! ## morph.panel -/

section MorphPanelSec
open Fw.Parts.MorphPanel

/-- morph.panel lines (TS functions). The conformance vectors for the TS morph panel. -/
def morphPanelLines : List String :=
  let ms : List Rat := [0, 0.001, 0.0011, 0.08, 0.2, 0.35, 0.3499, 0.44, 0.55, 0.5499, 0.8, 0.92, 0.9201, 1]
  (ms.flatMap fun m =>
    [line "panelProgress" [("morph", rin m)] (ratWire (panelProgress m)),
     line "panelOpacity" [("morph", rin m)] (ratWire (panelOpacity m)),
     line "panelBlurPx" [("morph", rin m)] (ratWire (panelBlurPx m)),
     line "panelScale" [("morph", rin m)] (ratWire (panelScale m)),
     line "sceneActive" [("morph", rin m)] (.bool (sceneActive m)),
     line "ariaHidden" [("morph", rin m)] (.bool (ariaHidden m)),
     line "ctaTabOff" [("morph", rin m)] (.bool (ctaTabOff m)),
     line "expanded" [("morph", rin m)] (.bool (expanded m))])

end MorphPanelSec

/-- Write the 27 golden files into `outDir` (first argument `args_0`, default `../packages/contracts/golden/parts`),
in this order, each file's lines joined with a newline after every line, and print each name with its line count.

Regenerates the pilot parts' golden vectors from the Lean definitions. -/
def main (args : List String) : IO Unit := do
  let dir := args.headD "../packages/contracts/golden/parts"
  IO.FS.createDirAll dir
  let files : List (String × List String) :=
    [("engine.scroll.jsonl", engineLines), ("engine.scroll.spec.jsonl", engineSpecLines),
     ("nav.hitTest.jsonl", navLines), ("nav.hitTest.spec.jsonl", navSpecLines),
     ("hero.countdown.jsonl", countdownLines), ("hero.exit.jsonl", exitLines),
     ("hero.exit.spec.jsonl", exitSpecLines), ("morph.tween.jsonl", tweenLines),
     ("morph.panel.jsonl", morphPanelLines),
     ("nav.jsonl", Fw.Parts.NavGolden.navLines), ("nav.langMenu.jsonl", Fw.Parts.NavGolden.menuLines),
     ("commission.jsonl", Fw.Parts.CommissionGolden.commissionLines),
     ("commission.typing.jsonl", Fw.Parts.CommissionGolden.typingLines),
     ("overlays.drawer.jsonl", OverlayGolden.drawerLines), ("overlays.signup.jsonl", OverlayGolden.signupLines),
     ("hero.orbit.jsonl", Fw.Parts.HeroGolden.orbitLines), ("hero.accent.jsonl", Fw.Parts.HeroGolden.accentLines)] ++ Fw.Parts.PeopleGolden.files ++ [("pain.notes.jsonl", Fw.Parts.PainNotesGolden.lines)] ++ PlatformGolden.files ++ Fw.Parts.CommissionOptGolden.files ()
  for (name, ls) in files do
    IO.FS.writeFile (dir ++ "/" ++ name) (String.join (ls.map (· ++ "\n")))
    IO.println s!"{name}: {ls.length} lines"

end Fw.Parts.Golden
