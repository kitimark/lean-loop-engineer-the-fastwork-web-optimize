# Feel session 2: arms, order, estimate and the one command (task feel-session-2-prep)

Nothing here touched the phone. Claims are marked CONFIRMED (Lean theorem, golden or unit test), MEASURED (a build or dry
run), INFERRED.

## Answer

One command starts the captured session after the user says yes: `sh scripts/feel-session.sh` (from the repo root). It
prints the plan, probes the phone read-only, starts `feel start` in the background (capture on, pin Serious, fresh dir
`.local/phone/<date>-feel2`, seed) and stops there. The lead then runs `feel next` and `feel rate`. 7 arms, 10 visits,
about 21 minutes (estimate).

## Where the arm flags come from (CONFIRMED)

`v2-proved` was a hard-coded 2-flag list in `Fw.Device.Feel`. It is now `sameArmsOf preset`: the flags of the generated
golden `packages/contracts/golden/preset/v2-proved.json` (read by `Fw.Preset.Gen.presetKeys`, sorted), so the arm is the
preset and there is no second copy. `FeelGolden.lean` reads that file and writes `feel.jsonl` (a `preset` row records the
source and the flags); the `device-feel golden check` job in `check.sh` regenerates it from the preset file, so a preset change
without a regenerated golden fails the check. The TS glue (`device-feel.mjs`) reads the preset file at load and throws
if `feel.jsonl` disagrees, so a stale golden never opens a wrong arm. Theorems: `sameArmsOf_proved` (the arm is exactly the
preset), `dropPart_sublist`, `dropPart_isolates` (the 2-flag arm lacks only flags of the dropped part), `dropPart_none`,
`dropPart_noop`, `arm_ids_nodup`, `lookArms_length`. The generator refuses a preset with no `platform` flag (the two arms
would be one).

## Arms

Same-look, blind, each shown twice, never twice in a row, letters per visit (A..F), order from `seed mod 3` (CONFIRMED in `lean/Fw/Device/Feel.lean`,
unchanged rule: `order_noRepeat`, `order_count`, `labels_fresh`):

| Arm | Flags | Why |
|---|---|---|
| base | none | the reference every score is compared with |
| v2-proved | `engine.scroll:unthrottle`, `hero.exit:threaded`, `platform:faded-pause` (read from the golden) | the current preset, which gained `platform:faded-pause` after session 1 |
| v2-proved-2flag | `engine.scroll:unthrottle`, `hero.exit:threaded` | the preset without the `platform` part (session 1's `v2-proved`), so the pair isolates `platform:faded-pause` |

Labelled look arms, one visit each (L1 to L4), the person is told what to look at; compared with both base scores:

| Label | Flags | What the person reads |
|---|---|---|
| L1 | `nav:earn-logical` | the Join waitlist button in the nav animates when the nav changes, as it does on a desktop browser |
| L2 | `platform.glint:compositor` | the shiny dash on the platform line glides; check it does not stutter or jump |
| L3 | `morph.end.nobounce:on` | the page end does not bounce |
| L4 | `morph.stage:on` | the nav morph at the page end follows your finger; the page is longer |

Why: L1 is the engine-parity look change (WebKit eases the earn button's padding as Chromium does; macOS WebKit 390 px
cell passes, `research/notes/2026/10-2x-earn-logical-preset.md`); L2 is the compositor glint, a look change for the user's visual review
(`platform.glint` part.json `compositor`); L3 and L4 are the two session-1 look arms the kit keeps (`morph.end.nobounce`, `morph.stage`), now as plain `:on` flags.
`morph.stage:on` adds about 739 px to the page height (MEASURED in the 2026-10-29 dry run).

## Arms built and resolving (local build in this branch, `apps/site/dist/aot/configs.json`, not a measurement)

The build command is generated from the arm list (`feel build-cmd`) and the six configs built in 1 s with all gates passing.
`feel plan` read `dist/aot/configs.json` and found every arm's `?fw=` (the same `armHashes` rule `feel start` uses):
base `""`, v2-proved `?fw=engine.scroll:unthrottle,hero.exit:threaded,platform:faded-pause`, v2-proved-2flag
`?fw=engine.scroll:unthrottle,hero.exit:threaded`, and the four look flags.

Conflicts with v2-proved (read from `apps/site/src/parts/*/part.json`): none of the four look flags is
listed in a `conflicts` entry against any of the three preset flags (INFERRED from the registry; the kit builds each look arm alone, not on top of v2-proved).
The registry does list real conflicts: `platform/part.json` (line 48) declares `platform:faded-pause` against
`morph.tween:waapi`, `morph.tween:waapi-scoped`, `platform.sweep:offscreen-pause` and `platform.glint:offscreen-pause`; none is a
look arm here. (The refusal at build time was not exercised in this task.) The kit does not compose look arms on top of
v2-proved at all: each look arm is its one flag alone, compared with base, as in session 1. So a look verdict says "this flag
alone against base"; it does not say how the flag behaves on the preset (follow-up if a look arm is liked).

## Visits and estimate

10 visits: 6 blind (3 arms x 2) and 4 labelled. Estimate 1235 s, about 21 min (`estimateS visits = 285 + visits x 95`, Lean
`fixedS`, `visitS`, `estimateS_mono`, `estimateMin_ge`, golden row `estimate`). Sources: 285 s fixed and 20 s per visit for
open, settle, scripted swipes and rating are the 2026-10-29 dry run in `research/notes/2026/10-2x-phone-feel-kit.md` (8 min from pin start to cleared pin, 196 s of it the
drive over 10 visits); 60 s for a person scrolling slowly to the end and back and 15 s to relay `next` and `rate` are INFERRED.
Add up to 3 min if the pin takes longer to reach Serious (gate bound 180 s).

## The script

`sh scripts/feel-session.sh [--seed N] [--date YYYY-MM-DD] [--build] [--plan]`. Without `--seed` the seed is the day number
(a new order each day; `--seed` pins it).

1. Prints the plan (`feel plan`): arm count, visit count, estimate, blind order with names (lead only), look texts, the next and rate commands. Arms missing from the build: exit 4 and
   the build command; `--build` builds them. `--plan` stops here and touches no phone.
2. Probes the phone read-only (`feel probe`): `devicectl list devices` (one physical measurement phone, paired, a
   transport), `idevice_id -l` (on USB), `devicectl device info lockState`. Lean `probeOf` names the first failing fact and
   `Probe.ask` is the sentence for the user (not listed, not paired, not connected, not on USB, locked, lock unknown); the
   script prints it, exits 3 and changes no setting. Theorems `probe_notListed` .. `probe_lockUnknown` (one per branch),
   `probe_ready_iff`, `ask_nonempty`; golden rows `probe` (all 48 combinations), `probeAsk`.
3. Starts `feel start --site ../../apps/site/dist/aot --dir .local/phone/<date>-feel2 --pin Serious --seed <n> --fresh`
   in its own process group, log `.local/phone/<date>-feel2-start.log` (+ `.pid`), and waits up to 300 s for the control server
   (`feel status` answers). If the process ends first it prints the log tail and the ask for the cause (`failOf`: no tab means Web
   Inspector off or Safari/phone locked, locked, not on USB, other; golden rows `fail`) and exits 1. Web Inspector cannot be read
   from the Mac before the proxy runs, so that ask comes from the start failure, not from the probe (INFERRED limit).

The script never runs `feel next`; its test (`test/device-feel-plan.test.mjs`, against a stub CLI) asserts no `next` or
`rate` call, one `start`, probe before start, exit 3 for a locked phone, exit 1 for a failed start, exit 4 for missing arms.

The command for the lead, after the user says yes (add up to 3 min to the 21 if the pin is slow to reach Serious):

```
sh scripts/feel-session.sh --seed <n>        # run_in_background; exit 0 means the session is running and no arm is open
node src/device-cli.mjs feel next --dir .local/phone/<date>-feel2        # from packages/measure-webkit; then rate, status, stop
```

## Limits

- No device run: the probe's devicectl field names (`pairingState`, `transportType`) come from a saved device list (INFERRED to hold on the
  live read); `tunnelState` is not used because the saved list shows `disconnected` for a paired idle phone. `connected` means a reachable transport.
- Look arms are labelled, not blind; n = 2 per same-look arm.
- Look arms are tested alone against base, not on top of v2-proved.
- Serious is induced; capture costs page time (see `10-2x-phone-feel-capture.md`).
- TS stand-ins (golden-checked, no decision logic of their own): `probeOf`, `failOf`, `estimateS` in `device-feel-plan.mjs`; I/O glue: `readFacts`, the script.
