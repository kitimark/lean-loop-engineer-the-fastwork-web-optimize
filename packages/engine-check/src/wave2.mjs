// Wave-2 analysis glue: part-page and whole-page counts runs read under an EXPLICIT plan (results/integrate-wave-2/plan.json).
// Every verdict is fwcore's (`fw engine-check`, Lean Fw.Measure.EngineCheck); this file stages files, copies numbers and
// labels confounds. TS stand-ins (no Lean twin yet): `totalsOf`, `median`, `deltaRow`, `confounds`, `stageAs` (the identity guard and the
// attribution tag: decision logic, Lean twin pending), `pairsOf`, `nonFaithful`.
//
//   node wave2.mjs check --plan plan.json --dl <dir of gh-downloaded runs> --out <dir>   engine-check per page of the plan
//   node wave2.mjs zonecmp --dir results/integrate-wave-2/zones --profile p --out <dir>    v2-proved zone baseline against the base one
//   node wave2.mjs frames --plan plan.json --dl <dir> --res <engine-check dir>             frame lists of the model-bug rows (after check)
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
 * The `part:variant` pairs a row variant names. `rewrite+?fw=a:b,c:d` names `a:b` and `c:d`; a bare variant (`hidden-pause`) is
 * expanded with the page's `part`. @param {string} variant @param {string} part
 */
export function pairsOf(variant, part) {
  const m = /^rewrite\+\?fw=(.+)$/.exec(variant);
  return m ? m[1].split(',') : [`${part}:${variant}`];
}

/** The `part:variant` pairs of a counts file's rewrite config whose variant is not `faithful`. @param {any} counts */
export function nonFaithful(counts) {
  const v = counts.meta?.rewrite?.config?.variants;
  if (!v) throw new Error('counts file has no meta.rewrite.config.variants');
  return Object.entries(v).filter(([, x]) => x !== 'faithful').map(([k, x]) => `${k}:${x}`).sort();
}

/**
 * Stage the files of one page: base files answer `rewrite`, arm files answer each variant of `armVariants`. Each copy carries
 * meta.variant, so `variantKeys` (apps/runner/src/engine-check.ts) returns that one key and never the bare target.
 * Identity, not inference (TS stand-in `stageAs`): the page's pairs (`pairsOf` over `armVariants` and `part`) must all be in the
 * rewrite config of every arm file, else it throws and nothing is staged. `attribution` is written here: MEASURED when every arm
 * file's non-faithful set equals the pair set and every base file has none (a single-flag arm), INFERRED otherwise (a preset arm: PLAN 10.7 open bridge).
 * @param {{path: string, counts: any}[]} baseFiles @param {{path: string, counts: any}[]} armFiles @param {string[]} armVariants @param {string} part
 * @returns {{files: {name: string, source: string, variant: string, counts: any}[], pairs: string[], armFlags: string[], attribution: 'MEASURED' | 'INFERRED'}}
 */
export function stageAs(baseFiles, armFiles, armVariants, part) {
  const pairs = [...new Set(armVariants.flatMap((v) => pairsOf(v, part)))].sort();
  const armSets = armFiles.map((f) => nonFaithful(f.counts));
  for (const [i, set] of armSets.entries()) {
    const missing = pairs.filter((p) => !set.includes(p));
    if (missing.length) throw new Error(`stageAs ${part}: arm file ${armFiles[i].path} did not run ${missing.join(', ')} (it ran: ${set.join(', ') || 'nothing'}); not staged`);
  }
  const key = (xs) => xs.join(' ');
  const single = armSets.every((s) => key(s) === key(pairs)) && baseFiles.every((f) => nonFaithful(f.counts).length === 0);
  const copy = (role, i, { path, counts }, v) => ({
    name: `${role}-${String(i).padStart(2, '0')}-${v.replace(/[^A-Za-z0-9.:@,_=+-]/g, '_')}`,
    source: path, variant: v, counts: { ...counts, meta: { ...counts.meta, variant: v } },
  });
  return {
    files: [
      ...baseFiles.map((f, i) => copy('base', i, f, 'rewrite')),
      ...armFiles.flatMap((f, i) => armVariants.map((v) => copy('arm', i, f, v))),
    ],
    pairs,
    armFlags: [...new Set(armSets.flat())].sort(),
    attribution: single ? 'MEASURED' : 'INFERRED',
  };
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
 * Frame-level reading of one count type across shards (descriptive; the verdict is fwcore's). `self` lists, per pair of shards of one arm, the
 * frames where the two differ; `cross` lists per (base shard, arm shard) the frames where the arm is above / below the base.
 * @param {number[][]} base per-frame series per base shard @param {number[][]} arm per-frame series per arm shard
 */
export function frameDiff(base, arm) {
  const diff = (a, b) => { const out = []; for (let i = 0; i < Math.max(a.length, b.length); i++) if ((a[i] ?? 0) !== (b[i] ?? 0)) out.push(i); return out; };
  const selfOf = (xs) => xs.flatMap((a, i) => xs.slice(i + 1).map((b, k) => ({ pair: [i, i + 1 + k], frames: diff(a, b) })));
  const cross = base.flatMap((b, i) => arm.map((a, j) => ({ base: i, arm: j, differ: diff(b, a), armAbove: diff(b, a).filter((f) => (a[f] ?? 0) > (b[f] ?? 0)), armBelow: diff(b, a).filter((f) => (a[f] ?? 0) < (b[f] ?? 0)) })));
  return { frames: { base: base.map((x) => x.length), arm: arm.map((x) => x.length) }, baseSelf: selfOf(base), armSelf: selfOf(arm), cross };
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

function framesCmd(a) {
  const plan = readJson(a.plan);
  for (const [name, pg] of Object.entries(plan.pages)) {
    const res = join(a.res, name, 'result.json');
    let bugs;
    try { bugs = readJson(res).verdicts.filter((v) => v.verdict === 'model-bug'); } catch { continue; }
    if (!bugs.length) continue;
    const bf = load(a.dl, pg.base), af = load(a.dl, pg.arm);
    const series = (files, t) => files.map((f) => f.counts.frames.map((x) => x.counts?.[t] ?? 0));
    const rows = bugs.map((v) => ({ variant: v.variant, stage: v.stage, countType: v.countType, prediction: v.prediction, class: v.class.variant, ...frameDiff(series(bf, v.countType), series(af, v.countType)) }));
    writeFileSync(join(a.res, name, 'frames.json'), JSON.stringify({ schema: 'fw.wave2.frames/1', page: name, base: pg.base, arm: pg.arm, rows }, null, 1));
    console.log(`${name}: ${rows.length} model-bug rows, frame lists in frames.json`);
  }
}

function main(argv) {
  const [cmd, ...rest] = argv;
  if (cmd === 'frames') { const o = {}; for (let i = 0; i < rest.length; i += 2) o[rest[i].slice(2)] = rest[i + 1]; return framesCmd(o); }
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
    if (!(pg.rowVariants ?? []).length) { console.log(`${name}: no row variants (descriptive page, delta.json only)`); continue; }
    const rows = allRows.filter((r) => (pg.rowVariants ?? []).includes(r.variant) && r.scenario === pg.scenario);
    if (!pg.part) throw new Error(`${name}: the plan page has no "part"`);
    const searches = [...new Set(armFiles.map((f) => f.counts.meta.search))];
    if (searches.length !== 1) throw new Error(`${name}: arm shards disagree on meta.search: ${searches.join(' | ')}`);
    const { files: staged, pairs, armFlags, attribution } = stageAs(baseFiles, armFiles, pg.rowVariants ?? [], pg.part);
    const baseSearch = [...new Set(baseFiles.map((f) => f.counts.meta.search))].join(' | ');
    rmSync(dir, { recursive: true, force: true });
    for (const s of staged) { mkdirSync(join(dir, s.name), { recursive: true }); writeFileSync(join(dir, s.name, 'counts.json'), JSON.stringify(s.counts)); }
    writeFileSync(join(dir, 'rows.jsonl'), rows.map((r) => JSON.stringify(r)).join('\n') + '\n');
    const r = spawnSync('node', [join(ROOT, 'apps/runner/src/fw.ts'), 'engine-check', '--rows', join(dir, 'rows.jsonl'), '--run', dir, '--json'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 28 });
    if (r.status !== 0 && r.status !== 3) { console.error(r.stderr || r.stdout); process.exit(r.status ?? 1); }
    const reply = JSON.parse(r.stdout);
    const active = [...new Set(rows.map((x) => x.variant))];
    const verdicts = reply.verdicts.map((v) => ({ ...v, confounds: confounds({ variant: v.variant, countType: v.countType }, rows, active) }));
    writeFileSync(join(dir, 'result.json'), JSON.stringify({ ...reply, verdicts, page: { part: pg.part, base: pg.base, arm: pg.arm, baseSearch, search: searches[0], pairs, armFlags, attribution } }, null, 1));
    summary[name] = { ...reply.tally, attribution, search: searches[0] };
    bug += reply.tally.modelBug;
    console.log(`${name} [${attribution}, ${searches[0]}]: ${reply.tally.pass} pass, ${reply.tally.modelBug} model-bug, ${reply.tally.unusable} unusable (${reply.verdicts.length} rows, ${staged.length} staged files)`);
    for (const v of verdicts) if (v.verdict !== 'pass') console.log(`  ${v.verdict.toUpperCase()} ${v.variant} ${v.stage} ${v.countType} ${v.prediction} [${v.class.variant}] sums ${v.totals.variant.join('/')} vs ${v.totals.base.join('/')}${v.confounds.length ? ` (CONFOUND: ${v.confounds.join('; ')})` : ''} ${v.reason}`);
  }
  if (cmd === 'check') writeFileSync(join(a.out, 'summary.json'), JSON.stringify(summary, null, 1));
  process.exit(bug > 0 ? 3 : 0);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
