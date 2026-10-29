# ledger-merge flake: 'the same incident edited differently is a conflict with markers'

Status: no deterministic repro; narrowed hypothesis list, no code change (accepted limit).

## Failing assertion (CONFIRMED, GitHub run 40853077465, land suites-a, ubuntu)
`setup` (apps/runner/test/ledger-merge.test.ts:126-139) threw at its `ok(...)` helper: `git checkout -qb a` exited 128,
`fatal: a branch named 'a' already exists`. The test body never ran; the merge driver is not involved. The file ran
41 tests in 444 ms; the other three scratch-repo tests passed in the same run, and the retry land passed.

## Mechanism of the symptom (CONFIRMED by a scratch repro)
`checkout -qb a` fails with exactly that message only when refs/heads/a already exists. `setup` makes the repo fresh by
`rmSync(.git)` then `git init -q -b main`. If the old .git survives the rm, `init` re-initialises it (git prints
"re-init: ignored --initial-branch=main"), the old branch `a` from the previous test is still there, and the next
`checkout -qb a` exits 128 with the logged text. Reproduced by hand in a scratch dir: init, branch a, init again,
checkout -qb a gives exit 128 and the same message.

## Why .git could survive (INFERRED, not reproduced)
- All four scratch-repo tests share one mkdtemp dir and rely on the rm-and-reinit; any residue of the old .git breaks the next test.
- A late writer into .git while rmSync runs (git's detached `gc --auto` / `maintenance run --auto` after the previous
  test's commit or merge) can leave a non-empty directory behind on a loaded runner.
- Ruled out by reading the test: GIT_* env leaking (the env filter drops every GIT_ var), parallel tests (no
  concurrent/shuffle option; vitest config only sets timeouts and maxWorkers), a shared dir between files (mkdtemp is
  unique), user identity and default branch (passed with -c and -b), merge driver registration (set after the branches exist).
- Not reproduced: 12 local loops of the scratch-repo describe all passed (4/4 each).

## Candidate fix, not applied (needs a repro first)
Give each `setup` its own mkdtemp dir and pass `-c gc.auto=0 -c maintenance.auto=false`, so no path or background
writer is reused. Follow-up: a stress repro that runs a detached writer against `rmSync(.git)` on a Linux runner (CI lane).
