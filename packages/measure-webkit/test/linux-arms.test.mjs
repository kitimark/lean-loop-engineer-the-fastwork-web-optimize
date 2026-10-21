// The arm matrix and the static server of the Linux WebKit probe (src/linux/arms.mjs, serve.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { armId, armList, schedule, selectArms } from '../src/linux/arms.mjs';
import { pagePath, startServer } from '../src/linux/serve.mjs';

test('matrix: 12 base arms (3 pages x 2 widths x 2 dpr) and 8 switch arms, ids unique', () => {
  const arms = armList();
  assert.equal(arms.filter((a) => !a.sw).length, 12);
  assert.equal(arms.filter((a) => a.sw).length, 8);
  assert.equal(new Set(arms.map((a) => a.id)).size, arms.length);
  for (const a of arms) assert.equal(a.id, armId(a));
});

test('the switches are exactly the four the task names, each with its own variable', () => {
  const sw = armList().filter((a) => a.sw);
  const envs = Object.fromEntries(sw.map((a) => [a.sw, a.env]));
  assert.deepEqual(envs.msaa0, { WEBKIT_SKIA_MSAA_SAMPLE_COUNT: '0' });
  assert.deepEqual(envs.cpu, { WEBKIT_SKIA_ENABLE_CPU_RENDERING: '1' });
  assert.deepEqual(envs.lp1, { LP_NUM_THREADS: '1' });
  assert.deepEqual(envs.fps, { WEBKIT_SHOW_FPS: '1' });
  assert.ok(sw.every((a) => a.width === 390 && a.dpr === 3));
});

test('selectArms: ids in order, unknown id throws, empty = all', () => {
  assert.deepEqual(selectArms('orig-w1280-d1,blank-w390-d3').map((a) => a.id), ['orig-w1280-d1', 'blank-w390-d3']);
  assert.throws(() => selectArms('nope'), /unknown arm nope/);
  assert.equal(selectArms('').length, 20);
});

test('schedule: round A over every arm, then round B (A/A)', () => {
  const s = schedule(selectArms('blank-w390-d1,paint-w390-d1'));
  assert.deepEqual(s.map((x) => `${x.round}:${x.arm.id}`), ['A:blank-w390-d1', 'A:paint-w390-d1', 'B:blank-w390-d1', 'B:paint-w390-d1']);
});

test('server: synthetic pages, snapshot file, 404, no path escape', async () => {
  const srv = await startServer();
  try {
    const blank = await fetch(srv.origin + pagePath('blank'));
    assert.equal(blank.status, 200);
    assert.match(await blank.text(), /height:30000px/);
    assert.equal((await fetch(srv.origin + pagePath('paint'))).status, 200);
    assert.equal(pagePath('orig'), '/');
    assert.equal((await fetch(srv.origin + '/definitely-missing.txt')).status, 404);
    const raw = await fetch(srv.origin + '/%2e%2e/package.json');
    assert.ok([400, 404].includes(raw.status));
  } finally {
    await srv.close();
  }
});
