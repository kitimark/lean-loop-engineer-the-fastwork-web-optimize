// Comparison report: where our port differs from the reference, and which fonts are used without a loaded face.
// Pure functions over the two datasets (reference = the original, port = our prerendered page, both in the dataset
// format of reduce.mjs). TS/JS stand-in: Lean's Fw.Site.Reference states the same classification (inheritedFromBody,
// classify); no golden vectors cross-check this file yet.
import { expandGroups } from './reduce.mjs';

export const CATEGORIES = [
  'port-element-missing', // the role matches nothing in the port
  'inherited-never-set', // the original inherits the value from body/html (or another ancestor); the port never sets it
  'declared-in-ref-unset-in-port', // the original declares it on the element; the port declares and inherits nothing
  'port-sets-differently', // both set it, with different results
];

const GENERIC = new Set(['serif', 'sans-serif', 'monospace', 'cursive', 'fantasy', 'system-ui', 'ui-serif', 'ui-sans-serif', 'ui-monospace', 'ui-rounded', 'emoji', 'math', 'fangsong']);

const index = (rows) => {
  const cells = new Map();
  const roles = new Map();
  for (const r of rows) {
    if (r.t === 'cell') cells.set(`${r.part}|${r.role}|${r.prop}`, r);
    else if (r.t === 'role') roles.set(`${r.part}|${r.role}`, r);
  }
  return { cells, roles };
};

/**
 * One comparison. Returns { total, same, diffs: [{part, role, prop, category, envs, ref, port, refSrc, portSrc}] } where envs is
 * the number of environments (out of `n`) that differ and ref/port are the values at the first differing environment.
 * Cells whose reference value is '@animated' (a running animation) are skipped, and counted in `animated`.
 */
export function compare(refRows, portRows, n) {
  const ref = index(refRows);
  const port = index(portRows);
  const diffs = [];
  let same = 0, animated = 0;
  for (const [key, rc] of ref.cells) {
    const [part, role, prop] = key.split('|');
    const rv = expandGroups(rc.v, n);
    if (rv.every((x) => x === '@animated')) { animated++; continue; }
    const pc = port.cells.get(key);
    const pv = pc ? expandGroups(pc.v, n) : new Array(n).fill(null);
    const rs = expandGroups(rc.s, n);
    const ps = pc ? expandGroups(pc.s, n) : new Array(n).fill(null);
    const pn = port.roles.get(`${part}|${role}`);
    const pcount = pn ? expandGroups(pn.n, n) : new Array(n).fill(null);
    const bad = [];
    for (let i = 0; i < n; i++) if (rv[i] !== null && rv[i] !== '@animated' && rv[i] !== pv[i]) bad.push(i);
    if (bad.length === 0) { same++; continue; }
    const i0 = bad[0];
    const kinds = bad.map((i) => (ps[i] ? ps[i].k : 'absent'));
    let category;
    if (bad.every((i) => !pcount[i])) category = 'port-element-missing';
    else if (bad.some((i) => rs[i] && rs[i].k === 'inherited' && ['body', 'html'].includes(rs[i].from) && (!ps[i] || ps[i].k === 'initial'))) category = 'inherited-never-set';
    else if (kinds.every((k) => k === 'initial' || k === 'absent') && bad.some((i) => rs[i] && (rs[i].k === 'rule' || rs[i].k === 'inline' || rs[i].k === 'inherited'))) category = 'declared-in-ref-unset-in-port';
    else category = 'port-sets-differently';
    diffs.push({ part, role, prop, category, envs: bad.length, ref: rv[i0], port: pv[i0], refSrc: rs[i0], portSrc: ps[i0] });
  }
  return { total: ref.cells.size, same, animated, diffs };
}

/** Counts by category and by property (properties sorted by the number of differing cells, ties by name). */
export function summarize(cmp) {
  const byCategory = Object.fromEntries(CATEGORIES.map((c) => [c, 0]));
  const byProp = new Map();
  const byPropInherited = new Map();
  for (const d of cmp.diffs) {
    byCategory[d.category]++;
    byProp.set(d.prop, (byProp.get(d.prop) ?? 0) + 1);
    if (d.category === 'inherited-never-set') byPropInherited.set(d.prop, (byPropInherited.get(d.prop) ?? 0) + 1);
  }
  const rank = (m) => Array.from(m.entries()).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).map(([prop, cells]) => ({ prop, cells }));
  return { total: cmp.total, same: cmp.same, animated: cmp.animated, differing: cmp.diffs.length, byCategory, topProps: rank(byProp), topInheritedProps: rank(byPropInherited) };
}

/** Per property of html and body (the engine.scroll roles): the original's source and value, the port's source and value, at the environment `env`. */
export function rootTable(refRows, portRows, n, env) {
  const ref = index(refRows);
  const port = index(portRows);
  const out = [];
  for (const [key, rc] of ref.cells) {
    const [part, role, prop] = key.split('|');
    if (part !== 'engine.scroll') continue;
    const pc = port.cells.get(key);
    const rv = expandGroups(rc.v, n)[env];
    const pv = pc ? expandGroups(pc.v, n)[env] : null;
    const rs = expandGroups(rc.s, n)[env];
    const ps = pc ? expandGroups(pc.s, n)[env] : null;
    if (rs && rs.k !== 'initial' && rv !== pv) out.push({ element: role === 'scroller' ? 'html' : 'body', prop, ref: rv, refSrc: rs.k, port: pv, portSrc: ps ? ps.k : 'absent' });
  }
  return out.sort((a, b) => (a.element + a.prop < b.element + b.prop ? -1 : 1));
}

const unq = (s) => s.trim().replace(/^["']|["']$/g, '');
export const familiesOf = (stack) => stack.split(',').map(unq).filter((x) => x !== '');

/**
 * Fonts in use per arm. For every family of every used stack: is it generic, is a FontFace of that family declared in the
 * page, is one loaded. `ships(family)` says whether the snapshot ships a font file for that family (its @font-face rule
 * exists and every file it names is in the snapshot).
 */
export function fontReport(fonts, ships) {
  const arm = (a) => {
    const faceByFamily = new Map();
    for (const f of a.faces) {
      const e = faceByFamily.get(f.family) ?? { declared: 0, loaded: 0 };
      e.declared++; if (f.status === 'loaded') e.loaded++;
      faceByFamily.set(f.family, e);
    }
    const families = new Map();
    for (const u of a.used) {
      familiesOf(u.family).forEach((fam, pos) => {
        const e = families.get(fam) ?? { family: fam, generic: GENERIC.has(fam.toLowerCase()), firstIn: 0, elements: 0 };
        if (pos === 0) { e.firstIn++; e.elements += u.elements; }
        families.set(fam, e);
      });
    }
    return Array.from(families.values()).sort((x, y) => (x.family < y.family ? -1 : 1)).map((e) => {
      const f = faceByFamily.get(e.family) ?? { declared: 0, loaded: 0 };
      return { ...e, faceDeclared: f.declared, faceLoaded: f.loaded, withoutLoadedFace: !e.generic && f.loaded === 0, snapshotShips: e.generic ? null : ships(e.family) };
    });
  };
  return { orig: arm(fonts.orig), port: arm(fonts.port) };
}

/** Markdown of one engine's report. */
export function renderMarkdown(engine, summary, root, fontRep) {
  const L = [];
  L.push(`## ${engine}`, '');
  L.push(`Reference cells ${summary.total}: same in the port ${summary.same}, differing ${summary.differing}, animated (skipped) ${summary.animated}.`, '');
  L.push('| category | cells |', '|---|---|');
  for (const c of CATEGORIES) L.push(`| ${c} | ${summary.byCategory[c]} |`);
  L.push('', 'Top differing properties (cells over all parts and roles):', '', '| property | cells |', '|---|---|');
  for (const p of summary.topProps.slice(0, 10)) L.push(`| ${p.prop} | ${p.cells} |`);
  L.push('', 'Top properties the original inherits from body/html and the port never sets:', '', '| property | cells |', '|---|---|');
  for (const p of summary.topInheritedProps.slice(0, 10)) L.push(`| ${p.prop} | ${p.cells} |`);
  L.push('', 'html and body at the reference environment (properties the original sets or inherits, where the port differs):', '', '| element | property | original (source) | port (source) |', '|---|---|---|---|');
  for (const r of root.slice(0, 40)) L.push(`| ${r.element} | ${r.prop} | ${r.ref} (${r.refSrc}) | ${r.port} (${r.portSrc}) |`);
  for (const arm of ['orig', 'port']) {
    L.push('', `Font families used by ${arm === 'orig' ? 'the original' : 'the port'} (text elements):`, '', '| family | generic | face declared | face loaded | first in stacks | snapshot ships |', '|---|---|---|---|---|---|');
    for (const f of fontRep[arm]) L.push(`| ${f.family} | ${f.generic} | ${f.faceDeclared} | ${f.faceLoaded} | ${f.firstIn} | ${f.snapshotShips === null ? '-' : f.snapshotShips} |`);
  }
  const missing = fontRep.port.filter((f) => f.withoutLoadedFace);
  L.push('', `Port families without a loaded face: ${missing.length === 0 ? 'none' : missing.map((f) => `${f.family} (snapshot ships: ${f.snapshotShips})`).join(', ')}.`);
  const missingOrig = fontRep.orig.filter((f) => f.withoutLoadedFace);
  L.push(`Original families without a loaded face: ${missingOrig.length === 0 ? 'none' : missingOrig.map((f) => f.family).join(', ')}.`, '');
  return L.join('\n');
}
// probe ci-own-trigger r2 (b2): a requested run of this lane; the next push reverts this line without asking for it
