#!/usr/bin/env node
// test-math-pending.mjs: fixtures for the decision part of scripts/math-pending.mjs (record precedence, the six
// statuses, the signed/pending partition and the batching). Run: node scripts/test-math-pending.mjs
import assert from 'node:assert/strict';
import { batchId, decide, makeBatches, parseRecords, statusOf, tsvLine } from './math-pending.mjs';

let n = 0;
const t = (name, f) => { f(); n++; console.log(`ok ${n} ${name}`); };
const rec = (file, round, rows) => ({
  file,
  text: `---\ntitle: x\n${round === null ? '' : `round: ${round}\n`}---\n\n| Declaration | Verdict | stmtHash | Note |\n|---|---|---|---|\n${rows.join('\n')}\n`,
});

t('rows: highest round wins, unnumbered ranks lowest, last row within a record wins', () => {
  const rows = parseRecords([
    rec('b-r12.md', 12, ['| `Fw.A.x` | agree | 1 | 2 |  |']),
    rec('a-r3.md', 3, ['| `Fw.A.x` | disagree | 1 | 2 | n |', '| `Fw.A.y` | agree | 5 | 6 |  |']),
    rec('c-fw.md', null, ['| `Fw.A.y` | disagree | 5 | 6 |  |', '| `Fw.A.z` | agree | 7 | 8 |  |', '| `Fw.A.z` | **disagree** | 7 | 8 |  |']),
  ]);
  assert.equal(rows.get('Fw.A.x').verdict, 'agree');
  assert.equal(rows.get('Fw.A.y').verdict, 'agree');
  assert.equal(rows.get('Fw.A.z').verdict, 'disagree');
});

t('rows: old formats, backticked hashes, non-review tables ignored', () => {
  const rows = parseRecords([rec('r.md', 1, [
    '| `Fw.B.a` | agree |', '| `Fw.B.b` | agree | `11` | note only |', '| `Fw.B.c` | agree | `11` | `22` |  |',
    '| Batch | 3 | 1 | 2 |', '| `Other.d` | agree | 1 | 2 |  |',
  ])]);
  assert.deepEqual([...rows.keys()], ['Fw.B.a', 'Fw.B.b', 'Fw.B.c']);
  assert.deepEqual(['Fw.B.a', 'Fw.B.b', 'Fw.B.c'].map((x) => rows.get(x).stmtHash), [null, '11', '11']);
});

t('rows: artifact records rank after every review round, by file name; their columns are decl, stmtHash, agree', () => {
  const art = (file, rows) => ({ file, text: `| decl | stmtHash | agree | artifact |\n|---|---|---|---|\n${rows.join('\n')}\n` });
  const rows = parseRecords([
    art('n/10-20-math-artifact-b.md', ['| `Fw.A.x` | 5 | agree | p.html |']),
    rec('r99.md', 99, ['| `Fw.A.x` | disagree | 1 |  |', '| `Fw.A.y` | agree | 2 |  |']),
    art('n/10-19-math-artifact-a.md', ['| `Fw.A.x` | 4 | disagree | p.html |', '| `Fw.A.y` | `3` | **agree** | p.html |']),
  ]);
  assert.deepEqual([rows.get('Fw.A.x').verdict, rows.get('Fw.A.x').stmtHash], ['agree', '5']);
  assert.deepEqual([rows.get('Fw.A.y').verdict, rows.get('Fw.A.y').stmtHash], ['agree', '3']);
});

t('rows: two records with one round fail', () => {
  assert.throws(() => parseRecords([rec('a.md', 4, []), rec('b.md', 4, [])]), /both have round: 4/);
});

t('status: the six cases', () => {
  const e = { name: 'Fw.A.x', stmtHash: '1' };
  const r = (verdict, stmtHash) => ({ verdict, stmtHash });
  assert.equal(statusOf(e, undefined), 'new');
  assert.equal(statusOf(e, r('agree', '1')), 'signed');
  assert.equal(statusOf(e, r('agree', '9')), 'stale');
  assert.equal(statusOf(e, r('agree', null)), 'unhashed');
  assert.equal(statusOf(e, r('disagree', '1')), 'disagree');
  assert.equal(statusOf(e, r('disagree', null)), 'disagree');
  assert.equal(statusOf(e, r('disagree', '3')), 'disagree-changed');
  assert.equal(statusOf({ ...e, stmtHash: 1 }, r('agree', '1')), 'signed'); // numeric export
});

const ent = (module, i) => ({ module, name: `${module}.d${i}`, kind: 'def', line: i, stmtHash: `${i}` });
const many = (module, k) => Array.from({ length: k }, (_, i) => ent(module, i + 1));

t('batches: partition, modules kept whole, balanced', () => {
  const items = [...many('Fw.M1', 10), ...many('Fw.M2', 9), ...many('Fw.M3', 5), ...many('Fw.M4', 4), ...many('Fw.M5', 3), ...many('Fw.M6', 1)];
  const bs = makeBatches(items, 3);
  const flat = bs.flat().map((e) => e.name).sort();
  assert.deepEqual(flat, items.map((e) => e.name).sort());
  for (const m of ['Fw.M1', 'Fw.M2', 'Fw.M3', 'Fw.M4', 'Fw.M5', 'Fw.M6']) {
    assert.equal(bs.filter((b) => b.some((e) => e.module === m)).length, 1, m);
  }
  const sizes = bs.map((b) => b.length);
  assert.ok(Math.max(...sizes) - Math.min(...sizes) <= 10, `${sizes}`);
  assert.deepEqual(sizes.slice().sort((a, b) => a - b), [10, 10, 12]);
});

t('batches: a module above the fair share is cut in line order; more batches than items give empty batches', () => {
  const bs = makeBatches(many('Fw.Big', 10), 4);
  assert.deepEqual(bs.map((b) => b.length), [3, 3, 3, 1]);
  assert.deepEqual(bs[0].map((e) => e.line), [1, 2, 3]);
  const es = makeBatches(many('Fw.S', 2), 4);
  assert.deepEqual(es.map((b) => b.length).sort(), [0, 0, 1, 1]);
  assert.throws(() => makeBatches([], 0));
});

t('batches: deterministic and sorted by module then line inside a batch', () => {
  const items = [...many('Fw.B', 3), ...many('Fw.A', 3)].reverse();
  const a = makeBatches(items, 1);
  assert.deepEqual(a[0].map((e) => `${e.module}:${e.line}`), ['Fw.A:1', 'Fw.A:2', 'Fw.A:3', 'Fw.B:1', 'Fw.B:2', 'Fw.B:3']);
  assert.deepEqual(makeBatches(items, 2), makeBatches(items.slice().reverse(), 2));
});

t('decide: pending ∪ signed = all, disjoint, batches partition pending', () => {
  const entries = [...many('Fw.A', 4), ...many('Fw.B', 3)];
  const rows = parseRecords([rec('r.md', 1, [
    '| `Fw.A.d1` | agree | 1 |  |', '| `Fw.A.d2` | agree | 1 |  |', '| `Fw.B.d1` | disagree | 1 |  |',
  ])]);
  const { status, signed, pending, batches } = decide(entries, rows, 2);
  assert.deepEqual(signed.map((e) => e.name), ['Fw.A.d1']);
  assert.equal(status.get('Fw.A.d2'), 'stale');
  assert.equal(status.get('Fw.B.d1'), 'disagree');
  assert.equal(signed.length + pending.length, entries.length);
  assert.deepEqual(batches.flat().map((e) => e.name).sort(), pending.map((e) => e.name).sort());
  assert.throws(() => decide([ent('Fw.A', 1), ent('Fw.A', 1)], rows, 2), /duplicate/);
});

t('output format', () => {
  assert.equal(tsvLine(ent('Fw.A', 7)), 'Fw.A\tFw.A.d7\tdef\t7');
  assert.deepEqual([0, 3, 25].map(batchId), ['A', 'D', 'Z']);
});

console.log(`${n} tests passed`);
