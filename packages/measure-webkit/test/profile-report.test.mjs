import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { KINDS, profileWindow } from '../src/profile/reduce.mjs';
import { medianNat } from '../src/profile/reduce.mjs';
import { writeRaws } from '../src/profile/raw.mjs';
import { jobCell, poolCell, runTable, armWindows, cadenceTable, kindTable, jobVerdicts, acrossJobs, legSummary, touchTable, isControl, headlineTable, verdictTable, ratioTable, fillBlocks, loadRuns, rereduce, reportMain, minutesTable, minutesOf } from '../src/profile/report.mjs';

const zero = () => KINDS.map((k) => [k, 0, 0]);
const prof = (frames, perFrame, layout) => ({ frames, work: perFrame * frames / 10, perFrame, cells: zero().map((c) => (c[0] === 'Layout' ? ['Layout', layout, layout * 10] : c)) });
const empty = () => ({ frames: 0, work: 0, perFrame: 0, cells: zero() });
function fileOf(perFrameByArm, { leg = 'mac', reps = 5 } = {}) {
  const arms = Object.keys(perFrameByArm);
  const rows = [];
  for (const a of arms) for (let rep = 0; rep < reps; rep++) {
    rows.push({ arm: a, window: 'hero', rep, mode: 'events', ok: true, ivs: [160, 170, 700], hitches: 1, profiles: { hero: prof(30, perFrameByArm[a] + rep, 4), rest: empty(), finish: empty() } });
  }
  return { leg, engine: 'x', version: '1', arms, plan: { kept: arms, dropped: [], flags: {} }, rows, wallSeconds: 10 };
}

test('jobCell: medians over the kept windows of a zone; a zone without frames has no cell', () => {
  const f = fileOf({ base: 100, aa: 100 });
  const c = jobCell(f, 'base', 'hero');
  assert.equal(c.reps, 5);
  assert.equal(c.frames, 30);
  assert.equal(c.perFrame, 102);
  assert.equal(c.kinds.Layout.n, 4);
  assert.equal(jobCell(f, 'base', 'finish').reps, 0);
});

test('jobVerdicts: first when the first arm does less in every window, same against a noisy A/A pair', () => {
  const f = fileOf({ orig: 100, base: 200, aa: 200 });
  assert.equal(jobVerdicts(f, 'hero')['orig|base'], 'first');
  const g = fileOf({ orig: 100, base: 200, aa: 100 });
  assert.equal(jobVerdicts(g, 'hero')['orig|base'], 'same');
  const few = fileOf({ orig: 100, base: 200, aa: 200 }, { reps: 4 });
  assert.equal(jobVerdicts(few, 'hero')['orig|base'], 'insufficient');
});

test('acrossJobs: two thirds of the decisive jobs, none against', () => {
  const v = acrossJobs([{ 'a|b': 'first' }, { 'a|b': 'first' }, { 'a|b': 'same' }]);
  assert.equal(v['a|b'].verdict, 'first');
  assert.equal(acrossJobs([{ 'a|b': 'first' }, { 'a|b': 'second' }, { 'a|b': 'first' }])['a|b'].verdict, 'same');
  assert.equal(acrossJobs([{ 'a|b': 'first' }, { 'a|b': 'first' }])['a|b'].verdict, 'insufficient');
  const d = acrossJobs([{ 'a|b': 'first' }, { 'a|b': 'first' }, { 'a|b': 'first' }, { 'a|b': 'insufficient' }, { 'a|b': 'insufficient' }])['a|b'];
  assert.deepEqual([d.jobs, d.need, d.verdict], [5, 2, 'first']);
});

test('legSummary and the tables: class counts need three jobs, the headline lists every arm', () => {
  const jobs = ['1:a', '2:a', '3:a'].map((label, i) => ({ label, leg: 'mac', file: fileOf({ orig: 100 + i, base: 200, aa: 200 }) }));
  const calls = [];
  const leg = legSummary(jobs, (runs, k, t) => { calls.push([runs.length, k, t]); return { Layout: { class: 'stable', k: 1, t: 1 } }; });
  assert.deepEqual(calls[0], [3, 4, 24]);
  assert.equal(leg.zones.hero.verdicts['orig|base'].verdict, 'first');
  assert.match(headlineTable(leg), /\| orig \| 15 \(5\+5\+5\) \| 30 \|/);
  assert.match(verdictTable(leg), /hero \| orig, base \| 3 \| 3 \| 0 \| 0 \| 0 \| first/);
  const two = legSummary(jobs.slice(0, 2), () => { throw new Error('classified two jobs'); });
  assert.equal(two.zones.hero.classes.orig, null);
});

test('fillBlocks replaces a marked block and names the missing ones', () => {
  const r = fillBlocks('a\n<!-- gen:x -->\nold\n<!-- /gen:x -->\nb', { x: 'new', y: 'z' });
  assert.equal(r.text, 'a\n<!-- gen:x -->\nnew\n<!-- /gen:x -->\nb');
  assert.deepEqual(r.missing, ['y']);
});

test('reportMain reads <runs>/<id>/<artifact>/mac.json, skips refused files, writes tables and fills the note', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'wkrep-'));
  for (const id of ['11', '12', '13']) {
    mkdirSync(join(dir, id, 'smoothness-webkit-mac'), { recursive: true });
    writeFileSync(join(dir, id, 'smoothness-webkit-mac', 'mac.json'), JSON.stringify(fileOf({ orig: 100, base: 200, aa: 200 })));
  }
  mkdirSync(join(dir, '14', 'smoothness-webkit-mac'), { recursive: true });
  writeFileSync(join(dir, '14', 'smoothness-webkit-mac', 'mac.json'), JSON.stringify({ ...fileOf({ orig: 1, base: 1, aa: 1 }), refused: true }));
  const note = join(dir, 'note.md');
  writeFileSync(note, '# n\n<!-- gen:mac-verdict -->\n<!-- /gen:mac-verdict -->\n');
  const out = join(dir, 'out');
  const r = await reportMain({ runs: dir, out, note, jobsDir: join(dir, "none"), classify: () => ({}) });
  assert.equal(r.jobs, 3);
  assert.deepEqual(r.skipped.map((s) => s.run), ['14:smoothness-webkit-mac']);
  assert.match(readFileSync(note, 'utf8'), /hero \| orig, base/);
  assert.match(readFileSync(join(out, 'tables.md'), 'utf8'), /gen:mac-headline/);
  assert.equal(loadRuns(dir).files.length, 3);
});

test('minutesOf reads the WebKit jobs of gh run view; minutesTable gives the median, the longest and the billed minutes', () => {
  const at = (a, b) => ({ startedAt: `2026-10-21T10:${a}:00Z`, completedAt: `2026-10-21T10:${b}:30Z` });
  const m = minutesOf({
    2: { jobs: [{ name: 'guard', ...at('00', '01') }, { name: 'webkit mac (playwright-webkit, macos-26)', conclusion: 'success', ...at('10', '20') }] },
    1: { jobs: [{ name: 'webkit mac (playwright-webkit, macos-26)', conclusion: 'success', ...at('00', '08') }, { name: 'webkit sim (mobile safari, xcode-27)', conclusion: 'failure', ...at('00', '14') }] },
  });
  assert.deepEqual(m.map((r) => [r.run, r.leg, r.conclusion, r.minutes]), [['1', 'mac', 'success', 8.5], ['1', 'sim', 'failure', 14.5], ['2', 'mac', 'success', 10.5]]);
  const t = minutesTable(m);
  assert.match(t, /\| median of successes \| mac \|  \| n=2 \| 9\.5 \|/);
  assert.match(t, /\| longest success \| mac \|  \|  \| 10\.5 \|/);
  assert.match(t, /\| all jobs billed \| sim \|  \| n=1 \|  \| 15 \|/);
  assert.equal(minutesTable([]), 'no job minutes were recorded');
});

test('loadRuns re-reduces the event windows from <leg>.raw.json.gz, so the tables follow the reducer, not the leg\'s own profiles', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wkraw-'));
  mkdirSync(join(dir, '5', 'smoothness-webkit-mac-1'), { recursive: true });
  const recs = [
    { type: 'TimeStamp', startTime: 10, endTime: 10, data: { message: 'wk:a' } },
    { type: 'Layout', startTime: 10.01, endTime: 10.011 },
    { type: 'Composite', startTime: 10.012, endTime: 10.9 },
    { type: 'TimeStamp', startTime: 10.02, endTime: 10.02, data: { message: 'wk:b' } },
  ];
  const page = { frames: [[100000, 0], [101000, 500]], vh10: 8440, maxY10: 21000, w0: 100000, w1: 102000, marks: { a: 100000, b: 102000 } };
  const w = profileWindow(page, recs);
  const stale = { arm: 'orig', window: 'hero', rep: 0, mode: 'events', ok: true, ivs: [160], hitches: 0, profiles: { hero: { frames: 2, work: 999999, perFrame: 1, span: 1, cells: [] } } };
  const res = { leg: 'mac', engine: 'x', arms: ['orig'], plan: { kept: ['orig'], dropped: [], flags: {} }, rows: [stale], raws: [{ arm: 'orig', window: 'hero', rep: 0, raw: w.raw }], wallSeconds: 1 };
  writeFileSync(join(dir, '5', 'smoothness-webkit-mac-1', 'mac.json'), JSON.stringify(writeRaws(join(dir, '5', 'smoothness-webkit-mac-1'), 'mac', res)));
  const got = loadRuns(dir).files[0];
  assert.equal(got.label, '5:smoothness-webkit-mac-1');
  assert.deepEqual(got.file.rows[0].profiles, w.profiles);
  assert.ok(got.file.rows[0].profiles.hero.work <= got.file.rows[0].profiles.hero.span);
  assert.equal(got.file.rows[0].profiles.hero.cells.find((c) => c[0] === 'Composite')[2], 0);
  const f = { rows: [stale] };
  rereduce(f, []);
  assert.equal(f.rows[0].profiles.hero.work, 999999);
});

test('ratioTable: computed from the pooled medians, orig over base and base over its A/A copy', () => {
  const jobs = ['1:a', '2:a', '3:a'].map((label) => ({ label, leg: 'mac', file: fileOf({ orig: 400, base: 100, aa: 100 }) }));
  const leg = legSummary(jobs, () => ({}));
  assert.match(ratioTable(leg), /\| render work us \/ frame \| 402 \| 102 \| 102 \| 3\.9 \| 1\.0 \|/);
  assert.match(ratioTable(leg), /\| Composite n \| 0 \| 0 \| 0 \| - \| - \|/);
});

test('bound arm (task earn-bound-arm): base|bound is judged against the A/A pair; the ratio column shows only when the arm ran', () => {
  const less = fileOf({ base: 200, aa: 200, bound: 100 });
  assert.equal(jobVerdicts(less, 'hero')['base|bound'], 'second');
  const noise = fileOf({ base: 200, aa: 100, bound: 100 });
  assert.equal(jobVerdicts(noise, 'hero')['base|bound'], 'same');
  const jobs = ['1:a', '2:a', '3:a'].map((label) => ({ label, leg: 'mac', file: fileOf({ base: 200, aa: 200, bound: 100 }) }));
  const leg = legSummary(jobs, () => ({}));
  assert.equal(leg.zones.hero.verdicts['base|bound'].verdict, 'second');
  assert.match(ratioTable(leg), /\| metric \| base \| aa \| bound \| orig \/ base \| base \/ aa \| bound \/ base \|/);
  assert.match(ratioTable(leg), /\| render work us \/ frame \| 202 \| 202 \| 102 \| - \| 1\.0 \| 0\.5 \|/);
  const none = legSummary(['1:a', '2:a', '3:a'].map((label) => ({ label, leg: 'mac', file: fileOf({ orig: 400, base: 100, aa: 100 }) })), () => ({}));
  assert.doesNotMatch(ratioTable(none), /bound/);
});


const golden = readFileSync(new URL('../../contracts/golden/measure/webkit-profile.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const fileOfValues = (values) => ({
  leg: 'mac', engine: 'x', version: '1', arms: ['base'], plan: { kept: ['base'], dropped: [], flags: {} }, wallSeconds: 1,
  rows: values.map((v, rep) => ({ arm: 'base', window: 'hero', rep, mode: 'events', ok: true, ivs: [160], hitches: 0, profiles: { hero: prof(30, v, 4), rest: empty(), finish: empty() } })),
});
const jobsOf = (...lists) => lists.map((l, i) => ({ label: `${i}:a`, leg: 'mac', file: fileOfValues(l) }));

test('poolCell: jobs with 5 and 1 windows give the median of the 6-window list (index 3), not the 1-window job\'s value', () => {
  const jobs = jobsOf([10, 20, 30, 40, 50], [1000]);
  const c = poolCell(jobs, 'base', 'hero');
  assert.deepEqual(armWindows(jobs, 'base', 'hero').map((p) => p.perFrame), [10, 20, 30, 40, 50, 1000]);
  assert.equal(c.reps, 6);
  assert.deepEqual(c.split, [5, 1]);
  assert.equal(c.perFrame, 40);
  assert.equal(c.frames, 30);
  assert.notEqual(c.perFrame, jobCell(jobs[1].file, 'base', 'hero').perFrame);
});

test('poolCell equals the Lean medianNat golden on the concatenation of the windows, however the list is split over jobs', () => {
  const cases = golden.filter((c) => c.kind === 'median' && c.values.length > 0);
  assert.ok(cases.length >= 4);
  for (const c of cases) {
    for (let cut = 0; cut <= c.values.length; cut++) {
      const jobs = jobsOf(c.values.slice(0, cut), c.values.slice(cut));
      assert.equal(poolCell(jobs, 'base', 'hero').perFrame, c.median, `${JSON.stringify(c.values)} cut ${cut}`);
      assert.equal(medianNat(armWindows(jobs, 'base', 'hero').map((p) => p.perFrame)), c.median);
    }
  }
});

test('headlineTable, kindTable, ratioTable: a cell with 4 pooled windows prints insufficient (n=4), 5 prints the number and the split', () => {
  const four = legSummary(jobsOf([1, 2, 3], [4]).map((j) => ({ ...j, file: { ...j.file, arms: ['orig', 'base'], rows: [...j.file.rows, ...j.file.rows.map((r) => ({ ...r, arm: 'orig' }))] } })), () => ({}));
  assert.match(headlineTable(four), /\| base \| 4 \(3\+1\) \| insufficient \(n=4\) \| insufficient \(n=4\) \|/);
  assert.doesNotMatch(headlineTable(four).split('**finish**')[0], /\| base \| 4 \(3\+1\) \| 30 /);
  assert.match(kindTable(four), /\| Layout \| insufficient \(n=4\) \| insufficient \(n=4\) \|/);
  assert.match(ratioTable(four), /\| render work us \/ frame \| insufficient \(n=4\) \| insufficient \(n=4\) \| - \| - \|/);
  const five = legSummary(jobsOf([1, 2, 3], [4, 5]).map((j) => ({ ...j, file: { ...j.file, arms: ['orig', 'base'], rows: [...j.file.rows, ...j.file.rows.map((r) => ({ ...r, arm: 'orig' }))] } })), () => ({}));
  assert.match(headlineTable(five), /\| base \| 5 \(3\+2\) \| 30 \| .* \| 3 \(1-5\) \|/);
  assert.match(ratioTable(five), /\| n windows \(per job\) \| 5 \(3\+2\) \| 5 \(3\+2\) \|/);
});

test('cadenceTable: p50 and p95 are quantiles over all intervals of all jobs\' repeats, not the median of per-job quantiles', () => {
  const job = (label, ivs, n) => ({ label, leg: 'mac', file: { leg: 'mac', arms: ['base'], plan: { kept: ['base'], dropped: [], flags: {} }, rows: Array.from({ length: n }, (_, rep) => ({ arm: 'base', window: 'hero', rep, mode: 'events', ok: true, ivs, hitches: ivs.filter((x) => x > 600).length })) } });
  const leg = legSummary([job('a', [100, 100, 100, 100], 5), job('b', [900, 900, 900, 900], 1)], () => ({}));
  const row = cadenceTable(leg).split('\n').find((l) => l.startsWith('| hero | on | base'));
  assert.match(row, /\| 6 \(5\+1\) \| 0 \| - \| - \| - \| - \| - \| 10\.0 \| 90\.0 \| 90\.0 \|/);
  const few = legSummary([job('a', [100], 4)], () => ({}));
  assert.match(cadenceTable(few), /\| 4 \(4\) \| insufficient \(n=4\) \| (- \| ){5}insufficient \(n=4\) \| insufficient \(n=4\) \| insufficient \(n=4\) \|/);
});

test('cadenceTable: miss counts are totals over all reps of a pooled cell, skipped slots come from the frame times', () => {
  const th = [0, 1667, 3333, 5000, 6667, 10000];
  const ivs = [167, 167, 167, 167, 333];
  const rep = (n) => Array.from({ length: n }, (_, i) => ({ arm: 'base', window: 'end', rep: i, mode: 'events', ok: true, ivs, th, hitches: 0 }));
  const job = (label, n) => ({ label, leg: 'mac', file: { leg: 'mac', arms: ['base'], plan: { kept: ['base'], dropped: [], flags: {} }, rows: rep(n) } });
  const leg = legSummary([job('a', 3), job('b', 3)], () => ({}));
  assert.deepEqual(leg.cadence['end|events'].pool.base.counts, { frames: 30, over25: 6, over34: 0, over50: 0, skips: 6 });
  const row = cadenceTable(leg).split('\n').find((l) => l.startsWith('| end | on | base'));
  assert.match(row, /\| 6 \(3\+3\) \| 0 \| 6 \| 0 \| 0 \| 6 \| 30 \|/);
});

test('legSummary: an end window pushed by touch is its own window, the synthetic wheel ones stay in end', () => {
  const th = [0, 167, 333, 500, 667, 1000];
  const ivs = [167, 167, 167, 167, 333];
  const r = (rep, push) => ({ arm: 'base', window: 'end', rep, mode: 'events', ok: true, ivs, th, hitches: 0, push });
  const job = { label: 'a', leg: 'sim', file: { leg: 'sim', arms: ['base'], plan: { kept: ['base'], dropped: [], flags: {} }, rows: [r(0, 'touch'), r(1, 'synthetic'), r(2, 'synthetic')] } };
  const leg = legSummary([job], () => ({}));
  assert.equal(leg.cadence['end touch|events'].pool.base.reps, 1);
  assert.equal(leg.cadence['end|events'].pool.base.reps, 2);
  assert.match(cadenceTable(leg), /\| end touch \| on \| base/);
});

test('runTable: the end push column counts the touch end windows and why a Simulator job fell back to the synthetic wheel', () => {
  const end = (push) => ({ mode: 'events', window: 'end', ok: true, push });
  const f = (leg, push, rows = []) => ({ label: leg, file: { leg, engine: 'e', arms: ['base'], plan: { dropped: [] }, rows, ...(push ? { push } : {}) } });
  const table = runTable([
    f('mac'),
    f('sim', { driver: true, touch: true, why: null }, [end('touch'), end('touch')]),
    f('sim', { driver: true, touch: false, why: 'the page did not answer; driver log tail: x\n y' }, [end('touch'), end('synthetic')]),
    f('sim'),
  ]);
  const cells = table.split('\n').slice(2).map((l) => l.split(' | ').at(-2));
  assert.deepEqual(cells, ['wheel', 'touch 2 of 2 end windows', 'touch 1 of 2 end windows; then synthetic wheel: the page did not answer', 'synthetic wheel']);
});

test('minutesOf bills the minutes rounded up from the unrounded seconds: 901 s is 16, not the 15 of the 0.1-minute display', () => {
  const m = minutesOf({ 1: { jobs: [{ name: 'webkit mac (x)', conclusion: 'cancelled', startedAt: '2026-10-21T10:00:00Z', completedAt: '2026-10-21T10:15:01Z' }, { name: 'webkit mac (y)', conclusion: 'success', startedAt: '2026-10-21T10:00:00Z', completedAt: '2026-10-21T10:10:00Z' }] } });
  assert.deepEqual(m.map((r) => [r.minutes, r.billed]), [[15, 16], [10, 10]]);
  assert.match(minutesTable(m), /\| all jobs billed \| mac \|  \| n=2 \|  \| 26 \|/);
});

test('cadenceTable: the Timeline column reads the row (timeline:false), not the mode; mixed rows say mixed', () => {
  const th = [0, 167, 333, 500, 667, 1000];
  const ivs = [167, 167, 167, 167, 333];
  const r = (rep, timeline) => ({ arm: 'base', window: 'end', rep, mode: 'events', ok: false, ivs, th, hitches: 0, push: 'touch', ...(timeline === undefined ? {} : { timeline }) });
  const job = (rows) => ({ label: 'a', leg: 'sim', file: { leg: 'sim', arms: ['base'], plan: { kept: ['base'], dropped: [], flags: {} }, rows } });
  assert.match(cadenceTable(legSummary([job([r(0, false), r(1, false)])], () => ({}))), /\| end touch \| off \| base/);
  assert.match(cadenceTable(legSummary([job([r(0), r(1)])], () => ({}))), /\| end touch \| on \| base/);
  assert.match(cadenceTable(legSummary([job([r(0, false), r(1)])], () => ({}))), /\| end touch \| mixed \| base/);
  const cad = { arm: 'base', window: 'end', rep: 0, mode: 'cadence', ok: true, ivs, th, hitches: 0 };
  assert.match(cadenceTable(legSummary([job([cad])], () => ({}))), /\| end \| off \| base/);
});

test('touchTable and isControl: the control job (Safari coordinates) is told apart and its pushes are counted per outcome', () => {
  const t = (variant, outcome, beginAt, swipeAt, doneAt, moves) => ({ arm: 'base', window: 'end', mode: 'events', timeline: false, push: 'touch', touched: { variant, outcome, obs: { beginAt, swipeAt, doneAt, moves } } });
  const test = { label: '1', file: { rows: [t('springboard', 'ok', 2000, 5000, 11000, 36), t('springboard', 'ok', 4000, 6000, 12000, 30), t('springboard', 'swipeLate', 4000, 25000, 60000, 6)] } };
  const control = { label: '4', file: { rows: [t('safari', 'ok', 3000, 4000, 20000, 40)] } };
  assert.equal(isControl(test.file), false);
  assert.equal(isControl(control.file), true);
  assert.equal(isControl({ rows: [] }), false);
  const lines = touchTable([test, control]).split('\n').slice(2);
  assert.equal(lines[0], '| 1 | springboard | off | 3 | 2 | swipeLate 1 | 4000 | 6000 | 12000 | 30 |');
  assert.equal(lines[1], '| 4 | safari | off | 1 | 1 | - | 3000 | 4000 | 20000 | 40 |');
});
