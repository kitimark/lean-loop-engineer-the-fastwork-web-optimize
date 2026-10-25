# Init-cost lint: why it hit maximum recursion depth near 1640 constants, and the flat fix

Tags: CONFIRMED (Lean source cited at lean4@eb6cafb, the v4.35.0 toolchain), MEASURED (local run named here),
INFERRED (reasoned, not seen).

## Answer

- **Cause (CONFIRMED).** The scan put every probe row into one definition, `initCostRows := [row0, ..., rowN]`.
  The compiler turns that literal into one chain of `5 * N + 1` lets (INFERRED from the MEASURED 1637/1638 boundary). Its `simp` pass recurses once per let
  (`src/Lean/Compiler/LCNF/Simp/Main.lean:218` adds a depth level through `withIncRecDepth`, `:258` recurses on the
  continuation). The compiler's depth limit is `max 8192 maxRecDepth` (`src/Lean/Compiler/LCNF/Main.lean:122`,
  `withAtLeastMaxRecDepth 8192`; `src/Lean/CoreM.lean:663`). So the limit is reached near N = 8192 / 5.
- **Boundary (MEASURED).** With the old scanner and a synthetic module of N constants, N = 1636 and 1637 pass, and
  1638, 1639 and 1640 fail with `maximum recursion depth has been reached`. Main had 1636 constants, so one more
  constant was enough to break the lint.
- **The second error (CONFIRMED).** Compilation runs as a separate task. When it fails, `compileDecls` marks the
  declaration noncomputable (`src/Lean/CoreM.lean:774-777`). The `#eval` of the report then fails with
  `dependsOnNoncomputable` on `initCostRows`. That error is a consequence of the first, not a second cause.
- **At 8192 constants (MEASURED).** At the default limit the old scanner also fails in the kernel with
  `(kernel) deep recursion detected` (`src/Lean/Message.lean:892`): the kernel checks the 8192-deep nested
  `List.cons` term recursively. With `set_option maxRecDepth 100000` (the builder's tested raise) the old scanner
  passes at 8192 in 16 s. The fix passes in 10 s. The raise was not taken because every recursion still grows with
  the count: the compiler's simp and the kernel each recurse once per list element, so the margin shrinks with every
  constant added. INFERRED: the next limit would be the native thread stack.
- **Fix.** `Fw.Lint.InitCostScan.addListTree` (lean/Fw/Lint/InitCostScan.lean:121) splits each list into constants of
  at most `fanOut = 256` elements: list-literal leaves, then `List.flatten` nodes level by level, up to the root
  `initCostRows`. No definition holds more than 256 elements (`5 * 256 + 1 = 1281` lets, 6.4x under 8192), whatever
  the constant count. Proved in Lean: `flatten_chunks` (the rows keep their order), `length_le_of_mem_chunks` (each
  part has at most `f` elements), `length_chunks_lt` (each level is smaller than the one below, so the loop ends),
  plus `chunks_zero` and `chunks_nil` for the empty branch.
  The unmapped and no-C string lists go through the same builder.
- **Regression check.** The check.sh job `init cost lint scale` builds `lean/scripts/init-cost-cases/Many.lean`, a
  module with 8192 synthetic constants (5.0x today's 1636). It requires the summary line
  `init-cost: 8192 start-time constants` and prints the lint time. The job fails against the old scanner (MEASURED:
  kernel deep recursion, then a compiler IR panic) and passes with the fix.

## Times (MEASURED, local, each run through `fw slot run --kind test`)

| run | constants | old scanner | fixed scanner |
|---|---|---|---|
| real lint over fwcore (`lake env lean scripts/InitCostLint.lean`) | 1636 | 14 s, 7 s, 7 s | 9 s, 7 s |
| scale case (Many.lean: compile plus lint) | 8192 | fails; 16 s with `maxRecDepth 100000` | lint 10 s, compile 7 s |

The fix leaves the lint time unchanged within run-to-run spread. The first old run (14 s) came right after a
memory-pressure wait. INFERRED: the extra `addAndCompile` calls (9 for 1636 rows: 7 leaves, 1 node, the root) cost too
little to show.

check.sh (MEASURED, `fw slot run --kind check`) is green at 9525f69ac and again at f1ad0601b (main f611b0f12 merged
in, with scene-pause-kcopy): the lint reports 1636 constants in 456 modules, and `init cost lint scale` reports 8192
constants linted in 10 s.

## Accepted limits

- `maxRecDepth` is not raised. The lint passes at the default limit, with no recursion that grows with the count.
- The `Unit` argument workarounds in `lean/Fw/Device/SimTouch.lean` and `lean/Fw/Parts/HeroScenePause.lean`
  (`heroAnims`, `baseAnims`) stay. Their owners remove them.
- No CI dispatch. The next lean run on any `ci/*` branch after the land is the live check.
- The scale case uses a fixed 8192. If fwcore passes 2048 start-time constants, that check drops below 4x and
  `Many.lean` should grow (follow-up).
