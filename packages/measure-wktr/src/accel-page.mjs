// The page script of the geom-track accel lane (task geom-track-style), served as /__fw/harness.js and loaded first in <head>, run in
// WebKitTestRunner where `window.internals` exists. It installs the shared probe (packages/gate-breakpoints/src/track-accel-page.mjs: the
// Element.animate wrapper, the arms and the scenario) and, on load, runs it once and prints one result line:
//   FWWKTR accel <json>   { facts, rows, tags, errors, accelProps }  (rows: per arm the stages with frames, ms, styleRecalcCount delta;
//                         the arm `all` row carries a table of every tag with playState and the accelerated animations of its element:
//                         internals.acceleratedAnimationsForElement, Internals.cpp:1534@862f17d)
//   FWWKTR error <json>, FWWKTR done {}
// Native requestAnimationFrame and timers; nothing is replaced or seeked. Counts only: nothing measured here is phone time.
import { bootstrapSource } from '../../measure-webkit/src/page.mjs';
import { probeSource } from '../../gate-breakpoints/src/track-accel-page.mjs';

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

/** The harness script for one mode (scrubbed or timed). */
export function accelHarnessSource({ mode, arms, sweepFrames = 60, windowMs = 560, settleMs = 2500 } = {}) {
  const pre = 'window.__fwN = { st: window.setTimeout.bind(window) };\n';
  const opts = { mode, sweepFrames, windowMs, settleMs };
  if (arms) opts.arms = arms;
  return pre + bootstrapSource({ clock: 'pinned' }) + '\n' + probeSource(opts) + '\n' + RUN_SRC;
}

/** Parse the console lines of one run. */
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
