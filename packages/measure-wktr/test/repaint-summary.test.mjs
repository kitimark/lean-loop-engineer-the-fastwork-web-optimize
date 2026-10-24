import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { groupByArm, armRows, toMarkdown, readJobs } from '../src/repaint-summary.mjs';
import { reduceRun } from '../src/repaint.mjs';

const META = { innerWidth: 402, innerHeight: 874, maxY: 5000, els: [{ d: 'section#hero', p: 'hero' }, { d: 'div.blob', p: 'pain' }] };
const FR = (f, y) => ({
  f, y, sy: y,
  view: [{ r: [0, 56, 402, 40], e: 0, h: 0, c: 'scroll', p: 'hero' }, { r: [0, 2000, 10, 10], e: 1, h: 0, c: 'anim:pulse', p: 'pain' }],
  rootCov: [0, y, 402, 1386], L: [], rs: [[4, 100, 60, 100, 70, 0, 0]],
});

function fileOf(arm, pass) {
  const red = reduceRun({ meta: META, frames: [FR(0, 0), FR(1, 2000), FR(2, 2000), FR(3, 4500)] });
  return { meta: { arm, pass, label: `j${pass}`, page: { innerWidth: 402, innerHeight: 874 } }, frames: red.frames, table: red.table };
}

test('groupByArm and armRows: per-100-frames numbers from the summed tables', () => {
  const arms = groupByArm([fileOf('orig', 1), fileOf('orig', 2), fileOf('v2', 1)]);
  assert.equal(arms.orig.runs, 2);
  assert.deepEqual(arms.orig.frames, { hero: 2, rest: 4, finish: 2 });
  const rows = armRows(arms.orig);
  const r = rows.find((x) => x.zone === 'rest' && x.part === 'pain');
  assert.equal(r.paintsPer100, 100);
  assert.equal(r.invisiblePer100, 100);
  assert.equal(r.byClassPer100['beyond-margin'], 100);
  assert.equal(r.wastePer100, 100 * 100);
  assert.match(r.causes, /anim:pulse \(4\)/);
  const hero = rows.find((x) => x.zone === 'rest' && x.part === 'hero');
  assert.equal(hero.invisiblePer100, 0);
  assert.equal(hero.reRasterLayersPer100, 100);
});

test('toMarkdown: a table and the classes of each zone', () => {
  const arms = groupByArm([fileOf('orig', 1)]);
  const md = toMarkdown(arms.orig, 'orig', { hero: { paintRects: { class: 'deterministic', k: 0, t: 0 } }, rest: {}, finish: {} });
  assert.match(md, /^### orig \(1 runs, frames hero 1, rest 2, finish 1\)/);
  assert.match(md, /\| rest \| pain \|/);
  assert.match(md, /hero: deterministic: paintRects/);
});

test('readJobs: tables and counts files of the job directories', () => {
  const d = mkdtempSync(join(tmpdir(), 'fw-rs-'));
  try {
    for (const j of ['wktr-j1', 'wktr-j2']) {
      mkdirSync(join(d, j));
      const t = fileOf('orig', 1);
      writeFileSync(join(d, j, 'table-orig-1.json'), JSON.stringify(t));
      writeFileSync(join(d, j, 'counts-orig-rest-1.json'), '{"frames":[]}');
      writeFileSync(join(d, j, 'runner.json'), '{}');
    }
    const g = readJobs(d);
    assert.equal(g.tables.length, 2);
    assert.equal(g.counts.orig.rest.length, 2);
    assert.equal(g.counts.orig.hero, undefined);
  } finally { rmSync(d, { recursive: true, force: true }); }
});
