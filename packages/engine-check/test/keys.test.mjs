// keys.mjs and stage.mjs against the Lean golden vectors (lean/Fw/Engine/Keys.lean) and the aliasing the staging removes.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { answers, runKey } from '../src/keys.mjs';
import { stageRuns } from '../src/stage.mjs';
import { variantKeys } from '../../../apps/runner/src/engine-check.ts';

const golden = readFileSync(new URL('../golden/keys.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));

test('the golden has 78 vectors, one per (run, variant)', () => {
  assert.equal(golden.length, 78);
});

test('runKey and answers equal every Lean golden vector', () => {
  for (const g of golden) {
    const m = { target: g.target, search: g.search };
    assert.equal(runKey(m), g.key, JSON.stringify(g));
    assert.equal(answers(m, g.variant), g.answers, JSON.stringify(g));
  }
});

test('exactly one golden run answers the base rewrite, and no search run does', () => {
  const base = golden.filter((g) => g.variant === 'rewrite' && g.answers);
  assert.deepEqual(base.map((g) => g.search), ['']);
});

const run = (target, search, scenario = 'swipe-v1') => ({ profile: { id: scenario }, meta: { target, search }, frames: [{ counts: { 'trace.Layout': 1 } }] });
const rows = [{ variant: 'rewrite+?fw=nav.hitTest:hit-skip', base: 'rewrite' }, { variant: 'hidden-pause', base: 'rewrite' }];

test('without staging variantKeys lets a flag run answer for the base (the aliasing)', () => {
  const k = variantKeys(run('rewrite', '?fw=nav.hitTest:hit-skip'));
  assert.deepEqual(k, ['rewrite+?fw=nav.hitTest:hit-skip', 'rewrite']);
});

test('staged, each file answers one variant and a flag run never reaches the base', () => {
  const { staged, unkeyed } = stageRuns([
    { path: 'a', counts: run('rewrite', '') },
    { path: 'b', counts: run('rewrite', '?fw=nav.hitTest:hit-skip') },
    { path: 'c', counts: run('rewrite', '?fw=engine.scene:hidden-pause') },
    { path: 'd', counts: run('rewrite', '?fw=engine.scene:hidden-pause,nav.hitTest:hit-skip') },
    { path: 'e', counts: run('original', '') },
  ], rows);
  assert.deepEqual(staged.map((s) => [s.source, s.variant]), [['a', 'rewrite'], ['b', 'rewrite+?fw=nav.hitTest:hit-skip'], ['c', 'hidden-pause']]);
  assert.deepEqual(unkeyed, ['d', 'e']);
  for (const s of staged) assert.deepEqual(variantKeys(s.counts), [s.variant]);
});

test('staging does not change the frames', () => {
  const c = run('rewrite', '');
  const { staged } = stageRuns([{ path: 'a', counts: c }], rows);
  assert.deepEqual(staged[0].counts.frames, c.frames);
  assert.equal(c.meta.variant, undefined);
});
