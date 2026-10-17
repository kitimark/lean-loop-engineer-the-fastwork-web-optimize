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
import { snapshotCounts, traceToFrameCounts, SPLITS, MAIN, N1_KEYS } from '../src/trace.mjs';
import { n0Windows, n0FrameCounts } from '../src/n0.mjs';
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

// trace.mjs keeps its own copy of the split table (Lean Fw.Measure.Splits): the same slices, put on a renderer main
// thread after an F0 mark, give the golden split counts; SPLITS and N1_KEYS equal the golden table.
test('trace.mjs splits (SPLITS, N1_KEYS, containment) equal every non-refused golden of measure.splits', () => {
  const cases = load('measure.splits').filter((c) => c.response.error === undefined);
  assert.ok(cases.length > 0);
  const tsSplits = Object.entries(SPLITS).map(([name, s]) => ({ base: MAIN[name].key, key: s.spec.key, name, within: s.within }));
  for (const c of cases) {
    assert.deepStrictEqual(tsSplits, c.response.splits, c.name);
    assert.deepStrictEqual(N1_KEYS, c.response.n1Keys, c.name);
    const ts0 = Math.min(0, ...c.request.slices.map((s) => s.ts)) - 1;
    const ev = [{ ph: 'M', name: 'thread_name', pid: 1, tid: 1, args: { name: 'CrRendererMain' } },
      { ph: 'I', name: 'TimeStamp', pid: 1, tid: 1, ts: ts0, args: { data: { message: 'F0' } } },
      ...c.request.slices.map((s) => ({ ...s, pid: 1, tid: 1, args: {} }))];
    const f = traceToFrameCounts(ev, 1).perFrame[0];
    const got = Object.fromEntries(Object.keys(c.response.counts).map((k) => [k, f[k] ?? 0]));
    assert.deepStrictEqual(got, c.response.counts, c.name);
  }
});

// n0.mjs (container side) attributes census events to windows; checked against Lean Fw.Measure.Neutral.
test('n0Windows / n0FrameCounts (n0.mjs) equal every non-refused golden of measure.n0Windows', () => {
  const cases = load('measure.n0Windows').filter((c) => c.response.error === undefined);
  assert.ok(cases.length > 0);
  for (const c of cases) {
    const { events, frameVts, startVt, dt } = c.request;
    const { win, perFrame } = n0Windows(events, frameVts, startVt, dt);
    const where = (e) => (win.load.includes(e) ? 'load' : win.preroll.includes(e) ? 'preroll' : win.after.includes(e) ? 'after' : perFrame.findIndex((l) => l.includes(e)));
    assert.deepStrictEqual(events.map(where), c.response.windows, c.name);
    assert.deepStrictEqual([win.load.length, win.preroll.length, win.after.length], [c.response.load, c.response.preroll, c.response.after], c.name);
    assert.deepStrictEqual(perFrame.map(n0FrameCounts), c.response.frames, c.name);
  }
});

for (const op of ['measure.zoneSums', 'measure.classify', 'measure.noMoreWork', 'measure.selfCheck', 'measure.snapshotCounts', 'measure.freeze',
  'measure.splits', 'measure.n0Windows', 'measure.spkq', 'measure.arms', 'measure.zoneBaseline']) {
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

// freeze.mjs (the frozen class table) over synthetic downloaded workflow runs: 3 runs x 2 jobs x 2 arms, one image.
// Type `a` is identical everywhere, `b` moves one frame in run 3 (deterministic inside every run, stable pooled), `c`
// exists only in run 2 (so it is quarantined; pooled, its total gap 100 is above tMax). The rewrite arm lacks `c` and
// has `onlyR`; the original arm has the overlay-ad detector type (by design).
const OVERLAY = 'trace.HitTest.overlayAdDetector';
function fakeRuns({ images = ['sha256:i', 'sha256:i', 'sha256:i'], n = 3, tamper = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'fw-freeze-'));
  const dirs = [];
  for (let r = 0; r < n; r++) {
    const dir = join(root, `run${r}`);
    mkdirSync(join(dir, 'chromium-classes'), { recursive: true });
    for (const target of ['original', 'rewrite']) {
      const meta = { image: images[r], snapshot: 's1', servedSha256: 'f00', target, trajectorySha256: 'tr' };
      const frames = [0, 1].map((i) => ({ n: i, phase: 'swipe', scrollY: i, counts: target === 'original'
        ? { a: 1, b: r === 2 ? 1 - i : i, [OVERLAY]: i * r, ...(r === 1 ? { c: 50 } : {}) }
        : { a: 1, onlyR: 2 } }));
      const jobs = [1, 2].map(() => ({ frames, meta }));
      jobs.forEach((c, j) => {
        mkdirSync(join(dir, `chromium-counts-${target}-r${j + 1}`), { recursive: true });
        writeFileSync(join(dir, `chromium-counts-${target}-r${j + 1}`, 'counts.json'), JSON.stringify(c));
        writeFileSync(join(dir, `chromium-counts-${target}-r${j + 1}`, 'image-id.txt'), `${images[r]}\n`);
      });
      const classes = classify(jobs, 4, 24);
      if (tamper && r === 0 && target === 'original') classes.a.class = 'stable';
      mkdirSync(join(dir, 'chromium-classes', target));
      writeFileSync(join(dir, 'chromium-classes', target, 'classes.json'), JSON.stringify(classes));
    }
    writeFileSync(join(dir, 'chromium-classes', 'run.txt'), `profile swipe-v1, workflow run ${100 + r}, attempt 1, sha abc\n`);
    writeFileSync(join(dir, 'chromium-classes', 'image-inputs.txt'), 'd0  Dockerfile\nd1  docker/apt-manifest.txt\n');
    dirs.push(dir);
  }
  return dirs;
}

test('freeze.mjs: worst class over 3 runs through fwcore measure.freeze; a type missing from a run is quarantined; roles and cross-arm from Lean', () => {
  const f = freezeRuns(fakeRuns(), { builtBy: 100, dockerfile: '/nonexistent' });
  const p = f.profiles['swipe-v1'];
  assert.deepStrictEqual(p.workflowRuns, ['100', '101', '102']);
  const o = p.arms.original;
  assert.deepStrictEqual(o.workflowRuns, ['100', '101', '102']);
  assert.equal(o.image, 'sha256:i');
  assert.equal(o.jobsPerRun, 2);
  const det3 = ['deterministic', 'deterministic', 'deterministic'];
  assert.deepStrictEqual(o.types.a, { class: 'deterministic', k: 0, t: 0, perRun: det3, role: 'gate', pooledClass: 'deterministic' });
  assert.deepStrictEqual(o.types.b, { class: 'deterministic', k: 0, t: 0, perRun: det3, role: 'gate', pooledClass: 'stable' });
  assert.deepStrictEqual(o.types.c, { class: 'quarantined', k: 0, t: 0, perRun: ['missing', 'deterministic', 'missing'], role: 'finding', pooledClass: 'quarantined' });
  assert.equal(o.types[OVERLAY].role, 'byDesign');
  assert.ok(o.types[OVERLAY].reason);
  assert.deepStrictEqual(o.roles, { gate: 2, finding: 1, byDesign: 1 });
  assert.deepStrictEqual(o.tally, { deterministic: 3, stable: 0, quarantined: 1 });
  assert.deepStrictEqual(p.arms.rewrite.tally, { deterministic: 2, stable: 0, quarantined: 0 });
  // cross-arm: `c` is on A only (A decides: quarantined, a finding); `onlyR` on R only (R decides: deterministic, a gate)
  assert.equal(p.crossArm.types.c.r, 'absent');
  assert.equal(p.crossArm.types.c.class, 'quarantined');
  assert.equal(p.crossArm.types.onlyR.a, 'absent');
  assert.equal(p.crossArm.types.onlyR.class, 'deterministic');
  assert.ok(p.crossArm.gates.includes('onlyR') && !p.crossArm.gates.includes('c') && !p.crossArm.gates.includes(OVERLAY));
  assert.deepStrictEqual(f.harness, { commit: 'abc', note: 'every workflow run below ran this commit; fwcore was built from it by the same workflow' });
  assert.equal(f.image.builtByRun, '100');
  assert.equal(f.image.baseImage, undefined);
});

test('freeze.mjs refuses 2 runs, mixed image digests, and a classes artifact fwcore does not reproduce', () => {
  assert.throws(() => freezeRuns(fakeRuns({ n: 2 })), /need at least 3 workflow runs/);
  assert.throws(() => freezeRuns(fakeRuns({ images: ['sha256:i', 'sha256:j', 'sha256:i'] })), /mixed image digests/);
  assert.throws(() => freezeRuns(fakeRuns({ tamper: true })), /differs from the run's original classes.json/);
});

test('diffPaths lists the differing leaves', () => {
  assert.deepStrictEqual(diffPaths({ a: 1, b: { c: [1, 2] } }, { a: 1, b: { c: [1, 3] }, d: 0 }), ['$.b.c.1: 2 -> 3', '$.d: undefined -> 0']);
});

// The committed cross-shard baseline is fwcore measure.zoneBaseline over the committed zones file and the current frozen
// table (zone-baseline.mjs baseline --check). After a refreeze of classes.frozen.json this fails until it is re-run.
test('results/baselines/chromium/swipe-v1/original.baseline.json is the Lean baseline of the committed zones and frozen table', () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const r = spawnSync(process.execPath, [join(here, '../src/zone-baseline.mjs'), 'baseline', '--out', join(here, '../../../results/baselines/chromium'), '--check']);
  assert.equal(r.status, 0, `stale baseline (re-run: node packages/measure-chromium/src/zone-baseline.mjs baseline --out results/baselines/chromium): ${r.stderr}`);
  const b = JSON.parse(readFileSync(join(here, '../../../results/baselines/chromium/swipe-v1/original.baseline.json'), 'utf8'));
  assert.deepStrictEqual(b.runs, ['r1', 'r2', 'r3']);
  assert.deepStrictEqual(b.detDrift, []);
  for (const z of b.zones) for (const c of Object.values(z.types)) assert.ok(c.lo <= c.base && c.base <= c.hi && c.perRun.includes(c.base));
});
