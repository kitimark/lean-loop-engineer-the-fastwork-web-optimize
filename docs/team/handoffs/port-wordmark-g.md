# port-wordmark-g handoff
State: nav wordmark now keeps the original's `<g>` (element structure 10 = svg, g, 9 paths).
- svg-extract: gen.art['nav.wordmark'] = parseSvg + `group` (attrs of the `<g>`, empty in the original); gen.wordmark removed.
- GenSvg: Art.group optional; wraps shapes in `<g>`. nav uses GenSvg art('nav.wordmark').
- svg-allow.json: dropped the stale nav `path` entry. svg-extract.test asserts viewBox, group, 9 path kids.
- Regenerated footprint golden (part-footprint.mjs --write): footprint.gen.json + lean/Fw/Parts/FootprintData.lean.
Verified: site pnpm test + typecheck, ci-paths test; fresh dist/aot port-svg no longer reports the wordmark (still reports platform.entries, other task).
Open: lean/scripts/check.sh not run (sandbox refused); lead runs it. Pixel equality is left to the gate.
Unrelated: apps/runner/src/fw.ts shows a mode-only change; not committed.
