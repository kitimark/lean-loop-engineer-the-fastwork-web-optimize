// Wave-2 analysis glue: part-page and whole-page counts runs read under an EXPLICIT plan (results/integrate-wave-2/plan.json).
// Every verdict is fwcore's (`fw engine-check`, Lean Fw.Measure.EngineCheck); this file stages files, copies numbers and
// labels confounds. TS stand-ins (no Lean twin yet): `totalsOf`, `median`, `deltaRow`, `confounds`, `stageAs`.
//
//   node wave2.mjs check --plan plan.json --dl <dir of gh-downloaded runs> --out <dir>   engine-check per page of the plan
//   node wave2.mjs zonecmp --dir results/integrate-wave-2/zones --profile p --out <dir>    v2-proved zone baseline against the base one
//   node wave2.mjs f6 --plan plan.json --dl <dir> --out <dir>                              F6 pilot: combined delta against the sum of part deltas
//   node wave2.mjs delta --plan plan.json --dl <dir> --out <dir>                          raw per-type sums, base vs arm, per page
//
// The plan names, per page, the base run and the arm run (a run id) and the row variants the arm run answers. A part page
// has a search (`?only=...&stage=...`) that Lean's `Fw.Engine.Keys.answers` does not map to a row variant, so the mapping is
// declared here, per run, instead of inferred from the search string.
import { mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const ROOT = resolve(HERE, '..', '..', '..');

/** Sum of a type over the frames plus its run-level count (the whole-run total). @param {any} counts */
export function totalsOf(counts) {
  const t = {};
  for (const f of counts.frames ?? []) for (const [k, v] of Object.entries(f.counts ?? {})) t[k] = (t[k] ?? 0) + v;
  for (const [k, v] of Object.entries(counts.runLevel ?? {})) t[k] = (t[k] ?? 0) + v;
  return t;
}

/** Observed value at sorted index floor((n-1)/2) (the Lean baseline convention). @param {number[]} xs */
export function median(xs) {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor((s.length - 1) / 2)];
}

/**
 * One count type of a page, base runs against arm runs. `where` is descriptive, not a verdict: `below`/`above` when every arm run is
 * outside [min, max] of the base runs on that side, `within` otherwise.
 * @param {number[]} base @param {number[]} arm
 */
export function deltaRow(base, arm) {
  const lo = Math.min(...base), hi = Math.max(...base);
  const where = arm.every((x) => x < lo) ? 'below' : arm.every((x) => x > hi) ? 'above' : 'within';
  const b = median(base), a = median(arm);
  return { base: b, arm: a, delta: a - b, baseRuns: base, armRuns: arm, baseLo: lo, baseHi: hi, where };
}

/** Per-type deltas of two lists of counts files. @param {any[]} baseFiles @param {any[]} armFiles */
export function pageDeltas(baseFiles, armFiles) {
  const bt = baseFiles.map(totalsOf), at = armFiles.map(totalsOf);
  const types = [...new Set([...bt, ...at].flatMap((o) => Object.keys(o)))].sort();
  const out = {};
  for (const t of types) out[t] = deltaRow(bt.map((o) => o[t] ?? 0), at.map((o) => o[t] ?? 0));
  return out;
}

/**
 * Stage the files of one page: base files answer `rewrite`, arm files answer each variant of `armVariants`. Each copy carries
 * meta.variant, so `variantKeys` (apps/runner/src/engine-check.ts) returns that one key and never the bare target.
 * @param {{path: string, counts: any}[]} baseFiles @param {{path: string, counts: any}[]} armFiles @param {string[]} armVariants
 */
export function stageAs(baseFiles, armFiles, armVariants) {
  const copy = (role, i, { path, counts }, v) => ({
    name: `${role}-${String(i).padStart(2, '0')}-${v.replace(/[^A-Za-z0-9.:@,_=+-]/g, '_')}`,
    source: path, variant: v, counts: { ...counts, meta: { ...counts.meta, variant: v } },
  });
  return [
    ...baseFiles.map((f, i) => copy('base', i, f, 'rewrite')),
    ...armFiles.flatMap((f, i) => armVariants.map((v) => copy('arm', i, f, v))),
  ];
}

/**
 * Other active variants whose rows touch the same count type with a prediction that is not `=o` (they can move the type in a run
 * where several flags are active). @param {{variant: string, countType: string, prediction: string}} row
 * @param {{variant: string, countType: string, prediction: string}[]} rows @param {string[]} active
 */
export function confounds(row, rows, active) {
  const names = rows.filter((r) => r.variant !== row.variant && active.includes(r.variant) && r.countType === row.countType && r.prediction !== '=o').map((r) => `${r.variant} ${r.prediction}`);
  return [...new Set(names)];
}

/**
 * Whole-run or per-zone cells of two zone baselines (fwcore `measure.zoneBaseline` output: type -> {perRun, class}), base arm against
 * changed arm. Descriptive: `where` is `deltaRow`'s band check. @param {Record<string, any>} r0 @param {Record<string, any>} rv
 */
export function bandCells(r0, rv) {
  const types = [...new Set([...Object.keys(r0), ...Object.keys(rv)])].sort();
  return types.map((type) => ({ type, class: (r0[type] ?? rv[type]).class, ...deltaRow(r0[type]?.perRun ?? rv[type].perRun.map(() => 0), rv[type]?.perRun ?? r0[type].perRun.map(() => 0)) }));
}

/**
 * F6 pilot: per count type, the combined run's delta against the sum of the part-page deltas. Margin: deterministic 0, stable its k,
 * quarantined none (not decidable). `strict` = |residual| <= margin, `widened` = |residual| <= margin * (parts + 1) (each run adds its own noise).
 * Only types where some delta is off its base band are listed. With `frames` ({combined, parts: number[]}, frames per run of each page)
 * every row also carries the per-frame rates, their sum and whether the rate residual is within 10 percent of the combined rate
 * (descriptive, a threshold of this pilot, not a class margin). @param {Record<string, any>} combined pageDeltas of the whole page
 * @param {{name: string, deltas: Record<string, any>}[]} parts @param {Record<string, {class: string, k: number}>} classes
 */
export function f6(combined, parts, classes, frames) {
  const types = [...new Set([combined, ...parts.map((p) => p.deltas)].flatMap((d) => Object.keys(d)))].sort();
  const rows = [];
  for (const type of types) {
    const involved = [combined[type], ...parts.map((p) => p.deltas[type])];
    if (involved.every((d) => !d || d.where === 'within')) continue;
    const cls = classes[type]?.class ?? 'unlisted';
    const margin = cls === 'deterministic' ? 0 : cls === 'stable' ? classes[type].k : null;
    const c = combined[type]?.delta ?? 0;
    const per = parts.map((p) => p.deltas[type]?.delta ?? 0);
    const sum = per.reduce((a, b) => a + b, 0);
    const residual = c - sum;
    const row = { type, class: cls, margin, combined: c, parts: per, sum, residual,
      strict: margin === null ? null : Math.abs(residual) <= margin,
      widened: margin === null ? null : Math.abs(residual) <= margin * (parts.length + 1) };
    if (frames) {
      const rate = c / frames.combined, rates = per.map((d, i) => d / frames.parts[i]);
      const rsum = rates.reduce((a, b) => a + b, 0);
      Object.assign(row, { rate, rates, rateSum: rsum, rateResidual: rate - rsum, rateWithin10pct: Math.abs(rate - rsum) <= 0.1 * Math.abs(rate) });
    }
    rows.push(row);
  }
  return rows;
}

function findCounts(dir) {
  const out = [];
  const walk = (d) => {
    for (const n of readdirSync(d).sort()) {
      const p = join(d, n);
      if (statSync(p).isDirectory()) walk(p);
      else if (n === 'counts.json') out.push(p);
    }
  };
  walk(dir);
  return out;
}

const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
const load = (dl, runId, target = 'rewrite') =>
  readdirSync(join(dl, String(runId))).filter((n) => n.startsWith(`chromium-counts-${target}-r`)).sort()
    .flatMap((n) => findCounts(join(dl, String(runId), n))).map((path) => ({ path, counts: readJson(path) }));

function zonecmp(a) {
  const rd = (arm, t) => readJson(join(a.dir, arm, a.profile, `${t}.baseline.json`));
  const [r0, rv, ctl] = [rd('base', 'rewrite'), rd('v2-proved', 'rewrite'), rd('control', 'original')];
  const totals = bandCells(r0.totals, rv.totals).map((c) => ({ ...c, control: ctl.totals[c.type]?.base ?? null }));
  const zones = r0.zones.map((z, i) => {
    const rz = rv.zones[i];
    if (rz.id !== z.id || rz.frames !== z.frames) throw new Error(`zone ${i}: ${z.id}/${z.frames} vs ${rz.id}/${rz.frames}`);
    return { id: z.id, frames: z.frames, cells: bandCells(z.types, rz.types).filter((c) => c.where !== 'within') };
  });
  mkdirSync(a.out, { recursive: true });
  writeFileSync(join(a.out, `${a.profile}.json`), JSON.stringify({ schema: 'fw.wave2.zonecmp/1', note: 'RV (v2-proved) against R0 (base): descriptive band check per whole-run type and off-band cells per zone; verdicts are fwcore faithful.verdict.', profile: a.profile, runs: { base: r0.source.runId, v2proved: rv.source.runId, control: ctl.source.runId }, totals, zones }, null, 1));
  const off = totals.filter((c) => c.where !== 'within');
  console.log(`${a.profile}: ${totals.length} whole-run types, ${off.length} off-band; zone off-band cells ${zones.map((z) => `${z.id}=${z.cells.length}`).join(' ')}`);
}

function f6cmd(a) {
  const plan = readJson(a.plan);
  const f = plan.f6;
  const classes = readJson(resolve(ROOT, 'packages/measure-chromium/classes.frozen.json')).profiles[f.profile].arms.rewrite.types;
  const d = (pg) => pageDeltas(load(a.dl, pg.base).map((x) => x.counts), load(a.dl, pg.arm).map((x) => x.counts));
  const nFrames = (pg) => median(load(a.dl, pg.base).map((x) => x.counts.frames.length));
  const rows = f6(d(f.combined), f.parts.map((p) => ({ name: p.name, deltas: d(p) })), classes, { combined: nFrames(f.combined), parts: f.parts.map(nFrames) });
  mkdirSync(a.out, { recursive: true });
  writeFileSync(join(a.out, 'f6.json'), JSON.stringify({ schema: 'fw.wave2.f6pilot/1', note: 'PILOT, INFERRED: raw whole-run delta of the combined page against the sum of part-page deltas; TS stand-in, the compose-check F6 verdict is not built in Lean.', profile: f.profile, combined: f.combined, parts: f.parts, frames: { combined: nFrames(f.combined), parts: f.parts.map(nFrames) }, rows }, null, 1));
  const dec = rows.filter((r) => r.strict !== null);
  console.log(`f6 pilot ${f.profile}: ${rows.length} types moved, ${dec.length} decidable: strict ${dec.filter((r) => r.strict).length} widened ${dec.filter((r) => r.widened).length}, per-frame rate within 10% ${dec.filter((r) => r.rateWithin10pct).length}, quarantined ${rows.length - dec.length}`);
}

function main(argv) {
  const [cmd, ...rest] = argv;
  if (cmd === 'f6') { const o = {}; for (let i = 0; i < rest.length; i += 2) o[rest[i].slice(2)] = rest[i + 1]; return f6cmd(o); }
  if (cmd === 'zonecmp') { const o = {}; for (let i = 0; i < rest.length; i += 2) o[rest[i].slice(2)] = rest[i + 1]; return zonecmp(o); }
  const a = {};
  for (let i = 0; i < rest.length; i += 2) a[rest[i].slice(2)] = rest[i + 1];
  if (!['check', 'delta'].includes(cmd) || !a.plan || !a.dl || !a.out) throw new Error('usage: wave2.mjs check|delta --plan f --dl d --out d');
  const plan = readJson(a.plan);
  mkdirSync(a.out, { recursive: true });
  const allRows = plan.rowFiles.flatMap((f) => readFileSync(resolve(ROOT, f), 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l))).filter((r) => r.engine === 'chromium' && r.prediction);
  let bug = 0;
  const summary = {};
  for (const [name, pg] of Object.entries(plan.pages)) {
    const baseFiles = load(a.dl, pg.base), armFiles = load(a.dl, pg.arm);
    if (baseFiles.length < 3 || armFiles.length < 3) { console.log(`${name}: ${baseFiles.length} base / ${armFiles.length} arm runs (< 3), skipped`); continue; }
    const dir = join(a.out, name);
    if (cmd === 'delta') {
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, 'delta.json'), JSON.stringify(pageDeltas(baseFiles.map((f) => f.counts), armFiles.map((f) => f.counts)), null, 1));
      console.log(`${name}: delta.json (${baseFiles.length} base, ${armFiles.length} arm runs)`);
      continue;
    }
    const rows = allRows.filter((r) => (pg.rowVariants ?? []).includes(r.variant) && r.scenario === pg.scenario);
    const staged = stageAs(baseFiles, armFiles, pg.rowVariants ?? []);
    rmSync(dir, { recursive: true, force: true });
    for (const s of staged) { mkdirSync(join(dir, s.name), { recursive: true }); writeFileSync(join(dir, s.name, 'counts.json'), JSON.stringify(s.counts)); }
    writeFileSync(join(dir, 'rows.jsonl'), rows.map((r) => JSON.stringify(r)).join('\n') + '\n');
    const r = spawnSync('node', [join(ROOT, 'apps/runner/src/fw.ts'), 'engine-check', '--rows', join(dir, 'rows.jsonl'), '--run', dir, '--json'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 });
    if (r.status !== 0 && r.status !== 3) { console.error(r.stderr || r.stdout); process.exit(r.status ?? 1); }
    const reply = JSON.parse(r.stdout);
    const active = [...new Set(rows.map((x) => x.variant))];
    const verdicts = reply.verdicts.map((v) => ({ ...v, confounds: confounds({ variant: v.variant, countType: v.countType }, rows, active) }));
    writeFileSync(join(dir, 'result.json'), JSON.stringify({ ...reply, verdicts }, null, 1));
    summary[name] = reply.tally;
    bug += reply.tally.modelBug;
    console.log(`${name}: ${reply.tally.pass} pass, ${reply.tally.modelBug} model-bug, ${reply.tally.unusable} unusable (${reply.verdicts.length} rows, ${staged.length} staged files)`);
    for (const v of verdicts) if (v.verdict !== 'pass') console.log(`  ${v.verdict.toUpperCase()} ${v.variant} ${v.stage} ${v.countType} ${v.prediction} [${v.class.variant}] sums ${v.totals.variant.join('/')} vs ${v.totals.base.join('/')}${v.confounds.length ? ` (CONFOUND: ${v.confounds.join('; ')})` : ''} ${v.reason}`);
  }
  if (cmd === 'check') writeFileSync(join(a.out, 'summary.json'), JSON.stringify(summary, null, 1));
  process.exit(bug > 0 ? 3 : 0);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
