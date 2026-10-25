import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PKG } from './serve.mjs';

export const FLAG_DELTA_GOLDEN = resolve(PKG, '../contracts/golden/gate/flag-delta.jsonl');
let cached = null;

export function loadDeltas(path = FLAG_DELTA_GOLDEN) {
  if (path === FLAG_DELTA_GOLDEN && cached) return cached;
  const ds = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.kind === 'delta');
  if (ds.length === 0) throw new Error(`no flag-delta allowlist in ${path}`);
  if (path === FLAG_DELTA_GOLDEN) cached = ds;
  return ds;
}

const FLAG_CHAR = /^[A-Za-z0-9._-]*$/;
const flagOk = (f) => { const p = f.split(':'); return p.length === 2 && p[0] !== '' && p[1] !== '' && FLAG_CHAR.test(p[0] + p[1]); };

export function flagsOfSearch(s) {
  const body = s.startsWith('?') ? s.slice(1) : s;
  if (body === '') return [];
  const acc = [];
  for (const seg of body.split('&')) {
    const [name, ...rest] = seg.split('=');
    if (name.includes('%')) return null;
    if (name !== 'fw') continue;
    if (rest.length !== 1) return null;
    const fs = rest[0].split(',').filter((x) => x !== '');
    if (!fs.every(flagOk)) return null;
    acc.push(...fs);
  }
  return [...new Set(acc)];
}

const matches = (d, flags, part, it) => flags.includes(d.flag) && d.part === part && it.cls === 'style' && !it.byRect &&
  it.status === 'differ' && d.role === it.role && d.property === it.key && it.a === d.orig && it.b === d.rewrite;

export const excuseItem = (flags, part, it, ds = loadDeltas()) => ds.find((d) => matches(d, flags, part, it)) ?? null;

const allExcused = (flags, part, fails, ds) => fails.length > 0 && fails.every((it) => excuseItem(flags, part, it, ds) !== null);

export const readingVerdict = (flags, part, v, fails, ds = loadDeltas()) => (v === 'fail' && allExcused(flags, part, fails, ds) ? 'pass' : v);

export const excusedItems = (flags, part, v, fails, ds = loadDeltas()) =>
  (v === 'fail' && allExcused(flags, part, fails, ds) ? fails.map((it) => [it, excuseItem(flags, part, it, ds)]) : []);

export const wireItem = (it) => ({
  cls: it.cls, role: it.role, key: it.key, status: it.status, byRect: it.byRect === true,
  a: typeof it.a === 'string' ? it.a : null, b: typeof it.b === 'string' ? it.b : null,
});
