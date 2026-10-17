// The frozen (signed) class table of the WKTR lane, from workflow runs already downloaded to disk. Downloads nothing:
//   gh run download <run> --dir runs/<run>      (artifacts wktr-j1.., wktr-classes), once per workflow run, then
//   node src/freeze.mjs runs/<run> runs/<run> runs/<run> ... [--kMax 4] [--tMax 24] [--out classes.frozen.json] [--check]
// Every decision is fwcore's; nothing is decided here (CLAUDE.md "Lean first"):
//   - each workflow run's class table per variant is re-derived from its counts files with fwcore measure.classify and
//     must equal the run's own wktr-classes/classes-<variant>-all.json (else the run is refused);
//   - the frozen class, k, t, per-run classes and tallies come from fwcore measure.freeze (Lean Fw.Measure.Freeze: worst
//     class over >= 3 workflow runs; a type missing from a run is quarantined there; mixed image digests, a repeated
//     run id and fewer than 3 runs are refused);
//   - pooledClass is fwcore measure.classify over every counts file of the variant at once.
// This module reads files, groups them by variant, moves JSON and checks that raw input facts agree between all passes
// (archive, runtime, harness parameters, viewport). The image digest handed to measure.freeze is the archive sha256 plus
// the iOS runtime build: the pieces of the measuring environment that are pinned (runner VM image versions are listed,
// not required to be equal).
// --check compares the result with the existing --out file and exits 1 listing the differing JSON paths.
import { readFileSync, readdirSync, existsSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { call } from '../../measure-chromium/src/fwcore.mjs';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const LANE_RUNNER = 'macos-26';
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
const readText = (p) => readFileSync(p, 'utf8').trim();

/** One downloaded workflow run: run.txt facts, its jobs' counts files per variant, its classes artifacts. */
export function readRun(dir) {
  const c = join(dir, 'wktr-classes');
  const runTxt = readText(join(c, 'run.txt'));
  const m = /^workflow run (\d+), attempt (\d+), sha ([0-9a-f]+), variants (\S+)$/.exec(runTxt);
  if (!m) throw new Error(`${dir}: run.txt not understood: ${runTxt}`);
  const jobDirs = readdirSync(dir).filter((d) => /^wktr-j\d+$/.test(d)).sort((a, b) => Number(a.slice(6)) - Number(b.slice(6)));
  if (jobDirs.length === 0) throw new Error(`${dir}: no wktr-j* job artifacts`);
  const variants = m[4].split(',');
  const byVariant = {};
  for (const v of variants) {
    const files = jobDirs.flatMap((d) => readdirSync(join(dir, d))
      .filter((f) => new RegExp(`^counts-${v}-\\d+\\.json$`).test(f)).sort().map((f) => ({ job: d, file: f, counts: readJson(join(dir, d, f)) })));
    if (files.length === 0) throw new Error(`${dir}: no counts files for variant ${v}`);
    byVariant[v] = { files, classes: readJson(join(c, `classes-${v}-all.json`)) };
  }
  const runners = readText(join(c, 'runners.jsonl')).replace(/}\s*{/g, '}\n{').split('\n').map((l) => JSON.parse(l));
  return { dir, id: m[1], attempt: m[2], sha: m[3], variants, byVariant, jobs: jobDirs, runners };
}

const classifyReq = (files, kMax, tMax) =>
  ({ op: 'measure.classify', mode: 'frames', kMax, tMax, runs: files.map((f) => ({ frames: f.counts.frames })) });

const digestOf = (meta) => `${meta.archive.sha256}/${meta.device.runtimeBuild}`;

/** The same value for every item, or throw naming the fact. */
function same(items, f, what) {
  const vals = items.map(f);
  if (!vals.every((v) => isDeepStrictEqual(v, vals[0]))) throw new Error(`${what} differs: ${JSON.stringify([...new Set(vals.map((v) => JSON.stringify(v)))])}`);
  return vals[0];
}

const tallyOrdered = (t) => ({ deterministic: t.deterministic, stable: t.stable, quarantined: t.quarantined });

/** The frozen table object for downloaded workflow-run directories (see the header). */
export function freezeRuns(dirs, { kMax = 4, tMax = 24 } = {}) {
  const runs = dirs.map(readRun);
  const variants = same(runs, (r) => r.variants, 'variants per workflow run');
  const profiles = {};
  const allMeta = [];
  for (const variant of variants) {
    const perRunFiles = runs.map((r) => r.byVariant[variant].files);
    const perRun = call(perRunFiles.map((fs) => classifyReq(fs, kMax, tMax)));
    runs.forEach((r, i) => {
      if (!isDeepStrictEqual(perRun[i].classes, r.byVariant[variant].classes)) throw new Error(`${r.dir}: fwcore measure.classify differs from the run's classes-${variant}-all.json (policy kMax ${kMax}, tMax ${tMax})`);
    });
    const allFiles = perRunFiles.flat();
    const [pooled] = call([classifyReq(allFiles, kMax, tMax)]);
    const [frozen] = call([{ op: 'measure.freeze', pooled: pooled.classes,
      runs: runs.map((r, i) => ({ id: r.id, images: r.byVariant[variant].files.map((f) => digestOf(f.counts.meta)), classes: perRun[i].classes })) }]);
    const metas = allFiles.map((f) => f.counts.meta);
    allMeta.push(...metas);
    for (const k of ['step', 'frames', 'settleMs', 'warm', 'vt', 'trace', 'still', 'header', 'variant']) same(metas, (m) => m[k], `${variant}: meta.${k}`);
    for (const k of ['innerWidth', 'innerHeight', 'dpr', 'docH', 'maxY']) same(metas, (m) => m.page[k], `${variant}: meta.page.${k}`);
    const types = {};
    for (const [ty, v] of Object.entries(frozen.types)) {
      types[ty] = { class: v.class, k: v.k, t: v.t, perRun: v.perRun, ...(v.pooledClass !== undefined && { pooledClass: v.pooledClass }) };
    }
    profiles[variant] = {
      workflowRuns: frozen.runs,
      jobsPerRun: same(runs, (r) => r.jobs.length, `${variant}: jobs per run`),
      countsFilesPerRun: perRunFiles.map((fs) => fs.length),
      image: frozen.image,
      harness: { step: metas[0].step, frames: metas[0].frames, settleMs: metas[0].settleMs, warm: metas[0].warm, vt: metas[0].vt, trace: metas[0].trace, header: metas[0].header },
      viewport: { innerWidth: metas[0].page.innerWidth, innerHeight: metas[0].page.innerHeight, dpr: metas[0].page.dpr, docH: metas[0].page.docH },
      tally: tallyOrdered(frozen.tally),
      pooledTally: tallyOrdered(frozen.pooledTally),
      types,
    };
  }
  const image = same(Object.values(profiles), (p) => p.image, 'image digest across variants');
  const archive = same(allMeta, (m) => m.archive, 'meta.archive');
  const device = same(allMeta, (m) => m.device, 'meta.device');
  const shas = [...new Set(runs.map((r) => r.sha))];
  const runnerImages = [...new Set(runs.flatMap((r) => r.runners.map((x) => x.imageVersion)))];
  return {
    schema: 'fw.wktr.classes.frozen/1',
    lane: `wktr (WebKitTestRunner, GitHub-hosted ${LANE_RUNNER}), counts only, never phone time`,
    rule: `The signed class of a type is its worst class (deterministic < stable < quarantined) over the workflow runs listed per variant; a type missing from a run counts as quarantined there; fewer than 3 workflow runs, a repeated run id and mixed image digests are refused (fwcore measure.freeze, Lean Fw.Measure.Freeze).`,
    policy: { kMax, tMax },
    image: { id: image, archive, device, runnerImageVersions: runnerImages, note: 'id = archive sha256 / iOS runtime build; runner VM image versions are listed, not required equal' },
    harness: shas.length === 1
      ? { commit: shas[0], note: 'every workflow run below ran this commit; fwcore was built from it by the same workflow' }
      : { commitByRun: Object.fromEntries(runs.map((r) => [r.id, r.sha])), note: 'the commit of each workflow run (its run.txt); fwcore was built from it by the same workflow' },
    profiles,
  };
}

/** JSON paths whose values differ between a and b (at most `max`). */
export function diffPaths(a, b, path = '$', out = [], max = 40) {
  if (out.length >= max) return out;
  const obj = (x) => x !== null && typeof x === 'object';
  if (obj(a) && obj(b) && Array.isArray(a) === Array.isArray(b)) {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) diffPaths(a[k], b[k], `${path}.${k}`, out, max);
  } else if (!isDeepStrictEqual(a, b)) out.push(`${path}: ${JSON.stringify(a)?.slice(0, 80)} -> ${JSON.stringify(b)?.slice(0, 80)}`);
  return out;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const argv = process.argv.slice(2);
  const opt = (n) => { const i = argv.indexOf(`--${n}`); return i >= 0 ? argv[i + 1] : undefined; };
  const valued = new Set(['--kMax', '--tMax', '--out']);
  const dirs = argv.filter((a, i) => !a.startsWith('--') && !valued.has(argv[i - 1]));
  const out = opt('out') ?? join(PKG, 'classes.frozen.json');
  const frozen = freezeRuns(dirs, { kMax: Number(opt('kMax') ?? 4), tMax: Number(opt('tMax') ?? 24) });
  const text = JSON.stringify(frozen, null, 1) + '\n';
  if (argv.includes('--check')) {
    const cur = existsSync(out) ? readFileSync(out, 'utf8') : '';
    if (cur === text) { console.log(`freeze: ${out} is identical`); process.exit(0); }
    const d = diffPaths(cur ? JSON.parse(cur) : {}, frozen);
    console.log(`freeze: ${out} differs (${d.length}${d.length >= 40 ? '+' : ''} paths, committed -> regenerated)\n${d.join('\n')}`);
    process.exit(1);
  }
  writeFileSync(out, text);
  for (const [p, v] of Object.entries(frozen.profiles)) console.log(`freeze: ${p}: runs ${v.workflowRuns.join(', ')}; ${JSON.stringify(v.tally)}`);
  console.log(`freeze: wrote ${out}`);
}
