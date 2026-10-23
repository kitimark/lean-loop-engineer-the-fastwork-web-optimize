import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, openSync } from 'node:fs';
import puppeteer from 'puppeteer-core';
import { startServer } from './server.mjs';
import { traceToFrameCounts, TRACE_CATEGORIES } from './trace.mjs';
import { accepts, gateSize, scrollRead, viewportGate } from './stage-mode.mjs';
import { overflowExpr, formatOverflow } from './overflow.mjs';
import { n0Windows, n0FrameCounts, byKind, N0_KEYS } from './n0.mjs';
import { parseProfile, replayEvents } from './profile.mjs';
import { collectCensus } from './census.mjs';
import { pngRegionHash } from './png-region.mjs';

const N0_ON = !process.env.FW_NO_N0;

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
const PROFILE_FILE = args['profile-file'] ?? `/profiles/${args.profile ?? 'swipe-v1'}.json`;
const { profile, strokes: replayStrokes } = parseProfile(JSON.parse(readFileSync(PROFILE_FILE, 'utf8')));
const OUT = args.out ?? '/out';
const DEBUG = !!process.env.FW_DEBUG;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const dt = 1000 / profile.hz;
const BARRIER_MS = +(process.env.FW_BARRIER_MS ?? 100);
const TOUCH_ACK_MS = +(process.env.FW_TOUCH_ACK_MS ?? 200);
const TOUCH_SETTLE_MS = +(process.env.FW_TOUCH_SETTLE_MS ?? 50);
const TOUCH_POST_ACK_MS = +(process.env.FW_TOUCH_POST_ACK_MS ?? 100);
const touch = { frames: 0, unacked: 0, sent: 0, stalls: 0, waiters: [], settled() { return this.unacked === 0 ? Promise.resolve() : new Promise((r) => this.waiters.push(r)); } };
const T0 = 5_000_000;
const START_VT = 20_000;
const EPOCH_MS = Date.parse(profile.pinnedDate);

const ROOT = args.root ?? '/snapshot/site';
const SEARCH = args.search && args.search !== true ? args.search : '';
const TARGET = args.target ?? 'original';
const POS = scrollRead(SEARCH) === 'scrollTop' ? 'document.scrollingElement.scrollTop' : 'scrollY';
const srv = await startServer(ROOT);
const CHROME_ARGS = [
  '--remote-debugging-port=9222', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', `--user-data-dir=${process.env.FW_PROFILE_DIR ?? '/tmp/fw-profile'}`,
  '--enable-begin-frame-control', '--run-all-compositor-stages-before-draw',
  '--disable-new-content-rendering-timeout', '--disable-checker-imaging', '--disable-image-animation-resync', '--num-raster-threads=2',
  // cc features::kWaitForLateScrollEvents (default on, cc/base/features.cc@f842f52) arms a WAIT_FOR_SCROLL deadline at frame_time + 0.333 * interval while a scroll is active
  // and no input is queued.
  '--disable-features=WaitForLateScrollEvents',
  // touch-race: blink's MainThreadEventQueue::DispatchRafAlignedInput (platform/widget/input/main_thread_event_queue.cc:741-770@f842f52) holds an async touchmove back
  // while the rAF-aligned queue holds exactly 1 event and frame_time < last_async_touch_move_timestamp_ + 200 ms.
  ...(((profile.input?.mode === 'touch' || profile.input?.mode === 'replay') && process.env.FW_TOUCH_THROTTLE !== 'default') ? ['--async-touch-move-throttle-time-ms=0'] : []),
  '--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE localhost, EXCLUDE 127.0.0.1',
  '--font-render-hinting=none', '--force-color-profile=srgb', '--hide-scrollbars', '--mute-audio',
  '--disable-background-networking', '--disable-breakpad', '--no-first-run', '--lang=en-US', ...(process.env.FW_CHROME_EXTRA ? process.env.FW_CHROME_EXTRA.split(' ') : []), 'about:blank',
];
const DROP = [...(process.env.FW_DROP_FLAGS ?? '').split(',').filter(Boolean), ...(profile.dropFlags ?? [])];
for (let i = CHROME_ARGS.length - 1; i >= 0; i--) if (DROP.some((d) => CHROME_ARGS[i].startsWith(d))) CHROME_ARGS.splice(i, 1);
const chrome = spawn(process.env.FW_CHROME, CHROME_ARGS, { stdio: ['ignore', DEBUG ? 'inherit' : openSync('/tmp/chrome.log', 'w'), DEBUG ? 'inherit' : openSync('/tmp/chrome.log', 'a')] });
process.on('exit', () => { try { chrome.kill('SIGKILL'); } catch {} });
for (let i = 0; i < 200; i++) { try { await fetch('http://127.0.0.1:9222/json/version'); break; } catch { await sleep(50); } }
const version = await (await fetch('http://127.0.0.1:9222/json/version')).json();

const browser = await puppeteer.connect({ browserURL: 'http://127.0.0.1:9222', defaultViewport: null, protocolTimeout: 60000 });
const bs = await browser.target().createCDPSession();
const browserArgs = CHROME_ARGS.filter((a) => !a.startsWith('--user-data-dir') && !a.startsWith('--remote-debugging-port'));
const { targetId } = await bs.send('Target.createTarget', { url: 'about:blank', enableBeginFrameControl: true, width: profile.viewport.width, height: profile.viewport.height });
const page = await (await browser.waitForTarget((t) => t._targetId === targetId)).page();
const c = await page.createCDPSession();
c.on('Inspector.targetCrashed', async () => {
  console.error('FW_RENDERER_CRASH: Inspector.targetCrashed');
  let log = '';
  for (let i = 0; i < 40; i++) { await sleep(250); try { log = readFileSync('/tmp/chrome.log', 'utf8'); } catch {} if (/Received signal/.test(log) && /\[end of stack trace\]/.test(log)) break; }
  const at = log.indexOf('Received signal');
  console.error('chrome.log signal block:\n' + (at >= 0 ? log.slice(at, at + 12000) : log.slice(-3000)));
  chrome.kill('SIGKILL');
  process.exit(76);
});
const ev = async (expression) => {
  const r = await c.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: false });
  if (r.exceptionDetails) throw new Error('evaluate failed: ' + JSON.stringify(r.exceptionDetails).slice(0, 400));
  return r.result.value;
};
if (process.env.FW_LOAD_TRACE) {
  let logged = 0;
  const say = (...a) => { if (logged++ < 40) console.error('page:', ...a); };
  c.on('Inspector.targetCrashed', () => say('TARGET CRASHED'));
  c.on('Inspector.detached', (e) => say('DETACHED', e.reason));
  bs.on('Target.targetCrashed', (e) => say('BROWSER: targetCrashed', e.status, e.errorCode));
  bs.send('Target.setDiscoverTargets', { discover: true }).catch(() => {});
  bs.on('Target.targetInfoChanged', (e) => say('target', e.targetInfo.type, e.targetInfo.url.slice(0, 60)));
  bs.on('Target.targetDestroyed', (e) => say('target destroyed', e.targetId));
  c.on('Page.frameNavigated', (e) => say('navigated', e.frame.url.slice(0, 60)));
  c.on('Page.lifecycleEvent', (e) => say('lifecycle', e.name));
  c.on('Page.javascriptDialogOpening', (e) => { say('DIALOG', e.type, JSON.stringify(e.message).slice(0, 200)); c.send('Page.handleJavaScriptDialog', { accept: true }).catch(() => {}); });
  c.on('Runtime.exceptionThrown', (e) => say('EXCEPTION', (e.exceptionDetails?.exception?.description ?? e.exceptionDetails?.text ?? '').slice(0, 300)));
  c.on('Runtime.consoleAPICalled', (e) => { if (e.type === 'error' || e.type === 'warning' || e.type === 'assert') say(e.type, e.args.map((x) => x.value ?? x.description ?? '').join(' ').slice(0, 300)); });
}
await c.send('Page.enable'); await c.send('Runtime.enable'); await c.send('Performance.enable');
await c.send('Emulation.setDeviceMetricsOverride', { width: profile.viewport.width, height: profile.viewport.height, deviceScaleFactor: profile.viewport.dpr, mobile: profile.viewport.mobile, screenWidth: profile.viewport.width, screenHeight: profile.viewport.height });
if (!process.env.FW_NOTOUCH) await c.send('Emulation.setTouchEmulationEnabled', { enabled: profile.viewport.touch, maxTouchPoints: 5 });
const SKIP = new Set((process.env.FW_SKIP ?? '').split(',').filter(Boolean));if (!SKIP.has('tz')) await c.send('Emulation.setTimezoneOverride', { timezoneId: profile.timezone });
if (!SKIP.has('locale')) await c.send('Emulation.setLocaleOverride', { locale: profile.locale });
if (!SKIP.has('ua')) await c.send('Emulation.setUserAgentOverride', { userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36', acceptLanguage: profile.locale });
const shim = readFileSync('/driver/clock-shim.js', 'utf8');
await c.send('Page.addScriptToEvaluateOnNewDocument', { source: `globalThis.__FW_CFG = ${JSON.stringify({ epochMs: EPOCH_MS, seed: profile.seed })};\n${shim}` });
await c.send('Page.addScriptToEvaluateOnNewDocument', { source: `(() => { const g = (k) => { const d = Object.getOwnPropertyDescriptor(window, k); return d && typeof d.get === 'function' ? d.get : null; }; const w = g('innerWidth'), h = g('innerHeight'); Object.defineProperty(window, '__fwRealSize', { value: () => (w && h ? { w: w.call(window), h: h.call(window) } : null) }); })();` });
if (profile.css) await c.send('Page.addScriptToEvaluateOnNewDocument', { source: `(() => { const add = () => { const s = document.createElement('style'); s.textContent = ${JSON.stringify(profile.css)}; document.documentElement.appendChild(s); }; if (document.documentElement) add(); else new MutationObserver((_, o) => { if (document.documentElement) { o.disconnect(); add(); } }).observe(document, { childList: true }); })();` });
if (N0_ON) await c.send('Page.addScriptToEvaluateOnNewDocument', { source: readFileSync('/driver/n0-census.js', 'utf8') });

let vt = 0;
const BARRIER_MIN_MS = Math.min(BARRIER_MS, +(process.env.FW_BARRIER_MIN_MS ?? BARRIER_MS));
async function networkBarrier(r0) {
  await sleep(BARRIER_MIN_MS);
  if (BARRIER_MIN_MS < BARRIER_MS && (srv.requests() !== r0 || srv.inflight() > 0)) await sleep(BARRIER_MS - BARRIER_MIN_MS);
  if (srv.requests() === r0 && srv.inflight() === 0) return;
  let last = -1, stableSince = Date.now();
  for (;;) {
    const r = srv.requests();
    if (r !== last || srv.inflight() > 0) { last = r; stableSince = Date.now(); }
    else if (Date.now() - stableSince >= 40) return;
    await sleep(5);
  }
}
async function hangProfile(frameNo) {
  try { const lg = readFileSync('/tmp/chrome.log', 'utf8'); const at = lg.indexOf('Received signal'); console.error('chrome.log crash:\n' + (at >= 0 ? lg.slice(Math.max(0, at - 300), at + 2600) : lg.slice(-3000))); } catch (e) { console.error('no chrome.log', String(e)); }
  await c.send('Tracing.start', { transferMode: 'ReturnAsStream', traceConfig: { recordMode: 'recordAsMuchAsPossible', includedCategories: ['disabled-by-default-v8.cpu_profiler', 'devtools.timeline', 'cc', 'viz', 'blink', 'headless', 'toplevel'] } });
  await sleep(8000);
  const done = new Promise((res) => c.once('Tracing.tracingComplete', res));
  await c.send('Tracing.end');
  const { stream } = await done;
  let txt = '';
  for (;;) { const r = await c.send('IO.read', { handle: stream, size: 1 << 20 }); txt += r.data; if (r.eof) break; }
  const events = JSON.parse(txt).traceEvents ?? [];
  const frames = new Map();
  const hits = new Map();
  for (const e of events) {
    if (e.name !== 'ProfileChunk') continue;
    const cp = e.args?.data?.cpuProfile;
    for (const n of cp?.nodes ?? []) frames.set(n.id, n.callFrame);
    for (const id of cp?.samples ?? []) hits.set(id, (hits.get(id) ?? 0) + 1);
  }
  const top = [...hits.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12).map(([id, n]) => { const f = frames.get(id) ?? {}; return `${n} ${f.functionName || '(anon)'} ${f.url ?? ''}:${(f.lineNumber ?? 0) + 1}:${(f.columnNumber ?? 0) + 1}`; });
  const longs = events.filter((e) => e.ph === 'X' && e.dur > 500000).slice(0, 8).map((e) => `${e.name} ${Math.round(e.dur / 1000)}ms ${JSON.stringify(e.args?.data ?? {}).slice(0, 160)}`);
  const byName = new Map();
  for (const e of events) { const k = `${e.cat}/${e.name}`; const a = byName.get(k) ?? { n: 0, dur: 0 }; a.n++; a.dur += e.dur ?? 0; byName.set(k, a); }
  const names = [...byName.entries()].sort((a, b) => b[1].n - a[1].n).slice(0, 25).map(([k, v]) => `${v.n}x ${Math.round(v.dur / 1000)}ms ${k}`);
  console.error(`hang trace names:\n  ${names.join('\n  ')}`);
  throw new Error(`load hang at frame ${frameNo}: ${events.length} trace events\n top samples:\n  ${top.join('\n  ') || '(none)'}\n long tasks:\n  ${longs.join('\n  ') || '(none)'}`);
}
let loaded = false;
async function frame(vtMs, pre = '', mid = null, shot = false) {
  touch.frames++;
  const sent0 = touch.sent;
  const r0 = srv.requests();
  const out = await ev(`(() => { ${pre}; __fwclock.advanceTo(${vtMs}); return typeof __fwStepResult === 'undefined' ? null : __fwStepResult; })()`);
  if (mid) await mid(out);
  if (DEBUG) console.error('frame', vtMs.toFixed(1));
  let bf = null;
  for (let attempt = 0; attempt < 20 && !bf; attempt++) {
    bf = await Promise.race([c.send('HeadlessExperimental.beginFrame', { frameTimeTicks: T0 + vtMs, interval: dt, ...(shot ? { screenshot: { format: 'png' } } : {}) }), sleep(+(process.env.FW_BF_TIMEOUT_MS ?? (loaded ? 5000 : 1500))).then(() => null)]);
    if (!bf && DEBUG) { console.error('beginFrame retry', attempt); console.error('main thread alive?', await Promise.race([ev('performance.now()').then((v) => 'yes ' + v, (e) => 'error ' + e), sleep(3000).then(() => 'NO (no answer in 3 s)')])); }
    if (!bf && DEBUG && process.env.FW_EXTRA_CATEGORIES) { const done = new Promise((res) => c.once('Tracing.tracingComplete', res)); await c.send('Tracing.end'); const { stream } = await done; let tx = ''; for (;;) { const r = await c.send('IO.read', { handle: stream, size: 1 << 20 }); tx += r.data; if (r.eof) break; } writeFileSync(`${OUT}/hang-trace.json`, tx); console.error('hang trace written'); process.exit(3); }
    if (!bf && loaded) { console.error(`FW_BEGINFRAME_HANG: no answer to beginFrame at vt ${vtMs} (touch events unacknowledged: ${touch.unacked}); the container is no good, run it again`); process.exit(75); }
  }
  if (!bf) throw new Error('beginFrame never answered at vt ' + vtMs);
  if (touch.unacked > 0) { const t = Date.now(); await Promise.race([touch.settled(), sleep(TOUCH_ACK_MS)]); if (DEBUG) console.error('touch unacked', touch.unacked, 'after', Date.now() - t, 'ms'); }
  if (touch.sent > sent0) await sleep(TOUCH_POST_ACK_MS);
  await networkBarrier(r0);
  return { out, hasDamage: !!bf.hasDamage, screenshot: bf.screenshotData ?? null };
}

const navRes = await c.send('Page.navigate', { url: `http://127.0.0.1:${srv.port}/${SEARCH}` });
if (navRes.errorText) throw new Error('navigation failed: ' + navRes.errorText);
let quiet = 0, loadFrames = 0;
for (; loadFrames < profile.load.maxFrames && quiet < profile.load.quietFrames; loadFrames++) {
  vt = loadFrames * dt;
  await frame(vt);
  if (process.env.FW_LOAD_TRACE) console.error(`load frame ${loadFrames} vt ${vt.toFixed(1)} inflight ${srv.inflight()} requests ${srv.requests()}`);
  let hangTimer;
  const st = await Promise.race([
    ev(`document.readyState + ',' + (document.fonts ? document.fonts.status : 'loaded') + ',' + document.images.length + ',' + [...document.images].filter((i) => !i.complete).length`),
    new Promise((_, reject) => { hangTimer = setTimeout(() => hangProfile(loadFrames).catch(reject), 20000); }),
  ]).finally(() => clearTimeout(hangTimer));
  const [rs, fonts, , pendingImgs] = st.split(',');
  quiet = rs === 'complete' && fonts === 'loaded' && srv.inflight() === 0 ? quiet + 1 : 0;
}
if (quiet < profile.load.quietFrames) throw new Error(`page not quiet after ${loadFrames} frames (server inflight ${srv.inflight()})`);
loaded = true;
vt = START_VT;
for (let i = 0; i < profile.load.prerollFrames; i++, vt += dt) { await frame(vt); }
if (process.env.FW_LOAD_ONLY) { console.error(`FW_LOAD_OK: ${loadFrames} load frames and ${profile.load.prerollFrames} pre-roll frames without a crash`); chrome.kill('SIGKILL'); process.exit(0); }
const geo = await ev(`({ docH: document.documentElement.scrollHeight, innerH: innerHeight, innerW: innerWidth, y: scrollY, dpr: devicePixelRatio, lang: navigator.language, tz: Intl.DateTimeFormat().resolvedOptions().timeZone, now: new Date().toISOString(), el: document.getElementsByTagName('*').length, real: window.__fwRealSize ? window.__fwRealSize() : null, scrollW: document.documentElement.scrollWidth, clientW: document.documentElement.clientWidth, clientH: document.documentElement.clientHeight, scale: window.visualViewport ? visualViewport.scale : null })`);
const profileSize = { w: profile.viewport.width, h: profile.viewport.height };
const frame0 = { pinned: { w: geo.innerW, h: geo.innerH }, real: { w: geo.real?.w ?? -1, h: geo.real?.h ?? -1 }, client: { w: geo.clientW, h: geo.clientH } };
if (!viewportGate(profileSize, frame0)) {
  console.error(formatOverflow(await ev(overflowExpr()).catch(() => null)));
  throw new Error(`viewport not faithful: the page reports a real frame ${frame0.real.w}x${frame0.real.h} (pinned ${frame0.pinned.w}x${frame0.pinned.h}, client ${frame0.client.w}x${frame0.client.h}, scrollWidth ${geo.scrollW}, scale ${geo.scale}), the profile ${profile.viewport.width}x${profile.viewport.height}; the run is refused`);
}
const gate = gateSize(frame0);
const maxScroll = geo.docH - gate.h;
if (process.env.FW_PROBE === '1') {
  await ev(`window.__probe = {}; for (const t of ['touchstart','touchmove','touchend','pointerdown','pointermove','pointerup','pointercancel','scroll','mousemove','click','wheel']) addEventListener(t, (e) => { __probe[t] = (__probe[t]||0)+1; }, { capture: true, passive: true }); 0`);
}
let rewrite = null;
if (TARGET === 'rewrite') {
  rewrite = await ev(`(() => { const f = window.__fw; if (!f) return null; if (f.markMeasureStart) f.markMeasureStart(); return { configHash: f.configHash, config: f.config, mode: f.mode, hydrated: f.hydrated, hydrationErrors: f.hydrationErrors, buildId: f.buildId, styleMisses: f.styleMisses.length, stage: window.__fwStage ? [window.__fwStage.env.y, window.__fwStage.env.vw, window.__fwStage.env.vh] : null, stageMissing: window.__fwStage ? window.__fwStage.missing.length : 0, stageUnset: window.__fwStage ? window.__fwStage.unset : [] }; })()`);
  if (!rewrite) throw new Error('target rewrite: window.__fw missing');
  if (!accepts(SEARCH, profileSize, { mode: rewrite.mode, hydrated: rewrite.hydrated, errors: rewrite.hydrationErrors.length, stage: rewrite.stage, missing: rewrite.stageMissing })) throw new Error('rewrite not measurable: ' + JSON.stringify({ search: SEARCH, mode: rewrite.mode, hydrated: rewrite.hydrated, errors: rewrite.hydrationErrors, stage: rewrite.stage, missing: rewrite.stageMissing, unset: rewrite.stageUnset }));
}

const inputMode = profile.input?.mode ?? 'scrollTo';
const plan = [];
if (inputMode === 'scrollTo' || inputMode === 'page') {
  let y = 0;
  for (const seg of profile.segments) {
    if (seg.anchor) {
      const ay = await ev(`(() => { const e = document.querySelector(${JSON.stringify(seg.anchor.selector)}); return e ? Math.round(e.getBoundingClientRect().top + scrollY - ${Number(seg.anchor.viewportTop)}) : null; })()`);
      if (ay === null) throw new Error(`segment ${seg.name}: no element matches ${seg.anchor.selector}`);
      y = Math.max(0, Math.min(maxScroll, ay));
    }
    if (seg.until === 'end') { while (y < maxScroll) { y = Math.min(maxScroll, y + seg.dyPerFrame); plan.push({ phase: seg.name, y }); } }
    else for (let i = 0; i < seg.frames; i++) { y = Math.min(maxScroll, y + (seg.dyPerFrame ?? 0)); plan.push({ phase: seg.name, y, run: i === 0 ? seg.eval : undefined }); }
  }
}
function touchPlanner(inp) {
  let down = false, fingerY = 0, holds = 0, gap = 0;
  return function next(yPrev, ended) {
    if (!down) {
      if (ended) return null;
      if (gap > 0) { gap--; return { phase: 'settle', touch: null }; }
      down = true; fingerY = inp.startY;
      return { phase: 'settle', touch: { type: 'touchStart', y: fingerY } };
    }
    if (!ended && fingerY - inp.dyPerFrame >= inp.minY) { fingerY -= inp.dyPerFrame; return { phase: 'swipe', touch: { type: 'touchMove', y: fingerY } }; }
    if (holds < inp.holdFrames) { holds++; return { phase: 'settle', touch: null }; }
    down = false; holds = 0; gap = ended ? 0 : inp.gapFrames;
    return { phase: 'settle', touch: { type: 'touchEnd', y: fingerY } };
  };
}
async function sendTouch(t, vtMs) {
  const timestamp = (EPOCH_MS + vtMs) / 1000;
  const p = t.type === 'wheel'
    ? c.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: profile.input.x, y: t.y, deltaX: 0, deltaY: profile.input.dyPerFrame, timestamp })
    : c.send('Input.dispatchTouchEvent', { type: t.type, touchPoints: t.type === 'touchEnd' ? [] : [{ x: t.x ?? profile.input.x, y: t.y, id: 0, radiusX: 1, radiusY: 1, force: 1 }], timestamp });
  touch.unacked++; touch.sent++;
  const sentAt = touch.frames;
  if (DEBUG) console.error('touch send', t.type, t.y, 'frame', sentAt);
  p.then(() => {}, (e) => { touch.error ??= String(e); }).then(() => {
    if (DEBUG) console.error('touch ack', t.type, 'after', touch.frames - sentAt, 'frames');
    touch.unacked--;
    if (touch.unacked === 0) for (const w of touch.waiters.splice(0)) w();
  });
  await sleep(TOUCH_SETTLE_MS);
  return null;
}

const KEEP = ['LayoutCount', 'RecalcStyleCount', 'Nodes', 'LayoutObjects', 'JSEventListeners', 'Documents', 'Frames', 'Resources'];
let prev = Object.fromEntries((await c.send('Performance.getMetrics')).metrics.map((m) => [m.name, m.value]));
const n0Start = N0_ON ? JSON.parse(await ev('JSON.stringify(__fwN0.read())')) : null;
await c.send('Tracing.start', { transferMode: 'ReturnAsStream', traceConfig: { recordMode: 'recordAsMuchAsPossible', includedCategories: [...TRACE_CATEGORIES, ...(process.env.FW_EXTRA_CATEGORIES ? process.env.FW_EXTRA_CATEGORIES.split(',') : [])], traceBufferSizeInKb: 1_000_000 } });
const frames = [];
const wallStart = Date.now();
const record = (n, phase, scrollY, r) => {
  const m0 = r.metrics;
  const counts = { hasDamage: r.hasDamage ? 1 : 0 };
  for (const k of KEEP) counts['metric.' + k] = m0[k] - prev[k];
  prev = m0;
  frames.push({ n, phase, scrollY, vt: +(vt - START_VT).toFixed(3), counts });
};
const metricsNow = async () => Object.fromEntries((await c.send('Performance.getMetrics')).metrics.map((x) => [x.name, x.value]));
const warmN = inputMode === 'page' ? plan.filter((x) => x.phase === 'warm').length : 0;
if (inputMode === 'scrollTo' || inputMode === 'page') {
  for (let n = 0; n < plan.length; n++, vt += dt) {
    const { phase, y, run } = plan[n];
    const pre = inputMode === 'page'
      ? `console.timeStamp('F${n}'); ${phase === 'warm' ? `window.__fwWarm(${n})` : `window.__fwStep(${n - warmN})`}; var __fwStepResult = ${POS};`
      : `console.timeStamp('F${n}'); ${run ? `(function () { ${run} })();` : ''} window.scrollTo({ top: ${y}, left: 0, behavior: 'instant' }); var __fwStepResult = ${POS};`;
    const r = await frame(vt, pre);
    r.metrics = await metricsNow();
    record(n, phase, r.out, r);
  }
} else {
  const inp = profile.input;
  const touchNext = inputMode === 'wheel' ? (yNow, ended) => (ended ? null : { phase: 'swipe', touch: { type: 'wheel', y: inp.y } }) : touchPlanner(inp);
  let last = null, yMax = 0, n = 0, swipeFrames = 0, ended = false, finished = false;
  const runFrame = async (choose) => {
    let step = null;
    const r = await frame(vt, `var __fwStepResult = ${POS}; console.timeStamp('F${n}')`, async (yNow) => {
      if (last) last.scrollY = yNow;
      yMax = Math.max(yMax, yNow); if (DEBUG) console.error("y", yNow);
      if (process.env.FW_PROBE) console.error('probe', n, yNow, process.env.FW_PROBE === '1' ? JSON.stringify(await ev('JSON.stringify(window.__probe)')) : '');
      step = choose(yNow);
      if (step && step.touch) return sendTouch(step.touch, vt - START_VT);
      return null;
    });
    r.metrics = await metricsNow();
    if (!step) throw new Error('no step');
    record(n, step.phase, null, r);
    last = frames[frames.length - 1];
    n++; vt += dt;
  };
  const script = replayStrokes ? replayEvents(replayStrokes) : [];
  for (const seg of profile.segments) {
    if (seg.until === 'script') { for (let f = 0; f < script.length; f++) await runFrame(() => ({ phase: 'replay', touch: script[f] ?? null })); if (script.length > 0 && yMax < 1) throw new Error('replayed gesture did not scroll the page'); continue; }
    if (seg.until !== 'end') { for (let i = 0; i < seg.frames; i++) await runFrame(() => ({ phase: seg.name, touch: null })); continue; }
    for (let guard = 0; !finished; guard++) {
      let stop = false;
      await runFrame((yNow) => {
        if (yNow >= maxScroll - 0.5) ended = true;
        const st = touchNext(yNow, ended);
        if (!st) { stop = true; return { phase: 'settle', touch: null }; }
        if (st.phase === 'swipe') swipeFrames++;
        return st;
      });
      if (stop) finished = true;
      if (guard > inp.maxFrames) throw new Error('touch swipe did not finish within maxFrames');
      if (swipeFrames === 40 && yMax < 1) throw new Error('touch input did not scroll the page after 40 moves');
    }
  }
  await Promise.race([touch.settled(), sleep(TOUCH_ACK_MS * 10)]);
  if (touch.error || touch.unacked) throw new Error('touch events failed or unacknowledged at the end: ' + (touch.error ?? touch.unacked));
  const lastY = await ev(POS);
  last.scrollY = lastY;
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
let n0 = { enabled: false };
if (N0_ON) {
  const n0End = JSON.parse(await ev('JSON.stringify(__fwN0.read())'));
  const { win, perFrame: n0Frames } = n0Windows(n0End.events, frames.map((f) => f.vt + START_VT), START_VT, dt);
  for (let n = 0; n < frames.length; n++) Object.assign(frames[n].counts, n0FrameCounts(n0Frames[n]));
  const total = (l) => ({ total: l.length, byKind: byKind(l) });
  n0 = { enabled: true, keys: N0_KEYS, load: total(win.load), preroll: total(win.preroll), profile: total(n0Frames.flat()), after: total(win.after), shapeAtProfileStart: n0Start.shape, shapeAtEnd: n0End.shape, firstProfileEvents: n0Frames.flat().slice(0, 10) };
}

let probe = null;
if (profile.cardProbe && (inputMode === 'scrollTo' || inputMode === 'page')) try {
  const { selector, faceSelector } = profile.cardProbe;
  const read = `(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return null; const q = (n) => { const r = n.getBoundingClientRect(); return [r.left, r.top, r.width, r.height].map((v) => Math.round(v * 1000) / 1000); };
    const f = ${faceSelector ? `document.querySelector(${JSON.stringify(faceSelector)})` : 'null'};
    const cb = []; for (let n = e.parentElement; n; n = n.parentElement) { const cs = getComputedStyle(n); const why = [cs.transform !== 'none' && 'transform', cs.translate !== 'none' && 'translate', cs.filter !== 'none' && 'filter', cs.perspective !== 'none' && 'perspective', cs.contain !== 'none' && 'contain:' + cs.contain, /transform|translate/.test(cs.willChange) && 'will-change', cs.backdropFilter !== 'none' && 'backdrop-filter'].filter(Boolean); if (why.length) cb.push(n.tagName.toLowerCase() + '.' + String(n.className).slice(0, 40) + ' ' + why.join(',')); }
    return { rect: q(e), face: f ? q(f) : null, top: e.style.top, left: e.style.left, translate: e.style.translate, cb }; })()`;
  const rows = [];
  let prevPng = '', prevCard = null, containing = null;
  for (let n = 0; n < plan.length; n++, vt += dt) {
    const { phase, y, run } = plan[n];
    const r = await frame(vt, `${run ? `(function () { ${run} })();` : ''} window.scrollTo({ top: ${y}, left: 0, behavior: 'instant' }); var __fwStepResult = ${POS};`, null, true);
    const v = await ev(read);
    const { cb, ...rest } = v ?? {};
    if (v && containing === null) containing = cb;
    if (r.screenshot) {
      prevPng = createHash('sha256').update(r.screenshot).digest('hex').slice(0, 16);
      prevCard = v ? pngRegionHash(r.screenshot, v.rect[0] - 60, v.rect[1] - 60, v.rect[0] + v.rect[2] + 60, v.rect[1] + v.rect[3] + 60) : null;
    } else if (!v) prevCard = null;
    rows.push({ n, phase, y: r.out, png: prevPng, cardPng: v ? prevCard : null, found: v !== null, ...rest });
  }
  probe = { selector, containing, frames: rows };
} catch (e) { probe = { selector: profile.cardProbe.selector, error: String(e.message ?? e).slice(0, 300) }; } // the counts stay valid: the probe runs after them

const censusPump = async () => {
  vt += dt;
  await ev(`__fwclock.advanceTo(${vt})`);
  const bf = await Promise.race([c.send('HeadlessExperimental.beginFrame', { frameTimeTicks: T0 + vt, interval: dt }), sleep(5000).then(() => null)]);
  if (!bf) throw new Error('beginFrame unanswered in the census');
};
const layerCensus = await Promise.race([
  collectCensus(c, { ev, pump: censusPump, maxScroll: Math.round(maxScroll) }),
  sleep(120000).then(() => ({ schema: 'fw.layer-census/1', engine: 'chromium', error: 'census timed out', samples: [] })),
]).catch((e) => ({ schema: 'fw.layer-census/1', engine: 'chromium', error: String(e.message ?? e).slice(0, 300), samples: [] }));

const served = srv.served();
const servedSha = createHash('sha256').update(JSON.stringify(served)).digest('hex');
const result = {
  schema: 'fw.counts/1',
  engine: 'chromium-headless-shell',
  profile: { id: profile.id, file: `${profile.id}.json`, sha256: createHash('sha256').update(readFileSync(PROFILE_FILE)).digest('hex') },
  meta: {
    browser: version.Browser, browserArgs, protocol: version['Protocol-Version'],
    image: process.env.FW_IMAGE_ID ?? null, snapshot: process.env.FW_SNAPSHOT_ID ?? null,
    servedFiles: Object.keys(served).length, servedSha256: servedSha, missing: srv.missing(),
    viewport: profile.viewport, hz: profile.hz, startVirtualMs: START_VT, pinnedDate: profile.pinnedDate, pageDateAtStart: geo.now, timezone: geo.tz,
    target: TARGET, search: SEARCH, rewrite, input: { mode: inputMode, touchEventsSent: touch.sent }, trajectorySha256: createHash('sha256').update(JSON.stringify(frames.map((f) => [f.phase, f.scrollY]))).digest('hex'),
    n0, docHeightPx: geo.docH, innerWidthPx: frame0.real.w, innerHeightPx: frame0.real.h, pinnedInnerWidthPx: geo.innerW, pinnedInnerHeightPx: geo.innerH, clientWidthPx: geo.clientW, clientHeightPx: geo.clientH, gateSize: gate, scrollRead: scrollRead(SEARCH), scrollWidthPx: geo.scrollW, visualViewportScale: geo.scale, maxScrollPx: maxScroll, elementCountAtStart: geo.el, threads, layerCensus,
  },
  frames,
  runLevel,
  ...(probe ? { cardProbe: probe } : {}),
};
mkdirSync(OUT, { recursive: true });
writeFileSync(`${OUT}/counts.json`, JSON.stringify(result, null, 1) + '\n');
console.error(`frames=${frames.length} loadFrames(not recorded)=${loadFrames} wallMs=${wallMs} (not a measurement of the phone)`);
browser.disconnect(); chrome.kill('SIGKILL'); await srv.close();
process.exit(0);
