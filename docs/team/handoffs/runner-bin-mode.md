# runner-bin-mode handoff

State: apps/runner/package.json no longer has a "bin" entry; apps/runner/src/fw.ts is 100644 on main and stays so.
Test: apps/runner/test/bin-mode.test.ts (git ls-files -s of every package.json bin target plus fw.ts equals 100644).

Cause (INFERRED from pnpm's bin linker, which chmods bin targets to 755 on install; not re-run here):
- package.json declared "bin": {"fw": "./src/fw.ts"}; `pnpm install` in a fresh worktree (wt-prep.sh) linked it and set +x.
- core.fileMode is true, so `git add -A` / `commit -a` recorded 100644 -> 100755 in that branch; branches disagree.
- Evidence: git log --summary -- apps/runner/src/fw.ts shows 10+ alternating mode changes; main is 100644.
- Nothing uses the bin: the root script is `node apps/runner/src/fw.ts`; no reference to node_modules/.bin/fw.

Decision: 100644, bin dropped (the shebang line is harmless). If a bin is ever wanted, set CANONICAL to 100755 in the test and commit +x once.
Open: existing branches carrying 100755 are fixed at their next merge with main (accepted limit).
