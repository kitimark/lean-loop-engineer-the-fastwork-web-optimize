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

| Item | Before (main) | After | Status |
|---|---|---|---|
| entry-client JS raw | 730,103 B | 625,895 B | MEASURED locally (one debug build, not a result); CI artifact pending |
| entry-client JS gzip | 208,054 B | 204,470 B | same |
| `matrix:` / `edgePairs` / `backingTheorems` in chunk | present | 0 matches | same |

`check-breakpoints` passes (30 conditions, 124 probes, generated file unchanged). Typecheck passes.

## Proofs

No decision logic changed. The CSS strings are byte-identical because the same `conditions[].css` values are read.
`neutralConditions()` had no caller and is deleted. Node scripts still read the full JSON.

## What this changes in the plan

Load-only win; no runtime counter expected. Follow-ups: a Lean-generated list of keys that must be absent from the
bundle with a build assertion; engine-source citations (V8 JsonParser, JSC LiteralParser) not re-read here; CI
chromium-counts and gate results are appended once the run finishes. Preset inclusion is the lead's decision.
