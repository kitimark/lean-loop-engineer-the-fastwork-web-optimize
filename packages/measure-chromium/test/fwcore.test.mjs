// Conformance: the measure.* golden vectors (generated from Lean, packages/contracts/golden/measure/) through the fwcore
// binary. Since fwcore matched them (and the stored zones of three real 503-frame runs), the TS zoneSums is gone: zones
// and classes come from fwcore only (src/fwcore.mjs). Needs lean/.lake/build/bin/fwcore (cd lean && lake build).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { classify, fwcoreBin, zoneSums } from '../src/fwcore.mjs';
import { snapshotCounts } from '../src/trace.mjs';
import { freezeRuns, diffPaths } from '../src/freeze.mjs';

const GOLDEN = join(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/measure');
const load = (op) => readFileSync(join(GOLDEN, `${op}.jsonl`), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

/** All requests of one file in one fwcore process; replies without ids. */
function replies(cases) {
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(fwcoreBin(), [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 28 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  assert.equal(r.stderr.length, 0, `fwcore stderr: ${r.stderr}`);
  return r.stdout.toString().trim().split('\n').map((l, i) => { const { id, ...rest } = JSON.parse(l); assert.equal(id, i); return rest; });
}

// trace.mjs snapshotCounts runs in the container (no Lean there), so it is checked against the Lean goldens here.
test('snapshotCounts (trace.mjs) equals every non-refused golden of measure.snapshotCounts', () => {
  const cases = load('measure.snapshotCounts').filter((c) => c.response.error === undefined);
  assert.ok(cases.length > 0);
  for (const c of cases) assert.deepStrictEqual(snapshotCounts(c.request.snapshot), c.response.counts, c.name);
});

for (const op of ['measure.zoneSums', 'measure.classify', 'measure.noMoreWork', 'measure.selfCheck', 'measure.snapshotCounts', 'measure.freeze']) {
  test(`${op}: fwcore reproduces every golden line`, () => {
    const cases = load(op);
    assert.ok(cases.length > 0);
    const got = replies(cases);
    cases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
  });
}

// classify.mjs (the CI classifier) sends only kMax/tMax; the pixel-area rule and its default 1/1000 live in Lean
// (Fw.Measure.classifyAllU). Totals of census.drawingAreaPx from CI run 39033771018, one frame per run.
test('classify through the client: pixel areas get the relative bound, the same gap on a count type does not', () => {
  const tot = [5340886817, 5338843401, 5340887569];
  const runs = tot.map((v) => ({ frames: [{ counts: { 'census.drawingAreaPx': v, 'census.drawingArea': v } }] }));
  const c = classify(runs, 4, 24);
  assert.deepStrictEqual(c['census.drawingAreaPx'], { class: 'stable', k: 1, t: 2044168, unit: 'px', tBound: 5338843 });
  assert.deepStrictEqual(c['census.drawingArea'], { class: 'quarantined', k: 1, t: 2044168 });
});

test('zoneSums through the client: the pure.test.mjs seed vector', () => {
  const frames = [
    { n: 0, phase: 'rest', scrollY: 0, counts: { a: 1, b: 2 } },
    { n: 1, phase: 'swipe', scrollY: 10, counts: { a: 1, b: 0 } },
    { n: 2, phase: 'swipe', scrollY: 490, counts: { a: 2, b: 1 } },
    { n: 3, phase: 'swipe', scrollY: 500, counts: { a: 4, b: 1 } },
    { n: 4, phase: 'tail', scrollY: 500, counts: { a: 0, b: 7 } },
  ];
  const z = zoneSums(frames, 500);
  assert.deepEqual(z.map((x) => x.id), ['rest', 'y00000', 'y00500', 'tail']);
  assert.deepEqual(z.map((x) => x.frames), [1, 2, 1, 1]);
  assert.deepEqual(z.map((x) => x.scrolledPx), [0, 490, 10, 0]);
  assert.deepEqual(z[1].sums, { a: 3, b: 1 });
  assert.equal(z.reduce((s, x) => s + x.sums.a, 0), 8);
});

// freeze.mjs (the frozen class table) over synthetic downloaded workflow runs: 3 runs x 2 jobs, one image.
// Type `a` is identical everywhere, `b` moves one frame in run 3 (deterministic inside every run, stable pooled), `c`
// exists only in run 2 (so it is quarantined; pooled, its total gap 100 is above tMax).
function fakeRuns({ images = ['sha256:i', 'sha256:i', 'sha256:i'], n = 3, tamper = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'fw-freeze-'));
  const meta = (img) => ({ image: img, snapshot: 's1', servedSha256: 'f00', target: 'original', trajectorySha256: 'tr' });
  const frames = (run) => [0, 1].map((i) => ({ n: i, phase: 'swipe', scrollY: i,
    counts: { a: 1, b: run === 2 ? 1 - i : i, ...(run === 1 ? { c: 50 } : {}) } }));
  const dirs = [];
  for (let r = 0; r < n; r++) {
    const dir = join(root, `run${r}`);
    const jobs = [1, 2].map(() => ({ frames: frames(r), meta: meta(images[r]) }));
    jobs.forEach((c, j) => {
      mkdirSync(join(dir, `chromium-counts-r${j + 1}`), { recursive: true });
      writeFileSync(join(dir, `chromium-counts-r${j + 1}`, 'counts.json'), JSON.stringify(c));
      writeFileSync(join(dir, `chromium-counts-r${j + 1}`, 'image-id.txt'), `${images[r]}\n`);
    });
    const classes = classify(jobs, 4, 24);
    if (tamper && r === 0) classes.a.class = 'stable';
    mkdirSync(join(dir, 'chromium-classes'));
    writeFileSync(join(dir, 'chromium-classes', 'classes.json'), JSON.stringify(classes));
    writeFileSync(join(dir, 'chromium-classes', 'run.txt'), `profile swipe-v1, workflow run ${100 + r}, attempt 1, sha abc\n`);
    writeFileSync(join(dir, 'chromium-classes', 'image-inputs.txt'), 'd0  Dockerfile\nd1  docker/apt-manifest.txt\n');
    dirs.push(dir);
  }
  return dirs;
}

test('freeze.mjs: worst class over 3 runs through fwcore measure.freeze; a type missing from a run is quarantined', () => {
  const f = freezeRuns(fakeRuns(), { builtBy: 100, dockerfile: '/nonexistent' });
  const p = f.profiles['swipe-v1'];
  assert.deepStrictEqual(p.workflowRuns, ['100', '101', '102']);
  assert.equal(p.image, 'sha256:i');
  assert.equal(p.jobsPerRun, 2);
  const det3 = ['deterministic', 'deterministic', 'deterministic'];
  assert.deepStrictEqual(p.types.a, { class: 'deterministic', k: 0, t: 0, perRun: det3, pooledClass: 'deterministic' });
  assert.deepStrictEqual(p.types.b, { class: 'deterministic', k: 0, t: 0, perRun: det3, pooledClass: 'stable' });
  assert.deepStrictEqual(p.types.c, { class: 'quarantined', k: 0, t: 0, perRun: ['missing', 'deterministic', 'missing'], pooledClass: 'quarantined' });
  assert.deepStrictEqual(p.tally, { deterministic: 2, stable: 0, quarantined: 1 });
  assert.deepStrictEqual(p.pooledTally, { deterministic: 1, stable: 1, quarantined: 1 });
  assert.deepStrictEqual(f.harness, { commit: 'abc', note: 'every workflow run below ran this commit; fwcore was built from it by the same workflow' });
  assert.equal(f.image.builtByRun, '100');
  assert.equal(f.image.baseImage, undefined);
});

test('freeze.mjs refuses 2 runs, mixed image digests, and a classes artifact fwcore does not reproduce', () => {
  assert.throws(() => freezeRuns(fakeRuns({ n: 2 })), /need at least 3 workflow runs/);
  assert.throws(() => freezeRuns(fakeRuns({ images: ['sha256:i', 'sha256:j', 'sha256:i'] })), /mixed image digests/);
  assert.throws(() => freezeRuns(fakeRuns({ tamper: true })), /differs from the run's classes.json/);
});

test('diffPaths lists the differing leaves', () => {
  assert.deepStrictEqual(diffPaths({ a: 1, b: { c: [1, 2] } }, { a: 1, b: { c: [1, 3] }, d: 0 }), ['$.b.c.1: 2 -> 3', '$.d: undefined -> 0']);
});
