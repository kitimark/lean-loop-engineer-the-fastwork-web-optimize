import Fw.Parts.NavEarnOpt
import Fw.Preset.Gen
/-!
# What a look change gives, what it changes, and why

The information panel of a look-change review card: a gain table per flag (each row with its status), the code ranges the
flag changes, the mechanism and the formulas with their Lean sources. The model rows are computed from `NavEarnOpt.countFor`
(the same function that writes `golden/parts/nav-earn.jsonl`), so they cannot differ from it. The measured rows are those of
`research/notes/2026/10-20-earn-transition-retarget.md`.
-/
namespace Fw.Console.ReviewInfo
open Fw.Parts

/-- Where a row's numbers come from. A gain is never listed without one. -/
inductive Status
  | measured (runs aa : List String)
  | modelled (thm golden : String)
  | unknown (why : String)
deriving DecidableEq, Repr

/-- One row of the gain table. `before` and `after` are ranges (low, high) of a count; the unit says what is counted. -/
structure Gain where
  metric : String
  engine : String
  push : String
  viewport : String
  before : Option (Nat × Nat)
  after : Option (Nat × Nat)
  noise : Nat
  unit : String
  status : Status
deriving DecidableEq, Repr

/-- What a row shows as its delta. -/
inductive Shown
  | gain (n : Nat)
  | noSaving
  | inNoise
  | worse (n : Nat)
  | unknown
deriving DecidableEq, Repr

/-- The delta of a row, worst case over the ranges: the lowest `before` minus the highest `after`. -/
def Gain.delta (g : Gain) : Option Int :=
  match g.before, g.after with
  | some b, some a => some ((b.1 : Int) - a.2)
  | _, _ => none

/-- What a row shows. A gain shows only when it exceeds the noise; a delta within the noise (either sign) is not shown. -/
def shownOf (noise : Nat) (d : Option Int) : Shown :=
  match d with
  | none => .unknown
  | some d =>
    if (noise : Int) < d then .gain d.toNat
    else if d < -(noise : Int) then .worse (-d).toNat
    else if noise = 0 then .noSaving
    else .inNoise

/-- A gain is shown only when it is larger than the noise. -/
theorem gain_beats_noise (noise : Nat) (d : Option Int) (n : Nat) (h : shownOf noise d = .gain n) :
    ∃ e, d = some e ∧ (noise : Int) < e := by
  unfold shownOf at h
  split at h
  · simp at h
  · rename_i e
    split at h
    · rename_i hl; exact ⟨e, rfl, hl⟩
    · split at h <;> (try split at h) <;> simp at h

/-- A delta inside the noise (and a noise above zero) is `inNoise`, never a gain or a loss. -/
theorem in_noise_hidden (noise : Nat) (e : Int) (hn : 0 < noise) (h1 : e ≤ noise) (h2 : -(noise : Int) ≤ e) :
    shownOf noise (some e) = .inNoise := by
  unfold shownOf
  have a : ¬ (noise : Int) < e := by omega
  have b : ¬ e < -(noise : Int) := by omega
  have c : noise ≠ 0 := by omega
  simp [a, b, c]

/-- An unknown row has no delta. -/
theorem unknown_no_delta (g : Gain) (h : g.before = none) : shownOf g.noise g.delta = .unknown := by
  simp [Gain.delta, h, shownOf]

private def earnRuns : List String := ["39463486725", "39464309993"]
private def earnAA : List String := ["39464294630", "39464322751"]
private def vpWord : String := "1440 and 390 (same)"

/-- The work count of a property of the earn button on one push at both viewports, from the model that writes the golden. -/
def modelCount (n : String) (a b : Rat) : Option (Nat × Nat) :=
  match NavEarnOpt.countFor ⟨1440, 900⟩ a b n, NavEarnOpt.countFor ⟨390, 844⟩ a b n with
  | some d, some p => if d == p then some (d.faithful, d.arm) else none
  | _, _ => none

private def model (metric n push : String) (a b : Rat) : Gain :=
  match modelCount n a b with
  | some (f, r) => { metric := metric, engine := "model (both engines)", push := push, viewport := vpWord, before := some (f, f), after := some (r, r),
                      noise := 0, unit := "frames of 91 with a style change", status := .modelled "Fw.Parts.NavEarnOpt.work_le" "golden/parts/nav-earn.jsonl (Fw.Parts.MorphTween time tween)" }
  | none => { metric := metric, engine := "model (both engines)", push := push, viewport := vpWord, before := none, after := none, noise := 0,
                      unit := "frames", status := .unknown "the model gives different counts at the two viewports" }

private def meas (metric push viewport : String) (b a : Nat × Nat) : Gain :=
  { metric := metric, engine := "chromium", push := push, viewport := viewport, before := some b, after := some a, noise := 2,
    unit := "frames whose value differs from the previous (3 reps)", status := .measured earnRuns earnAA }

private def webkit (push : String) : Gain :=
  { metric := "earn value changes", engine := "webkit", push, viewport := "390 and 1280", before := none, after := none, noise := 0,
    unit := "-", status := .unknown "playwright-webkit on Linux samples 3 to 9 frames per push, too few to count changes; WebKit paint and composite counters are a follow-up" }

/-- The gain table of `nav:earn-no-transition`. -/
def earnGains (_ : Unit := ()) : List Gain :=
  [ model "earn max-width" "maxW" "open" 0 1, model "earn padding-inline" "pad" "open" 0 1, model "earn opacity" "opacity" "open" 0 1,
    model "earn max-width" "maxW" "close" 1 0, model "earn padding-inline" "pad" "close" 1 0, model "earn opacity" "opacity" "close" 1 0,
    meas "earn max-width changes" "open" "390" (41, 41) (1, 4), meas "earn opacity changes" "open" "390" (18, 18) (1, 4),
    meas "earn max-width changes" "open" "1280" (17, 21) (3, 3), meas "earn opacity changes" "open" "1280" (6, 8) (3, 3),
    meas "earn max-width changes" "close" "390" (38, 40) (40, 41), meas "earn opacity changes" "close" "390" (12, 12) (25, 26),
    meas "earn max-width changes" "close" "1280" (23, 25) (21, 24), meas "earn opacity changes" "close" "1280" (9, 10) (13, 13),
    webkit "open", webkit "close" ]

-- the model rows are the golden counts (research note: open 43 to 3, 43 to 3, 29 to 3; close 65, 65, 51 unchanged)
#guard ((earnGains ()).take 6).map (fun g => (g.before, g.after)) ==
  [(some (43, 43), some (3, 3)), (some (43, 43), some (3, 3)), (some (29, 29), some (3, 3)),
   (some (65, 65), some (65, 65)), (some (65, 65), some (65, 65)), (some (51, 51), some (51, 51))]
#guard ((earnGains ()).take 6).map (fun g => shownOf g.noise g.delta) ==
  [.gain 40, .gain 40, .gain 26, .noSaving, .noSaving, .noSaving]
-- measured: open gains beat the noise; the close push is inside it; WebKit is unknown
#guard ((earnGains ()).drop 6).map (fun g => shownOf g.noise g.delta) ==
  [.gain 37, .gain 14, .gain 14, .gain 3, .worse 3, .worse 14, .inNoise, .worse 4, .unknown, .unknown]

/-- A code range a flag changes: the file, the lines, an anchor that must still be inside them, and which arm it belongs to. -/
structure Excerpt where
  id : String
  side : String
  file : String
  first : Nat
  last : Nat
  anchor : String
  note : String
deriving DecidableEq, Repr

/-- The code the flag changes (restated from the repository at request time by the console, never copied here). -/
def earnExcerpts : List Excerpt :=
  [ { id := "css-rule", side := "faithful", file := "apps/site/src/parts/nav/nav.module.css", first := 167, last := 185,
      anchor := "max-width 0.68s",
      note := "Both arms. The three properties are functions of --morph and carry a 680 ms transition (opacity 320 ms after a 120 ms delay)." },
    { id := "css-flag", side := "flag", file := "apps/site/src/parts/nav/nav.module.css", first := 201, last := 203,
      anchor := "transition: none",
      note := "Flag only: while the nav carries is-earn-still, the button has no transition, so it shows the computed value." },
    { id := "js-decision", side := "flag", file := "apps/site/src/parts/nav/logic.ts", first := 92, last := 95,
      anchor := "return !(flag && morphing)",
      note := "The decision (Lean transitionsOn): transitions run unless the flag is on and the nav is morphing." },
    { id := "js-morphing", side := "both", file := "apps/site/src/parts/nav/logic.ts", first := 63, last := 63,
      anchor := "m > MORPHING_CUT",
      note := "The nav counts as morphing above m = 0.001." },
    { id := "js-apply", side := "flag", file := "apps/site/src/parts/nav/index.tsx", first := 104, last := 104,
      anchor := "EARN_STILL_CLASS",
      note := "Each frame the class is set from the decision. Without the flag the call is always true, so the class is never set." } ]

/-- A step of the mechanism, in plain words. -/
def earnMechanism : List String :=
  [ "Each frame --morph changes, so the computed max-width, padding-inline and opacity of the earn button change (nav.module.css:173-175).",
    "The same rule lists transitions: 680 ms for max-width and padding-inline, 320 ms after a 120 ms delay for opacity (nav.module.css:179-182).",
    "In both engines a changed computed value while a transition runs cancels it and starts a new one from the value shown now, with the full duration and delay. So every frame restarts a 680 ms transition and the 120 ms delay.",
    "The curve starts flat and each restart begins at its start, so the shown value creeps while the computed value moves; the opacity does not move at all until the computed value stops changing (Lean faithful_lags).",
    "The flag sets is-earn-still while the nav morphs, which turns the transitions off. An unlisted property shows its computed value, so the button follows --morph directly (Lean shown_off).",
    "On the open push the computed values reach their end at frame 3 (--earn-out saturates at m = 0.2), so the flag restyles the button on 3 frames instead of 43. On the close push the transitions return at m <= 0.001 (frame 37), so the last steps still run as transitions and the work count is the same." ]

/-- An engine source line that supports the mechanism. -/
structure Source where
  claim : String
  status : String
  cite : String
deriving DecidableEq, Repr

/-- The engine sources of the mechanism (research note, table "Engine source"). -/
def earnSources : List Source :=
  [ { claim := "WebKit: a computed-value change of a listed property while a transition runs cancels it and starts a new one from the current value, with the full duration and delay",
      status := "CONFIRMED", cite := "WebKit@862f17d Source/WebCore/style/Styleable.cpp:743-756" },
    { claim := "Chromium: a running transition whose end value differs from the after-change value is cancelled and a new one starts from the before-change style, which includes the current animated value",
      status := "CONFIRMED", cite := "Chromium@f842f52 third_party/blink/renderer/core/animation/css/css_animations.cc:2703-2715, 2727-2732, 3191" },
    { claim := "WebKit: a property the new style does not list starts no transition and cancels a running one",
      status := "CONFIRMED", cite := "WebKit@862f17d Source/WebCore/style/Styleable.cpp:648-654, 683-690" },
    { claim := "Chromium: active transitions on properties that are no longer listed are cancelled",
      status := "CONFIRMED", cite := "Chromium@f842f52 css_animations.cc:3175-3182" } ]

/-- A formula, written from a Lean statement. `kind` is `theorem`, `def` or `guard` (a `#guard` witness); `line` is where the Lean
declaration starts (a test checks that the name is on that line). -/
structure Formula where
  id : String
  tex : String
  says : String
  decl : String
  file : String
  line : Nat
  kind : String
deriving DecidableEq, Repr

private def nf : String := "lean/Fw/Parts/NavEarnOpt.lean"

/-- The formulas of the earn flag. Notation: `g_k` the computed value at frame `k`, `t_k` the time of frame `k`, `\delta` and `d`
the delay and duration of the transition, `\mathrm{on}_k` whether the property is listed. -/
def earnFormulas : List Formula :=
  [ { id := "on", tex := "\\mathrm{on}(f,m)=\\lnot(f\\wedge m)", says := "Transitions are listed unless the flag is on and the nav is morphing.",
      decl := "transitionsOn", file := nf, line := 16, kind := "def" },
    { id := "off", tex := "\\mathrm{on}_k=\\mathrm{false}\\ \\Rightarrow\\ \\mathrm{shown}_k=g_k",
      says := "Unlisted, the button shows the computed value: it follows --morph with no lag.",
      decl := "shown_off", file := nf, line := 88, kind := "theorem" },
    { id := "lags", tex := "\\mathrm{live}(\\mathrm{run}_k)=\\mathrm{false}\\ \\wedge\\ g_{k+1}\\neq g_k\\ \\Rightarrow\\ \\mathrm{shown}_{k+1}=g_k",
      says := "Faithful arm, from rest: at the frame the computed value changes, the old value is still shown.",
      decl := "faithful_lags", file := nf, line := 107, kind := "theorem" },
    { id := "settled", tex := "\\big(\\forall i\\in(j,j{+}n]:\\ g_i=g_j\\big)\\wedge t_j+\\delta+d\\le t_{j+n}\\ \\Rightarrow\\ \\mathrm{shown}_{j+n}=g_{j+n}",
      says := "Once the computed value has been still for the delay plus the duration, every arm shows it.",
      decl := "shown_settled", file := nf, line := 145, kind := "theorem" },
    { id := "same", tex := "\\forall\\,\\mathrm{draw}:\\ \\mathrm{draw}\\big(\\mathrm{shown}^{\\mathrm{on}}_{j+n}\\big)=\\mathrm{draw}\\big(\\mathrm{shown}^{\\mathrm{on}'}_{j+n}\\big)\\quad\\text{on every settled window }(j,n)",
      says := "On settled frames the two arms look the same (VisSame E), for any scene drawn from the shown value.",
      decl := "visSame_settled", file := nf, line := 177, kind := "theorem" },
    { id := "work", tex := "\\mathrm{work}_{\\mathrm{on}}(n)=\\#\\{k<n\\mid \\mathrm{dirty}_{\\mathrm{on}}(k)\\},\\quad \\mathrm{dirty}(k{+}1)=[g_{k+1}\\neq g_k]\\vee\\mathrm{running}_{k+1}",
      says := "The work of a property is the number of frames on which its style changes: the value moved or a transition runs.",
      decl := "work", file := nf, line := 192, kind := "def" },
    { id := "worklE", tex := "\\mathrm{work}_{\\mathrm{on}}(n)\\ \\le\\ \\mathrm{work}_{\\mathrm{faithful}}(n)",
      says := "Over any frame range, the flag restyles the property on at most as many frames as the faithful arm.",
      decl := "work_le", file := nf, line := 230, kind := "theorem" },
    { id := "saving", tex := "s=\\mathrm{work}_{\\mathrm{faithful}}-\\mathrm{work}_{\\mathrm{flag}}\\ \\ge 0:\\quad 43-3=40,\\ \\ 29-3=26\\ (\\text{open}),\\ \\ 65-65=0,\\ \\ 51-51=0\\ (\\text{close})",
      says := "The saving is never negative (work_le); the model gives these counts at 1440 and 390 for 91 frames.",
      decl := "countFor", file := nf, line := 371, kind := "guard" },
    { id := "trace", tex := "\\mathrm{trace}\\ k\\ (\\mathrm{run}_k)\\ m=\\big[\\mathrm{run}_{k+i}\\big]_{i=0}^{m}",
      says := "The linear-time trace the golden uses equals the per-frame state, so the golden counts are the model's.",
      decl := "trace_eq", file := nf, line := 255, kind := "theorem" },
    { id := "all3", tex := "K\\in\\mathrm{Settled3}\\ \\Rightarrow\\ \\forall p\\in\\{\\mathrm{maxW},\\mathrm{pad},\\mathrm{opacity}\\}:\\ \\mathrm{shown}^{\\mathrm{on}}_p(K)=\\mathrm{shown}^{\\mathrm{on}'}_p(K)",
      says := "At a frame where all three properties have settled, each shows the same value in both arms.",
      decl := "settled3_same", file := nf, line := 429, kind := "theorem" },
    { id := "window", tex := "40\\cdot\\tfrac{50}{3}\\approx 666.7\\ \\mathrm{ms}<680\\ \\mathrm{ms}=\\max(0{+}680,\\,120{+}320)\\le 41\\cdot\\tfrac{50}{3}\\approx 683.3\\ \\mathrm{ms}",
      says := "The morph stops at frame 41; 41 more frames (683 ms) cover the longest delay plus duration, 40 do not. Witnessed per push and viewport.",
      decl := "settled3B", file := nf, line := 448, kind := "guard" } ]

/-- The info of a flag: `none` when no table is written for it. -/
def infoFor (key : String) : Option (List Gain × List Excerpt × List String × List Source × List Formula) :=
  if key == "nav:earn-no-transition" then some (earnGains (), earnExcerpts, earnMechanism, earnSources, earnFormulas) else none

/-- The summary line, computed from the table. -/
def earnSummary (_ : Unit := ()) : String :=
  match (earnGains ()).take 6 with
  | [mw, _, op, cmw, _, _] =>
    let n (g : Gain) := match shownOf g.noise g.delta with | .gain k => k | _ => 0
    s!"Open push: the earn button restyles {n mw} fewer frames for max-width and {n op} fewer for opacity (modelled, Chromium measured the same direction); close push: no saving ({n cmw}); WebKit: unknown."
  | _ => ""

#guard earnSummary () == "Open push: the earn button restyles 40 fewer frames for max-width and 26 fewer for opacity (modelled, Chromium measured the same direction); close push: no saving (0); WebKit: unknown."

end Fw.Console.ReviewInfo
