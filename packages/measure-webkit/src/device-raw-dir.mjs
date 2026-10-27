import { execFileSync } from 'node:child_process';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';

export function mainCheckout(cwd = process.cwd()) {
  try {
    const common = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return common ? dirname(common) : cwd;
  } catch { return cwd; }
}

export const isLocalRelative = (p) => typeof p === 'string' && !isAbsolute(p) && /^(\.\/)*\.local(\/|$)/.test(p);

export function worktreeTop(cwd = process.cwd()) {
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
  } catch { return null; }
}

export function rawResolveFrom(main, top, ...segs) {
  const p = resolve(...segs);
  if (top && top !== main) {
    const rel = relative(join(top, '.local'), p);
    if (!rel.startsWith('..') && !isAbsolute(rel)) return join(main, '.local', rel);
  }
  return isLocalRelative(segs[0]) ? resolve(main, ...segs) : p;
}

export const rawResolveIn = (main, ...segs) => rawResolveFrom(main, null, ...segs);

let mainOnce = null;
let topOnce;
export function rawResolve(...segs) {
  mainOnce ??= mainCheckout();
  if (topOnce === undefined) topOnce = worktreeTop();
  return rawResolveFrom(mainOnce, topOnce, ...segs);
}
