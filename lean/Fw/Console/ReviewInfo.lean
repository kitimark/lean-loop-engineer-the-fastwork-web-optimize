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

/-- What a row shows as its delta. `overlap`: the two ranges share a count, so no difference is shown. -/
inductive Shown
  | gain (n : Nat)
  | noSaving
  | inNoise
  | overlap
  | worse (n : Nat)
  | unknown
deriving DecidableEq, Repr

/-- The cautious delta of a gain: the lowest `before` minus the highest `after` (the least the flag can have saved). -/
def gainLow (b a : Nat × Nat) : Int := (b.1 : Int) - a.2

/-- The cautious delta of a loss: the highest `before` minus the lowest `after` (the least the flag can have cost; negative
when the flag did cost). -/
def lossHigh (b a : Nat × Nat) : Int := (b.2 : Int) - a.1

/-- The ranges share a count. -/
def overlaps (b a : Nat × Nat) : Bool := decide (a.1 ≤ b.2 ∧ b.1 ≤ a.2)

/-- What a row shows. A gain shows only when its cautious bound beats the noise; a loss shows only when its cautious bound
(the other end of each range) is worse than minus the noise; overlapping ranges show no difference; a delta inside the noise
is not shown. -/
def shownOf (noise : Nat) (b a : Option (Nat × Nat)) : Shown :=
  match b, a with
  | some b, some a =>
    if (noise : Int) < gainLow b a then .gain (gainLow b a).toNat
    else if lossHigh b a < -(noise : Int) then .worse (-(lossHigh b a)).toNat
    else if noise = 0 then .noSaving
    else if overlaps b a then .overlap
    else .inNoise
  | _, _ => .unknown

/-- A gain is shown only when its cautious bound is larger than the noise. -/
theorem gain_beats_noise (noise : Nat) (b a : Option (Nat × Nat)) (n : Nat) (h : shownOf noise b a = .gain n) :
    ∃ x y, b = some x ∧ a = some y ∧ (noise : Int) < gainLow x y := by
  unfold shownOf at h
  split at h
  · rename_i x y
    split at h
    · rename_i hl; exact ⟨x, y, rfl, rfl, hl⟩
    · split at h <;> (try split at h) <;> (try split at h) <;> simp at h
  · simp at h

/-- A loss is shown only when its cautious bound (highest before minus lowest after) is below minus the noise. -/
theorem worse_beats_noise (noise : Nat) (b a : Option (Nat × Nat)) (n : Nat) (h : shownOf noise b a = .worse n) :
    ∃ x y, b = some x ∧ a = some y ∧ lossHigh x y < -(noise : Int) := by
  unfold shownOf at h
  split at h
  · rename_i x y
    split at h
    · simp at h
    · split at h
      · rename_i hl; exact ⟨x, y, rfl, rfl, hl⟩
      · split at h <;> (try split at h) <;> simp at h
  · simp at h

/-- Overlapping ranges are never a gain or a loss, whatever the noise. -/
theorem overlap_no_difference (noise : Nat) (b a : Nat × Nat) (h : overlaps b a = true) :
    shownOf noise (some b) (some a) = .noSaving ∨ shownOf noise (some b) (some a) = .overlap := by
  unfold overlaps at h
  have h' := of_decide_eq_true h
  unfold shownOf gainLow lossHigh
  have a1 : ¬ (noise : Int) < (b.1 : Int) - a.2 := by omega
  have a2 : ¬ (b.2 : Int) - a.1 < -(noise : Int) := by omega
  simp only [a1, a2, ite_false]
  by_cases hn : noise = 0
  · simp [hn]
  · simp [hn, overlaps, h]

/-- A delta inside the noise (and a noise above zero) is `inNoise` or `overlap`, never a gain or a loss. -/
theorem in_noise_hidden (noise : Nat) (b a : Nat × Nat) (hn : 0 < noise) (h1 : gainLow b a ≤ noise)
    (h2 : -(noise : Int) ≤ lossHigh b a) :
    shownOf noise (some b) (some a) = .inNoise ∨ shownOf noise (some b) (some a) = .overlap := by
  unfold shownOf
  have a1 : ¬ (noise : Int) < gainLow b a := by omega
  have a2 : ¬ lossHigh b a < -(noise : Int) := by omega
  have c : noise ≠ 0 := by omega
  simp only [a1, a2, c, ite_false]
  split <;> simp

/-- What a row shows. -/
def Gain.shown (g : Gain) : Shown := shownOf g.noise g.before g.after

/-- An unknown row has no delta. -/
theorem unknown_no_delta (noise : Nat) (a : Option (Nat × Nat)) : shownOf noise none a = .unknown := by
  simp [shownOf]

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

/-- The A/A noise of a measured row, in the row's own metric: the largest cautious delta (gain bound or loss bound, either sign)
between the `base` and `cand` arms of the two A/A runs `earnAA`, over the widths 390, 640, 641, 1280 and both pushes. MEASURED:
`research/notes/2026/10-20-earn-transition-retarget.md`, table "A/A value changes". Opacity 2, max-width 4. -/
def aaNoise (metric : String) : Nat := if metric == "earn opacity changes" then 2 else 4

private def meas (metric push viewport : String) (b a : Nat × Nat) : Gain :=
  { metric := metric, engine := "chromium", push := push, viewport := viewport, before := some b, after := some a, noise := aaNoise metric,
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
    meas "earn max-width changes" "open" "640" (29, 30) (4, 4), meas "earn opacity changes" "open" "640" (11, 12) (4, 4),
    meas "earn max-width changes" "open" "641" (29, 30) (1, 2), meas "earn opacity changes" "open" "641" (11, 12) (1, 2),
    webkit "open", webkit "close" ]

-- the model rows are the golden counts (research note: open 43 to 3, 43 to 3, 29 to 3; close 65, 65, 51 unchanged)
#guard ((earnGains ()).take 6).map (fun g => (g.before, g.after)) ==
  [(some (43, 43), some (3, 3)), (some (43, 43), some (3, 3)), (some (29, 29), some (3, 3)),
   (some (65, 65), some (65, 65)), (some (65, 65), some (65, 65)), (some (51, 51), some (51, 51))]
#guard ((earnGains ()).take 6).map (fun g => g.shown) == [.gain 40, .gain 40, .gain 26, .noSaving, .noSaving, .noSaving]
-- measured, in the order of the 390 and 1280 rows: open gains beat the noise; 390 close max-width overlaps (38-40 and 40-41), 390 close
-- opacity (12 against 25-26) is a loss of 13 by the cautious bound, 1280 close max-width overlaps, 1280 close opacity (9-10 against 13) a loss of 3
#guard ((earnGains ()).drop 6 |>.take 8).map (fun g => g.shown) ==
  [.gain 37, .gain 14, .gain 14, .gain 3, .overlap, .worse 13, .overlap, .worse 3]
#guard ((earnGains ()).drop 14 |>.take 4).map (fun g => g.shown) == [.gain 25, .gain 7, .gain 27, .gain 9]
#guard ((earnGains ()).drop 18).map (fun g => g.shown) == [.unknown, .unknown]
-- the same rule on the three cases the review named
#guard shownOf 4 (some (38, 40)) (some (40, 41)) == .overlap
#guard shownOf 2 (some (12, 12)) (some (25, 26)) == .worse 13
#guard shownOf 2 (some (9, 10)) (some (13, 13)) == .worse 3

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
    "The curve starts flat and each restart begins at its start, so the shown value creeps while the computed value moves. At the frame the computed value first changes from rest, the old value is still shown (Lean faithful_lags, one frame). Over a whole close push the faithful opacity stays at 0 until the morph stops: #guard witnesses NavEarnOpt.lean:376 (frame 37, faithful 0) and :391 (opacity value changes 20 against 40).",
    "The flag sets is-earn-still while the nav morphs, which turns the transitions off. An unlisted property shows its computed value, so the button follows --morph directly (Lean shown_off).",
    "On the open push the computed values reach their end at frame 3 (--earn-out saturates at m = 0.2), so the flag restyles the button on 3 frames instead of 43. On the close push the transitions return at m <= 0.001 (frame 37), so the last steps still run as transitions and the work count is the same.",
    "A row that says 'N more' counts value changes, not restyle work. On the close push the faithful opacity is held at 0 by the restarting 120 ms delay, so it changes on fewer frames, yet the faithful arm restyles the button on as many frames as the flag arm (modelled work 51 against 51 of 91, golden nav-earn.jsonl fn=work); the flag arm's opacity follows the morph and so changes value more often.",
    "A delta uses the cautious bound of its direction: a gain is the lowest faithful count minus the highest flag count, a loss is the highest faithful count minus the lowest flag count; ranges that share a count show no difference. A gain is shown only when its bound is greater than the noise, a loss only when its bound is below minus the noise ('N more' is minus the loss bound). A delta inside the A/A noise of the same metric is not shown. The 640 and 641 close rows are left out: the research note's value-change table has only their open rows." ]

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
    { id := "lags", tex := "0\\le\\delta,\\ 0<d,\\ \\mathrm{live}(\\mathrm{run}^{F}_k)=\\mathrm{false},\\ g_{k+1}\\neq g_k\\ \\Rightarrow\\ \\mathrm{shown}^{F}_{k+1}=g_k",
      says := "Faithful arm F (on_k = true for every k), from rest: at the frame the computed value changes, the old value is still shown. One frame only; the longer hold is witnessed by #guards (mechanism step 4).",
      decl := "faithful_lags", file := nf, line := 107, kind := "theorem" },
    { id := "settled", tex := "t\\ \\text{monotone},\\ 0<d,\\ \\big(\\forall i\\in(j,j{+}n]:\\ g_i=g_j\\big),\\ t_j+\\delta+d\\le t_{j+n}\\ \\Rightarrow\\ \\mathrm{shown}_{j+n}=g_{j+n}",
      says := "Once the computed value has been still for the delay plus the duration, every arm shows it.",
      decl := "shown_settled", file := nf, line := 145, kind := "theorem" },
    { id := "same", tex := "t\\ \\text{monotone},\\ 0<d\\ \\Rightarrow\\ \\forall\\,\\mathrm{draw},\\mathrm{env},\\ \\forall (j,n)\\in\\mathrm{Settled}:\\ \\mathrm{visible}_{vp(\\mathrm{env})}\\big(\\mathrm{draw}_{\\mathrm{env}}(\\mathrm{shown}^{\\mathrm{on}}_{j+n})\\big)=\\mathrm{visible}_{vp(\\mathrm{env})}\\big(\\mathrm{draw}_{\\mathrm{env}}(\\mathrm{shown}^{\\mathrm{on}'}_{j+n})\\big)",
      says := "With frame times in order and a positive duration, on settled frames the two arms look the same in every viewport (VisSame E): what is visible after clipping to the viewport is equal, for any scene drawn from the shown value.",
      decl := "visSame_settled", file := nf, line := 177, kind := "theorem" },
    { id := "work", tex := "\\mathrm{work}_{\\mathrm{on}}(n)=\\#\\{k<n\\mid \\mathrm{dirty}_{\\mathrm{on}}(k)\\},\\quad \\mathrm{dirty}(0)=\\mathrm{false},\\ \\mathrm{dirty}(k{+}1)=[g_{k+1}\\neq g_k]\\vee\\mathrm{running}_{k+1},\\ \\mathrm{running}_{k}=\\mathrm{live}(\\mathrm{run}_k)\\wedge t_k<\\mathrm{start}(\\mathrm{run}_k)+\\delta+d",
      says := "The work of a property is the number of frames on which its style changes: the value moved or a transition runs.",
      decl := "work", file := nf, line := 192, kind := "def" },
    { id := "worklE", tex := "\\mathrm{work}_{\\mathrm{on}}(n)\\ \\le\\ \\mathrm{work}_{\\mathrm{faithful}}(n)",
      says := "Over the first n frames, for every n, the flag restyles the property on at most as many frames as the faithful arm.",
      decl := "work_le", file := nf, line := 230, kind := "theorem" },
    { id := "saving", tex := "s=\\mathrm{work}_{\\mathrm{faithful}}-\\mathrm{work}_{\\mathrm{flag}}\\ \\ge 0:\\quad 43-3=40,\\ \\ 29-3=26\\ (\\text{open}),\\ \\ 65-65=0,\\ \\ 51-51=0\\ (\\text{close})",
      says := "The saving is never negative: work_le bounds the model's work, and the golden counts are the model's because trace_eq equates the trace countFor reads with the per-frame state and dirtyAt is dirty by construction (that last link is by construction, not a theorem). The numbers are the fn=work lines of packages/contracts/golden/parts/nav-earn.jsonl (1440 and 390, 91 frames); the #guards at NavEarnOpt.lean:371-373 witness 43-3, 29-3 and the close max-width count only.",
      decl := "countFor", file := nf, line := 371, kind := "guard" },
    { id := "trace", tex := "\\mathrm{trace}\\ k\\ (\\mathrm{run}_k)\\ m=\\big[\\mathrm{run}_{k+i}\\big]_{i=0}^{m}",
      says := "The linear-time trace the golden uses equals the per-frame state, so the golden counts are the model's.",
      decl := "trace_eq", file := nf, line := 255, kind := "theorem" },
    { id := "all3", tex := "K\\in\\mathrm{Settled3}\\ \\Rightarrow\\ \\forall p\\in\\{\\mathrm{maxW},\\mathrm{pad},\\mathrm{opacity}\\}:\\ \\mathrm{shown}^{\\mathrm{on}}_p(K)=\\mathrm{shown}^{\\mathrm{on}'}_p(K)",
      says := "At a frame where all three properties have settled, each shows the same value in both arms.",
      decl := "settled3_same", file := nf, line := 429, kind := "theorem" },
    { id := "window", tex := "40\\cdot\\tfrac{50}{3}\\approx 666.7\\ \\mathrm{ms}<680\\ \\mathrm{ms}=\\max(0{+}680,\\,120{+}320)\\le 41\\cdot\\tfrac{50}{3}\\approx 683.3\\ \\mathrm{ms}",
      says := "The morph stops at frame 41; 41 more frames (683 ms) cover the longest delay plus duration, 41 frames are witnessed for both pushes at both viewports (NavEarnOpt.lean:448-451); that 40 do not is witnessed for desktop open only (:452).",
      decl := "settled3B", file := nf, line := 448, kind := "guard" } ]

/-- The info of a flag: `none` when no table is written for it. -/
def infoFor (key : String) : Option (List Gain × List Excerpt × List String × List Source × List Formula) :=
  if key == "nav:earn-no-transition" then some (earnGains (), earnExcerpts, earnMechanism, earnSources, earnFormulas) else none

/-- The summary line, computed from the table. -/
def earnSummary (_ : Unit := ()) : String :=
  let gs := earnGains ()
  let n (g : Gain) := match g.shown with | .gain k => k | .worse k => k | _ => 0
  match gs.take 6, gs.drop 6 with
  | [mw, _, op, cmw, _, _], _ :: _ :: _ :: _ :: _ :: c390 :: _ :: c1280 :: _ =>
    s!"Open push: the earn button restyles {n mw} fewer frames for max-width and {n op} fewer for opacity (modelled, Chromium measured the same direction); close push: no saving ({n cmw}, modelled); Chromium measured the opacity changing value on more frames on the close push (by at least {n c390} at 390 and {n c1280} at 1280; the 640 and 641 close pushes, not in the table, show at least 8 and 7 in run 39464309993), because the faithful opacity is held at 0 by the restarting delay, not because of more restyle work; WebKit: unknown."
  | _, _ => ""

#guard earnSummary () == "Open push: the earn button restyles 40 fewer frames for max-width and 26 fewer for opacity (modelled, Chromium measured the same direction); close push: no saving (0, modelled); Chromium measured the opacity changing value on more frames on the close push (by at least 13 at 390 and 3 at 1280; the 640 and 641 close pushes, not in the table, show at least 8 and 7 in run 39464309993), because the faithful opacity is held at 0 by the restarting delay, not because of more restyle work; WebKit: unknown."

end Fw.Console.ReviewInfo
