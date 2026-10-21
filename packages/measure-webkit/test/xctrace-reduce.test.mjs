import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseXml, rowsOf, tocStartMs, traceWindows, zoneCounts, issuesOf, reducePass } from '../src/xctrace/reduce.mjs';

// The shape of an `xctrace export` table: one element per column, a repeated value is a ref to an earlier id.
const TABLE = `<?xml version="1.0"?>
<trace-query-result><node xpath="x"><schema name="hitches"><col><mnemonic>start</mnemonic></col></schema>
<row><start-time id="1" fmt="00:01.000">1000000000</start-time><duration id="2" fmt="20 ms">20000000</duration><label id="3" fmt="Commit">Commit</label></row>
<row><start-time id="4" fmt="00:02.000">2000000000</start-time><duration ref="2"/><label ref="3"/></row>
<row><start-time id="5" fmt="00:09.000">9000000000</start-time><duration id="6">5000000</duration><label>R &amp; D</label></row>
</node></trace-query-result>`;

test('parseXml builds the tree and decodes entities', () => {
  const t = parseXml(TABLE);
  assert.equal(t.tag, 'trace-query-result');
  const rows = rowsOf(TABLE);
  assert.equal(rows.length, 3);
  assert.equal(rows[2].cols.label, 'R & D');
});

test('rowsOf resolves refs', () => {
  const rows = rowsOf(TABLE);
  assert.deepEqual(rows.map((r) => [r.t, r.dur, r.cols.label]), [[1e9, 2e7, 'Commit'], [2e9, 2e7, 'Commit'], [9e9, 5e6, 'R & D']]);
});

test('tocStartMs reads the start date', () => {
  assert.equal(tocStartMs('<run number="1"><summary><start-date>2026-10-22T01:02:03.500+00:00</start-date></summary></run>'), Date.UTC(2026, 9, 22, 1, 2, 3, 500));
  assert.equal(tocStartMs('<run/>'), null);
});

test('windows map to trace ns and rows count per zone', () => {
  const start = 1_000_000;
  const windows = [
    { zone: 'A', t0: start + 500, t1: start + 1500 }, { zone: 'A', t0: start + 1800, t1: start + 2200 },
    { zone: 'B', t0: start + 8500, t1: start + 9500 },
  ];
  assert.deepEqual(traceWindows(windows, start, 'A'), [[5e8, 1.5e9], [1.8e9, 2.2e9]]);
  const c = zoneCounts(rowsOf(TABLE), windows, start);
  assert.deepEqual(c, { rowsTotal: 3, timed: 3, A: { rows: 2, durMs: 40 }, B: { rows: 1, durMs: 5 } });
});

test('a row outside every window counts for no zone', () => {
  const c = zoneCounts(rowsOf(TABLE), [{ zone: 'A', t0: 0, t1: 10 }], 0);
  assert.equal(c.A.rows, 0);
  assert.equal(c.B.rows, 0);
});

test('issuesOf keeps the lines that name a problem', () => {
  const t = 'Starting recording\n* [Error] Hitches is not supported on this platform.\nCannot find process matching name: X\nok';
  assert.deepEqual(issuesOf(t), ['* [Error] Hitches is not supported on this platform.', 'Cannot find process matching name: X']);
});

test('reducePass reads the toc and the tables of a pass', () => {
  const files = {
    'a-p1/toc.xml': '<start-date>1970-01-01T00:00:00.000Z</start-date>',
    'a-p1/hitches.xml': TABLE,
  };
  const rec = {
    arm: 'a', pass: 1, started: true, sudo: false, stopped: { code: 0 }, xctraceOutput: '',
    windows: [{ zone: 'A', t0: 500, t1: 1500 }, { zone: 'B', t0: 8500, t1: 9500 }],
    tables: [{ schema: 'hitches', file: 'hitches.xml', bytes: 10 }, { schema: 'gone', file: 'gone.xml', bytes: 0 }],
  };
  const r = reducePass(rec, (f) => files[f] ?? null);
  assert.equal(r.startDate, 0);
  assert.deepEqual(r.tables.hitches.A, { rows: 1, durMs: 20 });
  assert.deepEqual(r.tables.hitches.B, { rows: 1, durMs: 5 });
  assert.deepEqual(r.tables.gone, { rowsTotal: 0, empty: true });
});
