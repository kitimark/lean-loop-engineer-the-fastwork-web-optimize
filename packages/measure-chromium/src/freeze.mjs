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
import { readFileSync, readdirSync, existsSync, writeFileSync, statSync } from 'node:fs';
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

/**
 * One downloaded workflow run: run.txt facts and, per arm (target), its jobs (counts + image id) and its classes
 * artifact. Layout of the workflow: chromium-counts-<target>-r<N>/ and chromium-classes/<target>/classes.json.
 */
export function readRun(dir) {
  const c = join(dir, 'chromium-classes');
  const runTxt = readText(join(c, 'run.txt')).split('\n')[0]; // line 2 names the rewrite search
  const m = /^profile (\S+), workflow run (\d+), attempt (\d+), sha ([0-9a-f]+)$/.exec(runTxt);
  if (!m) throw new Error(`${dir}: run.txt not understood: ${runTxt}`);
  const arms = {};
  for (const target of readdirSync(c).filter((d) => statSync(join(c, d)).isDirectory()).sort()) {
    const pre = `chromium-counts-${target}-r`;
    const jobDirs = readdirSync(dir).filter((d) => d.startsWith(pre) && /^\d+$/.test(d.slice(pre.length)))
      .sort((a, b) => Number(a.slice(pre.length)) - Number(b.slice(pre.length)));
    if (jobDirs.length === 0) throw new Error(`${dir}: no ${pre}* job artifacts`);
    const jobs = jobDirs.map((d) => ({ name: d, counts: readJson(join(dir, d, 'counts.json')), imageId: readText(join(dir, d, 'image-id.txt')) }));
    arms[target] = { jobs, classes: readJson(join(c, target, 'classes.json')) };
  }
  if (Object.keys(arms).length === 0) throw new Error(`${dir}: chromium-classes has no per-target directory`);
  const inputs = Object.fromEntries(readText(join(c, 'image-inputs.txt')).split('\n').map((l) => {
    const [sha, path] = l.trim().split(/\s+/);
    return [path, sha];
  }));
  return { dir, profile: m[1], id: m[2], attempt: m[3], sha: m[4], arms, inputs };
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
  const armImages = [];
  for (const [name, rs] of byProfile) {
    const targets = same(rs, (r) => Object.keys(r.arms), `${name}: arms (targets) per workflow run`);
    const armsOut = {};
    for (const target of targets) {
      const label = `${name}/${target}`;
      const ars = rs.map((r) => ({ ...r.arms[target], id: r.id, dir: r.dir }));
      // per-run class tables: fwcore must reproduce each run's own artifact
      const perRun = call(ars.map((r) => classifyReq(r.jobs, kMax, tMax)));
      ars.forEach((r, i) => {
        if (!isDeepStrictEqual(perRun[i].classes, r.classes)) throw new Error(`${r.dir}: fwcore measure.classify differs from the run's ${target} classes.json (policy kMax ${kMax}, tMax ${tMax})`);
      });
      const allJobs = ars.flatMap((r) => r.jobs);
      const [pooled] = call([classifyReq(allJobs, kMax, tMax)]);
      // images: every job's image-id.txt and the image its counts.json names
      const [frozenP] = call([{ op: 'measure.freeze', pooled: pooled.classes,
        runs: ars.map((r) => ({ id: r.id, images: r.jobs.flatMap((j) => [j.imageId, j.counts.meta.image]), classes: r.classes })) }]);
      const metas = allJobs.map((j) => j.counts.meta);
      metasAll.push(...metas);
      for (const k of ['snapshot', 'servedSha256', 'target']) same(metas, (m) => m[k], `${label}: meta.${k}`);
      if (metas[0].target !== target) throw new Error(`${label}: counts say target ${metas[0].target}`);
      const types = {};
      for (const [ty, v] of Object.entries(frozenP.types)) {
        types[ty] = { class: v.class, k: v.k, t: v.t, perRun: v.perRun, role: v.role,
          ...(v.reason !== undefined && { reason: v.reason }),
          ...(v.unit !== undefined && { unit: v.unit }), ...(v.tBound !== undefined && { tBound: v.tBound }),
          ...(v.pooledClass !== undefined && { pooledClass: v.pooledClass }) };
      }
      armImages.push(frozenP.image);
      armsOut[target] = {
        workflowRuns: frozenP.runs,
        jobsPerRun: same(ars, (r) => r.jobs.length, `${label}: jobs per run`),
        image: frozenP.image,
        snapshot: metas[0].snapshot,
        servedSha256: metas[0].servedSha256,
        trajectorySha256: metas[0].trajectorySha256,
        allImagesEqual: true, // measure.freeze refuses mixed digests
        allTrajectoriesEqual: metas.every((m) => m.trajectorySha256 === metas[0].trajectorySha256),
        tally: tallyOrdered(frozenP.tally),
        roles: frozenP.roles,
        pooledTally: tallyOrdered(frozenP.pooledTally),
        types,
      };
    }
    profiles[name] = { workflowRuns: rs.map((r) => r.id), arms: armsOut };
    if (armsOut.original && armsOut.rewrite) {
      // cross-arm level and role per type (Lean Fw.Measure.Arms): an arm without the type reads as deterministic there
      const tab = (a) => Object.fromEntries(Object.entries(a.types).map(([ty, v]) =>
        [ty, { class: v.class, k: v.k, t: v.t, ...(v.tBound !== undefined && { tBound: v.tBound }) }]));
      const [x] = call([{ op: 'measure.arms', a: tab(armsOut.original), r: tab(armsOut.rewrite) }]);
      profiles[name].crossArm = { types: x.types, gates: x.gates, roles: x.roles };
    }
  }
  const image = same(armImages, (i) => i, 'image digest across profiles and arms');
  const inputs = same(runs, (r) => r.inputs, 'image inputs (Dockerfile, apt manifest, npm lock)');
  const targets = [...new Set(metasAll.map((m) => m.target))].sort().join(' and ');
  const nJobs = runs.reduce((s, r) => s + Object.values(r.arms).reduce((n, a) => n + a.jobs.length, 0), 0);
  const shas = [...new Set(runs.map((r) => r.sha))];
  const filesPerProfile = [...new Set(Object.values(profiles).flatMap((p) => Object.values(p.arms).map((a) => a.workflowRuns.length * a.jobsPerRun)))].join('/');
  return {
    schema: 'fw.classes.frozen/2',
    lane: `chromium-counts (GitHub-hosted ${LANE_RUNNER}), target ${targets}`,
    rule: `The signed class of a type is its worst class (deterministic < stable < quarantined) over the workflow runs listed per profile and arm (original = A, rewrite = R); a type missing from a run counts as quarantined there; fewer than 3 workflow runs, a repeated run id or more than one image digest are refused. Each workflow run classifies its jobs (separate VMs) with fwcore measure.classify (re-derived from the run's counts files and equal to its classes artifact); the worst class, k and t (maxima over the workflow runs) and tBound (pixel types, the smallest over the workflow runs) come from fwcore measure.freeze (Lean Fw.Measure.Freeze), written by src/freeze.mjs; role (gate, finding, byDesign) and crossArm (cross-arm level, role and gate list; an arm without the type reads as deterministic) come from Lean Fw.Measure.Arms (measure.freeze rows, measure.arms). pooledClass is the class over all ${filesPerProfile} counts files at once (a stricter cross-check, not the signed class).`,
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
  for (const [p, v] of Object.entries(frozen.profiles)) for (const [t, a] of Object.entries(v.arms)) console.log(`freeze: ${p}/${t}: runs ${v.workflowRuns.join(', ')}; ${JSON.stringify(a.tally)} roles ${JSON.stringify(a.roles)}`);
  console.log(`freeze: wrote ${out}`);
}
