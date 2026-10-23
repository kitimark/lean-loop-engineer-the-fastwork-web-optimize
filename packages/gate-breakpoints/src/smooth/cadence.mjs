// The cadence lane (task smoothness-probe, part B): how evenly frames arrive while a scripted wheel scroll runs, per arm, per window.
// Glue only. The decisions (a bad frame, a rate, the A/A spread, the verdict) are reduce.mjs, the TS twin of lean/Fw/Gate/Smooth.lean.
//
// Arms: the original (`orig`), the faithful rewrite (`base`), the same faithful rewrite on a second server (`aa`, so base against aa is
// the A/A pair that bounds the noise) and the candidate (`cand`, the dispatched search). Windows:
//   hero: from the top, a wheel burst of 60 events of 42 px every 16 ms (about 2520 px, the span the phone note measured)
//   end:  approach to the end of the page, rest, then one wheel push open and one push close (the end-of-page morph), each held 1 s
// Every window is read by an in-page rAF recorder (the phone note's probe): the intervals between rAF callbacks, in tenths of ms.
// Reps: each rep opens a fresh page per arm and window; arms are interleaved per rep and the order rotates, so slow drift of the
// runner hits every arm alike. Traced reps (`traceReps`) repeat the windows with Chromium's frame trace on; tracing slows the page,
// so those reps are reported apart and never enter the verdict.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PIN_SRC, waitReady } from '../page.mjs';
import { startServer, snapshotRoot, siteDist, rewriteFor } from '../serve.mjs';
import { envFor } from '../trajectory/registry.mjs';
import { runCheck } from '../trajectory/reduce.mjs';
import { HERO_BURST, END_PUSH, orderFor } from './schedule.mjs';
import { hundredthsFrom } from './reduce.mjs';
import { launchCadence } from './launch.mjs';
import { eventsOf, summariseTrace } from './trace.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const HISTOGRAM_WAIT_MS = 600;
const log = (...a) => process.stderr.write(`${a.join(' ')}\n`);

/**
 * Installed before the page's own scripts: a rAF loop that records callback times and the scroll position while `on`, and the
 * long animation frames the browser reports (duration, blocking time, scripts), so a bad frame can be placed and attributed
 * afterwards. It only observes; descriptive, never in the verdict.
 */
export function installRecorder() {
  const st = { on: false, ts: [], ys: [], loaf: [], t0: 0 };
  window.__sm = st;
  const tick = (t) => { if (st.on) { st.ts.push(t); st.ys.push(Math.round(window.scrollY)); } requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
  try {
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) {
        if (!st.on || e.startTime < st.t0) continue;
        st.loaf.push({ at: Math.round(e.startTime), d: Math.round(e.duration), block: Math.round(e.blockingDuration || 0),
          scripts: (e.scripts || []).slice(0, 4).map((x) => ({ src: String(x.sourceURL || '').split('/').slice(-2).join('/'), fn: x.sourceFunctionName || '', inv: x.invoker || '', d: Math.round(x.duration) })) });
      }
    }).observe({ type: 'long-animation-frame', buffered: false });
  } catch { /* no long-animation-frame in this engine */ }
  st.start = () => { st.ts = []; st.ys = []; st.loaf = []; st.t0 = performance.now(); st.on = true; };
  st.stop = () => { st.on = false; return { ts: st.ts, ys: st.ys, loaf: st.loaf }; };
}
const INIT = `${PIN_SRC}\n(${installRecorder.toString()})();`;

export { HERO_BURST, END_PUSH, orderFor };

/** Tenths of ms between neighbouring rAF timestamps (ms, fractional). */
export const intervalsOf = (ts) => ts.slice(1).map((t, i) => Math.round((t - ts[i]) * 10));

/** Scroll to the end of the page and let it rest (the same place the trajectory probe's approach ends at). */
const toEnd = () => new Promise((resolve) => {
  window.scrollTo(0, document.documentElement.scrollHeight - window.innerHeight);
  setTimeout(resolve, 1800);
});

async function open(engine, env, origin, site, search) {
  const s = await engine.open({ origin, path: site === 'rewrite' ? `/${search}` : '/', init: INIT });
  await s.evaluate(waitReady, { site, capMs: 20000 });
  const arm = await s.evaluate(() => (window.__fw ? { config: window.__fw.configHash ?? null, mode: window.__fw.mode ?? null } : { config: null, mode: null }));
  return { s, arm };
}

async function oneWindow(engine, env, a, win, traced, cpuThrottle) {
  const { s, arm } = await open(engine, env, a.origin, a.site, a.search);
  try {
    const cx = env.width / 2;
    const cy = env.height / 2;
    if (win === 'end') await s.evaluate(toEnd);
    else await sleep(400);
    await s.setCpuThrottle(cpuThrottle);
    if (traced) await s.startTrace();
    await s.histograms();
    await s.evaluate(() => window.__sm.start());
    if (win === 'hero') {
      await s.wheelBurst(cx, cy, HERO_BURST.dy, HERO_BURST.count, HERO_BURST.everyMs);
      await sleep(HERO_BURST.tailMs);
    } else {
      await s.wheel(cx, cy, END_PUSH.dy);
      await sleep(END_PUSH.holdMs);
      await s.wheel(cx, cy, -END_PUSH.dy);
      await sleep(END_PUSH.holdMs);
    }
    const rec = await s.evaluate(() => window.__sm.stop());
    await sleep(HISTOGRAM_WAIT_MS);
    const hist = (await s.histograms())?.filter((h) => h.count > 0) ?? null;
    const trace = traced ? summariseTrace(eventsOf(await s.stopTrace())) : null;
    return { ivs: intervalsOf(rec.ts), th: hundredthsFrom(rec.ts), ys: rec.ys.slice(1), loaf: rec.loaf, arm, trace, hist };
  } finally { await s.close().catch(() => {}); }
}

export async function runCadence({ widths, search = '', reps = 6, traceReps = 2, cpuThrottle = 1, env = process.env, chromePath }) {
  const variant = rewriteFor(siteDist(env), { ...env, FW_SEARCH: search });
  const configs = JSON.parse(readFileSync(join(siteDist(env), 'configs.json'), 'utf8'));
  const baseHash = configs.bySearch[''];
  const want = variant.hash ?? baseHash;
  const origin = await startServer(snapshotRoot(env));
  const faithful = await startServer(siteDist(env));
  const second = await startServer(siteDist(env));
  const rewrite = variant.rewrite ? await startServer(siteDist(env), variant.rewrite) : faithful;
  const arms = [
    { id: 'orig', site: 'orig', search: '', want: null, origin: origin.origin },
    { id: 'base', site: 'rewrite', search: '', want: baseHash, origin: faithful.origin },
    { id: 'aa', site: 'rewrite', search: '', want: baseHash, origin: second.origin },
    { id: 'cand', site: 'rewrite', search, want, origin: rewrite.origin },
  ];
  const runs = [];
  const traces = [];
  let refused = false;
  let version = '';
  try {
    for (const width of widths) {
      const e = envFor(width);
      const engine = await launchCadence({ chromePath, env: e });
      version = await engine.version();
      try {
        const total = reps + traceReps;
        outer: for (let rep = 0; rep < total; rep++) {
          const traced = rep >= reps;
          for (const a of orderFor(arms, rep)) {
            for (const win of ['hero', 'end']) {
              const t0 = Date.now();
              const r = await oneWindow(engine, e, a, win, traced, cpuThrottle);
              const row = { width, arm: a.id, window: win, rep: traced ? rep - reps : rep, config: r.arm.config, mode: r.arm.mode };
              if (traced) traces.push({ ...row, trace: r.trace, frames: r.ivs.length });
              else runs.push({ ...row, ivs: r.ivs, th: r.th, ys: r.ys, loaf: r.loaf, hist: r.hist });
              if (runCheck([{ site: a.site, want: a.want, config: r.arm.config, mode: r.arm.mode }]) !== 'ok') {
                refused = true;
                log(`cadence ${width} ${a.id} ${win}: REFUSED config (${JSON.stringify(r.arm)})`);
                break outer;
              }
              log(`cadence ${width} rep ${rep}${traced ? ' (traced)' : ''} ${a.id} ${win}: ${r.ivs.length} frames in ${Date.now() - t0} ms`);
            }
          }
        }
      } finally { await engine.close().catch(() => {}); }
      if (refused) break;
    }
    return { engine: 'chromium', version, cpuThrottle, search, hash: want, baseHash, reps, traceReps, hero: HERO_BURST, end: END_PUSH, refused, runs, traces };
  } finally {
    await origin.close(); await faithful.close(); await second.close();
    if (rewrite !== faithful) await rewrite.close();
  }
}
