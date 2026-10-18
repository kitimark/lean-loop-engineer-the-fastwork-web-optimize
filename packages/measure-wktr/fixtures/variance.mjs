// Run-to-run variance of the WKTR fixture lane's class kinds (task wktr-serial-baseline). The decisions are Lean's
// (Fw.Measure.WktrVariance: differs, varying, findings, claim, pairDiffs, overlap, rangeOf); this file is the port, checked against
// packages/contracts/golden/measure/wktr.variance.jsonl by test/variance.test.mjs, plus the readers of the CI artifacts.
//   node variance.mjs --base <src> --runs <src>,<src>... [--cand <src>,<src>...] [--range name=1,2,3 --range name2=4,5] [--json]
// <src> is a class table of one workflow run: `<dir>/premise.json:<tag>` (artifact wktr-fix-classes of a run with premise.mjs,
// tag auto or k1) or `<dir>` holding classes-<arm>-<variant>.txt (the older artifact). A table maps arm/variant/type to a kind.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const keysOf = (a) => Object.keys(a);

/** Fw.Measure.WktrVariance.differs: the keys whose kind differs between two tables or that exist on one side only (sorted). */
export function differs(a, b) {
  return [...new Set([...keysOf(a), ...keysOf(b)])].filter((k) => a[k] !== b[k]).sort();
}

/** Fw.Measure.WktrVariance.varying: the keys whose kind is not the same in every run of the set (sorted). */
export function varying(rs) {
  const ks = new Set(rs.flatMap(keysOf));
  return [...ks].filter((k) => rs.some((r) => rs.some((s) => r[k] !== s[k]))).sort();
}

/** Fw.Measure.WktrVariance.findings: the diffs between base and cand outside the varying keys (sorted). */
export function findings(base, cand, rs) {
  const v = new Set(varying(rs));
  return differs(base, cand).filter((k) => !v.has(k));
}

/** Fw.Measure.WktrVariance.verdict (counts of baselines and findings). */
export const verdict = (n, fs) => (n < 2 ? 'noBaseline' : fs.length === 0 ? 'measured' : 'unexplained');

/** Fw.Measure.WktrVariance.claim. */
export const claim = (base, cand, rs) => verdict(rs.length, findings(base, cand, rs));

/** Fw.Measure.WktrVariance.typeOf: the count type of a key arm/variant/type. */
export const typeOf = (k) => k.split('/').pop();

/** Fw.Measure.WktrVariance.findingsBy typeOf: the diffs whose count type does not vary among the runs (sorted). */
export function findingsByType(base, cand, rs) {
  const v = new Set(varying(rs).map(typeOf));
  return differs(base, cand).filter((k) => !v.has(typeOf(k)));
}

/** Fw.Measure.WktrVariance.claimBy typeOf. */
export const claimByType = (base, cand, rs) => verdict(rs.length, findingsByType(base, cand, rs));

/** Fw.Measure.WktrVariance.pairDiffs: the diff count of every pair i < j. */
export function pairDiffs(rs) {
  const out = [];
  for (let i = 0; i < rs.length; i++) for (let j = i + 1; j < rs.length; j++) out.push(differs(rs[i], rs[j]).length);
  return out;
}

/** Fw.Measure.WktrVariance.overlap: closed intervals share a point. */
export const overlap = (a, b) => a[0] <= b[1] && b[0] <= a[1];

/** Fw.Measure.WktrVariance.rangeOf: (min, max) of a sample, null when empty. */
export const rangeOf = (xs) => (xs.length ? [Math.min(...xs), Math.max(...xs)] : null);

const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));

/** Table of premise.json (premise.mjs --out): classes[tag][arm][variant][type].class. */
export function tableOfPremise(p, tag) {
  const out = {};
  const cl = readJson(p).classes?.[tag];
  if (!cl) throw new Error(`${p}: no tag ${tag}`);
  for (const [arm, vs] of Object.entries(cl)) for (const [variant, ts] of Object.entries(vs)) for (const [type, c] of Object.entries(ts)) out[`${arm}/${variant}/${type}`] = c.class;
  return out;
}

/** Table of a directory of classes-<arm>-<variant>.txt files (fwcore classify output: `type class k t`). */
export function tableOfClassesDir(d) {
  const out = {};
  for (const f of readdirSync(d).sort()) {
    const m = /^classes-(.+-f\d+)-(live-trace|live)\.txt$/.exec(f);
    if (!m) continue;
    for (const line of readFileSync(join(d, f), 'utf8').split('\n').slice(1)) {
      const w = line.trim().split(/\s+/);
      if (w.length >= 2 && /^(deterministic|stable|quarantined)$/.test(w[1])) out[`${m[1]}/${m[2]}/${w[0]}`] = w[1];
    }
  }
  return out;
}

/** `<dir>/premise.json:<tag>` or `<dir>`. */
export function loadSource(src) {
  const m = /^(.*premise\.json):(.+)$/.exec(src);
  if (m) return tableOfPremise(m[1], m[2]);
  if (existsSync(src) && readdirSync(src).some((f) => f.startsWith('classes-'))) return tableOfClassesDir(src);
  throw new Error(`${src}: neither premise.json:<tag> nor a classes-*.txt directory`);
}

/** The label of a source: `run <id>` (and the tag) from the run.txt of its artifact directory, else the source itself. */
export function labelOf(src) {
  const m = /^(.*)\/premise\.json(?::(.+))?$/.exec(src);
  const dir = m ? m[1] : src;
  const f = join(dir, 'run.txt');
  const id = existsSync(f) ? /workflow run (\d+)/.exec(readFileSync(f, 'utf8'))?.[1] : null;
  return id ? `run ${id}${m?.[2] ? ` ${m[2]}` : ''}` : src;
}

const byType = (ks) => Object.entries(ks.reduce((o, k) => ({ ...o, [typeOf(k)]: (o[typeOf(k)] ?? 0) + 1 }), {})).sort().map(([t, n]) => `${t} ${n}`).join(', ') || '-';

function main(argv) {
  const opt = (n) => argv.flatMap((a, i) => (a === `--${n}` ? [argv[i + 1]] : []));
  const base = loadSource(opt('base')[0]);
  const runs = opt('runs').flatMap((s) => s.split(',')).map((s) => ({ name: labelOf(s), t: loadSource(s) }));
  const cands = opt('cand').flatMap((s) => s.split(',')).map((s) => ({ name: labelOf(s), t: loadSource(s) }));
  const rs = runs.map((r) => r.t);
  const v = varying(rs);
  const res = {
    keys: Object.keys(base).length, baselines: runs.map((r) => r.name), pairDiffs: pairDiffs(rs), varying: v,
    pairs: runs.flatMap((r, i) => runs.slice(i + 1).map((s) => ({ a: r.name, b: s.name, differs: differs(r.t, s.t) }))),
    cands: cands.map((c) => ({ name: c.name, differs: differs(base, c.t), findings: findings(base, c.t, rs), claim: claim(base, c.t, rs), findingsByType: findingsByType(base, c.t, rs), claimByType: claimByType(base, c.t, rs) })),
    ranges: opt('range').map((x) => { const [n, vs] = x.split('='); return { name: n, range: rangeOf(vs.split(',').map(Number)) }; }),
  };
  if (argv.includes('--json')) { console.log(JSON.stringify(res)); return; }
  console.log(`keys ${res.keys}; ${runs.length} baselines; diff count per pair: ${res.pairDiffs.join(', ') || '-'}`);
  console.log(`varying across the baselines (${v.length}): ${byType(v)}`);
  for (const p of res.pairs) console.log(`pair ${p.a} ~ ${p.b}: ${p.differs.length} (${byType(p.differs)})`);
  for (const c of res.cands) console.log(`cand ${c.name}: ${c.differs.length} diffs (${byType(c.differs)}); findings ${c.findings.length} [${c.findings.join(' ')}]; claim ${c.claim}; by type: findings ${c.findingsByType.length}, claim ${c.claimByType}`);
  for (const r of res.ranges) console.log(`range ${r.name}: ${r.range ? r.range.join('..') : '-'}`);
  for (let i = 0; i < res.ranges.length; i++) for (let j = i + 1; j < res.ranges.length; j++) {
    if (res.ranges[i].range && res.ranges[j].range) console.log(`overlap ${res.ranges[i].name} ~ ${res.ranges[j].name}: ${overlap(res.ranges[i].range, res.ranges[j].range)}`);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) { try { main(process.argv.slice(2)); } catch (e) { console.error(String(e?.stack || e)); process.exit(1); } }
