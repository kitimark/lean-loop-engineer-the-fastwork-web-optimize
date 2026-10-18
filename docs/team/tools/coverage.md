# fw coverage: which gate-probed values have a Lean source

`pnpm fw coverage` lists every value the breakpoint gate compares and says where Lean stands behind it. Spec and
proofs: `lean/Fw/Gate/Coverage.lean`. Glue: `apps/runner/src/coverage.ts`. Golden vectors:
`packages/contracts/golden/gate/coverage.jsonl`, replayed by `apps/runner/test/coverage.test.ts`.

## Probes

A probe is `(part, role, class, key, breakpoint class)`, with the same item model as `Fw.Gate.Items`:
- count: one per role, key `count`.
- box: one per `dims` entry of the role in `packages/gate-breakpoints/src/anchors.json`.
- style: one per compared property. This is the run header's `restated` list for the role, minus the role's
  `skipProps` and `skipSets` and the global `skipPrefixes` (`comparedProps`).
- Breakpoint classes: the probe blocks (`desk`, `touch`, `dark`, ...) plus the sweep ids. They come from the run, or
  from `spec.mjs` (`gen.matrix.probes[].block` + `sweepDefs`) when no run is given.

Info items are never judged, so they are not probes. The matchMedia table rows are checked against Lean by the
gate's own "matchMedia =Lean" row and are not part probes either.

## Sources

| kind | holds when |
|---|---|
| `generated <file>` | the file exists and a non-test file under `apps/site/src` names it (basename) |
| `golden <file>` | the file exists and a `*.test.ts(x)` under `apps/` or `packages/` names it, or for `golden/parts/<id>.jsonl` calls `goldenConformance('<id>'` |
| `exempt <why>` | always; `why` ∈ transcribedEmpiricalOnly, hoverDependent, eventCount, engineDefault (closed enum) |

A claim is `{part, role, cls, key, bp, src}`:
- `role`, `key` and `bp` are patterns: `*` = any, `s*` = prefix `s`, anything else = exact.
- `cls` is `count`, `box`, `style` or `*`.

The first usable claim is the probe's source (`sourceOf`). `lint` is the list of probes with no usable claim.

Theorems:
- `coverage_lint_sound`: lint is empty iff every probe has a usable claim.
- `lint_monotone`: more evidence or more claims never adds a lint entry.
- `lint_nil_judged_sourced`: an empty lint means every judged gate item has a source.
- `tally_total`: the per-kind counts add up to |probes|, and uncovered = |lint|.

## Usage

```
pnpm fw coverage [--root <tree>] [--run <engine.json|dir>]... [--failures <summary.json>]... [--summary] [--json]
```
- `--root`: the tree whose anchors, site sources and tests are read (default: this checkout). Claims always come from
  this checkout's golden.
- `--run`: raw gate run files (`<engine>.json`, or a directory holding them, e.g. an unpacked `gate-merged-*`
  artifact). The props are a union over engines. Without `--run`, only count and box probes are listed (with a warning).
- `--failures`: gate `summary.json` files. Each failing item is split into cells, one per breakpoint class: labels
  are probe ids (mapped to their block) or `<sweep>#<i>`. Each cell is marked UNCOVERED or with its source.
- Exit 1 when any probe is uncovered (warn mode: `fw land` does not call it).

## Changing claims

1. Edit `claims` in `lean/Fw/Gate/Coverage.lean`. The `#guard` on `patWireSafe` keeps patterns wire-safe.
2. Regenerate the golden from `lean/`:

```
printf 'import Fw.Gate.Coverage\ndef main (args : List String) : IO UInt32 :=\n  Fw.Wire.Coverage.Golden.run ".." (!args.contains "--check")\n' > /tmp/CovGolden.lean
lake build Fw.Gate.Coverage && lake env lean --run /tmp/CovGolden.lean          # write
lake env lean --run /tmp/CovGolden.lean --check                                  # exit 1 when stale
```

3. Run `pnpm --filter ./apps/runner exec vitest run test/coverage.test.ts`.
