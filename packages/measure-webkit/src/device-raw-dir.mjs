import { execFileSync } from 'node:child_process';
import { dirname, isAbsolute, resolve } from 'node:path';

export function mainCheckout(cwd = process.cwd()) {
  try {
    const common = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return common ? dirname(common) : cwd;
  } catch { return cwd; }
}

export const isLocalRelative = (p) => typeof p === 'string' && !isAbsolute(p) && /^(\.\/)*\.local(\/|$)/.test(p);

export function rawResolveIn(main, ...segs) {
  const first = segs[0];
  return isLocalRelative(first) ? resolve(main, ...segs) : resolve(...segs);
}

let mainOnce = null;
export function rawResolve(...segs) {
  if (isLocalRelative(segs[0])) mainOnce ??= mainCheckout();
  return rawResolveIn(mainOnce, ...segs);
}
