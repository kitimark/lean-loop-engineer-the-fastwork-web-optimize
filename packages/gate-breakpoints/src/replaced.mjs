import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PKG } from './serve.mjs';
import { FLAG_DELTA_GOLDEN, loadDeltas, excuseItem } from './flag-delta.mjs';

export const REPLACED_GOLDEN = resolve(PKG, '../contracts/golden/gate/replaced.jsonl');
let cached = null;

export function loadReplaced(path = FLAG_DELTA_GOLDEN) {
  if (path === FLAG_DELTA_GOLDEN && cached) return cached;
  const es = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.kind === 'replaced');
  if (path === FLAG_DELTA_GOLDEN) cached = es;
  return es;
}

export const absent = (it) => it.cls === 'count' && it.key === 'count' && !it.byRect && it.status === 'differ' && it.rewriteCount === 0;

const hits = (e, flags, part, it) => flags.includes(e.flag) && e.part === part && absent(it);

export function excuse(flags, part, it, es = loadReplaced(), ds = loadDeltas()) {
  const d = excuseItem(flags, part, it, ds);
  if (d !== null) return { by: 'delta', id: d.id, entry: d };
  const e = es.find((x) => hits(x, flags, part, it));
  return e ? { by: 'replaced', id: e.id, entry: e } : null;
}

const allExcused = (flags, part, fails, es, ds) => fails.length > 0 && fails.every((it) => excuse(flags, part, it, es, ds) !== null);

export const readingVerdict = (flags, part, v, fails, es = loadReplaced(), ds = loadDeltas()) =>
  (v === 'fail' && allExcused(flags, part, fails, es, ds) ? 'pass' : v);

export const excusedItems = (flags, part, v, fails, es = loadReplaced(), ds = loadDeltas()) =>
  (v === 'fail' && allExcused(flags, part, fails, es, ds) ? fails.map((it) => [it, excuse(flags, part, it, es, ds)]) : []);
