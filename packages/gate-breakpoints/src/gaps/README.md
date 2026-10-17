# Gaps lane (Q33): the 8 cells the default gate cannot judge

Results come from CI (workflow `gate-gaps`, `.github/workflows/gate-gaps.yml`); this Mac runs one short debug run at most.

```sh
cd packages/gate-breakpoints
node src/cli.mjs gaps collect --out out/gaps [--engines chromium,webkit] [--skip-mac] [--skip-sim] [--ci] [--owner <you>]
node src/cli.mjs gaps summary --out out/gaps   # judge the raw files with Lean (fwcore): gaps.json, gaps.md
node src/cli.mjs gaps run ...                  # collect, then summary
FW_CORE_BIN=<path to fwcore> node --test "test/*.test.mjs"
```

Local Simulator steps need the sim-lock held by `--owner` (same shell command: `sh ../../scripts/sim-lock.sh acquire <you>` ...
`release <you>`); `--ci` (a GitHub runner, its own VM) skips that and creates the iPad device if the image has none. A step that
cannot run on the machine is recorded under `evidence.skipped` with its reason.

Cells: the 4 `fractional-gaps` probes (600.5, 640.5, 860.5, 1000.5 at DPR 2) and the 4 `hover-pointer-cross` probes of the Lean matrix.

Who decides: Lean. `gate.state` takes the engine's port (`chromium`, `webkit-apple`, `webkit-glib`; `run.header.port`) and
answers `pass` / `fail` / `not-comparable` / `unreachable:<reason>` (Fw.Gate.Reach: `primary-pair`, `whole-width`,
`width-dpr`). The model check sends what the WebKit pages reported (media width, primary pair) to `gate.reach` and the
statuses through `gate.cell`, so a record that contradicts the model turns the verdict into `fail`.

| cell kind | engine | how the environment is built | state |
|---|---|---|---|
| fractional | Chromium | Lean's env as is (width w, DPR 2): browser zoom 2 (`Default/Preferences` `partition.default_zoom_level.x = log 2 / log 1.2`) + CDP override `2w` x `2h`, DSF 1. The record keeps Lean's env (`env`) and the built one (`realized`) | `pass`/`fail` like every gate cell |
| fractional | WebKit | none: media width is an int. Playwright asks for ceil(width) and the page reports it | `unreachable:whole-width` (Lean) |
| cross | Chromium | `--blink-settings` (one browser per pair) | `pass`/`fail` |
| cross | WebKit | none: primary pair is one platform constant | `unreachable:primary-pair` (Lean) |

Evidence on the WebKit side (all checked by the model check): Playwright WebKit at 4 widths x 4 DPRs and 4 pairs, macOS system
WebKit in a WKWebView at page zoom 0.9 to 2, the iOS Simulator iPhone and iPad (2 plain loads, then 8 meta-viewport variants:
`vp=width=<w>` and `aim=<w>` = `width=device-width, initial-scale=screen.width/w`, the iOS rounding path), and an informative
A=R row (original vs rewrite in the WKWebView at page zoom 2, window 1201; never in a count).

| File | Role |
|---|---|
| `cells.mjs` | the 8 cells from the Lean gen file, `realizeChromium` / `realizeWebkit`, `probeVariants`, display-only `HOW` |
| `engines.mjs` | Chromium launcher with browser zoom (env.zoom, env.override) |
| `inpage.mjs`, `probe.mjs` | in-page report (media width by bisection, window sizes, gap queries, 15 pointer queries) and our probe page / POST server (`vp=`, `aim=`) |
| `evidence.mjs`, `wkzoom.swift` | Playwright DPR, WKWebView host (page zoom, plan mode for the A=R row), Simulator driver (variants, device creation in CI; a Safari warm-up, 3 launch attempts per page; on the slow runner `FW_SIM_TIMEOUT_SCALE=3` and `FW_SIM_ARM_BUDGET_MS=480000` scale the waits and stop an arm adding variants, each failure listed in `skipped`) |
| `judge.mjs` | shaping only: run file / records -> fwcore requests (`judgeRun`, `modelCheck`) |
| `devicejudge.mjs`, `device.mjs`, `DEVICE.md` | the phone session: server, records, pass rule (W via Lean reach, X, T, S, L) |
| `cli.mjs` | collect / summary / run, `gaps.json` and `gaps.md` |

TS stand-ins (decision-free glue, listed for the lead): the `touchArm` expectation `(none, coarse) and wLe1200` in T
(devicejudge.mjs), the status mapping equal/differ/missing for the model check (judge.mjs), the S and X record comparisons.
