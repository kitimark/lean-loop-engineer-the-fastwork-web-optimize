import Fw.Site.Stage
import Fw.Measure.Viewport

/-! Driver decisions for a part page (`?only=`) in the Chromium counts lane. The stage route pins `scrollY`, `innerWidth` and
`innerHeight` on `window` to the stage environment (`apps/site/src/stage/fixedEnv.ts`), so a driver that reads them learns
the query, not the browser. Three decisions follow from that: the plan appends the profile viewport as the stage
environment (a), the driver accepts a client-rendered page only for a stage search whose page reports exactly that
environment (b), and the real document scrolls under a pinned `y` while the driver reads real sizes and positions (c). The viewport
gate of a stage page decides on the real frame size (the native `innerWidth`/`innerHeight` getters captured before the page
pins them), exactly as `Fw.Measure.Viewport` for a whole page; `clientWidth`/`clientHeight` are recorded, never gated.
Twins: `packages/measure-chromium/src/stage-mode.mjs` (driver and workflow plan), checked against
`packages/contracts/golden/parts/stage-mode.jsonl` (`lean/scripts/StageModeGolden.lean`). Every result rests on the
contract premise `declared-rows-unverified`.

Meaning of a part-page count (c). The stage query carries `y` = 0 and the page pins `scrollY` to it for the whole run, so
no part sees a scroll position other than rest. The driver still scrolls the real document (hosts plus fixed-height
stubs) with the profile's plan. A part-page count is therefore the browser work of the part's own band under real
document scrolling with scroll-driven part logic held at rest: not a slice of the whole-page count, and the part counts
do not sum to it. Letting `y` follow the plan needs a live pinned getter in the site (follow-up). -/

namespace Fw.Site.StageMode

open Fw.Site.Stage (Env pairs parse Result Err)
open Fw.Measure.Viewport (Size viewportFaithful)
open Fw.Parts.Contract (parts premise jstr jarr)

/-- Whether a search carries an `only` key (a part page). -/
def onlySearch (q : String) : Bool := (pairs q).any (·.1 == "only")

/-- Whether a search carries a `stage` key. -/
def hasStage (q : String) : Bool := (pairs q).any (·.1 == "stage")

/-- Every query that `Stage.parse` accepts as a stage page carries an `only` key. -/
theorem parse_not_none_onlySearch (q : String) (h : parse q ≠ .none) : onlySearch q = true := by
  cases hb : onlySearch q with
  | true => rfl
  | false =>
  exfalso
  apply h
  unfold parse
  dsimp only
  have hn : ((pairs q).filter (·.1 == "only")).map (·.2) = [] := by
    unfold onlySearch at hb
    have h2 := List.any_eq_false.mp hb
    have h3 : (pairs q).filter (·.1 == "only") = [] := by
      apply List.filter_eq_nil_iff.mpr
      intro a ha
      have := h2 a ha
      simpa using this
    rw [h3]; rfl
  rw [hn]

/-- The stage environment of a profile: top of the page and the profile viewport. -/
def plannedEnv (p : Size) : Env := { y := 0, vw := p.w, vh := p.h }

/-- The `stage` value the plan appends. -/
def stageParam (p : Size) : String := "vw:" ++ toString p.w ++ ",vh:" ++ toString p.h

/-- The search the plan hands to the driver: a search without `only` is unchanged, a part-page search gets
`&stage=vw:<w>,vh:<h>` of the profile appended, and a search that already names a stage is refused (the environment
is derived, never typed). -/
def planSearch (q : String) (p : Size) : Option String :=
  if onlySearch q then
    if hasStage q then none else some (q ++ "&stage=" ++ stageParam p)
  else some q

/-- A search without `only` passes the plan unchanged. -/
theorem planSearch_plain (q : String) (p : Size) (h : onlySearch q = false) : planSearch q p = some q := by
  simp [planSearch, h]

/-- A part-page search without a stage gets the profile viewport appended. -/
theorem planSearch_appends (q : String) (p : Size) (ho : onlySearch q = true) (hs : hasStage q = false) :
    planSearch q p = some (q ++ "&stage=" ++ stageParam p) := by
  simp [planSearch, ho, hs]

/-- A part-page search that already names a stage is refused. -/
theorem planSearch_refuses_typed_stage (q : String) (p : Size) (ho : onlySearch q = true) (hs : hasStage q = true) :
    planSearch q p = none := by
  simp [planSearch, ho, hs]

/-- The planned environment is valid when the profile viewport is in range, so `parseEnv` can accept it. -/
theorem plannedEnv_valid (p : Size) (hw : 1 ≤ p.w ∧ p.w ≤ 10000) (hh : 1 ≤ p.h ∧ p.h ≤ 10000) :
    (plannedEnv p).valid = true := by
  simp [plannedEnv, Env.valid, hw.1, hw.2, hh.1, hh.2]

/-- The pinned `innerWidth`/`innerHeight` of a planned stage equal the profile, so the page's own size reads cannot tell a
wrong browser viewport from the right one: the viewport gate must read the real frame size on a stage page (the native
getters captured before the pin). -/
theorem pinned_size_vacuous (p : Size) : viewportFaithful p ⟨(plannedEnv p).vw, (plannedEnv p).vh⟩ = true := by
  simp [plannedEnv, viewportFaithful]

/-- The scroll environment of a planned stage does not follow the scroll plan: `y` is 0 whatever the profile. -/
theorem plannedEnv_y_rest (p : Size) : (plannedEnv p).y = 0 := rfl

/-- Value of `window.__fw.mode`. -/
inductive Mode | hydrate | clientRender | other
deriving Repr, DecidableEq

/-- Wire name of a mode. Any other string is `other`. -/
def Mode.ofString : String → Mode
  | "hydrate" => .hydrate
  | "client-render" => .clientRender
  | _ => .other

/-- Wire name of a mode value. -/
def Mode.wire : Mode → String
  | .hydrate => "hydrate" | .clientRender => "client-render" | .other => "other"

/-- What the driver reads from the page after load: `window.__fw` (mode, hydrated, error count) and `window.__fwStage.env`
(present only when the page mounted a stage, with `missing`: the count of input writes whose owner element was not on the page). -/
structure Report where
  mode : Mode
  hydrated : Bool
  errors : Nat
  stage : Option Env
  missing : Nat
deriving Repr, DecidableEq

/-- The driver measures the page only when it is the kind of page the search asks for. A part-page search needs a
client-rendered page that mounted a stage at exactly the planned environment with every input write placed (`missing` = 0);
any other search needs a hydrated prerender. Both need `hydrated` and no hydration errors. -/
def accepts (q : String) (p : Size) (r : Report) : Bool :=
  r.hydrated && r.errors == 0 &&
    (if onlySearch q then r.mode == .clientRender && r.stage == some (plannedEnv p) && r.missing == 0 else r.mode == .hydrate)

/-- A prerendered page is accepted when hydrated without errors. -/
theorem accepts_hydrate (q : String) (p : Size) (r : Report) (hq : onlySearch q = false) (hm : r.mode = .hydrate)
    (hh : r.hydrated = true) (he : r.errors = 0) : accepts q p r = true := by
  simp [accepts, hq, hm, hh, he]

/-- A client-rendered page is accepted for a part-page search when it mounted the planned stage without errors. -/
theorem accepts_clientRender_stage (q : String) (p : Size) (r : Report) (hq : onlySearch q = true)
    (hm : r.mode = .clientRender) (hs : r.stage = some (plannedEnv p)) (hk : r.missing = 0) (hh : r.hydrated = true)
    (he : r.errors = 0) : accepts q p r = true := by
  simp [accepts, hq, hm, hs, hk, hh, he]

/-- A part page with an input write whose owner element was not on the page is refused: the part would be measured
with an input left unwritten. -/
theorem refuses_missing_inputs (q : String) (p : Size) (r : Report) (hq : onlySearch q = true) (hk : r.missing ≠ 0) :
    accepts q p r = false := by
  simp [accepts, hq, hk]

/-- `missing` is not read for a search without `only`. -/
theorem accepts_plain_ignores_missing (q : String) (p : Size) (r : Report) (hq : onlySearch q = false) :
    accepts q p r = accepts q p { r with missing := 0 } := by
  simp [accepts, hq]

/-- A client-rendered page is refused for a search without `only`. -/
theorem refuses_clientRender_plain (q : String) (p : Size) (r : Report) (hq : onlySearch q = false)
    (hm : r.mode = .clientRender) : accepts q p r = false := by
  simp [accepts, hq, hm]

/-- A hydrated page is refused for a part-page search (a stage page is never hydrated). -/
theorem refuses_hydrate_stage (q : String) (p : Size) (r : Report) (hq : onlySearch q = true)
    (hm : r.mode = .hydrate) : accepts q p r = false := by
  simp [accepts, hq, hm]

/-- A part page that mounted another environment, or none (an error page), is refused. -/
theorem refuses_wrong_stage (q : String) (p : Size) (r : Report) (hq : onlySearch q = true)
    (hs : r.stage ≠ some (plannedEnv p)) : accepts q p r = false := by
  simp [accepts, hq, hs]

/-- A mode that is neither `hydrate` nor `client-render` is refused. -/
theorem refuses_other_mode (q : String) (p : Size) (r : Report) (hm : r.mode = .other) : accepts q p r = false := by
  by_cases hq : onlySearch q = true <;> simp [accepts, hq, hm]

/-- A page that did not hydrate is refused. -/
theorem refuses_unhydrated (q : String) (p : Size) (r : Report) (hh : r.hydrated = false) : accepts q p r = false := by
  simp [accepts, hh]

/-- A page that logged hydration errors is refused, in either mode. -/
theorem refuses_errors (q : String) (p : Size) (r : Report) (he : r.errors ≠ 0) : accepts q p r = false := by
  simp [accepts, he]

/-- Where the driver reads the scroll position: `scrollY` on a page, `scrollingElement.scrollTop` on a stage page (its
`scrollY` is a pinned constant). -/
inductive ScrollRead | scrollY | scrollTop
deriving Repr, DecidableEq

/-- The scroll read of a search. Iff `only(q)`, else `scrollY` -/
def scrollRead (q : String) : ScrollRead := if onlySearch q then .scrollTop else .scrollY

/-- Wire name of a scroll read. -/
def ScrollRead.wire : ScrollRead → String
  | .scrollY => "scrollY" | .scrollTop => "scrollTop"

/-- A part page is read at the real scroll position; any other page is read as before. -/
theorem scrollRead_cases (q : String) :
    (onlySearch q = true → scrollRead q = .scrollTop) ∧ (onlySearch q = false → scrollRead q = .scrollY) := by
  constructor <;> intro h <;> simp [scrollRead, h]

/-- What the driver reads of the frame before the viewport gate: the page's pinned `innerWidth`/`innerHeight` (the stage
environment on a stage page), the real frame size from the native getters captured before any page script pins them, and the
layout viewport `clientWidth`/`clientHeight`. -/
structure Frame where
  pinned : Size
  real : Size
  client : Size
deriving Repr, DecidableEq

/-- The size the viewport gate decides on: the real frame size, on a stage page as on a whole page. `innerWidth` grows with
content that overflows under mobile emulation (frame size / minimum page scale), `clientWidth` does not, so only the real
frame size can catch the failure `Fw.Measure.Viewport` was written for. -/
def gateSize (f : Frame) : Size := f.real

/-- The viewport gate of the driver. -/
def viewportGate (profile : Size) (f : Frame) : Bool := viewportFaithful profile (gateSize f)

/-- The gate is the existing rule on the real frame size. -/
theorem viewportGate_real (profile : Size) (f : Frame) : viewportGate profile f = viewportFaithful profile f.real := rfl

/-- The gate ignores the pinned sizes and the layout viewport: frames with the same real size get the same verdict. -/
theorem viewportGate_ignores_pinned_client (profile : Size) (f f' : Frame) (h : f.real = f'.real) :
    viewportGate profile f = viewportGate profile f' := by
  simp [viewportGate, gateSize, h]

/-- A frame whose real size is not the profile is refused although the pinned sizes equal the profile and the layout viewport
is the profile (the overflowing page: pinned `430 × 932`, `clientWidth` `430`, real frame `645 × 1398`). -/
theorem viewportGate_refuses_overflow (profile : Size) (f : Frame) (h : f.real ≠ profile) : viewportGate profile f = false := by
  have : viewportFaithful profile f.real = false := by
    cases hf : viewportFaithful profile f.real with
    | false => rfl
    | true => exact absurd ((Fw.Measure.Viewport.accepts_iff profile f.real).1 hf) h
  simp [viewportGate, gateSize, this]

/-- A frame whose real size is the profile is accepted whatever the pinned sizes and the layout viewport are. -/
theorem viewportGate_accepts_real (profile : Size) (f : Frame) (h : f.real = profile) : viewportGate profile f = true := by
  simp [viewportGate, gateSize, h, viewportFaithful]

/-- The planned search of a target parses as the target's own search does, with the environment of the profile. With
`q_t = ?only=t` and `T = ids(parts) ++ [g1,...,g5]` the Bool splits on `parse(q_t)`: if it
is a stage, the planned search parses to the same target and members at `E(p)`; if it is a refusal `e` (a page-level part,
an empty group), the planned search parses to the same refusal `e`; any other case (`none`, or `plan = ⊥`) is false. Checked by
evaluation over `V` (the string round trip is not a theorem, accepted limit `parseEnv-stageParam-checked-not-proved`). -/
def roundTrips (vps : List Size) : Bool :=
  let targets := (parts.map (·.id)) ++ ["g1", "g2", "g3", "g4", "g5"]
  targets.all fun t => vps.all fun p =>
    let q := "?only=" ++ t
    match parse q, planSearch q p with
    | .ok s, some q' => (match parse q' with | .ok s' => s'.target == s.target && s'.members == s.members && s'.env == plannedEnv p | _ => false)
    | .err e, some q' => (match parse q' with | .err e' => e == e' | _ => false)
    | _, _ => false

/-- Viewports of the profiles in `packages/measure-chromium/profiles` plus two more phone sizes. -/
def viewports : List Size := [⟨430, 932⟩, ⟨390, 844⟩, ⟨360, 640⟩]

/-- Boundary sizes of the stage grammar: one to five digits, both ends of the valid range. -/
def boundarySizes : List Size :=
  [1, 9, 10, 99, 100, 999, 1000, 9999, 10000].flatMap fun w => [1, 9, 10, 99, 100, 999, 1000, 9999, 10000].map fun h => ⟨w, h⟩

#guard roundTrips viewports
#guard roundTrips boundarySizes
#guard planSearch "?only=hero" ⟨430, 932⟩ == some "?only=hero&stage=vw:430,vh:932"
#guard planSearch "?preset=v2-proved&only=hero.exit" ⟨390, 844⟩ == some "?preset=v2-proved&only=hero.exit&stage=vw:390,vh:844"
#guard planSearch "?only=hero&stage=y:5" ⟨430, 932⟩ == none
#guard planSearch "?fw=a:b" ⟨430, 932⟩ == some "?fw=a:b"
#guard planSearch "" ⟨430, 932⟩ == some ""
#guard onlySearch "?only=hero" && !onlySearch "?fw=only" && !onlySearch "?stage=y:1"

/-- Profile viewport used by the golden. -/
def goldenProfile : Size := ⟨430, 932⟩

/-- Queries of the plan vectors. -/
def planQueries : List String :=
  ["", "?", "?fw=original", "?preset=v2-proved", "?preset=v2-proved&fw=hero.countdown:strip", "?stage=y:100", "?only=hero",
   "?only=hero.exit", "?only=g1", "?only=g2", "?only=g4", "?only=morph.tween", "?only=nope", "?only", "?only=",
   "?preset=v2-proved&only=hero", "?fw=hero.countdown:strip&only=nav", "?only=hero&stage=y:5", "?only=hero&stage=vw:430,vh:932",
   "?stage=vw:1,vh:1&only=hero", "?only=hero&only=nav"]

/-- JSON of an optional search. -/
def optStr : Option String → String | some s => jstr s | none => "null"

/-- JSON of what `Stage.parse` makes of a planned search: `null` when not a stage page, else the refusal code or the
environment. -/
def parseJson (q : String) : String :=
  match parse q with
  | .none => "{\"kind\":\"none\"}"
  | .err e => "{\"kind\":\"err\",\"code\":" ++ jstr e.name ++ "}"
  | .ok s => "{\"kind\":\"ok\",\"target\":" ++ jstr s.target ++ ",\"env\":[" ++ toString s.env.y ++ "," ++ toString s.env.vw ++ "," ++ toString s.env.vh ++ "]}"

/-- Plan vectors. -/
def planRows : List String :=
  (planQueries.flatMap fun q => viewports.map fun p => (q, p)).map fun (q, p) =>
    let r := planSearch q p
    "{\"kind\":\"plan\",\"query\":" ++ jstr q ++ ",\"profile\":[" ++ toString p.w ++ "," ++ toString p.h ++ "],\"only\":" ++
      toString (onlySearch q) ++ ",\"search\":" ++ optStr r ++ ",\"parsed\":" ++ (match r with | some s => parseJson s | none => "null") ++ "}"

/-- Queries of the accept and read vectors: plain and part-page searches. -/
def modeQueries : List String := ["", "?fw=original", "?only=hero&stage=vw:430,vh:932", "?preset=v2-proved&only=g1&stage=vw:430,vh:932"]

/-- Environments a page can report. -/
def stageReports : List (Option Env) := [none, some (plannedEnv goldenProfile), some Env.default, some { plannedEnv goldenProfile with y := 300 }]

/-- JSON of an optional environment. -/
def optEnv : Option Env → String
  | some e => "[" ++ toString e.y ++ "," ++ toString e.vw ++ "," ++ toString e.vh ++ "]"
  | none => "null"

/-- Accept vectors. For every mode, `hydrated`, error count 0 and 1, stage report and missing count 0 and 1. -/
def acceptRows : List String :=
  modeQueries.flatMap fun q => [Mode.hydrate, .clientRender, .other].flatMap fun m => [true, false].flatMap fun h =>
    [0, 1].flatMap fun e => stageReports.flatMap fun s => [0, 1].map fun k =>
      let r : Report := { mode := m, hydrated := h, errors := e, stage := s, missing := k }
      "{\"kind\":\"accept\",\"query\":" ++ jstr q ++ ",\"profile\":[" ++ toString goldenProfile.w ++ "," ++ toString goldenProfile.h ++
        "],\"mode\":" ++ jstr m.wire ++ ",\"hydrated\":" ++ toString h ++ ",\"errors\":" ++ toString e ++ ",\"stage\":" ++ optEnv s ++
        ",\"missing\":" ++ toString k ++ ",\"accept\":" ++ toString (accepts q goldenProfile r) ++ "}"

/-- Sizes the gate vectors read. -/
def sizes : List Size := [⟨430, 932⟩, ⟨645, 1398⟩, ⟨1280, 800⟩]

/-- JSON of a size. -/
def sizeJson (s : Size) : String := "[" ++ toString s.w ++ "," ++ toString s.h ++ "]"

/-- Read vectors: the scroll read of a plain and a part-page search, and the viewport gate over every pinned, real and
layout-viewport size triple. The gate decides on the real size alone, so the row `pinned` `(430,932)`, `client` `(430,932)`,
`real` `(645,1398)` is refused. -/
def readRows : List String :=
  modeQueries.flatMap fun q => sizes.flatMap fun i => sizes.flatMap fun r => sizes.map fun c =>
    let f : Frame := { pinned := i, real := r, client := c }
    "{\"kind\":\"read\",\"query\":" ++ jstr q ++ ",\"profile\":[430,932],\"pinned\":" ++ sizeJson i ++ ",\"real\":" ++ sizeJson r ++
      ",\"client\":" ++ sizeJson c ++ ",\"scrollRead\":" ++ jstr (scrollRead q).wire ++ ",\"gateSize\":" ++ sizeJson (gateSize f) ++
      ",\"faithful\":" ++ toString (viewportGate goldenProfile f) ++ "}"

/-- Text of `packages/contracts/golden/parts/stage-mode.jsonl`: a premise line, then plan, accept and read rows. -/
def goldenText : String :=
  String.join ((("{\"kind\":\"premise\",\"premise\":" ++ jstr premise ++ ",\"yFollowsPlan\":false,\"scope\":\"own band, y pinned\"}") ::
    (planRows ++ acceptRows ++ readRows)).map (· ++ "\n"))

/-- Command-line driver (`lean/scripts/StageModeGolden.lean`): no argument prints the golden; `--check <file>` exits 0 when
the file holds exactly the generated bytes, 1 otherwise; any other arguments exit 2. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | [] => IO.print goldenText; return 0
  | ["--check", f] =>
    let cur ← IO.FS.readBinFile f
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"stage-mode golden: {f} is up to date"
      return 0
    IO.eprintln s!"stage-mode golden: {f} differs from the generated bytes"
    return 1
  | _ => IO.eprintln "usage: StageModeGolden [--check <stage-mode.jsonl>]"; return 2

end Fw.Site.StageMode
