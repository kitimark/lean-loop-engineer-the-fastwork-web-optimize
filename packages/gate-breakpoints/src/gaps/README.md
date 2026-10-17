# Gaps lane (Q33): the 8 cells the default gate cannot judge

```sh
cd packages/gate-breakpoints
sh ../../scripts/sim-lock.sh acquire <you>      # same shell command as the run; release after
node src/cli.mjs gaps run --out out/gaps-a      # [--skip-sim] [--skip-mac] [--owner <you>] [--ipad "iPad Pro 13-inch (M5)"]
node src/cli.mjs gaps summary --out out/gaps-a  # re-judge from the raw files: gaps.json, gaps.md
node --test "test/*.test.mjs"
```

Cells: the 4 `fractional-gaps` probes (600.5, 640.5, 860.5, 1000.5) and the 4 `hover-pointer-cross` probes of the Lean matrix.

| cell kind | engine | mechanism | state |
|---|---|---|---|
| fractional | Chromium | browser zoom 200% from the profile (`Default/Preferences` `partition.default_zoom_level.x = log 2 / log 1.2`) + CDP override `2N+1` x `2H`, DSF 1: the page sees width N+1/2, DPR 2 | `pass`/`fail` as every gate cell (orig = rewrite, = Lean, legacy text, parts) plus the gap check |
| fractional | WebKit | none: media width is an int (WebKit source). Evidence records: Playwright WebKit at 4 widths x 4 DPRs, macOS system WebKit WKWebView at page zoom 0.9 to 2, iOS Simulator iPhone and iPad | `unreachable` if every record has a whole media width and no gap |
| cross | Chromium | `--blink-settings` (one browser per pair) | `pass`/`fail` |
| cross | WebKit | none: primary pair is one platform constant. Evidence: the same records | `unreachable` if every record shows (hover, fine) or (none, coarse) |

`run` reuses the gate's `runEngine` (same loads, same A-vs-R items, same `verdict.mjs`) through its optional `gaps` argument
(launcher, probe mapping, one extra in-page report under `raw.gap`); a default gate run is byte-identical (checked against the
HEAD copy). The raw files are `chromium.json` and `playwright-webkit.json` (same shape as the gate's) plus `evidence.json`.

| File | Role |
|---|---|
| `cells.mjs` | the 8 cells from the Lean gen file, the mechanism table, `realizeEnv` (stand-in), `WEBKIT_PRIMARY_PAIRS` (stand-in) |
| `engines.mjs` | Chromium launcher with browser zoom |
| `inpage.mjs` | in-page report: media width by `(width > X)` bisection (1/64 grid), window sizes, gap queries, 15 pointer queries |
| `probe.mjs` | our own probe page and its POST server (Simulator, macOS WKWebView, phone) |
| `evidence.mjs`, `wkzoom.swift` | Playwright DPR, macOS WKWebView page zoom (Swift host, compiled into `out/`), Simulator driver |
| `judge.mjs` | per cell and engine: pass/fail via the gate's rule, `unreachable`, `not-comparable` |
| `devicejudge.mjs`, `device.mjs`, `DEVICE.md` | the phone session: server, records, pass rule |

TS stand-ins (Lean first, to be specified and proved before this is final): the `unreachable` state and its two evidence
checks (`judge.mjs`), `WEBKIT_PRIMARY_PAIRS` and the mechanism table (`cells.mjs`), `realizeEnv` (the Lean probes still say
dpr 5/4 for the fractional widths; DPR is inert in every condition, `MQ.eval_indep_height_dpr`), and the device rule.
