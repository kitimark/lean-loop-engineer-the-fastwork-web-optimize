// The generated tables of the Linux WebKit note (src/linux/table.mjs): layout on synthetic results, the splice, and
// the committed note equals the regeneration from the committed results JSON.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BEGIN, END, aaTable, median, renderBlock, samples, splice, stepTable } from '../src/linux/table.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');

const step = (i, layout) => ({ i, delimited: true, window_ms: 500, counts: layout ? { Layout: { n: layout, ms: 1 } } : {}, frames: 3, max_gap_ms: 160 });
const reduced = (p50, records, error = null) => ({
  idle: { p50: 17, p90: 18 }, scroll: { p50, p90: p50 + 10, max: p50 + 20 }, wheel: { p50: 140 },
  timeline: { records, total: { Layout: { n: 4, ms: 2 }, TimeStamp: { n: 40, ms: 0 } }, stepsDelimited: 10, perStep: Array.from({ length: 10 }, (_, i) => step(i, 1)) },
  timelineError: null, fps: [], renderer: 'llvmpipe (LLVM 19.1.1, 128 bits)', error,
});
const file = (vm, a, b) => ({
  meta: { vm: String(vm), runId: '99' },
  runs: [{ round: 'A', arm: { id: 'orig-w390-d3', sw: null }, reduced: reduced(a, 1000) }, { round: 'B', arm: { id: 'orig-w390-d3', sw: null }, reduced: reduced(b, 1010) }],
});

test('median handles odd, even and non-numbers', () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([1, 2, 3, 4]), 2.5);
  assert.equal(median([null, 5]), 5);
  assert.equal(median([]), null);
});

test('samples separates failed runs', () => {
  const f = file(1, 150, 152);
  f.runs.push({ round: 'A', arm: { id: 'x' }, reduced: reduced(0, 0, 'boom') });
  const s = samples([f]);
  assert.equal(s.ok.length, 2);
  assert.equal(s.failed.length, 1);
});

test('A/A table: both rounds per VM and the largest relative difference', () => {
  const t = aaTable([file(1, 150, 160), file(2, 100, 100)]);
  assert.match(t, /\| `orig-w390-d3` \| 150 \/ 160 \| 100 \/ 100 \| 1000 \/ 1010 \| 1000 \/ 1010 \| 6.5 % \|/);
});

test('step table: ten rows, A and B side by side', () => {
  const t = stepTable([file(1, 150, 160)], 'orig-w390-d3');
  assert.equal(t.split('\n').filter((l) => /^\| \d+ \|/.test(l)).length, 10);
  assert.match(t, /vm1, run 99/);
  assert.match(stepTable([file(1, 150, 160)], 'nope'), /no complete A\/B pair/);
});

test('block carries every section and the failed-run list', () => {
  const f = file(1, 150, 160);
  f.runs.push({ round: 'A', arm: { id: 'bad' }, reduced: reduced(0, 0, 'timeout after 30000 ms: goto') });
  const b = renderBlock([f]);
  for (const h of ['Frame intervals', 'A/A', 'Timeline records', 'Timeline per settled step', 'Renderer string', 'Failed runs']) assert.ok(b.includes(h), h);
  assert.match(b, /timeout after 30000 ms: goto/);
});

test('splice replaces only the marked block and refuses missing or repeated markers', () => {
  const note = `head\n${BEGIN}\nold\n${END}\ntail\n`;
  assert.equal(splice(note, 'new'), `head\n${BEGIN}\nnew\n${END}\ntail\n`);
  assert.throws(() => splice('no markers', 'x'), /markers/);
  assert.throws(() => splice(`${BEGIN}${END}${BEGIN}${END}`, 'x'), /markers/);
});

test('the committed note is the regeneration of the committed results', { skip: !existsSync(join(ROOT, 'results/linux-webkit')) }, () => {
  const dir = join(ROOT, 'results/linux-webkit');
  const files = readdirSync(dir).filter((f) => f.endsWith('.json') && !f.endsWith('-raw.json')).sort().map((f) => JSON.parse(readFileSync(join(dir, f), 'utf8')));
  const note = readFileSync(join(ROOT, 'research/notes/2026/10-2x-linux-webkit.md'), 'utf8');
  assert.equal(splice(note, renderBlock(files)), note);
});
