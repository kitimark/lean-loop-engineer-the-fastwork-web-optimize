// compose.mjs against the Lean golden vectors of measure.compose (packages/contracts/golden/measure, Fw.Measure.Golden).
// Needs lean/.lake/build/bin/fwcore (cd lean && lake build fwcore).
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { classTable, loadRun, render, request, rowLine } from '../src/compose.mjs';
import { fwcoreCall } from '../../../apps/runner/src/run.ts';

const golden = readFileSync(new URL('../../contracts/golden/measure/measure.compose.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l))
  .map(({ request: { op, ...request }, response }) => ({ request, reply: response }));
const ok = golden.filter((g) => g.reply.error === undefined);

test('the golden covers every verdict branch, both evidence marks and both refusals', () => {
  const seen = new Set(ok.flatMap((g) => g.reply.rows.map((r) => r.verdict === 'not-comparable' ? r.why : r.verdict)));
  assert.deepEqual([...seen].sort(), ['composes', 'coupled', 'drift', 'missing', 'no-zone-margin', 'quarantined', 'reported']);
  assert.deepEqual([...new Set(ok.flatMap((g) => g.reply.rows.map((r) => r.informative)))].sort(), [false, true]);
  assert.deepEqual(golden.filter((g) => g.reply.error !== undefined).map((g) => g.reply.error.split(': ')[1].split(' ')[0]).sort(), ['adds', 'not']);
  assert.ok(ok.some((g) => g.reply.combined.baseFlags.length > 0));
});

test('loadRun refuses a counts file without variants', () => {
  const dir = mkdtempSync(join(tmpdir(), 'compose-'));
  writeFileSync(join(dir, 'counts.json'), JSON.stringify({ meta: {}, frames: [] }));
  writeFileSync(join(dir, 'zones.json'), JSON.stringify({ zones: [] }));
  assert.throws(() => loadRun(dir), /no meta.rewrite.config.variants/);
});

test('fwcore reproduces every golden reply', () => {
  const call = fwcoreCall(fileURLToPath(new URL('.', import.meta.url)));
  for (const g of golden) {
    if (g.reply.error !== undefined) {
      assert.throws(() => call({ op: 'measure.compose', ...g.request }), (e) => e.message.endsWith(g.reply.error));
      continue;
    }
    assert.deepEqual(call({ op: 'measure.compose', ...g.request }), g.reply);
  }
});

/** Lay a golden request out as downloaded CI runs: `<id>/chromium-counts-rewrite-r<n>/{counts,zones}.json`. */
function layOut(dir, req) {
  const runs = [req.combined, ...req.singles];
  const write = (id, side) => side.forEach((r, i) => {
    const d = join(dir, id, `chromium-counts-rewrite-r${i + 1}`);
    mkdirSync(d, { recursive: true });
    writeFileSync(join(d, 'counts.json'), JSON.stringify({ meta: { rewrite: { config: { variants: r.variants } } }, frames: [] }));
    writeFileSync(join(d, 'zones.json'), JSON.stringify({ schema: 'fw.zones/1', zoneHeightPx: 500, zones: r.zones }));
  });
  for (const c of runs) { write(c.baseId, c.base); write(c.id, c.arm); }
}

test('request() rebuilds the first golden request from run dirs', () => {
  const req = golden[0].request;
  const dir = mkdtempSync(join(tmpdir(), 'compose-'));
  layOut(dir, req);
  const plan = { arm: 'rewrite', singles: req.singles.map((s) => ({ run: s.id, base: s.baseId })) };
  const frozen = { profiles: { p: { arms: { rewrite: { types: Object.fromEntries(Object.entries(req.classes).map(([k, v]) => [k, { ...v, role: 'gate' }])) } } } } };
  const built = request(plan, { combined: { run: req.combined.id, base: req.combined.baseId } }, classTable(frozen, 'p', 'rewrite'), dir);
  assert.deepEqual(built, { op: 'measure.compose', ...req });
});

test('render prints one line per judged row and every whole-run pass row', () => {
  for (const g of ok) {
    const md = render('t', g.reply).split('\n');
    const lines = g.reply.rows.filter((r) => r.verdict !== 'reported' || r.zone === 'run').map(rowLine);
    for (const l of lines) assert.ok(md.includes(l));
    for (const r of g.reply.rows.filter((x) => x.verdict === 'coupled')) assert.ok(rowLine(r).includes(r.named.join(', ')));
  }
});
