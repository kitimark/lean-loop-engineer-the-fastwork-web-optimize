# trajectory-frames: side-by-side nav frames for a person's visual review of a look change

The probe and the gate decide numbers. A look change (class L, for example `nav:earn-no-transition`) needs a person to see the
frames. This lane captures the nav band of the faithful rewrite and of one flagged rewrite through the same wheel pushes and puts
the two rows one above the other. It is review material: it decides nothing. Code: `packages/gate-breakpoints/src/trajectory/frames.mjs`
(capture and strips), `engines.mjs` (`shot`, `screencast`). Workflow: `.github/workflows/trajectory-probe.yml`.

## Run it (a push, no dispatch)

Head commit message of a `ci/*` push:

    [ci:trajectory-probe] [frames:nav:earn-no-transition]
    [trajectory engines=playwright-webkit widths=390,1280]

A `[frames:` message is exempt from the verdict/diagnostic mark rule (Lean `Fw.Ci.Trigger.effLane`: a frames run is read by eye and never stored as a verdict run), so `widths=390,1280` needs no `diagnostic`; `trajectory-line.test.mjs` parses this very line.

Wait with `pnpm -s fw ci wait --branch ci/<name> --workflow trajectory-probe --sha <sha>` (polls >= 120 s), read the artifacts with
`pnpm fw ci <runId>` or `gh run download <runId>`.

| Job | Runner | Artifact | Holds |
| --- | --- | --- | --- |
| `frames` (engines chromium, playwright-webkit) | ubuntu arm | `frames-chromium`, `frames-playwright-webkit` | Linux Chromium and Linux WebKit strips, screenshots only |
| `probe-apple` (one leg per width) | macos-26 | `frames-apple-390`, `frames-apple-1280` | macOS Playwright WebKit strips, screenshot and screencast |

`probe-apple` is the existing macOS job (no new macOS job: Lean `Fw.Ci.Pool.Caps.rows_files_nodup`, cap 15 min). On a push whose message
carries `[frames:` its walk, `merge-apple` and the `probe` and `merge` jobs are skipped and a frames step runs in each width leg. The
`[trajectory ...]` line picks the legs: `widths=390,1280` is two legs (Lean `Fw.Gate.Trajectory.legs`, `plan.mjs`), `engines=playwright-webkit`
keeps the Linux Chromium plan out of the apple matrix. `Fw.Ci.Intent.macosFiles` lists `trajectory-probe.yml` (its push run holds a macOS job),
`golden/ci/intent.jsonl` is regenerated from it (`cd lean && lake test -- --write-ci-trigger-golden`).

## What a strip is

`strips/<engine>-<width>-<push>[-screencast].png` inside the artifact, one per engine, width and push (open, close); `strips/index.json` lists
them with `columns`, `crop`, `shots {faithful, flag}`, `usable`, `identity`, `source`. Top row: no flag; bottom row: the flag. Under each
image: `#i from-to ms`, the interval after the wheel event the image stands for. Both arms get the same wheel input and are sampled at their
own times, so columns line up by time, not by frame number.

- `--source screenshot`: `page.screenshot` of the band in a loop for 1.5 s after the wheel event; the interval is the time that screenshot took.
- `--source screencast`: `page.screencast.start({onFrame})` (playwright-core 1.64.1), the JPEG frames the engine composites; the interval is
  from the frame's swap time to the next frame's. The frame in effect at the wheel event is shot 0, from 0. Not `recordVideo` (ffmpeg resamples to 25 fps).
- `--reps N`: the capture repeats each push N times per arm and pools the shots of the repeats, ordered by ms after the wheel event
  (`pooled` in `frames.mjs`); the label carries the repeat (`#i rK from-to ms`). The `probe-apple` frames step uses `--reps 3`. Why: run
  39529343997 (one repeat) gave 4 to 10 shots per push on macOS (130 to 300 ms per screenshot on the runner), none usable; run
  39530106935 (3 repeats) gave 18 to 35 per arm, all 8 strips usable, identity ok.
- `usable` = min(shots.faithful, shots.flag) >= 10 (Lean `Fw.Gate.Frames.usable`, TS stand-in `usable` in `frames.mjs`, same cases in
  `test/frames.test.mjs`). Decided per strip.

Strips are CI artifacts only (retention 30 days); PNGs never enter git. `results/earn-look-review/index.json` names each strip by run id,
artifact and path.

## Limits

- macOS Playwright WebKit is not Safari on a phone. Linux WebKit (WebKitGTK/WPE) screenshots land 1 to 10 shots per push.
- Pooled repeats mix the timing jitter of separate pushes: a column shows shots of different repeats at about the same ms, not one continuous run.
- Screencast times: Playwright WebKit fixes a clock offset per page at its first delivered frame (coreBundle.js `_onScreencastFrame`). Each arm is its own page, so the two rows carry different unknown offsets. In run 39530106935 the labels trail the in-page recorder by about 150 to 450 ms. Screencast columns are not time-aligned between rows. Use the screenshot strips to compare timing, and the screencast strips only for the frame sequence within one row. (Chromium screencast times are the compositor's swap time.)
- The wheel time is the node wall clock after the mouse moved to the wheel point, before the wheel call; its latency to the page is not subtracted.
- No flag or site change: the strips show the flag as built.

## The transitions recording (earn and language buttons, per frame)

`[transitions:earn]` next to a `[frames:...]` flag token (the flag token keeps the mark-rule exemption and the walk skipped; its frames steps
are skipped by `[transitions:`) turns the macOS leg into a per-frame recording of the "Join waitlist" and language buttons:

    [ci:trajectory-probe] [frames:nav:earn-no-transition] [transitions:earn]
    [trajectory engines=playwright-webkit widths=390,1280]

Per width leg (macos-26, the Lean cap of 15 min): Playwright Chromium and Playwright WebKit on the same runner, the original (`snapshot/site`) and the
faithful rewrite, each with 3 full repeats and one light page (`src/trajectory/transitions.mjs capture`). A row per rendered frame (native
requestAnimationFrame, no seeking): the rects of earn, language wrap, actions and nav flags, and in full mode the computed padding-left/right,
max-width, opacity, `--nav-expand`, `--earn-out`, `--earn-layout`, `column-gap` and the live CSSTransition list. The light page reads rects only,
so the cost of style reads is bounded. Sequences: hero-exit and hero-entry (a scripted scroll ramp, 2 viewport heights in 600 ms), morph-open and
morph-close (wheel pushes; the CI step passes `--morph 0`, so the 15 min cap holds: hero sequences only). Then Safari itself through `safaridriver` (`transitions-safari.mjs`, hero sequences, widths of 640 and up, best
effort, `safari-status.txt` says ok, skipped or failed and why). `transitions.mjs summary` reduces every recording (`index.json`,
`*.summary.json`, `*.summary.txt` with the per-frame table). Artifact `transitions-apple-<leg>`. Why the cause is in Lean: `Fw.Engine.TransitionStart`
(golden `packages/contracts/golden/engine/transition-start.jsonl`); the reduction in `transitions.mjs` is a TS stand-in.
