// The tables of the smoothness-webkit-cadence lane (src/profile/report.mjs) on synthetic leg files; the decisions under them are
// golden-checked in profile.test.mjs.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { KINDS } from '../src/profile/reduce.mjs';
import { jobCell, jobVerdicts, acrossJobs, legSummary, headlineTable, verdictTable, fillBlocks, loadRuns, reportMain, minutesTable } from '../src/profile/report.mjs';

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

test('acrossJobs: two thirds of the jobs, none against', () => {
  const v = acrossJobs([{ 'a|b': 'first' }, { 'a|b': 'first' }, { 'a|b': 'same' }]);
  assert.equal(v['a|b'].verdict, 'first');
  assert.equal(acrossJobs([{ 'a|b': 'first' }, { 'a|b': 'second' }, { 'a|b': 'first' }])['a|b'].verdict, 'same');
  assert.equal(acrossJobs([{ 'a|b': 'first' }, { 'a|b': 'first' }])['a|b'].verdict, 'insufficient');
});

test('legSummary and the tables: class counts need three jobs, the headline lists every arm', () => {
  const jobs = ['1:a', '2:a', '3:a'].map((label, i) => ({ label, leg: 'mac', file: fileOf({ orig: 100 + i, base: 200, aa: 200 }) }));
  const calls = [];
  const leg = legSummary(jobs, (runs, k, t) => { calls.push([runs.length, k, t]); return { Layout: { class: 'stable', k: 1, t: 1 } }; });
  assert.deepEqual(calls[0], [3, 4, 24]);
  assert.equal(leg.zones.hero.verdicts['orig|base'].verdict, 'first');
  assert.match(headlineTable(leg), /\| orig \| 3 \| 15 \| 30 \|/);
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
  const r = await reportMain({ runs: dir, out, note, minutesFile: join(dir, 'none.json'), classify: () => ({}) });
  assert.equal(r.jobs, 3);
  assert.deepEqual(r.skipped.map((s) => s.run), ['14:smoothness-webkit-mac']);
  assert.match(readFileSync(note, 'utf8'), /hero \| orig, base/);
  assert.match(readFileSync(join(out, 'tables.md'), 'utf8'), /gen:mac-headline/);
  assert.equal(loadRuns(dir).files.length, 3);
});

test('minutesTable lists the runs and the median per leg', () => {
  const t = minutesTable([{ run: 1, leg: 'mac', job: 'm', minutes: 9 }, { run: 2, leg: 'mac', job: 'm', minutes: 11 }, { run: 1, leg: 'sim', job: 's', minutes: 30 }]);
  assert.match(t, /\| median \| mac \|  \| 11 \|/);
  assert.match(t, /\| median \| sim \|  \| 30 \|/);
});
