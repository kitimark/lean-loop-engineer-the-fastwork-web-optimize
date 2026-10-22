import { test } from 'node:test';
import assert from 'node:assert/strict';
import { simWindow } from '../src/sim-local.mjs';

/** A fake inspector client: a reload fires the navigation and load events, scripts answer from `facts`. */
function fakeClient({ info, rec }) {
  const handlers = [];
  const emit = (m) => handlers.forEach((h) => h(m));
  const log = [];
  return {
    log,
    enable: async () => {},
    on: (h) => { handlers.push(h); return () => {}; },
    send: async (method) => {
      log.push(method);
      if (method === 'Page.reload') { emit({ method: 'Page.frameNavigated' }); emit({ method: 'Page.loadEventFired' }); }
      if (method === 'Timeline.stop') emit({ method: 'Timeline.recordingStopped' });
      return {};
    },
    evaluate: async (src) => {
      if (src.includes('document.readyState') && !src.includes('navigator')) return 'complete';
      if (src.includes('__wkBootstrap || null') && !src.includes('navigator')) return 'pinned';
      if (src.includes('navigator.userAgent')) return JSON.stringify(info);
      return null;
    },
    runAsync: async (src) => { log.push(src.includes('wheel') ? 'end' : src.includes('scrollBy') ? 'hero' : 'toEnd'); return src.includes('scrollBy') || src.includes('wheel') ? rec : true; },
  };
}

const rec = { ts: [0, 16.7, 33.4, 90, 106.7], ys: [0, 10, 20, 30, 40], a: 0, b: 120, vh10: 9000, maxY10: 50000 };
const origInfo = { ua: 'UA', vw: 430, fw: null };

test('simWindow reads the cadence of the arm asked for and keeps the profile when the Timeline has no marks', async () => {
  const c = fakeClient({ info: origInfo, rec });
  const ctx = { c, setArm: () => {}, armHash: () => null };
  const v = await simWindow(ctx, { settleMs: 0, log: () => {} })({ id: 'orig', site: 'orig', search: '' }, 'hero');
  assert.equal(v.frames, 5);
  assert.equal(v.stat.long, 1, 'the 56.6 ms gap is over 25 ms');
  assert.equal(v.vw, 430);
  assert.equal(v.profile.ok, false, 'no marks in the fake Timeline: the profile is refused, the cadence is kept');
  assert.ok(c.log.includes('Timeline.start') && c.log.includes('hero'));
});

test('simWindow runs the end window from the end of the page', async () => {
  const c = fakeClient({ info: origInfo, rec });
  await simWindow({ c, setArm: () => {}, armHash: () => null }, { settleMs: 0, log: () => {} })({ id: 'orig', site: 'orig', search: '' }, 'end');
  assert.ok(c.log.indexOf('toEnd') < c.log.indexOf('Timeline.start') || c.log.includes('end'));
  assert.ok(c.log.includes('end'));
});

test('simWindow refuses a page that is not the arm asked for', async () => {
  const c = fakeClient({ info: { ua: 'UA', vw: 430, fw: { configHash: 'zzz', mode: 'aot' } }, rec });
  await assert.rejects(() => simWindow({ c, setArm: () => {}, armHash: () => 'abc' }, { settleMs: 0, log: () => {} })({ id: 'base', site: 'rewrite', search: '' }, 'hero'), /wrong page/);
});
