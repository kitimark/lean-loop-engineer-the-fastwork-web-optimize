// Pure data shaping: no browser, no file system. Values from the page become dataset rows; rows of several runs become
// the stable dataset plus a list of unstable cells. Decisions here are only "are these two values the same string".
import { createHash } from 'node:crypto';

export const SCHEMA = 'fw.snapshot-extract.reference/1';

const sha8 = (s) => createHash('sha256').update(s).digest('hex').slice(0, 8);

/**
 * A committed value carries numbers and keywords only: an asset reference keeps its file name (a data: URI keeps a short
 * hash), and anything longer than 300 characters keeps its length and a hash. Same input, same output.
 */
export function cleanValue(v) {
  let s = String(v);
  s = s.replace(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/g, (_m, a, b, c) => {
    const u = a ?? b ?? c ?? '';
    if (u.startsWith('data:')) return `url(data:#${sha8(u)})`;
    const path = u.split(/[?#]/)[0];
    return `url(${path.slice(path.lastIndexOf('/') + 1)})`;
  });
  if (s.length > 300) s = `long:${s.length}#${sha8(s)}`;
  return s;
}

/** The source as committed: keywords and file names, no selector text. */
export function cleanSource(s) {
  const { sel: _sel, ...rest } = s;
  return rest;
}

/**
 * Group per-environment values: `values[i]` is the value in environment i (undefined = the element was absent).
 * Returns [{x, e}] in order of first appearance, e = 'all' when one value covers every environment, else the sorted list
 * of environment indices. x is null for absent.
 */
export function groupValues(values) {
  const groups = new Map();
  values.forEach((v, i) => {
    const x = v === undefined ? null : v;
    const key = JSON.stringify(x);
    if (!groups.has(key)) groups.set(key, { x, e: [] });
    groups.get(key).e.push(i);
  });
  const list = Array.from(groups.values());
  if (list.length === 1) return [{ x: list[0].x, e: 'all' }];
  return list;
}

/** Expand [{x, e}] back to one value per environment (inverse of groupValues). */
export function expandGroups(groups, n) {
  const out = new Array(n);
  for (const g of groups) {
    if (g.e === 'all') out.fill(g.x);
    else for (const i of g.e) out[i] = g.x;
  }
  return out;
}

/**
 * Build the rows of one arm from its per-environment collections.
 * perEnv[i] = result of collectReference at environment i. `order` = [{part, role}] fixes the row order.
 * Returns { rows, props } where rows are 'role' rows and 'cell' rows, and props maps 'part/role' to its sorted property names.
 * `withSelector` keeps the selector text in the sources (the full artifact only).
 */
export function buildRows(perEnv, order, { withSelector = false } = {}) {
  const rows = [];
  const props = {};
  for (const { part, role } of order) {
    const at = perEnv.map((env) => env.find((r) => r.part === part && r.role === role));
    rows.push({ t: 'role', part, role, n: groupValues(at.map((r) => (r ? r.count : undefined))) });
    const names = new Set();
    for (const r of at) if (r) for (const n of Object.keys(r.cells)) names.add(n);
    const sorted = Array.from(names).sort();
    props[`${part}/${role}`] = sorted;
    for (const prop of sorted) {
      const v = at.map((r) => (r && r.cells[prop] ? cleanValue(r.cells[prop].v) : undefined));
      const s = at.map((r) => (r && r.cells[prop] ? JSON.stringify(withSelector ? r.cells[prop].s : cleanSource(r.cells[prop].s)) : undefined));
      rows.push({ t: 'cell', part, role, prop, v: groupValues(v), s: groupValues(s).map((g) => ({ x: g.x === null ? null : JSON.parse(g.x), e: g.e })) });
    }
  }
  return { rows, props };
}

export const rowKey = (r) => (r.t === 'role' ? `role|${r.part}|${r.role}` : `cell|${r.part}|${r.role}|${r.prop}`);

/**
 * Keep the rows that are byte-identical in every run; the others are unstable. Runs must agree on the set of row keys
 * for a row to count as stable (a row present in some runs only is unstable). Returns { stable, unstable } where unstable
 * lists { key, variants } (the number of distinct renderings).
 */
export function stableRows(runs) {
  const keys = new Set();
  const maps = runs.map((rows) => new Map(rows.map((r) => [rowKey(r), JSON.stringify(r)])));
  for (const m of maps) for (const k of m.keys()) keys.add(k);
  const stable = [];
  const unstable = [];
  const first = runs[0] ? new Map(runs[0].map((r) => [rowKey(r), r])) : new Map();
  for (const k of Array.from(keys).sort()) {
    const renders = maps.map((m) => m.get(k));
    const distinct = new Set(renders.map((x) => (x === undefined ? '<absent>' : x)));
    if (distinct.size === 1 && renders[0] !== undefined) stable.push(first.get(k));
    else unstable.push({ key: k, variants: distinct.size });
  }
  return { stable, unstable };
}

/** Restore the row order of the first run for the stable rows. */
export function inOrder(stable, reference) {
  const pos = new Map(reference.map((r, i) => [rowKey(r), i]));
  return [...stable].sort((a, b) => (pos.get(rowKey(a)) ?? 1e9) - (pos.get(rowKey(b)) ?? 1e9));
}

export const toJsonl = (rows) => rows.map((r) => JSON.stringify(r)).join('\n') + '\n';
export const fromJsonl = (text) => text.split('\n').filter((l) => l.trim() !== '').map((l) => JSON.parse(l));
