import { bootstrapSource } from '../../measure-webkit/src/page.mjs';
import { probeSource } from './mid-page.mjs';

const RUN_SRC = `(() => {
  const out = (tag, obj) => console.log('FWWKTR ' + tag + ' ' + JSON.stringify(obj));
  if (!window.testRunner || !window.internals) { out('error', { message: 'no testRunner/internals in this page' }); return; }
  testRunner.dumpAsText();
  testRunner.waitUntilDone();
  const finish = () => { out('done', {}); testRunner.notifyDone(); };
  addEventListener('load', () => {
    window.__fwx.run().then((t) => { out('accel', t); }, (e) => { out('error', { message: String((e && e.message) || e) }); }).then(finish);
  });
})();`;

export function accelHarnessSource({ mode, arms, sweepFrames = 60, windowMs = 560, settleMs = 2500, mid, rsIdleMs, rsReps, rsWin, tk, gh, gk, lay, qsets } = {}) {
  const pre = 'window.__fwN = { st: window.setTimeout.bind(window) };\n';
  const opts = { mode, sweepFrames, windowMs, settleMs };
  if (arms) opts.arms = arms;
  if (mid) opts.mid = mid;
  if (rsIdleMs) opts.rsIdleMs = rsIdleMs;
  if (rsReps) opts.rsReps = rsReps;
  if (rsWin) opts.rsWin = rsWin;
  if (tk) opts.tk = true;
  if (gh) opts.gh = true;
  if (gk) opts.gk = true;
  if (lay) opts.lay = true;
  if (qsets) opts.qsets = qsets;
  return pre + bootstrapSource({ clock: 'pinned' }) + '\n' + probeSource(opts) + '\n' + RUN_SRC;
}

export function parseAccel(text) {
  const got = { report: null, error: null, done: false };
  for (const line of text.split('\n')) {
    const m = /FWWKTR (accel|error|done) (.*)$/.exec(line.trim());
    if (!m) continue;
    const v = JSON.parse(m[2]);
    if (m[1] === 'accel') got.report = v;
    else if (m[1] === 'error') got.error = v;
    else got.done = true;
  }
  return got;
}
