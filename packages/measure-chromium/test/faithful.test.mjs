// Conformance: the faithful.verdict and faithful.comparable golden vectors (generated from Lean, packages/contracts/golden/faithful/)
// through the fwcore binary, the region helper of src/faithful.mjs, and the two named refusals of the verdict tool (NO DATA, not
// comparable: exit 1, no verdict). Needs lean/.lake/build/bin/fwcore (cd lean && lake build).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { fwcoreBin } from '../src/fwcore.mjs';
import { PROFILES, REGION, regionOf, summarize, verdictRun, metaOf, load } from '../src/faithful.mjs';

const GOLDEN = join(dirname(fileURLToPath(import.meta.url)), '../../contracts/golden/faithful');
const read = (f) => readFileSync(join(GOLDEN, f), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const cases = read('faithful.verdict.jsonl');
const cmpCases = read('faithful.comparable.jsonl');
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const RUNS = join(ROOT, 'results/faithful/runs');
const OUT = join(ROOT, 'results/faithful');

function replies(cases) {
  const input = cases.map((c, i) => JSON.stringify({ ...c.request, id: i })).join('\n') + '\n';
  const r = spawnSync(fwcoreBin(), [], { input, env: { ...process.env, LEAN_ABORT_ON_PANIC: '1' }, maxBuffer: 1 << 28 });
  assert.equal(r.status, 0, `fwcore exit: ${r.stderr}`);
  assert.equal(r.stderr.length, 0, `fwcore stderr: ${r.stderr}`);
  return r.stdout.toString().trim().split('\n').map((l, i) => { const { id, ...rest } = JSON.parse(l); assert.equal(id, i); return rest; });
}

test('every faithful.verdict golden equals the fwcore reply', () => {
  assert.ok(cases.length >= 10);
  const got = replies(cases);
  cases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
});

test('the goldens pin both outcomes and the refusal', () => {
  const pass = cases.filter((c) => c.response.pass === true).length;
  const fail = cases.filter((c) => c.response.pass === false).length;
  const err = cases.filter((c) => c.response.error !== undefined).length;
  assert.ok(pass >= 2 && fail >= 5 && err === 1, `pass ${pass} fail ${fail} error ${err}`);
});

test('regionOf keeps exactly the region zones, in file order', () => {
  const zones = ['rest', 'y03500', 'tail', 'y04000', 'y04500'].map((id) => ({ id }));
  assert.deepStrictEqual(regionOf({ zones }).map((z) => z.id), ['tail', 'y04000', 'y04500']);
  assert.deepStrictEqual(REGION, ['y04000', 'y04500', 'tail']);
});

test('summarize lists failed cells and unbanded differences only', () => {
  const v = { pass: false, failedZones: ['tail'], zones: [{ id: 'tail', present: true, shape: true, pass: false, framesA: 3, framesR: 3,
    pxA: 0, pxR: 0, tally: {}, failed: ['x'], cells: { x: { family: 'exact', status: 'fail', lo: 1, hi: 1, a: 1, r: 2 },
      y: { family: 'unbanded', status: 'unbanded', lo: 1, hi: 1, a: 1, r: 1 }, z: { family: 'unbanded', status: 'unbanded', lo: 1, hi: 1, a: 1, r: 4 },
      p: { family: 'exact', status: 'pass', lo: 1, hi: 1, a: 1, r: 1 } } }] };
  const s = summarize(v).zones[0];
  assert.deepStrictEqual(s.offBand.map((c) => c.type), ['x']);
  assert.deepStrictEqual(s.unbandedDiffs, [{ type: 'z', a: 1, r: 4 }]);
});

test('every faithful.comparable golden equals the fwcore reply, and the goldens pin every field and the 645 px run', () => {
  const got = replies(cmpCases);
  cmpCases.forEach((c, i) => assert.deepStrictEqual(got[i], c.response, c.name));
  const fields = new Set(cmpCases.map((c) => c.response.field).filter(Boolean));
  assert.deepStrictEqual([...fields].sort(), ['browser', 'preset', 'profile', 'viewport', 'zoneHeightPx']);
  assert.ok(cmpCases.some((c) => c.response.comparable === true) && cmpCases.some((c) => c.response.error !== undefined));
  assert.equal(cmpCases.find((c) => c.name.startsWith('the 645')).response.field, 'viewport');
});

function scratch(fn) {
  const dir = mkdtempSync(join(tmpdir(), 'fwfaithful-'));
  try { return fn(dir); } finally { rmSync(dir, { recursive: true, force: true }); }
}
const editJson = (path, f) => { const j = JSON.parse(readFileSync(path, 'utf8')); f(j); writeFileSync(path, JSON.stringify(j)); };

test('the two cited runs are comparable and reproduce the committed verdict files byte for byte', () => {
  const r = verdictRun({ runs: RUNS, out: OUT, check: true });
  assert.equal(r.code, 0, r.lines.join('\n'));
  assert.deepStrictEqual(r.lines.map((l) => l.split(':')[0]), ['identical', 'identical']);
  for (const p of PROFILES) {
    const d = load(p, RUNS);
    assert.equal(metaOf(d.R).observed.width, 430);
    assert.equal(metaOf(d.A).observed.width, 430, 'the font-image frozen original records its observed viewport');
  }
});

test('a profile with no rewrite baseline prints NO DATA, records no verdict and exits 1', () => scratch((dir) => {
  const runs = join(dir, 'runs');
  cpSync(join(RUNS, 'swipe-v1'), join(runs, 'swipe-v1'), { recursive: true });
  const out = join(dir, 'out');
  const r = verdictRun({ runs, out });
  assert.equal(r.code, 1);
  assert.ok(r.lines.some((l) => l.startsWith('NO DATA: swipe-touch-v1')), r.lines.join('\n'));
  const f = JSON.parse(readFileSync(join(out, 'swipe-touch-v1.verdict.json'), 'utf8'));
  assert.equal(f.verdict, null);
  assert.equal(f.refusal.kind, 'no-data');
  assert.equal(JSON.parse(readFileSync(join(out, 'swipe-v1.verdict.json'), 'utf8')).refusal, undefined);
}));

test('a rewrite measured at another layout viewport (the 645 x 1398 run) is not comparable: viewport, exit 1, no verdict', () => scratch((dir) => {
  cpSync(RUNS, dir, { recursive: true });
  editJson(join(dir, 'swipe-v1/rewrite.baseline.json'), (j) => { j.source.innerWidthPx = 645; j.source.innerHeightPx = 1398; });
  const r = verdictRun({ runs: dir, out: join(dir, 'out') });
  assert.equal(r.code, 1);
  assert.ok(r.lines.some((l) => l.startsWith('not comparable: viewport')), r.lines.join('\n'));
  const f = JSON.parse(readFileSync(join(dir, 'out/swipe-v1.verdict.json'), 'utf8'));
  assert.equal(f.verdict, null);
  assert.deepStrictEqual(f.refusal, { kind: 'not-comparable', field: 'viewport', text: f.refusal.text });
  assert.notEqual(JSON.parse(readFileSync(join(dir, 'out/swipe-touch-v1.verdict.json'), 'utf8')).verdict, null, 'the other profile is judged on its own');
}));

test('a rewrite that recorded no observed viewport, another browser or another preset is refused by field', () => {
  const cases = [
    [(s) => { delete s.innerWidthPx; delete s.innerHeightPx; }, 'viewport'],
    [(s) => { s.browser = 'HeadlessChrome/157.0.0.0'; }, 'browser'],
    [(s) => { s.preset = 'rewrite'; }, 'preset'],
    [(s) => { s.zoneHeightPx = 400; }, 'zoneHeightPx'],
    [(s) => { s.viewport = { ...s.viewport, touch: false }; }, 'viewport'],
  ];
  for (const [edit, field] of cases) scratch((dir) => {
    cpSync(RUNS, dir, { recursive: true });
    editJson(join(dir, 'swipe-v1/rewrite.baseline.json'), (j) => edit(j.source));
    const r = verdictRun({ runs: dir, out: join(dir, 'out'), profiles: ['swipe-v1'] });
    assert.equal(r.code, 1, field);
    assert.ok(r.lines[0].startsWith(`not comparable: ${field}:`), r.lines.join('\n'));
  });
});

test('the CLI exits 1 on a refusal and 0 when every profile has a Lean verdict', () => scratch((dir) => {
  const cli = join(dirname(fileURLToPath(import.meta.url)), '../src/faithful.mjs');
  const runs = join(dir, 'runs');
  cpSync(join(RUNS, 'swipe-v1'), join(runs, 'swipe-v1'), { recursive: true });
  const bad = spawnSync('node', [cli, 'verdict', '--runs', runs, '--out', join(dir, 'out')]);
  assert.equal(bad.status, 1);
  assert.match(bad.stderr.toString(), /^NO DATA: swipe-touch-v1/m);
  const ok = spawnSync('node', [cli, 'verdict', '--check']);
  assert.equal(ok.status, 0, ok.stderr.toString());
}));
