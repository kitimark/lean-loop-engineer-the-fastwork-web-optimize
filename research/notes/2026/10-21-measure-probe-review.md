---
id: 2026-10-21-measure-probe-review
kind: note
title: "Why our checks missed three real-device bugs, and how to measure and probe correctly (Fable review + adversarial check)"
status: final
created: 2026-10-20
authors: [agent:fable-measure-review, agent:adversarial-check]
topics: [measurement, trajectory-probe, webkit, proofs, gate]
---

# Measurement and probe review (2026-10-20)

Two read-only reviews after the user found bugs A (hero.exit:scoped, Safari only), B (morph.tween:waapi, nav logo) and C (is-on-dark at 390). The adversarial check corrects the first report: every trajectory-probe CI run at 0e141662 measured the rewrite with its flags off (client render of the default config), so its A/B conclusions are void. Read the check first.

## Part 1: adversarial check (read first)


Read-only. Worktree HEAD is now b9f07066 (unreviewed WIP on top of 0e141662).

## Headline: every CI probe run so far tested the rewrite with its flags OFF

- All 5 dispatches ran at 0e141662 (`gh run list --workflow trajectory-probe.yml`: headSha 0e141662 for 39397458446, 39399299613, 39399321897, 39399346162, 39400870750). MEASURED.
- At 0e141662, `open()` loaded the rewrite at `path: '/'` with no search (`git diff 0e141662 b9f07066 -- .../trajectory/run.mjs`). The server swaps in the flagged HTML (`serve.mjs:49`), but the client resolves flags from `location.search` (`apps/site/src/entry-client.tsx:16`). The hash differs, so the page client-renders the DEFAULT config (`entry-client.tsx:29-33`). CONFIRMED.
- The raw artifacts show it: the rewrite arm has `fwMode: "client-render"` in all three downloaded runs (waapi-chromium, waapi-webkit, scoped-webkit; `.runs[1].hero.ready`). MEASURED. The gate records `fwMode` but never refuses on it (`page.mjs:133,163`). CONFIRMED.
- What follows from that:
  - "A did not reproduce on Linux WebKit" is not evidence.
  - The B discrepancy (the logo glides in the "waapi" arm) is explained: that arm was the faithful arm.
  - The near-equal fail counts (46/44/43/43) are one config measured four times.
  - Fable's fonts-settling and WPE explanations for A are unneeded, so drop them.
  - This repeats incident `inc-variant-gate-flags-off`. b9f07066 adds a config-hash assert (`run.mjs` `assertConfig`), but it has not been reviewed or run.

## Fable's 5 key claims

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | getComputedStyle does not refresh WebKit's stale cache | CONFIRMED | `StyleExtractor.cpp:184-205@862f17d` calls only `document->updateStyleIfNeeded()` (same resolver). The cache keys on `inheritedCustomProperties` identity plus `inheritedEqual` (`MatchedDeclarationsCache.cpp:139-163`). The local Mac Playwright WebKit repro read stale values without a screenshot (hero-bug-mechanism.md) |
| 2 | Linux Playwright WebKit is not Safari, so the probe there is no witness for A | Fact CONFIRMED (`visual-diff.md:90`); conclusion REFUTED as premature | The probe never ran the flag (see above). The cache code is WebCore, platform-independent (INFERRED). Mac Playwright WebKit DID reproduce A locally |
| 3 | WebKit under-sampling: "300-2000 ms per sample" | Under-sampling CONFIRMED, numbers overstated, cause OPEN | Push-phase gaps: p50 176, p90 549, max 670 ms (n=53, waapi-webkit raw). Chromium p50 18 ms. `snap` stamps `t` after the reads (`kit.mjs:107-113`), so read cost and slow rAF cannot be told apart |
| 4 | Free macOS runner for public repos | CONFIRMED | Repo is PUBLIC (`gh repo view`). "free ... for public repositories that use standard GitHub-hosted runners"; larger runners always charged (https://docs.github.com/en/billing/concepts/product-billing/github-actions). Cost Fable omitted: 5 macOS slots shared by every lane, p90 queue wait 15 min (`research/notes/2026/10-17-macos-queue.md`) |
| 5 | Proof-to-code gaps (View-scoped theorem, `hints==[0,1]`, stale anchors, no premise on scoped) | CONFIRMED | `MorphTweenOpt.lean:856-872`; `waapi.driver.ts:110,140`; `waapi.driver.test.ts:47`; `anchors.json:834-839`; `Premise.lean:419-423` lists only MorphTween theorems |

Also CONFIRMED: `windowOf` returns the whole original phase when m is null (`Trajectory.lean:219-226`), a bucket with no rewrite sample is a skip (`:242`), and `laneFails` fails only on `fail` (`:260`). The work-graph scope mismatch is CONFIRMED. Fable missed a second one: the golden is `packages/contracts/golden/gate/trajectory.jsonl`, but writes list `golden/trajectory/**`.

## What it missed

- The flags-off runs above, which change Fable's whole progress section.
- Raw artifacts record neither the resolved config hash nor a refusal of `client-render`.
- b9f07066 adds `beyond`, which returns an empty window and so a skip (`Trajectory.lean:210-226`). The WIP adds a new route to skip while coverage is the main hole.
- The cheapest Apple-port witness is the existing driver with Playwright WebKit on `macos-26`, which reproduced A locally. An inspector-proxy Simulator port can come later.
- `engine-premises.yml:237` already runs a `macos-26` WebKit job. Add the 325900 premise there instead of building a new lane.

## Wrong or misordered recommendations

- Fable #1 ranks the per-unit baseline first. Without a valid flagged run the true fail set is unknown, so the baseline would be built on flags-off data.
- Fable #2 (lighter read set) assumes read cost is the cause. Measure it first.
- Fable #5, step 5 (preset blocked by any failing unit) would block every flag, since C fails in faithful. It must be "no new failing unit versus the faithful arm".
- Fable §4.1 (channel-level Lean) belongs to the waapi fix and preset-drop-waapi, not the measurement lane.

## Corrected ranked recommendations

1. **Make the arm identity a hard check, then re-run.**
   - Review b9f07066. Write `config` and `fwMode` into the raw artifact, and refuse `client-render` and any hash mismatch (Lean verdict, closed allowlist).
   - Re-dispatch default, `?preset=v2-proved`, `?fw=morph.tween:waapi` and `?fw=hero.exit:scoped`. No claim about A or B before that run.
   - Fix the work-graph writes (lead).
   - Cost: small, 4 runs of about 12 min.
2. **Coverage is a verdict.**
   - An empty bucket 1-9 in a push phase, a null m in a push phase, and `beyond` are `fail:coverage`, never skip.
   - Then build the per-unit baseline: faithful and A/A arms. Red means a unit fails beyond the baseline (`red_iff_unacked` pattern).
3. **Time the reads.**
   - Add `t0`/`t1` per sample.
   - If reads dominate, cut per-frame reads to discrete props plus m plus logo rect. If rAF dominates, slow the push or move WebKit pushes to macOS.
4. **Apple witness.** Run the same lane with Playwright WebKit on `macos-26`, `?fw=hero.exit:scoped` only, `max-parallel: 1`. Later, add the Simulator (`xcode-27`) for Mobile Safari.
5. **Engine premise `wk.mdc-explicit-inherit`.** Use a 325900/321094 fixture in `engine-premises` (the `macos-26` job exists), attached to `consumer_eq_scoped`.
6. **Delete stale exclusions** at `anchors.json:834-839`, and add a gate stop at the end of the page after the morph.
7. **Touch swipe** at 390/640 (CDP touch in Chromium, Simulator touch in WebKit).
8. **Combination policy.**
   - Probe each `partly-proved` flag alone before it is put in any shared link.
   - Probe pairs only where flags share readers (from anchors roles).
   - The preset gate is "no new failing unit vs faithful, both engines".
9. **Proof-to-code links**, done in the fix tasks, not this lane:
   - waapi: `hints == crossings(Θ)` golden.
   - is-on-dark: event set in the Lean statement.

## Part 2: Fable report


Date 2026-10-20. Read-only. Tags: CONFIRMED (source/log cited), MEASURED (CI artifact read), INFERRED, OPEN.

## 0. Progress of the trajectory probe

- Built at 0e141662 (worktree-wf_b2d9cca1-299-1): Lean verdict `lean/Fw/Gate/Trajectory.lean` (710 lines, incl. `byM_stale_class` "bug B shape"), TS twin + golden (62 rows), kit/run/reduce/registry, workflow; 26 files. No handoff, no `docs/team/tools/trajectory-probe.md` yet. The work-graph `writes` list says `packages/trajectory-probe/**` but the code lives in `packages/gate-breakpoints/src/trajectory/` (CONFIRMED, work-graph.json): a land will refuse on scope unless the graph is corrected.
- CI: 5 dispatches on `ci/trajectory-probe`, 4 completed, 1 in progress; 11-12 min per run, both engines on `ubuntu-24.04-arm`. Results (MEASURED from raw artifacts; 14416 units per engine):

| search | Chromium fail/skip | WebKit fail | C seen | B seen | A seen |
|---|---|---|---|---|---|
| (default, no flags) | 46 / 4472 | 86 | yes (is-on-dark 390) | n/a | n/a |
| ?preset=v2-proved | 44 / 4398 | ~70 | yes | no | n/a |
| ?fw=morph.tween:waapi | 43 | ~80 | yes | no in Chromium; WebKit only `is-morphing`/`logo.position` at `close@0` | n/a |
| ?fw=hero.exit:scoped | 43 | ~70 | yes | n/a | no: zero failing hero units in either engine |

- "Must fail today on three things" holds for C only. Verified reasons:
  1. WebKit under-sampling: one sample (getComputedStyle + rects of ~60 elements x 9 props) costs 300-2000 ms on the arm runner; the 680 ms open tween has 3-6 samples (`m=[0,0,1780]` at 390). Chromium samples every 16-60 ms (MEASURED, raw `t`). 11 of 12 `byM` buckets become `skip`, which never fails the lane (`laneFails_iff`).
  2. In Chromium the waapi arm's logo glided (x 24 -> 559 across open samples, MEASURED), contradicting the nav-bug note's local "24 until finish". Either the tip build differs from the local one or the local repro was another build: OPEN; settle before any "closes B" claim. The WebKit `close@0` hit is the stale `is-expanded`/`is-morphing` at the end of close (B's close half).
  3. A did not reproduce on Linux WebKit 27.2 (Playwright 1.64.1): hero.copy opacity equals the original's at every step (MEASURED). The mechanism is platform-independent (`StyleResolver.cpp:693-728@862f17d` copies non-inherited properties from the cache when `inheritedEqual`; `MatchedDeclarationsCache.cpp:139-163` keys on the parent's inherited custom-property pointer), but `isCacheable` refuses container-dependent styles and styles computed during a font-environment change (`MatchedDeclarationsCache.cpp:87-96`), so a runner with fonts still settling may miss the cache and look correct (INFERRED). Linux Playwright WebKit is WPE, not Safari (visual-diff.md Caveats). The probe on this runner is not a WebKit witness for A.
- False-positive floor: the flagless rewrite already fails 46/86 units (approach `nav.background-color`, `earn.max-width`, `close@0` geometry), so red carries no news (pattern inc-red-on-main-by-design). The lane needs a per-unit baseline or expected-red list before it can gate.

## 1. Root causes

A. hero.exit:scoped (Safari only)
- Layer: proof scope + engine model + observable. `consumer_eq_scoped` (`HeroExitOpt.lean:1289`) is equality of `valueAt` in one cascade; `wk_units` (:1321) assumes full recomputation; no style cache in `Fw.Engine.Restyle`; no premise attached (`Premise.lean:419-423` has `css.inherits-false` for MorphTween only). CONFIRMED.
- Process: WebKit evidence was "source-only"; the row is `partly-proved` so the preset rule (V2Proved.lean:4-6) kept it out, yet it shipped in a user link with no WebKit run of any kind. The gate reads each part at scroll 0 after settling (`page.mjs:398`) where exit=1 equals the cached value; counts measure work and a cache hit is less work, so A reads as a win. PLAN §10.7 dropped phone sessions and sibling visual re-checks "under premise".
- Sampling artifact: a screenshot refreshed the stale style (local MEASURED). `getComputedStyle` does not: `Extractor::updateStyleIfNeededForProperty` only calls `document->updateStyleIfNeeded()` (`StyleExtractor.cpp:184-205`), the same resolver and cache, so the forced read returns the stale value (CONFIRMED). Why a screenshot refreshes it: OPEN (viewport/scale override invalidation, INFERRED).

B. morph.tween:waapi nav classes
- Layer: proof-to-code link. `waapi_vis`/`view_eq` quantify over `View` (m, target, flags) and scenes that are functions of it (`MorphTweenOpt.lean:855-870`); the nav reads `data-fw-morph`, written at start/finish only (`waapi.driver.ts:110,140`). `waapi.driver.test.ts:47` pins `hints == [0,1]`: the bug is specified behaviour. Goldens check registrations and offsets, not "every threshold has a track".
- Process: row g0.0b is `proved`, so waapi entered v2-proved. Anchors exclude "nav at morph > 0" and "is-on-dark" with the stale reason "no platform section yet" (`anchors.json:835,839`). Reviews asked for same counts, not same classes.

C. is-on-dark not re-evaluated
- Layer: port fidelity + stale exclusion. Original binding is reactive per morph frame (snapshot `2.DyWL8TcE.js:13228`); the port evaluates in the scroll callback only (`nav.hitTest/index.tsx:36-46`), the push `preventDefault`s. `NavHitTest.isOnDark`, `Nav.view` prove the value, never the re-evaluation events. Same class as inc-hidden-pause-unfaithful-port.

## 2. Threat model for "same look"

| Class | Caught by | Missed by |
|---|---|---|
| Mid-tween values | probe `byM` in Chromium; PL4 (planned, never built, PLAN.md:730) | gate (rest only), counts, WebKit probe (3-6 samples) |
| Scroll away and back | probe hero path s0->mid->b0 | gate; single-cascade proofs |
| Engine cache staleness (A) | probe on a WebKit that hits the cache | Linux WPE probe (did not reproduce), any screenshot check, Chromium lanes |
| Discrete state (classes, aria, tabindex) | probe `discrete`, tol 0 | gate (excluded), counts |
| Colour/theme | probe `colour` after 300 ms quiet (caught C) | gate, visual-diff (m=0 only) |
| Touch vs wheel | nothing: probe uses `mouse.wheel` at all widths (`run.mjs`, `engines.mjs`) | the user's touch path |
| Resize mid-animation | nothing | all |
| Prerender vs client | gate and probe refuse non-prerendered search | a flag reachable only after hydration |
| Flag combinations | preset as one set | pairwise; interactions (inc-preset-change-stale-counts) |
| Compositor vs main value (H3) | `getComputedStyle` of an accelerated running animation returns `renderer()->animatedStyle()` (`StyleExtractor.cpp:208-214`), partial | pixels, layer tree |
| Port unfaithfulness (C) | nothing systematic | proofs over the port's own spec |

## 3. Probe design review

- Observable: getComputedStyle is right for A/B (forces style through the same cache, no refresh). It is not paint. Add, by cost: `getAnimations()` + timing per sample (stuck/unstarted WAAPI); Chromium-only 16x16 pixel crops of 3 regions via CDP `Page.captureScreenshot {clip}` (never mid-path in WebKit: refreshes the cache); `LayerTree.layersForNode` through the Simulator proxy already in `measure-webkit/src/census.mjs`.
- Sampling: fails in WebKit. Read discrete props + 2-3 continuous props per frame during pushes, the full set at rest; emit a coverage verdict: a push phase whose buckets 1-9 have no rewrite sample is `fail:coverage`, not skip (`byM_no_sample` makes it skip today).
- Alignment hole: `windowOf` returns the whole original phase when any `m` is null, so a static value inside the original's range passes. Null `m` in a push phase must fail.
- Paths: no touch; no scroll during open; hero move frames are recorded but not judged (`stepRows` keeps `rest` only), so a freeze that recovers at rest is invisible; 1.2 s hold vs the 5 s the local repro needed.
- Fidelity: Linux WPE is the WebKit-on-Linux witness only.
- Tolerances fine (C caught). Baseline: needs A/A and faithful per unit; red = new vs baseline (`red_iff_unacked` pattern).

## 4. Proof-to-code link

1. Channels, not views: state `vis` over the channels the code writes (hints, inline writes, class toggles); generate the crossing schedule from Lean's Θ and assert the driver consumes it (golden `hints == crossings(Θ)`, not `[0,1]`).
2. Engine premises with citations and a per-engine CI test: `wk.mdc-explicit-inherit` (325900/321094, `StyleResolver.cpp:693-728`) as a `page` premise with a fixture; `consumer_eq_scoped` requires its negation or an inline write per reader; run premise-tests on Apple WebKit too.
3. Refinement against traces: replay `run_o(E)` in Lean on the probe's recorded events and compare predicted `View` per frame with sampled classes (F3/F4 for state).
4. Reactive bindings carry their re-evaluation event set in the Lean statement; the port test asserts the handlers.
5. Preset rule: `V2Proved.ok` also requires no failing trajectory unit on the flag's part roles in both engines on the current preset.

## 5. Recommendations (ranked)

| # | Change | Closes | Cost | First step |
|---|---|---|---|---|
| 1 | Coverage verdict, null-m failure, per-unit baseline (A/A + faithful), expected-red list in `Fw.Gate.Trajectory` | false pass by skip; red floor | half day Lean+TS; 0 extra minutes | `fail:coverage` for empty buckets 1-9 |
| 2 | Lighter WebKit per-frame read set | WebKit under-sampling (B open half) | small | check `dt` in the next raw artifact |
| 3 | Apple WebKit witness: probe in the iOS Simulator lane via the inspector proxy (`Runtime.evaluate` in `wip.mjs`) on `xcode-27`, or safaridriver on `macos-26` | A | ~15 min/run. Standard GitHub-hosted runners are free in public repos, larger runners are charged (docs.github.com billing page); macOS is a standard OS option; cap 5 concurrent macOS jobs on Free (docs limits table); repo already uses `macos-26` (wktr.yml:115) | one Simulator job: `?fw=hero.exit:scoped`, hero.copy opacity at 10 steps |
| 4 | Touch swipe at 390/640 (CDP `Input.dispatchTouchEvent`; Simulator touch) | interaction class | small | touch `dy` in `PUSH_PHASES` for touch envs |
| 5 | Combination policy: preset as one set (keep) plus every `partly-proved` flag probed alone before it appears in any link; pairwise only for flags sharing readers (nav, hero.exit) | A shipped unprobed | 1 run/flag | list shared-reader flags from anchors roles |
| 6 | Delete stale exclusions `anchors.json:835,839`; gate reads the nav at the end stop | C recurrence | small | re-run gate |
| 7 | Roles: trajectory = gate stage for the preset; engine bugs (325900) = preset premise with CI test; pixel/layer = Chromium spot lane | clarity | none | PLAN §4.7 |
| 8 | Stop: calling Linux Playwright WebKit "WebKit"; dropping nav/hero visual re-checks "under premise"; treating `skip` as neutral; local repro numbers as results (the B discrepancy shows why) | | | |
