branch: worktree-wf_e059e36c-9b9-1
worktree: .claude/worktrees/wf_e059e36c-9b9-1
last commit: see git log (top: "polish: reword docstring (grep gate)")
CI runs: none (accepted limit: no CI run)

# polish-plan-path-redaction

Done
- Lean `Fw.Plan.Polish.wtName dir`: the name of an absolute `/.../.claude/worktrees/<name>`, none for a relative, `~` or
  placeholder path, `.`/`..`/empty or a name outside [A-Za-z0-9_.-]. Theorems `wtName_relative`, `wtName_safe`,
  `wtName_not_dots` (+ example for the `~` path from the 2026-10-24 incident). `sh lean/scripts/check.sh` green.
- TS STAND-IN `wtName` (apps/runner/src/polish.ts, same rule, table test in polish.test.ts). Not Lean-golden-checked: wiring
  an op `plan.wtName` needs lean/Fw/Wire/Plan.lean and packages/contracts/golden/plan/polish.jsonl, outside this task's writes
  (followUp).
- `fw polish plan` prints `worktree-name <name>` (or `-`) right after `worktree <abs dir>`; the name is one word of safe characters.
- (a) polish-protected-from-settings handoff reworded and subagent-worktree line added; (b) polish.test.ts sample2 checks
  `<dir>/z.md` for every Edit rule, so a narrower protectedDirs entry fails.
- Verified: `pnpm --filter @fw/runner test` 3243 passed; lean check green.

Open: the .claude/ edit below (lead applies, user present); op `plan.wtName` wiring (followUp).

## Exact build-review.js change (.claude/workflows/build-review.js, Polish stage)
Idea: the workflow never needs the absolute dir. It keeps the identity (name) and uses the repo-relative
`.claude/worktrees/<name>` under the main checkout, which the home prefix cannot damage.

OLD (3 lines, ~122-124):
```
const wtLine = outLines.find((l) => l.startsWith('worktree '))
const wt = wtLine ? wtLine.slice(9).trim() : ''
if (!/^\/.+\/\.claude\/worktrees\/[^/]+$/.test(wt)) return [{ task: t.id, build: b, gate: ready, adv, polish: { stages: 'error', plan: `polish-plan printed no worktree path (got "${wt}")` } }]
```
NEW:
```
const nameLine = outLines.find((l) => l.startsWith('worktree-name '))
const wtn = nameLine ? nameLine.slice(14).trim() : ''
if (!/^[A-Za-z0-9_.-]+$/.test(wtn) || wtn === '.' || wtn === '..' || (b.branch.startsWith('worktree-') && b.branch !== `worktree-${wtn}`)) return [{ task: t.id, build: b, gate: ready, adv, polish: { stages: 'error', plan: `polish-plan printed no worktree name (got "${wtn}")` } }]
const wt = `.claude/worktrees/${wtn}`
```
Then in the comment-sicko prompt replace `in the worktree ${wt}.` by
`in the worktree ${wt} (relative to the main checkout: the parent of the path git rev-parse --path-format=absolute --git-common-dir prints; resolve it there, never type or shorten a home path).`
and `Never edit a file outside ${wt}` stays. Replace the strays test
`sicko.edited.filter((p) => !p.startsWith(`${wt}/`))` by
`sicko.edited.filter((p) => !p.includes(`/${wt}/`) && !p.startsWith(`${wt}/`))`.
Prose: in the slop-checker prompt, after `${prose.join('\n')}`, add ` (relative to the main checkout: the parent of the path git rev-parse --path-format=absolute --git-common-dir prints; resolve it there, never type or shorten a home path)`. In the polish-cuts run1 call, replace `JSON.stringify({ cuts: slop.cuts })` by
`JSON.stringify({ cuts: slop.cuts.map((c) => ({ ...c, path: relOf(c.path) || c.path })) })`, since fw polish cuts rebases only absolute paths (polish.ts relative(dir, p)) and a `.claude/worktrees/<n>/docs/x.md` path would match no prose file.
When applying, also reword the run1 sentence "every path exactly as printed (absolute, never shortened ...)" and the comment "every path is rebuilt here from the worktree line".
Optional test in scripts/build-review.test.mjs: the workflow text contains `worktree-name ` and no `\.claude\/worktrees\/\[\^\/\]\+\$` regex.
Delete the stale comment line "plan lines: `worktree <absolute dir>`" mention only if wanted; fw still prints that line.
Read first: lean/Fw/Plan/Polish.lean wtName, apps/runner/src/polish.ts plan branch.
