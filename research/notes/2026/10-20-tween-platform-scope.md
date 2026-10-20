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
Status words: CONFIRMED (source cited), MEASURED (CI run id cited), INFERRED.

## Answer

- `morph.tween:waapi-scoped` recalcs 113 fewer elements per tween frame than `waapi` on swipe-touch-v1 in Chromium.
  That is 3745 fewer per run (−6.8 %), and it holds in all 3 runs (MEASURED). swipe-v1 has no tween, so all three arms
  are equal there.
- The variant registers `--platform-morph` (`<number>`, inherits false, initial 0) and animates it on the platform
  section instead of the inherited `--morph`. `--morph-fade` is now inherits false and reads `var(--platform-morph)`.
  Lean proves the fade value is equal at every history (`fade_eq`). The gate's platform row passes in both engines.
- The original premise is refuted. MorphTweenOpt said the extra `--morph` on the section "adds no element". In fact the
  original stops restyling the section subtree once the fade clamps (m ≥ 0.55), while `waapi` keeps changing an
  inherited value there until the tween ends. Lean records this as `waapi_section_finding`.
- A residual stays open. In frames 509-530 the scoped arm still recalcs 117-118 more elements per frame than faithful.
  The nav subtree has only 24 elements, so the nav alone cannot explain it (INFERRED). This is the morph-nav-scope
  follow-up.

## Census (step 0, INFERRED)

The source is the prerendered page of site-dist run 39292323514, config 9dee133d165da417 (`?fw=morph.tween:waapi`).
"Model" counts elements a full inherited recalc would touch, from parsing the page's CSS: an element is touched if it
has a `var()` reference, a custom-property declaration, an animation or a transition, or if its parent was touched
through inheritance.

| subtree | descendants | children | var() or decl | anim or transition | model |
|---|---|---|---|---|---|
| platform `section` | 339 | 1 | 64 | 46 | 143 |
| nav `header` | 24 | 1 | 4 | 16 | 20 (+1 pseudo) |

The counters show what the model can explain. Per frame, `waapi` minus faithful is +117 in frames 500-508 and +231
in frames 509-530. Faithful early minus faithful late is 114. The scoped arm saves 108-114. So the platform share is
about 114 elements, below the model's 143, and the model overestimates. The second half of +231 (about 117) is not
platform and does not fit in the 24-element nav.

## Measurements

The count is `trace.UpdateLayoutTree.elementCount` in Chromium. Each arm has 3 runs. The engine-reported
`RecalcStyleCount` totals are equal across arms (1863-1864 touch, 1832 swipe). Data:
`results/tween-platform-scope/chromium-counts.json`.

| profile | arm | run | frames 500-508 | frames 509-530 | run total |
|---|---|---|---|---|---|
| swipe-touch-v1 | waapi | 39337826915 | 2862 / 2862 / 2872 | 6996 / 6996 / 6996 | 54976 / 55059 / 54990 |
| swipe-touch-v1 | waapi-scoped | 39337815445 | 1893 / 1893 / 1891 | 4493 / 4493 / 4493 | 51238 / 51278 / 51273 |
| swipe-touch-v1 | faithful | 39337848138 | 1809 / 1809 / 1809 | 1898 / 1897 / 1897 | 48523 / 48477 / 48523 |
| swipe-v1 | waapi | 39337835026 | 40 / 40 / 40 | none | 44178 / 44168 / 44176 |
| swipe-v1 | waapi-scoped | 39337830847 | 40 / 39 / 40 | none | 44171 / 44177 / 44175 |
| swipe-v1 | faithful | 39337852096 | 39 / 40 / 40 | none | 44176 / 44136 / 44188 |

swipe-v1 has 503 frames, so its first phase is frames 500-502 and its second phase is empty.

Per frame on touch: `waapi` is 318 in both phases. waapi-scoped is about 210 early and 203-205 late. Faithful is 201
early and 85-88 late.

Gates and lanes:

- **Lean lane** 39337809166: pass.
- **breakpoint-gate** 39337856330 (`fw=morph.tween:waapi-scoped`, config a2b80cf241434062):
  - Chromium: 7048 pass, 7 excused, 1 fail. The fail is `commission|sweep:pain-1440-600-1440`, the known margin-inline
    flake.
  - playwright-webkit: 0 fail, 291 excused (cross primary-pair and whole-width cells are unreachable), so the verdict
    is "incomplete".
  - The `platform` row passes in every reachable column in both engines. The section probe reads `--morph-fade`, and
    it serializes the same as the original. Earlier, the waapi arm failed 10 of 14 columns on exactly this probe
    (`docs/team/handoffs/gate-preset-input.md:37`). No part contract lists `--platform-morph` as an input, so the gate
    does not probe it.
  - Re-run 39340504860: the platform row passes again in both engines.
    - Chromium has 2 fails, both commission `inner`/`rows` margin-inline cells: `pain-1440-600-1440` and
      `desktop-1512-320-1512` (132px vs 0px). morph.tween does not touch commission, so this is the same flake.
    - WebKit again has 0 fail. Its one not-ok cell is phone-rotation, marked not-comparable.
- **webkit-sim** 39337860689 (`fw=morph.tween:waapi-scoped`, target rewrite): failed on both attempts, in step
  "Determinism sessions".
  - Attempt 1: `Runtime.evaluate` timed out after 120 s, then the Safari tab was unreachable.
  - Attempt 2: `Runtime.evaluate`, `Timeline.stop` and `LayerTree.reasonsForCompositingLayer` timed out, then
    ECONNREFUSED.
  - The control run 39347940719 (`fw=morph.tween:waapi`) passed, but it hit the same kind of timeout twice and
    recovered. Its scroll passes show style 662 and 651. So the lane is flaky with inspector timeouts. Whether the
    scoped arm makes them worse is open (INFERRED: lane flake, 1 control run).
  - The lane's profile is a scroll with no tween push, so a passing run would not show the saving either. The WebKit
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
  recalcs nothing below the section, while `waapi`'s inherited `--morph` recalcs every reader below it.
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
  The census rules out the nav subtree alone.
