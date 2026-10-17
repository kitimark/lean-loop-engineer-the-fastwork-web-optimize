// In-container driver (counts lane, Chromium arm; PLAN 4.2 "One virtual frame in Chromium").
// Runs inside the image built from ../Dockerfile. Mounts: /driver (this dir, ro), /profiles (ro), /snapshot/site (ro),
// /out (rw). Writes /out/counts.json: raw per-frame counts only, plain JSON, stable schema "fw.counts/1".
// No decision logic lives here: zone sums, classes, screening and verdicts are Lean (fwcore, called by the host).
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, openSync } from 'node:fs';
import puppeteer from 'puppeteer-core';
import { startServer } from './server.mjs';
import { traceToFrameCounts, TRACE_CATEGORIES } from './trace.mjs';

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, '').split('=')).map(([k, v]) => [k, v ?? true]));
const profile = JSON.parse(readFileSync(`/profiles/${args.profile ?? 'swipe-v1'}.json`, 'utf8'));
const OUT = args.out ?? '/out';
const DEBUG = !!process.env.FW_DEBUG;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const dt = 1000 / profile.hz;
const BARRIER_MS = +(process.env.FW_BARRIER_MS ?? 100); // real-time grace after each frame for async completions
const T0 = 5_000_000; // BeginFrame tick base (ms); any value above the browser's uptime works
const START_VT = 20_000; // virtual ms at which the profile begins, whatever number of frames the load took
const EPOCH_MS = Date.parse(profile.pinnedDate);

const srv = await startServer('/snapshot/site');
const chrome = spawn(process.env.FW_CHROME, [
  '--remote-debugging-port=9222', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--user-data-dir=/tmp/fw-profile',
  '--enable-begin-frame-control', '--deterministic-mode', '--run-all-compositor-stages-before-draw',
  '--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE localhost, EXCLUDE 127.0.0.1',
  '--font-render-hinting=none', '--force-color-profile=srgb', '--hide-scrollbars', '--mute-audio',
  '--disable-background-networking', '--disable-breakpad', '--no-first-run', '--lang=en-US', 'about:blank',
], { stdio: ['ignore', DEBUG ? 'inherit' : openSync('/tmp/chrome.log', 'w'), DEBUG ? 'inherit' : openSync('/tmp/chrome.log', 'a')] });
for (let i = 0; i < 200; i++) { try { await fetch('http://127.0.0.1:9222/json/version'); break; } catch { await sleep(50); } }
const version = await (await fetch('http://127.0.0.1:9222/json/version')).json();

const browser = await puppeteer.connect({ browserURL: 'http://127.0.0.1:9222', defaultViewport: null, protocolTimeout: 60000 });
const bs = await browser.target().createCDPSession();
const { targetId } = await bs.send('Target.createTarget', { url: 'about:blank', enableBeginFrameControl: true, width: profile.viewport.width, height: profile.viewport.height });
const page = await (await browser.waitForTarget((t) => t._targetId === targetId)).page();
const c = await page.createCDPSession();
const ev = async (expression) => {
  const r = await c.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: false });
  if (r.exceptionDetails) throw new Error('evaluate failed: ' + JSON.stringify(r.exceptionDetails).slice(0, 400));
  return r.result.value;
};
// Network.enable makes BeginFrame hang at navigation commit (observed), so in-flight requests are counted by the
// static server instead (every request that can succeed goes through it; external hosts are unresolvable by design).
await c.send('Page.enable'); await c.send('Runtime.enable'); await c.send('Performance.enable');
await c.send('Emulation.setDeviceMetricsOverride', { width: profile.viewport.width, height: profile.viewport.height, deviceScaleFactor: profile.viewport.dpr, mobile: profile.viewport.mobile, screenWidth: profile.viewport.width, screenHeight: profile.viewport.height });
if (!process.env.FW_NOTOUCH) await c.send('Emulation.setTouchEmulationEnabled', { enabled: profile.viewport.touch, maxTouchPoints: 5 });
await c.send('Emulation.setTimezoneOverride', { timezoneId: profile.timezone });
await c.send('Emulation.setLocaleOverride', { locale: profile.locale });
await c.send('Emulation.setUserAgentOverride', { userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36', acceptLanguage: profile.locale });
const shim = readFileSync('/driver/clock-shim.js', 'utf8');
await c.send('Page.addScriptToEvaluateOnNewDocument', { source: `globalThis.__FW_CFG = ${JSON.stringify({ epochMs: EPOCH_MS, seed: profile.seed })};\n${shim}` });

let vt = 0;
// Network barrier: a request started during a frame (lazy image, chunk) must finish, and its load handlers run, before
// the next frame, so arrival time never decides which frame sees it. All reachable requests are local (milliseconds).
async function networkBarrier(r0) {
  await sleep(BARRIER_MS);
  if (srv.requests() === r0 && srv.inflight() === 0) return;
  let last = -1, stableSince = Date.now();
  for (;;) {
    const r = srv.requests();
    if (r !== last || srv.inflight() > 0) { last = r; stableSince = Date.now(); }
    else if (Date.now() - stableSince >= 40) return;
    await sleep(5);
  }
}
async function frame(vtMs, pre = '') {
  const r0 = srv.requests();
  // One virtual frame: virtual clock to vtMs (timers due fire), optional page-side step, then one BeginFrame.
  const out = await ev(`(() => { ${pre}; __fw.advanceTo(${vtMs}); return typeof __fwStepResult === 'undefined' ? null : __fwStepResult; })()`);
  if (DEBUG) console.error('frame', vtMs.toFixed(1));
  // During navigation commit a BeginFrame can go unanswered (the target is swapping render widgets): resend it.
  let bf = null;
  for (let attempt = 0; attempt < 20 && !bf; attempt++) {
    bf = await Promise.race([c.send('HeadlessExperimental.beginFrame', { frameTimeTicks: T0 + vtMs, interval: dt }), sleep(1500).then(() => null)]);
    if (!bf && DEBUG) console.error('beginFrame retry', attempt);
  }
  if (!bf) throw new Error('beginFrame never answered at vt ' + vtMs);
  await networkBarrier(r0);
  return { out, hasDamage: !!bf.hasDamage };
}

// ---- load: pump frames until the page is quiet (readyState complete, no requests in flight, fonts loaded)
// No frames are sent until the navigation has committed: the new document's virtual clock must start at 0 on its first
// frame, whatever number of frames the browser would otherwise have spent waiting for the commit.
const navRes = await c.send('Page.navigate', { url: `http://127.0.0.1:${srv.port}/` });
if (navRes.errorText) throw new Error('navigation failed: ' + navRes.errorText);
let quiet = 0, loadFrames = 0;
for (; loadFrames < profile.load.maxFrames && quiet < profile.load.quietFrames; loadFrames++) {
  vt = loadFrames * dt;
  await frame(vt);
  const st = await ev(`document.readyState + ',' + (document.fonts ? document.fonts.status : 'loaded') + ',' + document.images.length + ',' + [...document.images].filter((i) => !i.complete).length`);
  const [rs, fonts, , pendingImgs] = st.split(',');
  quiet = rs === 'complete' && fonts === 'loaded' && srv.inflight() === 0 ? quiet + 1 : 0;
}
if (quiet < profile.load.quietFrames) throw new Error(`page not quiet after ${loadFrames} frames (server inflight ${srv.inflight()})`);
// Jump to the fixed profile start, whatever number of frames the load took, then pre-roll with the page idle.
vt = START_VT;
for (let i = 0; i < profile.load.prerollFrames; i++, vt += dt) { await frame(vt); }
const geo = await ev(`({ docH: document.documentElement.scrollHeight, innerH: innerHeight, innerW: innerWidth, y: scrollY, dpr: devicePixelRatio, lang: navigator.language, tz: Intl.DateTimeFormat().resolvedOptions().timeZone, now: new Date().toISOString(), el: document.getElementsByTagName('*').length })`);
const maxScroll = geo.docH - geo.innerH;

// ---- scroll plan (a pure function of the profile and the page height)
const plan = [];
{
  let y = 0;
  for (const seg of profile.segments) {
    if (seg.until === 'end') { while (y < maxScroll) { y = Math.min(maxScroll, y + seg.dyPerFrame); plan.push({ phase: seg.name, y }); } }
    else for (let i = 0; i < seg.frames; i++) { y = Math.min(maxScroll, y + (seg.dyPerFrame ?? 0)); plan.push({ phase: seg.name, y }); }
  }
}

// ---- profile run
const KEEP = ['LayoutCount', 'RecalcStyleCount', 'Nodes', 'LayoutObjects', 'JSEventListeners', 'Documents', 'Frames', 'Resources'];
let prev = Object.fromEntries((await c.send('Performance.getMetrics')).metrics.map((m) => [m.name, m.value]));
await c.send('Tracing.start', { transferMode: 'ReturnAsStream', traceConfig: { recordMode: 'recordAsMuchAsPossible', includedCategories: TRACE_CATEGORIES, traceBufferSizeInKb: 1_000_000 } });
const frames = [];
const wallStart = Date.now();
for (let n = 0; n < plan.length; n++, vt += dt) {
  const { phase, y } = plan[n];
  const r = await frame(vt, `console.timeStamp('F${n}'); window.scrollTo({ top: ${y}, left: 0, behavior: 'instant' }); var __fwStepResult = scrollY;`);
  const m = Object.fromEntries((await c.send('Performance.getMetrics')).metrics.map((x) => [x.name, x.value]));
  const counts = { hasDamage: r.hasDamage ? 1 : 0 };
  for (const k of KEEP) counts['metric.' + k] = m[k] - prev[k];
  prev = m;
  frames.push({ n, phase, scrollY: r.out, vt: +(vt - START_VT).toFixed(3), counts });
}
const wallMs = Date.now() - wallStart;
const done = new Promise((res) => c.once('Tracing.tracingComplete', res));
await c.send('Tracing.end');
const { stream } = await done;
let traceText = '';
for (;;) { const r = await c.send('IO.read', { handle: stream, size: 1 << 20 }); traceText += r.data; if (r.eof) break; }
await c.send('IO.close', { handle: stream });
const trace = JSON.parse(traceText);
if (args['dump-trace']) writeFileSync(`${OUT}/trace.json`, traceText);
const { perFrame, runLevel, threads } = traceToFrameCounts(trace.traceEvents ?? trace, frames.length);
for (let n = 0; n < frames.length; n++) Object.assign(frames[n].counts, perFrame[n]);

const served = srv.served();
const servedSha = createHash('sha256').update(JSON.stringify(served)).digest('hex');
const result = {
  schema: 'fw.counts/1',
  engine: 'chromium-headless-shell',
  profile: { id: profile.id, file: `${profile.id}.json`, sha256: createHash('sha256').update(readFileSync(`/profiles/${args.profile ?? 'swipe-v1'}.json`)).digest('hex') },
  meta: {
    browser: version.Browser, protocol: version['Protocol-Version'],
    image: process.env.FW_IMAGE_ID ?? null, snapshot: process.env.FW_SNAPSHOT_ID ?? null,
    servedFiles: Object.keys(served).length, servedSha256: servedSha, missing: srv.missing(),
    viewport: profile.viewport, hz: profile.hz, startVirtualMs: START_VT, pinnedDate: profile.pinnedDate, pageDateAtStart: geo.now, timezone: geo.tz,
    docHeightPx: geo.docH, maxScrollPx: maxScroll, elementCountAtStart: geo.el, threads,
  },
  frames,
  runLevel,
};
mkdirSync(OUT, { recursive: true });
writeFileSync(`${OUT}/counts.json`, JSON.stringify(result, null, 1) + '\n');
// Wall time is reported on stderr only: it never enters counts.json.
console.error(`frames=${frames.length} loadFrames(not recorded)=${loadFrames} wallMs=${wallMs} (not a measurement of the phone)`);
browser.disconnect(); chrome.kill('SIGKILL'); await srv.close();
process.exit(0);
