import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  BAND, FILE_OF, MIN_READ, PARK_ARMS, PARK_FW, PARK_KEYS, decideParkJob, isParkMode, jobLinesS, overallLinesS, overallP, overallS, park, parkMode, split,
} from '../src/scroll-park.mjs';
import { decideDirsS, rowsOfRunS } from '../src/scroll-park-cli.mjs';
import { MODES, headerOf } from '../src/accel-cli.mjs';
import { probeSource } from '../src/mid-page.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/scroll-park-verdict.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  assert.equal(BAND, k.band);
  assert.equal(MIN_READ, k.minRead);
});

test('split verdicts equal the Lean split on every case', () => {
  assert.ok(of('split').length >= 12);
  for (const l of of('split')) assert.equal(split({ full: l.full, minusF: l.minusF, onlyF: l.onlyF, base: l.base }), l.verdict, l.name);
});

test('park verdicts equal the Lean park on every case', () => {
  assert.ok(of('park').length >= 9);
  for (const l of of('park')) assert.equal(park(l.on, l.off), l.verdict, l.name);
});

test('overall lines equal the Lean overall', () => {
  assert.ok(of('overallS').length >= 4 && of('overallP').length >= 4);
  for (const l of of('overallS')) assert.equal(overallS(l.verdicts), l.overall, l.name);
  for (const l of of('overallP')) assert.equal(overallP(l.verdicts), l.overall, l.name);
});

test('modes: seven builds, each a registered flag combination, all with the threaded pref off', () => {
  assert.deepEqual(PARK_KEYS, ['v2p', 'nohero', 'nout', 'base', 'hp', 'up', 'both']);
  for (const k of PARK_KEYS) {
    assert.equal(MODES[parkMode(k)], PARK_FW[k]);
    assert.ok(isParkMode(parkMode(k)));
    assert.match(headerOf(parkMode(k), 'h'), /ThreadedTimeBasedAnimationsEnabled=false/);
  }
  assert.ok(!isParkMode('probe-v2p-thr-off'));
  const fw = (k) => new Set(PARK_FW[k].split(','));
  assert.ok(fw('v2p').has('hero.exit:threaded') && fw('v2p').has('engine.scroll:unthrottle'));
  assert.ok(!fw('nohero').has('hero.exit:threaded') && fw('nohero').has('engine.scroll:unthrottle'));
  assert.ok(fw('nout').has('hero.exit:threaded') && !fw('nout').has('engine.scroll:unthrottle'));
  assert.ok(!fw('base').has('hero.exit:threaded') && !fw('base').has('engine.scroll:unthrottle'));
  assert.ok(fw('both').has('hero.exit:threaded-park') && fw('both').has('engine.scroll:unthrottle-park'));
});

test('the page probe carries the end and mid idle arms and the mid-page scroll', () => {
  const src = probeSource({ mode: 'timed', arms: PARK_ARMS });
  assert.deepEqual(PARK_ARMS, ['rs-idle-pbpd', 'rs-idle-pbpm']);
  assert.match(src, /pbpm/);
  assert.match(src, /toAt/);
});

const pb = (n, r) => ({ n, r, u: n, ms: n * 16, src: 'raf', w: n });
const row = (arm, perFrame, frames = 576) => ({ arm, rs: { kt: [], reps: 12, pb: Array.from({ length: 12 }, () => pb(frames / 12, (perFrame * frames) / 12 / 100)), dn: [] } });
const report = (endRate, midRate, frames) => ({ rows: [row('rs-idle-pbpd', endRate, frames), row('rs-idle-pbpm', midRate, frames)] });

const reports = (rates, frames = 576) =>
  Object.fromEntries(PARK_KEYS.map((k) => [k, report(rates[k][0], rates[k][1], frames)]));
const SHARED = { v2p: [102, 102], nohero: [102, 102], nout: [102, 102], base: [4, 4], hp: [102, 102], up: [102, 102], both: [4, 4] };

test('a job where each flag keeps the floor alone: both shared, one park alone none, both parks cut', () => {
  const d = decideParkJob(reports(SHARED));
  assert.deepEqual(d.splits.map((s) => s.v), ['shared', 'shared', 'shared', 'shared']);
  assert.deepEqual(d.parks.map((p) => `${p.key}:${p.v}`), ['hp:none', 'up:none', 'both:cut', 'hp:none', 'up:none', 'both:cut']);
});

test('a job where one flag alone holds the floor is sole', () => {
  const r = { ...SHARED, nohero: [4, 4], nout: [102, 102] };
  const d = decideParkJob(reports(r));
  const hero = d.splits.find((s) => s.flag === 'hero.exit:threaded' && s.arm === 'idle-pbpd');
  assert.equal(hero.v, 'sole');
  const ut = d.splits.find((s) => s.flag === 'engine.scroll:unthrottle' && s.arm === 'idle-pbpd');
  assert.equal(ut.v, 'innocent');
});

test('unequal frames or short arms are unread', () => {
  const short = reports(SHARED, 100);
  assert.ok(decideParkJob(short).splits.every((s) => s.v === 'unread'));
  const rep = reports(SHARED);
  rep.both = report(4, 4, 570);
  assert.equal(decideParkJob(rep).parks.find((p) => p.key === 'both' && p.arm === 'idle-pbpd').v, 'unread');
});

test('lines name the arm, the flag and the verdict, and the overall line pools the jobs', () => {
  const a = jobLinesS('j1', reports(SHARED));
  assert.ok(a.lines.some((l) => /scroll-park-split j1 end-of-page idle hero.exit:threaded: .*verdict shared$/.test(l)));
  assert.ok(a.lines.some((l) => /scroll-park-effect j1 mid-page idle both parks: .*verdict cut$/.test(l)));
  const all = overallLinesS([a.d, jobLinesS('j2', reports(SHARED)).d, jobLinesS('j3', reports(SHARED)).d]);
  assert.ok(all.some((l) => /scroll-park-effect overall end-of-page idle both parks: cut \(jobs cut \| cut \| cut\)/.test(l)));
  assert.ok(all.some((l) => /scroll-park-split overall mid-page idle engine.scroll:unthrottle: shared/.test(l)));
});

test('the cli reads a job directory and lists the rows of a run', () => {
  const dir = mkdtempSync(join(tmpdir(), 'scroll-park-'));
  try {
    const run = join(dir, 'run');
    const job = join(run, 'wktr-j1');
    mkdirSync(job, { recursive: true });
    const reps = reports(SHARED);
    for (const k of PARK_KEYS) writeFileSync(join(job, FILE_OF(k)), JSON.stringify({ rows: reps[k].rows.map((r) => ({ ...r, rs: { ...r.rs, dn: [{}] } })) }));
    const out = decideDirsS([job]);
    assert.equal(out.jobs.length, 1);
    assert.ok(out.lines.some((l) => /scroll-park-effect overall/.test(l)));
    const rows = rowsOfRunS(run);
    assert.equal(rows.length, PARK_KEYS.length * 2);
    assert.match(rows[0], /^wktr-j1 accel-park-v2p-thr-off-1.json rows\[0\] rs-idle-pbpd: frames 576 recalcs/);
    assert.match(decideDirsS(['/nonexistent-dir']).lines[0], /no result file/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
