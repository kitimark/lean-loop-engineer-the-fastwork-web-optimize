---
id: 2026-10-21-trajectory-probe
kind: note
title: "Trajectory probe round 3: per-pass windows, and what CI measured for bugs A, B and C"
status: final
created: 2026-10-20
authors: [agent:measure-engineer]
topics: [measurement, trajectory-probe, webkit, gate]
---

# Trajectory probe rounds 2 and 3 (2026-10-20)

Round 1 measured the rewrite with its flags off (`research/notes/2026/10-21-measure-probe-review.md`). Round 2 made that
impossible to repeat and re-measured. **Round 3 corrects a reducer bug of round 2**: the passes of `--reps` were pooled into
one list, every window became the whole phase, and the note below said "bug B not witnessed" because of it. Every
number in the verdict table is re-reduced from the existing CI raw artifacts (no new CI run). Tool doc:
`docs/team/tools/trajectory-probe.md`. Incident: `inc-trajectory-pooled-window`.

## The reducer bug (round 2) and its fix (round 3)

- **Bug (CONFIRMED by replay).** `--reps 3` walks the morph path three times and the rows of a phase were concatenated, so the
  original's morph values read [0..10000, 0..10000, 0..10000]. The neighbouring pair (last sample of pass k at 10000, first of
  pass k+1 at 0) encloses every morph value, so every window held both ends of the phase and a stuck class or a frozen transform
  passed. Lean `window_concat_whole_phase` states it. The round-2 numbers "B not witnessed" and "0 / 1 / 4 new B units" came
  from this, not from the site.
- **Fix, Lean first.** `Samp` carries its pass `rep`. `windowOne` is the old single-pass window; `windowOf` is the union of the
  windows of the passes that have one (none only when no pass has one). Theorems: `windowOf_pass_iff` (a sample is in the pooled
  window exactly when it is in the window of its own pass alone: pooling never widens a window), `windowOf_none_iff`,
  `window_concat_whole_phase`, `windowOf_pooled_ramp`, `windowOf_union_has_pass` (a slow pass does not hide a pass that
  reached 1.0), `byM_pooled_stuck`, `byM_pooled_ramp`. Golden: 10 new rows with `rep > 0` (`pooled ramp original, static rewrite`
  gives `fail:differs` at 0.5). `reduce.mjs` mirrors it; the reps test has a ramping original and a stuck rewrite over two passes
  and fails on the old concatenated window.
- **`Rel.unmeasured`.** A candidate content failure against a faithful-arm `fail:coverage` was `both`. It is now `unmeasured` (no
  verdict either way; never `new`, never `both`), with theorems `rel_unmeasured`, `rel_both_*`, `laneRed_unmeasured`.

## What changed in round 2 (decided in Lean, `lean/Fw/Gate/Trajectory.lean`; golden `packages/contracts/golden/gate/trajectory.jsonl`)

- **Arm identity.** Every arm records its config hash and `fwMode`. Allowlist: rewrite = the search's hash, non-empty, `hydrate`;
  original = no `window.__fw`. Else `refused:config` (exit 2, no verdict). It caught a bug of mine at once: the faithful arm was
  served the variant server, whose flagged HTML client-renders for the default search; it now has its own server.
- **Coverage is a verdict.** Empty bucket 1-9 in a push, missing morph value, `beyond` window: `fail:coverage`.
- **Baseline per unit.** Faithful rewrite vs original gives `new / both / unmeasured / cleared / ok` for each unit; red iff some unit is new.
- **Read timing.** `t0`/`t1` around the reads; p50/p90 of read cost and frame gap per arm and phase (Lean `quantile`).
- **Reps.** The morph path is walked 3 times; each row keeps its pass (windows are per pass since round 3).
- **Apple witness.** Job `probe-apple`: Playwright WebKit 27.2 on macos-26, hero path only, max-parallel 1.

## Runs

All arms of every run passed the identity check (24 or 48 arms per Linux job; 12 on macOS): each rewrite arm had the hash of its
search and `hydrate`. "Pre" = one pass of the morph path (ff592d6b, unaffected by the pooling bug), "reps" = three passes
(f19913eb / e85d995e), re-reduced in round 3. The Apple job ran in every dispatch that named a search (b, c and d); its
condition now needs `hero.exit` in the search.

| id | case | commit | run (Linux Chromium + Linux WebKit + Apple macos-26 where it ran) |
|---|---|---|---|
| a | default config | pre ff592d6b | 39405218882 (not re-reduced) |
| a | default config (A/A control) | reps f19913eb | 39409003529 (no Apple job) |
| b | `?preset=v2-proved` (8 flags; preset-drop-waapi is on main) | reps f19913eb | 39415671864 (Apple ran) |
| c | `?fw=morph.tween:waapi` | reps f19913eb | 39412301221 (Apple ran) |
| d | `?fw=hero.exit:scoped` | pre ff592d6b | 39407166794 (not re-reduced) |
| d | `?fw=hero.exit:scoped` | reps e85d995e | 39419128841 (Apple ran) |

## Verdicts, re-reduced with per-pass windows (MEASURED)

Units that are `new` against the faithful arm, per run and engine. B = the nav and logo units of the morph (all phases); the
Linux WebKit cell splits the push units into `no verdict: coverage` (the faithful arm itself fails coverage there, so the push was
not measured) and the rest. C = `nav.cls.is-on-dark` at 390 against the original.

| run | engine | A hero copy, cta, countdown, deck cards: new | B nav+logo: new content (new coverage) | C is-on-dark 390: both / new |
|---|---|---|---|---|
| a default | Chromium | 0 | 0 (23) | 18 / 1 |
| a default | Linux WebKit | 0 | no verdict: coverage on 1219 of 2208 push units; elsewhere 3 content (23 cov) | 13 / 1 |
| b v2-proved | Chromium | 0 | 1 (23) | 18 / 1 |
| b v2-proved | Linux WebKit | 0 | no verdict: coverage on 1288 of 2208; elsewhere 8 content (69 cov) | 13 / 1 |
| b v2-proved | macos-26 | 0 (hero 54 both) | not walked | not walked |
| c waapi | Chromium | 0 | **205 (0)** | 18 / 0 |
| c waapi | Linux WebKit | 0 | no verdict: coverage on 1150 of 2208; elsewhere 16 content (298 cov); 1 unmeasured | 12 / 5 |
| c waapi | macos-26 | 0 (hero 54 both) | not walked | not walked |
| d scoped | Chromium | 0 | 2 (0), both approach flicker | 18 / 0 |
| d scoped | Linux WebKit | **228** (hero all 278) | no verdict: coverage on 1265 of 2208; elsewhere 0 content (46 cov); 1 unmeasured | 15 / 0 |
| d scoped | macos-26 | **187** (hero all 229), 57 both in A's nodes | not walked | not walked |

The pre-reps d run (39407166794) says the same for A: macos-26 241 new (of 330 failing), Linux WebKit 416 new, Chromium 0.

Reading the table:

- **Bug A (CONFIRMED by measurement, unchanged by round 3):** `hero.exit:scoped` fails exactly where it was reported: WebKit
  only (macos-26 and Linux, all 4 widths: macos-26 50/58/49/72 new hero units at 390/640/641/1280, Linux 58/72/76/72), in
  `hero.copy`, `hero.cta`, `hero.countdown.unit`, `hero.deck.card` (reasons `apart`; props opacity 52, rect 79, transform 29, filter 21,
  translate 6 on macos-26) and `hero.cue` (42 more). Chromium has none. The default config and the 8-flag preset have none.
- **Bug B (CONFIRMED in Chromium, round 2's "not witnessed" was the reducer bug):** `morph.tween:waapi` has 205 new nav and
  logo content units in Chromium, 0 in the A/A control and 0 in the other two flag sets. They are in all 4 widths: nav
  `cls.is-expanded` 37 (open@9, open@10, close@0 to close@8) and `cls.is-morphing` 35, logo `position` 35, `rect-in-nav` 34,
  `translate` 32, `transform-origin` 18, `color` 10, and 4 `nav.background-color` units at close@0 (one per width, the
  close half of B: the candidate keeps `is-expanded` until the end of the close). The same flag also fails 254 units of the
  other morph nodes (earn 77, panel 109, panel.cta 38, actions 30). MEASURED at 1280, pass 0: the original has `is-morphing` on from m=0.0727 and `is-expanded` on from m=0.9303 in the open; the candidate
has both off until m=1.0000 (14 samples, all at 1.0) and, in the close, still on at m=0 (INFERRED: the waapi tween sets the
classes when it ends, not as it runs). The 4 close@0 units were filed as flicker
  in round 2; with this signal they are B. Linux WebKit: no verdict for the push (below); its hold and approach phases show 1, 2, 0 and 0 new content units
  (a, b, c, d), which is the noise level of that engine.
- **Bug C (CONFIRMED, baseline):** `is-on-dark` at 390 fails in the faithful arm too, as `both`: in Chromium 18 units (steps `a0`,
  `open@3` to `open@10`, `close@3` to `close@10`, `open-hold@10`), Linux WebKit 12 to 15. The round-2 note said 2; the push steps
  were hidden by the whole-phase windows. Never `new` from the flag sets (the occasional `new` 1 to 5 is that unit's flicker).
- **No verdict, Linux WebKit push.** The faithful arm fails coverage on 1150 to 1288 of the 2208 nav and logo push units (frames of
  150 ms or more, below), so a push cell is a count of the rest only. `Rel.unmeasured` marks the content failures that fall on such a unit:
  `logo.color` at 390, close@6 in c and close@1 in d (both `fail:apart`, faithful arm `fail:coverage`).

## Findings that were not predicted

1. **Round-1 coverage was frame-phase noise (coverage numbers unchanged by round 3).** With one pass the default config (cand and
   faithful are the same site) scored 126 new coverage units in Chromium (a single empty bucket fails every unit that shares
   it, ~42 units). Three passes give 42 in runs a and b (one bucket at 390 each), 0 in runs c and d (MEASURED, re-reduced).
   What round 2 got wrong was the content count, not the coverage count. Not tuned away: coverage stays a verdict, the summary
   shows content and coverage apart.
2. **Linux WebKit cannot measure the morph push.** Frame gaps are p50 140-200 ms (p90 400-600 ms), the tween passes a tenth in
   about one frame (INFERRED from the Chromium counts), so 1150-1288 of 2208 nav and logo push units fail coverage in the faithful
   arm as well. Its hero path is measurable.
3. **Reads do not dominate** (MEASURED): Chromium read 0.4 ms vs gap 17 ms; Linux WebKit read 1 ms vs gap 150 ms; macOS hero read
   1 ms (p90 3). So the lean read set was not needed and not run on CI; the slow frame is the engine's, not the probe's.
4. **The faithful rewrite is baseline red on macOS in the hero path** (MEASURED, node list from the artifacts). Run d (macos-26):
   114 `both` units: copy 27, countdown 10, cta 10, deck.card 10 (57 in A's four nodes), cue 18, orbit.card 19, track 10, stage 4,
   orbit 2, orbit.stage 2, deck 2 (the other 57). Runs b and c: 54 `both`: copy 15, orbit.card 11, cue 10, deck.card 6,
   track 4, cta 4, countdown 4. Linux WebKit has 0 `both` in the hero path, Chromium 0. Not investigated; it needs its own task.
5. `approach` steps (`a*`) and `open@1` flicker in the morph path (nav.background-color in a, b, d at one width only,
   earn.opacity at 1280 close-hold@0); a group counts only when it repeats across widths, as the four close@0 units of B did.

## Limits and follow-ups

Not a gate stage and no preset reads it. Touch input, the WebKit 325900 engine-premise test, stale anchor exclusions, Mobile Safari
in the iOS Simulator, the macOS morph path and the parallel-width speed work are follow-ups. Each case ran once on CI (repeats are a
follow-up); B is one Chromium run against three controls, 4 widths each. TS stand-ins: the kit's in-page reads and `reduce.mjs`
loops (the decisions are checked against the Lean golden).

Writes outside the task's graph writes: `lean/Fw/Store/Layout.lean`, `lean/Fw/Wire/Store.lean`, `lean/Fw/Store/Golden.lean`,
`lean/Fw/Ops/LakeJobsGen.lean`, `lean/scripts/check.sh`, `packages/contracts/golden/store/trajectory.jsonl`,
`packages/contracts/src/artifacts.ts` (the `fw run --trajectory` dispatch and the lean job, from round 1); round 3 adds
`docs/team/incidents/ledger.json` (the incident row the lead asked for).
