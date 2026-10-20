---
id: 2026-10-20-tween-platform-scope
kind: note
title: "morph.tween:waapi-scoped: a non-inherited --platform-morph removes the platform subtree from every tween frame"
status: draft
created: 2026-10-20
topics: [morph.tween, waapi, css-properties, inherits, chromium, style-recalc, lean]
---

# morph.tween:waapi-scoped

Task tween-platform-scope, branch `worktree-wf_c156a96a-23d-1`, CI branch `ci/tween-platform-scope`, commit 50dbdd6e.
Round 2 adds the live nav census, the base gate runs and the per-phase numbers; the flag code is unchanged.
Round 3 adds the lead-dispatched webkit-sim runs, the base evidence for `desktop-1512` and the committed live census.
Status words: CONFIRMED (source cited), MEASURED (CI run id cited), INFERRED.

## Answer

- `morph.tween:waapi-scoped` recalcs fewer elements than `waapi` on swipe-touch-v1 in Chromium: −108 per frame in
  frames 500-508 and −114 per frame in frames 509-530 (means of 3 runs, MEASURED). Those two phases give 3476 of the
  3745 fewer elements per run (−6.8 %). Frames 498-499 give another 268: `waapi` has 352 + 320 there (477 + 320 in
  run 2) and the scoped arm 239 + 207. The other frames differ by 2. swipe-v1 has no tween, so all three arms are
  equal there.
- The variant registers `--platform-morph` (`<number>`, inherits false, initial 0) and animates it on the platform
  section instead of the inherited `--morph`. `--morph-fade` is now inherits false and reads `var(--platform-morph)`.
  Lean proves the fade value is equal at every history (`fade_eq`). The gate's platform row passes in both engines.
  The not-ok cells of both flag gate runs (39337856330, 39340504860) lie inside the base's measured not-ok set:
  39355333307 at the merge-base c62aae1c plus 39314718340 at 1791b7ec, an ancestor of c62aae1c (MEASURED).
  webkit-sim run 39357698535 with the flag passes (MEASURED); its scroll profile has no tween push, so the WebKit
  saving stays INFERRED.
- The original premise is refuted. MorphTweenOpt said the extra `--morph` on the section "adds no element". In fact the
  original stops restyling the section subtree once the fade clamps (m ≥ 0.55), while `waapi` keeps changing an
  inherited value there until the tween ends. Lean records this as `waapi_section_finding`.
- The open item from `10-20-nav-oof-root-finding.md` (frames 517-530: 32 layout objects and 318 elements per frame
  with no rAF) is confirmed for the elements (MEASURED, frames 518-530, 3 runs per arm). These frames have no
  `FireAnimationFrame` in `waapi` and the scoped arm, and one in faithful. Their `UpdateLayoutTree.elementCount` is
  318 in `waapi`, 203-204 in the scoped arm and 85-86 in faithful, so the 318 is the WAAPI tween's style work.
  `trace.Layout.dirtyObjects` is 32 per frame in all three arms (`totalObjects` 1594, `metric.LayoutObjects` 0). The
  32 layout objects are therefore driver-independent: faithful's rAF tween and both WAAPI arms show the same 32, and
  scoping leaves them unchanged. Their source stays open (morph-nav-scope). Data: field
  `frames[].counts["trace.Layout.dirtyObjects"]` of `counts.json` in artifacts `chromium-counts-rewrite-r1` to `-r3`
  of runs 39337826915 (`waapi`), 39337815445 (scoped) and 39337848138 (faithful); the committed
  `chromium-counts.json` does not carry this field.
- A residual stays open. In frames 509-530 the scoped arm still recalcs 117-118 more elements per frame than faithful.
  With the panel mounted, the live nav subtree has 104 elements (the header included). So nav + panel can explain at
  most 104 + p of them, where p is the live nav's pseudo-elements (1 in the SSR model), and at least 117 − 104 − p
  elements per late frame, so about 12, come from outside the nav (INFERRED, see Census). This is the
  morph-nav-scope follow-up.

## Census (step 0, INFERRED)

The prerendered rows come from the page of site-dist run 39292323514, config 9dee133d165da417
(`?fw=morph.tween:waapi`). The same counts come out of config a2b80cf241434062 (`?fw=morph.tween:waapi-scoped`) in
site-dist run 39337815445. "Model" counts elements a full inherited recalc would touch, from parsing the page's CSS:
an element is touched if it has a `var()` reference, a custom-property declaration, an animation or a transition, or
if its parent was touched through inheritance.

The prerendered page has no morph panel. `App.tsx:55-65` mounts `MorphPanel` inside `<Nav>` once `MorphMount` calls
`onMount`, which is before the tween frames. The panel brings its content, the countdown and five `MorphColumns`
tracks of images. The live row renders `<Nav>` with `MorphPanel`, `MorphColumns` and `MorphCountdown` and the same
props as `App.tsx:55-65`, under config a2b80cf241434062. It uses Vite SSR of the branch sources and maps the
CSS-module class names onto the CSS of site-dist run 39337815445. The classification rules are the same as for the
other rows. The same render without the panel reproduces the prerendered nav row exactly. The element list with its
classification and the three nav rows are in `results/tween-platform-scope/nav-live-census.json` (re-rendered in
round 3 at 5db1e155, same counts as round 2).

| subtree | descendants | children | var() or decl | anim or transition | model |
|---|---|---|---|---|---|
| platform `section` | 339 | 1 | 64 | 46 | 143 |
| nav `header`, prerendered | 24 | 1 | 4 | 16 | 20 (+1 pseudo) |
| nav + hosted panel, live | 103 | 2 | 26 | 35 | 71 (+1 pseudo) |

The counters show what the model can explain. Per frame, `waapi` minus faithful is +117 in frames 500-508 and +231
in frames 509-530. Faithful early minus faithful late is 114. The scoped arm saves 108-114. So the platform share is
about 114 elements, below the model's 143, and the model overestimates.

The other half of +231 is about 117 elements per late frame. It is not in the platform. Frames 509-530 run one
`UpdateLayoutTree` each in every arm and run. `elementCount` is the growth of `StyleForElementCount` over the pass
(document.cc:2855-2867@f842f52), and `IncStyleForElementCount` runs for every resolved style, pseudo-element style
requests included (style_resolver.cc:1362-1366@f842f52). So pseudo-elements count. If an element or pseudo-element
counts at most once per pass, the live nav can supply at most 104 elements (103 descendants and the header) plus p,
its pseudo-elements (p = 1 in the SSR model), and the model puts its reach at 72. Faithful also restyles some of the
nav each frame, which lowers the nav's share further. So nav + panel can explain at most 104 + p of the residual,
never all of it, and at least 117 − 104 − p elements per late frame, so about 12, sit outside the nav. This is
INFERRED: it rests on the once-per-pass reading of `elementCount`, on p from the SSR model, and on the panel adding no
elements after mount that SSR does not render.

## Measurements

The count is `trace.UpdateLayoutTree.elementCount` in Chromium. Each arm has 3 runs. The engine-reported
`RecalcStyleCount` totals are equal across arms (1863-1864 touch, 1832 swipe). Data:
`results/tween-platform-scope/chromium-counts.json`.

| profile | arm | run | frames 500-508 | frames 509-530 | run total |
|---|---|---|---|---|---|
| swipe-touch-v1 | waapi | 39337826915 | 2862 / 2862 / 2872 | 6996 / 6996 / 6996 | 54976 / 55059 / 54990 |
| swipe-touch-v1 | waapi-scoped | 39337815445 | 1893 / 1893 / 1891 | 4493 / 4493 / 4493 | 51238 / 51278 / 51273 |
| swipe-touch-v1 | faithful | 39337848138 | 1809 / 1809 / 1809 | 1898 / 1897 / 1897 | 48523 / 48477 / 48523 |
| swipe-v1 | waapi | 39337835026 | 39 / 40 / 40 | none | 44178 / 44168 / 44176 |
| swipe-v1 | waapi-scoped | 39337830847 | 40 / 39 / 40 | none | 44171 / 44177 / 44175 |
| swipe-v1 | faithful | 39337852096 | 39 / 40 / 40 | none | 44176 / 44136 / 44188 |

swipe-v1 has 503 frames, so its first phase is frames 500-502 and its second phase is empty.

Per frame on touch: `waapi` is 318 in both phases. waapi-scoped is about 210 early and 203-205 late. Faithful is 201
early and 85-88 late.

Gates and lanes:

- **Lean lane** 39337809166: pass.
- **breakpoint-gate** 39337856330 (`fw=morph.tween:waapi-scoped`, config a2b80cf241434062):
  - Chromium: 7048 pass, 7 excused, 1 fail. The fail is `commission|sweep:pain-1440-600-1440` (`inner`/`rows`
    margin-inline).
  - playwright-webkit: 0 fail, 291 excused (cross primary-pair and whole-width cells are unreachable), so the verdict
    is "incomplete".
  - The `platform` row passes in every reachable column in both engines. The section probe reads `--morph-fade`, and
    it serializes the same as the original. Earlier, the waapi arm failed 10 of 14 columns on exactly this probe
    (`docs/team/handoffs/gate-preset-input.md:37`). No part contract lists `--platform-morph` as an input, so the gate
    does not probe it.
  - Re-run 39340504860: the platform row passes again in both engines.
    - Chromium has 2 fails, both commission `inner`/`rows` margin-inline cells: `pain-1440-600-1440` and
      `desktop-1512-320-1512` (132px vs 0px).
    - WebKit again has 0 fail. Its one not-ok cell is phone-rotation, marked not-comparable.
- **breakpoint-gate, base** at the merge-base c62aae1c of 50dbdd6e (default config, `ci/tween-platform-scope-base`,
  a marker comment on top). Not-ok sets, MEASURED:

  All commission cells are `inner`/`rows` margin-inline.

  | run | arm | Chromium not ok | WebKit not ok |
  |---|---|---|---|
  | 39353161468 | base | none (7049 pass, 7 excused) | phone-rotation, not-comparable |
  | 39355333307 | base | commission `pain-1440-600-1440` (0px vs 96px / 8px) | phone-rotation, not-comparable |
  | 39337856330 | scoped | commission `pain-1440-600-1440` | phone-rotation, not-comparable |
  | 39340504860 | scoped | commission `pain-1440-600-1440`, `desktop-1512-320-1512` | phone-rotation, not-comparable |

  Base run 39355333307 and scoped run 39337856330 have the same not-ok set. The base itself flips the `pain-1440`
  cell between runs (none in 39353161468, not ok in 39355333307), so that cell is a base flake, not the flag's. The
  `desktop-1512-320-1512` cell of 39340504860 is the same commission probe at another sweep. Base evidence for it:
  breakpoint-gate run 39314718340 at 1791b7ec on `ci/ci-telemetry`, an ancestor of c62aae1c, no flags, fails
  `desktop-1512-320-1512#0` with `inner` 0px vs 132px and `rows` 0px vs 8px
  (`research/notes/2026/10-20-commission-margin-recur.md:53-54` on main, MEASURED). So the not-ok cells of both flag
  runs lie inside the base's measured not-ok set, 39355333307 at c62aae1c plus 39314718340 at 1791b7ec.
- **webkit-sim** 39337860689 (`fw=morph.tween:waapi-scoped`, target rewrite): failed on both attempts, in step
  "Determinism sessions".
  - Attempt 1: `Runtime.evaluate` timed out after 120 s, then the Safari tab was unreachable.
  - Attempt 2: `Runtime.evaluate`, `Timeline.stop` and `LayerTree.reasonsForCompositingLayer` timed out, then
    ECONNREFUSED.
  - Control run 39347638740 (`fw=morph.tween:waapi`) is a dispatch failure: it was sent without `target=rewrite`, and
    the plan job refused it ("target original takes no preset or flags").
  - Control run 39347940719 (`fw=morph.tween:waapi`, target rewrite) passed, but it hit the same kind of timeout twice
    and recovered. Its scroll passes show style 662 and 651. So the lane has inspector timeouts on the comparison arm
    too. The round-3 runs below decide the scoped arm's verdict.
  - Scoped re-run 39357698535 (round 3, dispatched by the lead: `fw=morph.tween:waapi-scoped`, target rewrite, at
    50dbdd6e): success (MEASURED). Its two scroll passes show style 667 and 646 (layout 618 and 601). Each pass hit one
    `Runtime.evaluate` timeout of 120 s in its scroll step and recovered from a fresh load, the same kind of recovery
    as control 39347940719 (`fw=morph.tween:waapi`, style 662 and 651).
  - Control re-run 39358530780 (`target=rewrite`, no `fw`, same ref, same window): success (MEASURED). Scroll style
    667 and 647 (layout 606 and 607); one `Runtime.evaluate` timeout in the warm-up, recovered. The scoped arm's 667
    and 646 match it within 1, as expected for a scroll profile with no tween push. Both arms of the round-3 pair hit
    and survived the same inspector timeout. So the timeouts that failed 39337860689 are a lane behaviour that both
    arms show (INFERRED: the scoped arm has failed 1 run and passed 1, the control has passed 2).
  - Why the lead dispatched both: `fw run` prints BLOCKED for webkit with these inputs. `workflowInputs .webkit` lists
    only `vms`, `sessions`, `fresh_boot` (lean/Fw/Store/Layout.lean:414), so `blocked` (:447-448) names `target`; and
    `dispatchInputs .webkit` is `[]` (:440), so even a fixed table would send no inputs. A `ci/**` push run of
    webkit-sim takes no inputs (target original, no `fw`), so `pnpm fw ci push` cannot start this arm either.
  - The lane's profile is a scroll with no tween push, so the passing run does not show the saving. The WebKit
    saving stays INFERRED from WebKit's own inherited-change rule (StyleChange.cpp:36-45@862f17d).

## Proofs

All proofs are in `lean/Fw/Parts/MorphTweenOpt.lean`, section "MT-R, the scoped arm". `#print axioms` shows standard
axioms only.

- `registrationsScoped_rule`: each scoped registration inherits exactly when a reader sits below its writer
  (`needsInherit`).
- `registrationsScoped_see`: every reader still sees its writer's value.
- `scoped_scope_le`: the scoped arm recalcs a sublist of what `waapi` recalcs, and every reader sees the same value.
  This is the "⊆" form of `morph_scope_eq`'s first conjunct for the scoped arm.
- `platform_morph_local`: only the depth-0 reader (the section) recalcs for `--platform-morph`.
- `fade_eq`: for every history `h`, the evaluated fade of `--platform-morph` equals `fade` of the original's `m`. The
  proof goes through `view_eq` and `fade_css` on numbers, not by string `rfl`.
- `waapi_section_finding`: after the fade clamps (`fadeEnd ≤ m, m'`, `m ≠ m'`), the original's `--morph-fade` frame
  recalcs nothing below the section, while `waapi`'s inherited `--morph` recalcs every descendant in `ds`. `ds` models
  the elements the engine recalcs on an inherited change (`var()` references, animations; INFERRED model). The
  measured platform share is about 114 of the section's 339 descendants.
- `orig_below_le_waapi` and `scoped_below_nil`: below the section, the original's recalcs are a sublist of `waapi`'s,
  and the scoped arm recalcs nothing below the section.
- `Fw.Ops.Premise` css.inherits-false now cites `waapi_vis` and `registrationsScoped_see`.

Chromium source (CONFIRMED, f842f52):

- computed_style.cc:467-478: an inherited variable change on an element with var refs gives `kRecalcChildren`. A
  non-inherited change does not.
- abstract_property_set_css_style_declaration.cc:278-281: an equal inline write is dropped. This is why faithful stops
  restyling the section subtree once the fade clamps.

## Deviations from the brief

- `waapi` stays unchanged as the comparison arm. Its `registrations`, `registrations_rule` and the
  `morph_scope_eq` statement are kept. The scoped arm gets its own `registrationsScoped` and `readersScoped`, so the
  "⊆" statement is `scoped_scope_le`, not an edit of `morph_scope_eq`. The `morph_scope_eq` docstring now records the
  refuted premise.
- The golden has 5 scoped registration rows and 7 scoped reader rows, not 8: the section reads `--platform-morph` and
  `--morph-fade` instead of `--morph`.
- `docs/plan/math-view.html` is frozen (`docs/team/tools/math-artifact.md`), so it was not regenerated.
- `apps/site/src/stage/inputs.ts` was not changed. `REST` mirrors Lean `Fw.Site.Stage.rest`, and no contract declares
  a `--platform-morph` input.

## What this changes in the plan

- The lead can decide whether `morph.tween:waapi-scoped` replaces `waapi` in a preset. On touch it is 6.8 % fewer
  elements than `waapi`, but still 5.7 % above faithful (51263 vs 48508, means).
- The rule is general: give each animated custom property the narrowest scope that its readers need. A property that
  only its own element reads must be registered `inherits: false`. Lean states this as `needsInherit`.
- Next is morph-nav-scope: find the 117-118 elements per late frame that the scoped arm still recalcs above faithful.
  The live nav with its hosted panel holds at most 104 + p of them (p its pseudo-elements, 1 in the SSR model), so
  the search covers nav + panel and at least 117 − 104 − p, about 12, elements outside it (INFERRED). The 32 layout
  objects per late frame, the same in every arm, are also this task's to explain.
