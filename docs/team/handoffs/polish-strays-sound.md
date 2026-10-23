branch: worktree-wf_ac9a61ca-a32-1
worktree: .claude/worktrees/wf_ac9a61ca-a32-1
last commit: see git log (top: "polish-strays-sound")
CI runs: none (accepted limit: no CI run)

# polish-strays-sound

Done
- (1) lean/Fw/Plan/Polish.lean: `wtSegs`, `inWtAny`, `inWtAt` moved here from Wire/Plan.lean; `inWtB_iff`; `resolveSegs` (lexical, `..` pops);
  `inWtAt_sound` (all-plain p: its resolution is below the resolved `root/.claude/worktrees/name`); `escape_walks_out`;
  `ownEdit main name raw` (anchor relative raw at main, reject any non-plain segment, root-pin) with one theorem per branch
  (`ownEdit_badMain`, `_badName`, `_notPlain`, `_outside`, `_own_iff`), `ownEdit_dot`, `ownEdit_sound`.
  Op `plan.inWt {main,name,path}` -> `{verdict, own}`; 21 golden rows in packages/contracts/golden/plan/polish.jsonl (`inWt: ...`).
- (2) `other_checkout_passes_name_only` over any `main other` with `¬ main <+: other`, unused `_hmem`/`_huniq` (unique names);
  `nested_checkout_inside`: the premise cannot be weakened to `main ≠ other`.
- Verb `fw polish strays --branch <b> --task <id> --paths <file|->` (apps/runner/src/polish.ts `straysCli`): realpath I/O only; prints
  `stray <p>` per rejected path and `VERDICT polish-strays <id> clean|strays|error`; exit 0 only on clean.

(3) build-review.js, for the lead. Base directory: run1 runs in the main checkout, so a relative path in `sicko.edited` is
anchored at the main checkout root (parent of git-common-dir), the same base `ownEdit`'s `anchor` uses. Replace line 137
(`const strays = ...startsWith(`${wt}/`)...`) with these three lines (fail closed: any word but clean is a stray):

```js
const strayRun = sicko && sicko.edited && sicko.edited.length ? await run1('polish-strays', `pnpm -s fw polish strays --branch ${b.branch} --task ${t.id} --paths -`, JSON.stringify({ paths: sicko.edited })) : null
const strayWord = sicko && sicko.edited && sicko.edited.length ? verdictWord(strayRun, 'polish-strays') : 'clean'
const strays = strayWord === 'clean' ? [] : ((listed) => (listed.length && strayWord === 'strays' ? listed : [...listed, `fw polish strays: ${strayWord}`]))(((strayRun && strayRun.out) || '').split('\n').filter((l) => l.startsWith('stray ')).map((l) => l.slice(6)))
```

Open: the build-review.js edit (lead; .claude/). fw-main.ts usage line still lists `polish plan|cuts|commit|--staged` (outside writes).
Read first: lean/Fw/Plan/Polish.lean (ownEdit section), apps/runner/src/polish.ts `straysCli`.
