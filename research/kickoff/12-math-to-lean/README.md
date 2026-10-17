# 12 · Math to Lean (study lessons)

Twelve lessons (set A: levels 1-5, set B: levels 6-10) that show how a math statement becomes Lean. Each one uses a real
declaration from `research/kickoff/05-lean-sketch/Fw/Spec/*.lean`. Every lesson was checked by an independent reviewer,
and every "fix" correction from that review has been applied.

| File | What it is |
|---|---|
| `lessons.json` | The lessons (math, Lean excerpt with file:lines, math-to-Lean pairs, proof steps, gotcha, exercise) and the notation table |
| `StudyA.lean`, `StudyB.lean` | `#check` / `#eval` lines for each lesson, plus proofs of the exercise answers (no `sorry`, no Mathlib) |
| `docs/plan/math-to-lean.html` | The study page; it embeds `lessons.json` |

## Run the study files

```sh
cd research/kickoff/05-lean-sketch && lake env lean ../12-math-to-lean/StudyA.lean
cd research/kickoff/05-lean-sketch && lake env lean ../12-math-to-lean/StudyB.lean
```

Run `lake build Fw` there first if the library is not built yet. The only output should be the `#check` / `#eval`
results; the expected value is in a comment next to each line. `lake env` may print an info line about the
`plausible` package's remote URL; that is not an error.

## Re-check

```sh
node docs/plan/tools/check-lean-lessons.mjs --check   # exit 1 on drift
node docs/plan/tools/check-lean-lessons.mjs           # after editing lessons.json: re-embed it into the page
```

The check confirms that each `lean_excerpt` is still exactly the cited lines of `lean_file`, that each proof step still
appears in its excerpt, that all TeX parses with KaTeX 0.16.11 (when KaTeX is available; set `FW_KATEX` to its
`katex.min.js` otherwise), and that the page embeds the current `lessons.json`. If a Lean file changes, update the
lesson's lines and text, then re-run both study files.
