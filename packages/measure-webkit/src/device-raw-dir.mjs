// Raw lanes of a device run (per-frame timelines) live under .local/ of the MAIN checkout, never of a worktree: a
// landed worktree is removed by disk-gc, and with it every ignored file in it (inc-raw-in-worktree).
import { execFileSync } from 'node:child_process';
import { dirname, isAbsolute, resolve } from 'node:path';

/** The main checkout: the parent of `git rev-parse --path-format=absolute --git-common-dir`; `cwd` itself outside git. */
export function mainCheckout(cwd = process.cwd()) {
  try {
    const common = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return common ? dirname(common) : cwd;
  } catch { return cwd; }
}

/** True for a relative path whose first segment is `.local`. */
export const isLocalRelative = (p) => typeof p === 'string' && !isAbsolute(p) && /^(\.\/)*\.local(\/|$)/.test(p);

/** `resolve` with one rule: a relative path under `.local/` is taken from `main`, every other path from the cwd. */
export function rawResolveIn(main, ...segs) {
  const first = segs[0];
  return isLocalRelative(first) ? resolve(main, ...segs) : resolve(...segs);
}

let mainOnce = null;
/** `rawResolveIn` against the main checkout of the current process directory (looked up once). */
export function rawResolve(...segs) {
  if (isLocalRelative(segs[0])) mainOnce ??= mainCheckout();
  return rawResolveIn(mainOnce, ...segs);
}
