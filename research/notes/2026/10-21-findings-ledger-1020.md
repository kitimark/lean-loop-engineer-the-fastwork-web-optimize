---
id: 2026-10-21-findings-ledger-1020
kind: note
title: "Findings ledger catch-up: every experiment since 48d7ea86, wins and no-wins"
status: final
created: 2026-10-21
topics: [findings, ledger, negative-results]
---

# Findings ledger catch-up (findings-ledger-1020)

Answer: `research/findings/ledger.json` now holds every experiment tried between 48d7ea86 and 84a662d4. That is
16 new findings rows (n 6-38) and 5 new notes rows on existing findings. Failed and reverted experiments are rows too:
nav containment, land-fwcore-once, the stale-margin premise and the Playwright screen premise. Each row only restates
its task's own note, run ids and commits. Nothing new was measured or proved here. Items whose note says OPEN stay
OPEN.

| | findings | notes |
|---|---|---|
| before (84a662d4) | 48 | 38 |
| after | 64 | 43 |

## Rows added

Findings rows. None carries a `flag` field and none reuses a linked (part, candidate) key, so the v2-proved preset is
unchanged.

| id | n | listed item or scan find | status | chromium / webkit |
|---|---|---|---|---|
| hero.exit.scoped | 6 | scan: exit-scoped-var | partly-proved | win / unknown |
| hero.countdown.oneChain | 8 | countdown-one-chain | partly-proved | win / unknown |
| morph.tween.waapiScoped | 9 | tween-platform-scope | partly-proved | win / unknown |
| morph.mount.shiftDormant | 12 | morph-layers | partly-proved | trade / unknown |
| morph.mount.idleNone | 12 | morph-layers (rejected variant) | not-tried | not-tried / not-tried |
| pain.notes.visibleIdem | 21 | notes-scroll-idem | proved | win / unknown |
| nav.oofRoot.containment | 29 | nav-oof-root-finding | refuted | no-win / no-win |
| premise.cv.used-margin-fresh | 30 | commission-margin-recur | refuted | premise-false-intermittent / not-tried |
| premise.cv.margin-typed-om | 31 | cmr-margin-typed-om | holds | premise-holds / premise-holds |
| gate.margin.rectRule | 32 | cmr-margin-rect-rule | proved | win / unknown |
| premise.webkit.screen-kept | 33 | gate-green-baseline | refuted | not-tried / premise-false |
| load.breakpoints.namedImport | 34 | breakpoints-named-import | partly-proved | win / win |
| tooling.land.fwcoreOnce | 35 | land-fwcore-once (reverted) | refuted | not-tried / not-tried |
| tooling.land.legs | 36 | scan: land-lane-speed | proved | not-tried / not-tried |
| tooling.fwcore.lazyTables | 37 | scan: fwcore-startup | proved | not-tried / not-tried |
| tooling.ci.circleciPilot | 38 | scan: circleci-pilot | partly-proved | unknown / unknown |

Notes rows. Each entry is the existing candidate text, copied verbatim.

| finding (n, part) | task | field |
|---|---|---|
| 9 morph.tween (g0.0b WAAPI) | waapi-touch-arm (scan find) | chromium |
| 9 morph.tween (g0.0b WAAPI) | tween-platform-scope | mechanism |
| 12 morph.mount (warm-up) | morph-layers | mechanism |
| 12 morph.mount (warm-up) | mount-scroll-tap | chromium |
| 7 hero.countdown (strip) | countdown-one-chain | mechanism |

One listed item has no findings row of its own. mount-scroll-tap extends the existing shift finding as a notes row,
and the lead already decided it lands. The three cmr items get one row each (n 30-32).

## Checks (all run on this branch)

- Every Lean name in leanFor/leanAgainst (58 names) and every Lean name in the new texts resolves to a declaration on
  main (CONFIRMED by a declaration index of `lean/Fw` at 84a662d4).
- Every run id, commit and number of three or more digits in the new rows appears in the cited note, handoff or
  `results/` file (CONFIRMED by a token scan).
  - The countdown runs trace to `results/countdown-one-chain/counts.md`.
  - The notes-scroll-idem runs trace to `results/notes-scroll-idem/runs.json`.
- The file still equals `JSON.stringify(d, null, 1)` with no trailing newline, so the merge driver's identity holds.
- `Fw.Preset.Gen.run ["--check"]` reports "v2-proved: up to date, 9 flags". The 9 flags are unchanged.
- `apps/runner` `pnpm test` passes 1437 of 1437 tests in 48 files, including typecheck, ledger-merge, premises and
  land-inputs. `node --test scripts/ci-paths.test.mjs` passes 41 of 41.
- Preset membership comes from `packages/contracts/golden/preset/v2-proved.decisions.jsonl`. These are all `no-link`
  with member false: hero.exit:scoped, hero.countdown:one-chain, morph.tween:waapi-scoped, morph.mount:shift-dormant
  and pain.notes:visible-idem.

## Scan of 48d7ea86..84a662d4

Scanned every file under `research/notes` and `docs/team/handoffs` that changed in the range.

In scope (a tried change or premise with a measurement or proof):

- Listed items: nav-oof-root-finding, commission-margin-recur, cmr-margin-typed-om, cmr-margin-rect-rule,
  land-fwcore-once, tween-platform-scope, mount-scroll-tap, notes-scroll-idem, countdown-one-chain,
  breakpoints-named-import, morph-layers, gate-green-baseline.
- Scan finds:
  - exit-scoped-var: hero.exit:scoped, a 64 % elementCount cut.
  - waapi-touch-arm: the touch arm, plus the refuted start premise R5.
  - land-lane-speed: parallel land legs.
  - fwcore-startup (handoff fwcore-lazy-tables): 812.4 ms to 40.4 ms per spawn.
  - circleci-pilot: provider pilot, OPEN.

Out of scope:

| files | reason |
|---|---|
| ci-telemetry, cache-relations, lake-gc-refs, gh-budget-waiter-liveness, gh-budget-watch-expiry, console-daemon, fw-run-inputs, land-wait, land-queue-why, land-queue-fwcore-rebuild, land-remote-fail-wins, land-legs-followups, runner-bin-mode, latex-strip-c, scrub-session-paths (r1, r2), preview-e2e, preview-e2e-entry, preview-inspect, preview-proxy-direct | tooling or features built to a spec; no speed or work hypothesis was tried and measured |
| lean-migration, lean-migration-inventory | plans |
| 10-19-ci-wait-lag (note and handoff) | a diagnosis with instrumentation; no tried change was measured |
| 10-17-sim-speed-review | a review of a note from before 48d7ea86 |
| preview-original-gate | a tooling bug (Sec-Fetch-Dest is sent only to secure origins); a candidate if the lead wants tooling bugs in the ledger |
| fwcore-query-speed, fwcore-replay-speed | defect fixes measured only in local debug runs, with no CI run id to cite; candidates once a CI number exists |

## What this changes in the plan

- **Findings ledger:** new rows use ids. Tooling experiments get their own parts (`tooling.land`, `tooling.fwcore`,
  `tooling.ci`) at n 35-38. The next catch-up starts from the commit of this note.
- **Preset (lead):** four measured wins sit outside v2-proved as `no-link`. They are scoped, one-chain, waapi-scoped
  and visible-idem. Adding any of them needs a `flag` on its row and a regenerated golden.
- **Open items unchanged:** cmr-strut-asym, morph-nav-scope (117-118 residual elements per frame), the waapi touch
  row redesign, countdown touch frame 499, the CircleCI repeat samples and the breakpoints absent-key golden.
