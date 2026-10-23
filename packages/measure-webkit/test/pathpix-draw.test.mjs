import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { encodePng } from '../src/pathpix-png.mjs';
import { drawTimes } from '../src/pathpix-exit.mjs';
import { analyzeDraw, drawBand, drawTable, drawFile } from '../src/pathpix-exit-draw.mjs';
import { DRAW_STATE_EXPR, drawAdvanceExpr, drawSeekExpr } from '../src/pathpix-exit-draw-page.mjs';
import { DRAW_FLAGS, drawSearch } from '../src/pathpix-exit-draw-webkit.mjs';

const W = 40, H = 20;
const grey = (v) => ({ w: W, h: H, rgba: new Uint8Array(W * H * 4).fill(v) });
const dot = (img, x, y, d) => { const o = (y * W + x) * 4; img.rgba[o] = (img.rgba[o] + d) & 255; return img; };

function fakeDraw(edit) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-draw-test-'));
  mkdirSync(join(dir, 'shots'), { recursive: true });
  const times = drawTimes();
  const samples = {};
  for (const arm of ['A', 'A2', 'N', 'F']) {
    samples[arm] = { out: [], in: [] };
    for (const phase of ['out', 'in']) {
      times.forEach((t, k) => {
        const img = edit(arm, phase, k, grey(100));
        writeFileSync(join(dir, drawFile(arm, phase, k)), encodePng(img));
        samples[arm][phase].push({ k, t, file: drawFile(arm, phase, k), tries: 2, stable: true, n: 2, kinds: ['animation:900'], rect: [5, 5, 20, 8], times: [t, t] });
      });
    }
  }
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify({ schema: 'fw.path-pix/1', mode: 'draw', flags: DRAW_FLAGS, engine: 'webkit', run: 'x', dpr: 1, frame: { w: W, h: H }, times, cut: [], samples }));
  return dir;
}

test('the draw lane serves the faithful page and one page per accent flag', () => {
  assert.equal(drawSearch('A'), '');
  assert.equal(drawSearch('A2'), '');
  assert.equal(drawSearch('N'), '?fw=hero.accent:draw-nolayout');
  assert.equal(drawSearch('F'), '?fw=hero.accent:draw-nolayout-full');
});

test('draw page expressions are well-formed scripts', () => {
  for (const e of [DRAW_STATE_EXPR, drawAdvanceExpr('a b', 4000, 50), drawSeekExpr(150)]) assert.doesNotThrow(() => new Function(`return ${e}`));
});

test('the band covers the word boxes and stays inside the frame', () => {
  assert.deepEqual(drawBand([[10, 4, 20, 6], null], 2, 100, 40, 1), [18, 62, 6, 22]);
  assert.deepEqual(drawBand([[0, 0, 500, 500]], 2, 100, 40, 8), [0, 100, 0, 40]);
  assert.equal(drawBand([null], 2, 100, 40), null);
});

test('arms equal to faithful read same; a change inside the faithful floor reads floor; above it reads above', () => {
  const dir = fakeDraw((arm, phase, k, img) => {
    if (arm === 'A2' && phase === 'out' && k === 1) dot(img, 8, 8, 5);
    if (arm === 'N' && phase === 'out' && k === 1) dot(img, 8, 8, 3);
    if (arm === 'N' && phase === 'out' && k === 2) dot(img, 8, 8, 3);
    if (arm === 'F' && phase === 'in' && k === 3) { dot(img, 8, 8, 1); dot(img, 38, 15, 1); }
    return img;
  });
  try {
    const res = analyzeDraw(dir, { strips: 'none' });
    assert.equal(res.missing, 0);
    assert.equal(res.frames.length, 14);
    const at = (phase, k) => res.frames.find((f) => f.phase === phase && f.k === k);
    assert.equal(at('out', 0).arms.N.draw, 'same');
    assert.deepEqual(at('out', 1).floor && { c: at('out', 1).floor.changed, m: at('out', 1).floor.maxDelta }, { c: 1, m: 5 });
    assert.equal(at('out', 1).arms.N.draw, 'floor');
    assert.equal(at('out', 2).arms.N.draw, 'above');
    assert.equal(at('in', 3).arms.F.draw, 'above');
    assert.equal(at('in', 3).arms.F.changed, 2);
    assert.equal(at('in', 3).arms.F.band.changed, 1);
    assert.equal(at('in', 3).arms.F.rest.changed, 1);
    assert.equal(res.worst.N, 'above');
    assert.equal(res.worstBy.N.in, 'same');
    assert.equal(res.worstBy.N.out, 'above');
    assert.equal(res.worst.F, 'above');
    assert.match(drawTable(res), /worst frame above/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('an arm that was cut leaves its frames missing and out of the worst reading', () => {
  const dir = fakeDraw((_a, _p, _k, img) => img);
  try {
    const man = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
    delete man.samples.F;
    writeFileSync(join(dir, 'manifest.json'), JSON.stringify(man));
    const res = analyzeDraw(dir, { strips: 'none' });
    assert.equal(res.missing, 14);
    assert.equal(res.worst.F, 'missing');
    assert.equal(res.worst.N, 'same');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
