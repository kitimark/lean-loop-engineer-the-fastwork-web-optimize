---
id: breakpoints-named-import
kind: note
title: Named import of breakpoint conditions cuts the client bundle
status: open
created: 2026-10-20
topics: [load, bundle, breakpoints]
---

# Named import of breakpoint conditions

Answer: `import { conditions } from './breakpoints.gen.json'` makes the bundler drop `matrix`, `edgePairs` and
`backingTheorems` from the client chunk. The CSS strings are unchanged. CI artifact sizes are pending (see below).

## Measurements

Both columns are MEASURED from CI site-dist artifacts of the same lane (breakpoint-gate, `site` job). Base: run
39352403687 on `ci/breakpoints-named-import-base` (main at 0fcfa5d9 plus a comment-only marker in breakpoints.ts so
the gate guard runs). Change: run 39352271160 on `ci/breakpoints-named-import` (c1e669a8). gzip level 6 (level 9 in
brackets).

| Item | Base | Change | Delta |
|---|---|---|---|
| entry-client JS raw | 731,665 B | 626,880 B | -104,785 B (-14.3%) |
| entry-client JS gzip -6 | 209,430 B | 204,919 B | -4,511 B (-2.2%) |
| entry-client JS gzip -9 | 208,727 B | 204,556 B | -4,171 B |
| `matrix:` / `edgePairs` / `backingTheorems` in chunk | 1 matching line | 0 | removed |

Breakpoint gate (MEASURED, same runs): chromium pass in both (504 cells, 7049 pass, 0 fail, 7 excused). playwright-webkit
is `incomplete` in both with the identical single not-ok cell `matchMedia =Lean|sweep:phone-rotation` (phone-rotation#1
and #3 not-comparable), 0 fail, 291 excused. So the not-ok set is the same on base and change: a pre-existing
not-comparable cell, not caused by this change. WebKit coverage is the playwright-webkit arm of the gate; webkit-sim
is not dispatched because its inputs do not include apps/site.

## Proofs

No decision logic changed. The CSS strings are byte-identical because the same `conditions[].css` values are read;
`breakpoints.gen.json` is unchanged in the diff. `neutralConditions()` had no caller and is deleted. `breakpoints.ts`
keeps a checked assignment (`const list: readonly GenCondition[] = genConditions`) so the compiler still checks the
JSON shape. Node scripts still read the full JSON. Vite's JSON default `namedExports: true` is at
apps/site/node_modules/vite/dist/node/chunks/node.js:37300-37303 (vite 8.3.4, CONFIRMED).

Not done, filed as follow-up (below the pinned unit): the Lean-generated golden list of keys that must be absent from
the client chunk, with a build assertion on `entry-client-*.js`. It needs a new Lean generator, a generated file and a
Trigger row; the CI artifact check above already shows the keys absent. Engine-source citations (V8 JsonParser, JSC
LiteralParser) are not re-read here.

## What this changes in the plan

Load-only win; no runtime counter expected. Follow-ups: a Lean-generated list of keys that must be absent from the
bundle with a build assertion; engine-source citations (V8 JsonParser, JSC LiteralParser) not re-read here; CI
chromium-counts and gate results are appended once the run finishes. Preset inclusion is the lead's decision.
