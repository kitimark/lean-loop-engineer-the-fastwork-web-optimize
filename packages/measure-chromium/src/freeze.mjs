// The frozen (signed) class table of the counts lane, from CI workflow runs already downloaded to disk. Downloads
// nothing: fetch the artifacts first, one directory per workflow run, e.g.
//   gh run download <run> --dir runs/<run> --pattern 'chromium-c*'
// then
//   node src/freeze.mjs runs/<run> runs/<run> ... [--built-by <run>] [--kMax 4] [--tMax 24]
//        [--out classes.frozen.json] [--check]
// Every decision is fwcore's (nothing decided here):
//   - each workflow run's class table is re-derived from its counts files with fwcore measure.classify and must equal
//     the run's own chromium-classes/classes.json artifact (else the run is refused);
//   - the frozen class, k, t, tBound, per-run classes and tallies come from fwcore measure.freeze (Lean
//     Fw.Measure.Freeze: worst class over >= 3 runs, a type missing from a run is quarantined, mixed image digests and
//     repeated run ids are refused);
//   - pooledClass is fwcore measure.classify over all counts files of the profile at once.
// This module only reads files, groups runs by the profile named in run.txt, moves JSON and checks that raw input
// facts agree (same Dockerfile inputs, snapshot, served files and target within a profile).
// --check compares the result with the existing --out file and exits 1 listing the differing JSON paths.
import { readFileSync, readdirSync, existsSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { call } from './fwcore.mjs';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PX_REL = { num: 1, den: 1000 };
const LANE_RUNNER = 'ubuntu-24.04-arm'; // runs-on of .github/workflows/chromium-counts.yml

const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
const readText = (p) => readFileSync(p, 'utf8').trim();

/** One downloaded workflow run: run.txt facts, its jobs (counts + image id) and its classes artifact. */
export function readRun(dir) {
  const c = join(dir, 'chromium-classes');
  const runTxt = readText(join(c, 'run.txt'));
  const m = /^profile (\S+), workflow run (\d+), attempt (\d+), sha ([0-9a-f]+)$/.exec(runTxt);
  if (!m) throw new Error(`${dir}: run.txt not understood: ${runTxt}`);
  const jobDirs = readdirSync(dir).filter((d) => /^chromium-counts-r\d+$/.test(d))
    .sort((a, b) => Number(a.slice(16)) - Number(b.slice(16)));
  if (jobDirs.length === 0) throw new Error(`${dir}: no chromium-counts-r* job artifacts`);
  const jobs = jobDirs.map((d) => {
    const counts = readJson(join(dir, d, 'counts.json'));
    return { name: d, counts, imageId: readText(join(dir, d, 'image-id.txt')) };
  });
  const inputs = Object.fromEntries(readText(join(c, 'image-inputs.txt')).split('\n').map((l) => {
    const [sha, path] = l.trim().split(/\s+/);
    return [path, sha];
  }));
  return { dir, profile: m[1], id: m[2], attempt: m[3], sha: m[4], jobs, classes: readJson(join(c, 'classes.json')), inputs };
}

const classifyReq = (jobs, kMax, tMax) =>
  ({ op: 'measure.classify', mode: 'frames', kMax, tMax, pxRel: PX_REL, runs: jobs.map((j) => ({ frames: j.counts.frames })) });

/** The same value for every item, or throw naming the fact. */
function same(items, f, what) {
  const vals = items.map(f);
  if (!vals.every((v) => isDeepStrictEqual(v, vals[0]))) throw new Error(`${what} differs: ${JSON.stringify([...new Set(vals.map((v) => JSON.stringify(v)))])}`);
  return vals[0];
}

/** base image and browser pins, read from the Dockerfile only when its sha256 is the one the runs recorded. */
function dockerPins(dockerfile, sha) {
  if (!existsSync(dockerfile)) return {};
  const text = readFileSync(dockerfile);
  if (createHash('sha256').update(text).digest('hex') !== sha) {
    console.error(`freeze: ${dockerfile} is not the Dockerfile the runs used (sha256 differs); baseImage and browser omitted`);
    return {};
  }
  const s = text.toString();
  const from = /^FROM\s+(\S+)/m.exec(s)?.[1];
  const ver = /^ARG HS_VERSION=(\S+)/m.exec(s)?.[1];
  const zip = /^ARG HS_SHA256=(\S+)/m.exec(s)?.[1];
  return { ...(from && { baseImage: from }), ...(ver && zip && { browser: `chrome-headless-shell ${ver}, zip sha256 ${zip}` }) };
}

const tallyOrdered = (t) => ({ deterministic: t.deterministic, stable: t.stable, quarantined: t.quarantined });

/** The frozen table object for downloaded workflow-run directories (see the header). */
export function freezeRuns(dirs, { kMax = 4, tMax = 24, builtBy, dockerfile = join(PKG, 'Dockerfile') } = {}) {
  const runs = dirs.map(readRun);
  const byProfile = new Map();
  for (const r of runs) byProfile.set(r.profile, [...(byProfile.get(r.profile) ?? []), r]);
  const profiles = {};
  const metasAll = [];
  for (const [name, rs] of byProfile) {
    // per-run class tables: fwcore must reproduce each run's own artifact
    const perRun = call(rs.map((r) => classifyReq(r.jobs, kMax, tMax)));
    rs.forEach((r, i) => {
      if (!isDeepStrictEqual(perRun[i].classes, r.classes)) throw new Error(`${r.dir}: fwcore measure.classify differs from the run's classes.json (policy kMax ${kMax}, tMax ${tMax})`);
    });
    const allJobs = rs.flatMap((r) => r.jobs);
    const [pooled] = call([classifyReq(allJobs, kMax, tMax)]);
    // images: every job's image-id.txt and the image its counts.json names
    const [frozenP] = call([{ op: 'measure.freeze', pooled: pooled.classes,
      runs: rs.map((r) => ({ id: r.id, images: r.jobs.flatMap((j) => [j.imageId, j.counts.meta.image]), classes: r.classes })) }]);
    const metas = allJobs.map((j) => j.counts.meta);
    metasAll.push(...metas);
    for (const k of ['snapshot', 'servedSha256', 'target']) same(metas, (m) => m[k], `${name}: meta.${k}`);
    const types = {};
    for (const [ty, v] of Object.entries(frozenP.types)) {
      types[ty] = { class: v.class, k: v.k, t: v.t, perRun: v.perRun,
        ...(v.unit !== undefined && { unit: v.unit }), ...(v.tBound !== undefined && { tBound: v.tBound }),
        ...(v.pooledClass !== undefined && { pooledClass: v.pooledClass }) };
    }
    profiles[name] = {
      workflowRuns: frozenP.runs,
      jobsPerRun: same(rs, (r) => r.jobs.length, `${name}: jobs per run`),
      image: frozenP.image,
      snapshot: metas[0].snapshot,
      servedSha256: metas[0].servedSha256,
      trajectorySha256: metas[0].trajectorySha256,
      allImagesEqual: true, // measure.freeze refuses mixed digests
      allTrajectoriesEqual: metas.every((m) => m.trajectorySha256 === metas[0].trajectorySha256),
      tally: tallyOrdered(frozenP.tally),
      pooledTally: tallyOrdered(frozenP.pooledTally),
      types,
    };
  }
  const image = same(Object.values(profiles), (p) => p.image, 'image digest across profiles');
  const inputs = same(runs, (r) => r.inputs, 'image inputs (Dockerfile, apt manifest, npm lock)');
  const target = same(metasAll, (m) => m.target, 'meta.target');
  const nJobs = runs.reduce((s, r) => s + r.jobs.length, 0);
  const shas = [...new Set(runs.map((r) => r.sha))];
  const filesPerProfile = [...new Set(Object.values(profiles).map((p) => p.workflowRuns.length * p.jobsPerRun))].join('/');
  return {
    schema: 'fw.classes.frozen/1',
    lane: `chromium-counts (GitHub-hosted ${LANE_RUNNER}), target ${target}`,
    rule: `The signed class of a type is its worst class (deterministic < stable < quarantined) over the workflow runs listed per profile; a type missing from a run counts as quarantined there; fewer than 3 workflow runs, a repeated run id or more than one image digest are refused. Each workflow run classifies its jobs (separate VMs) with fwcore measure.classify (re-derived from the run's counts files and equal to its classes artifact); the worst class, k and t (maxima over the workflow runs) and tBound (pixel types, the smallest over the workflow runs) come from fwcore measure.freeze (Lean Fw.Measure.Freeze), written by src/freeze.mjs. pooledClass is the class over all ${filesPerProfile} counts files at once (a stricter cross-check, not the signed class).`,
    policy: {
      kMax, tMax,
      pixelRule: {
        appliesTo: 'types whose name ends in AreaPx',
        tBound: 'max(tMax, floor(num * min|run total| / den))',
        pxRel: PX_REL,
        source: 'lean/Fw/Measure/Classes.lean section "Pixel-area types" (task pixel-tolerance)',
      },
    },
    image: {
      id: image,
      ...(builtBy !== undefined && { builtByRun: String(builtBy) }),
      sharedByAllRuns: `${builtBy !== undefined ? `every workflow run below reused the artifact of run ${builtBy} (workflow input image_run); ` : ''}all ${nJobs} jobs report this image id`,
      ...dockerPins(dockerfile, inputs.Dockerfile),
      inputSha256: inputs,
    },
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
  const valued = new Set(['--built-by', '--kMax', '--tMax', '--out']);
  const dirs = argv.filter((a, i) => !a.startsWith('--') && !valued.has(argv[i - 1]));
  const out = opt('out') ?? join(PKG, 'classes.frozen.json');
  const frozen = freezeRuns(dirs, { kMax: Number(opt('kMax') ?? 4), tMax: Number(opt('tMax') ?? 24), builtBy: opt('built-by') });
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
