// Premise test and assertions of the WKTR fixture lane. Decisions are Lean's (Fw.Measure.WktrLayout: Expect.ok, classesEqual);
// this file reads the results, asks fwcore for the classes, applies the Lean rules (checked against the golden vectors in
// test/premise.test.mjs) and prints tables.
//   node premise.mjs <job dir>... [--golden f] [--out dir] [--kMax 4] [--tMax 24]
// Each job dir holds <tag>/<fixture>-f<frames>/counts-<variant>-<pass>.json, tag `auto` (production layout) or `k<w>` (premise
// test, w processes at once). Per tag, arm and variant the passes of every job are pooled and classed. Exit 1 when an
// assertion fails in the serial tag k1 or in `auto`; failures in k2/k3 are the answer of the premise test, not errors.
import { existsSync, readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const GOLDEN = join(HERE, '..', '..', 'contracts', 'golden', 'measure', 'wktr.fixtures.jsonl');
const KIND = { deterministic: 'deterministic', stable: 'stable', quarantined: 'quarantined' };

/** Fw.Measure.WktrLayout.Expect.ok: the class kind matches and every pass is in the band lo..hi (thousandths of a rate). */
export function expectOk(e, observedClass, sums) {
  return observedClass === e.class && sums.every(([a, u]) => e.lo * u <= 1000 * a && 1000 * a <= e.hi * u);
}

/** Fw.Measure.WktrLayout.classesEqual: same count types and the same class kind for each (k and t are observed maxima). */
export function classesEqual(a, b) {
  const kinds = (t) => Object.fromEntries(Object.entries(t).map(([n, c]) => [n, c.class]));
  const ka = kinds(a), kb = kinds(b);
  return Object.keys(ka).every((n) => kb[n] === ka[n]) && Object.keys(kb).every((n) => ka[n] === kb[n]);
}

/** The types whose class kind differs (or exists on one side only). */
export function classDiff(a, b) {
  return [...new Set([...Object.keys(a), ...Object.keys(b)])].filter((n) => a[n]?.class !== b[n]?.class).sort();
}

const sum = (xs) => xs.reduce((x, y) => x + y, 0);
/** Per-pass total of one count type of a counts file (schema fw.wktr.scroll/1). */
export const totalOf = (run, type) => sum(run.frames.map((f) => f.counts[type] ?? 0));

/** Collect {tag -> {arm -> {variant -> [counts file path...]}}} over the job dirs. */
export function collect(jobDirs) {
  const out = {};
  for (const jd of jobDirs) {
    for (const tag of existsSync(jd) ? readdirSync(jd).sort() : []) {
      if (!/^(auto|k\d+)$/.test(tag)) continue;
      for (const arm of readdirSync(join(jd, tag)).sort()) {
        if (!/-f\d+$/.test(arm)) continue;
        for (const f of readdirSync(join(jd, tag, arm)).sort()) {
          const m = /^counts-(.+)-(\d+)\.json$/.exec(f);
          if (!m) continue;
          (((out[tag] ??= {})[arm] ??= {})[m[1]] ??= []).push(join(jd, tag, arm, f));
        }
      }
    }
  }
  return out;
}

const mean = (xs) => (xs.length ? Math.round(sum(xs) / xs.length) : 0);
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));

/** Wall-time spans of the layouts and passes: per job and tag the layout total; per tag the mean of each pass span. */
export function spanTable(jobDirs) {
  const rows = [];
  for (const jd of jobDirs) {
    for (const tag of existsSync(jd) ? readdirSync(jd).sort() : []) {
      if (!/^(auto|k\d+)$/.test(tag)) continue;
      const lay = join(jd, tag, 'spans-layout.json');
      const passSpans = {}, armSpans = {};
      for (const arm of readdirSync(join(jd, tag)).sort()) {
        if (!/-f\d+$/.test(arm)) continue;
        for (const f of readdirSync(join(jd, tag, arm))) {
          if (/^spans-arm-.+\.json$/.test(f)) { for (const [k, v] of Object.entries(readJson(join(jd, tag, arm, f)).spans)) (armSpans[k] ??= []).push(v); }
          else if (/^spans-.+-\d+\.json$/.test(f)) { for (const [k, v] of Object.entries(readJson(join(jd, tag, arm, f)).spans)) (passSpans[k] ??= []).push(v); }
        }
      }
      const lj = existsSync(lay) ? readJson(lay) : null;
      rows.push({ job: jd.split('/').pop(), tag, layoutMs: lj?.totalMs ?? null, phases: lj?.phases ?? [],
        passMeanMs: Object.fromEntries(Object.entries(passSpans).map(([k, v]) => [k, mean(v)])), passN: Math.max(0, ...Object.values(passSpans).map((v) => v.length)),
        armMeanMs: Object.fromEntries(Object.entries(armSpans).map(([k, v]) => [k, mean(v)])), armN: Math.max(0, ...Object.values(armSpans).map((v) => v.length)) });
    }
  }
  return rows;
}

async function main() {
  const argv = process.argv.slice(2);
  const opt = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };
  const flagged = new Set(['--golden', '--out', '--kMax', '--tMax']);
  const dirs = argv.filter((a, i) => !a.startsWith('--') && !flagged.has(argv[i - 1]));
  const lines = readFileSync(opt('golden', GOLDEN), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const expects = lines.filter((l) => l.kind === 'expect');
  const kMax = Number(opt('kMax', 4)), tMax = Number(opt('tMax', 24));
  const { classify } = await import('../../measure-chromium/src/fwcore.mjs');

  const files = collect(dirs);
  const classes = {}; // tag -> arm -> variant -> {type: {class,k,t}}
  for (const [tag, arms] of Object.entries(files)) for (const [arm, vs] of Object.entries(arms)) for (const [variant, fs] of Object.entries(vs)) {
    if (fs.length < 2) continue;
    (((classes[tag] ??= {})[arm] ??= {})[variant]) = classify(fs.map((f) => ({ frames: readJson(f).frames })), kMax, tMax);
  }

  const assertions = [];
  for (const tag of Object.keys(files)) for (const e of expects) {
    const fs = files[tag]?.[e.arm]?.[e.variant];
    const cls = classes[tag]?.[e.arm]?.[e.variant]?.[e.type];
    if (!fs || !cls) { assertions.push({ tag, arm: e.arm, variant: e.variant, type: e.type, expect: e.class, observed: null, ok: false, note: 'no data' }); continue; }
    const sums = fs.map((f) => { const r = readJson(f); return [totalOf(r, e.type), totalOf(r, 'renderingUpdates')]; });
    assertions.push({ tag, arm: e.arm, variant: e.variant, type: e.type, expect: e.class, band: [e.lo, e.hi], observed: KIND[cls.class], passes: fs.length, sums, ok: expectOk(e, KIND[cls.class], sums) });
  }

  // layouts that could not run (lanes.mjs records `failed`): the premise does not hold for that width
  const failedTags = new Set();
  for (const jd of dirs) for (const tag of existsSync(jd) ? readdirSync(jd) : []) {
    const f = join(jd, tag, 'spans-layout.json');
    if (/^k\d+$/.test(tag) && existsSync(f) && readJson(f).failed) failedTags.add(tag);
  }
  const premise = [];
  const serial = classes.k1;
  for (const tag of [...new Set([...Object.keys(classes), ...failedTags])].sort().filter((t) => /^k\d+$/.test(t) && t !== 'k1')) for (const variant of ['live', 'live-trace']) {
    if (failedTags.has(tag)) { premise.push({ variant, k: Number(tag.slice(1)), held: false, arms: [], failed: true }); continue; }
    const arms = Object.keys(classes[tag] ?? {}).filter((a) => classes[tag][a][variant] && serial?.[a]?.[variant]);
    const per = arms.map((a) => ({ arm: a, equal: classesEqual(serial[a][variant], classes[tag][a][variant]), diff: classDiff(serial[a][variant], classes[tag][a][variant]) }));
    premise.push({ variant, k: Number(tag.slice(1)), held: Boolean(serial) && per.length > 0 && per.length === Object.values(serial).filter((vs) => vs[variant]).length && per.every((p) => p.equal), arms: per });
  }

  const spans = spanTable(dirs);
  const result = { assertions, premise, spans, classes };
  const outDir = opt('out', null);
  if (outDir) { mkdirSync(outDir, { recursive: true }); writeFileSync(join(outDir, 'premise.json'), JSON.stringify(result)); }

  const bad = assertions.filter((a) => !a.ok && (a.tag === 'k1' || a.tag === 'auto'));
  console.log('### assertions (Fw.Measure.WktrLayout.expects)\n');
  console.log('| tag | arm | variant | type | expected | observed | ok |\n|---|---|---|---|---|---|---|');
  for (const a of assertions) console.log(`| ${a.tag} | ${a.arm} | ${a.variant} | ${a.type} | ${a.expect} ${a.band ? a.band.join('..') : ''} | ${a.observed} | ${a.ok} |`);
  console.log('\n### premise (class kinds at k processes equal serial)\n');
  console.log('| variant | k | held | arms not equal (types) |\n|---|---|---|---|');
  for (const p of premise) console.log(`| ${p.variant} | ${p.k} | ${p.held} | ${p.failed ? 'layout did not run' : p.arms.filter((x) => !x.equal).map((x) => `${x.arm}: ${x.diff.join(',')}`).join('; ') || '-'} |`);
  console.log('\n### spans (ms, CI VM wall time)\n');
  console.log('| job | tag | layout | pass mean (n) | arm mean (n) |\n|---|---|---|---|---|');
  for (const r of spans) console.log(`| ${r.job} | ${r.tag} | ${r.layoutMs} | ${JSON.stringify(r.passMeanMs)} (${r.passN}) | ${JSON.stringify(r.armMeanMs)} (${r.armN}) |`);
  if (bad.length) { console.error(`premise.mjs: ${bad.length} assertion(s) failed in k1/auto`); process.exit(1); }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((e) => { console.error(String(e?.stack || e)); process.exit(1); });
