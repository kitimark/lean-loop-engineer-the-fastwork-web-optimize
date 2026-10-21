import { performance } from 'node:perf_hooks';
import { POLL_JS } from '../device-record.mjs';
import { startRecorderJs, recorderSeconds, checkRecord } from '../device-replay-wd.mjs';
import { compile, simulateEvents, expected, seen, LIM } from '../device-replay.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function sleepUntil(target, clock = () => performance.now(), wait = sleep) {
  for (;;) {
    const left = target - clock();
    if (left <= 0) return;
    if (left > 3) await wait(left - 2);
  }
}

const TOUCH = { s: 'touchStart', m: 'touchMove', e: 'touchEnd' };

export const touchMessage = ([, ph, x, y]) => ({ type: TOUCH[ph], touchPoints: ph === 'e' ? [] : [{ x, y, id: 0 }] });

export async function dispatchAt(cdp, events, { clock = () => performance.now(), wait = sleep } = {}) {
  const t0 = clock() + 50;
  const late = [], pending = [];
  for (const e of events) {
    await sleepUntil(t0 + e[0], clock, wait);
    late.push(clock() - (t0 + e[0]));
    pending.push(cdp.send('Input.dispatchTouchEvent', touchMessage(e)));
  }
  await Promise.all(pending);
  return late;
}

export function lateStats(late) {
  const s = [...late].sort((a, b) => a - b);
  const at = (q) => (s.length === 0 ? 0 : s[Math.min(s.length - 1, Math.ceil(q * s.length) - 1)]);
  return { n: s.length, max: Number((s[s.length - 1] ?? 0).toFixed(2)), p95: Number(at(0.95).toFixed(2)) };
}

export async function chromiumPass({ browser, origin, profile, throttle = 6, lim = LIM, settleMs = 4000, pollMs = 1000, log = () => {} }) {
  const acts = compile(profile);
  const context = await browser.newContext({ viewport: { width: profile.w, height: profile.h }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  try {
    await context.route('**/*', (route) => (route.request().url().startsWith(origin) ? route.continue() : route.abort()));
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    if (profile.load === 'cold') await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle });
    await page.goto(`${origin}/`, { waitUntil: 'load' });
    await sleep(settleMs);
    await page.evaluate('scrollTo({ top: 0, behavior: "instant" }); 1');
    if (profile.load !== 'cold') await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle });
    const seconds = recorderSeconds(acts);
    await page.evaluate(startRecorderJs(seconds));
    const events = simulateEvents(acts);
    log(`replaying ${profile.id}: ${events.length} touch events, ${(acts.reduce((t, a) => t + (a[0] === 'm' ? a[3] : a[0] === 'p' ? a[1] : 0), 0) / 1000).toFixed(1)} s, throttle ${throttle}x`);
    const late = await dispatchAt(cdp, events);
    let rec = null;
    const tEnd = Date.now() + (seconds + 90) * 1000;
    while (rec === null && Date.now() < tEnd) {
      await sleep(pollMs);
      const v = await page.evaluate(POLL_JS);
      if (v) rec = JSON.parse(v);
    }
    if (rec === null || rec.err) throw new Error(`recording did not finish: ${rec?.err ?? 'timeout'}`);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    const c = checkRecord({ rec, profile, lim });
    return {
      matches: c.matches, perSwipe: c.perSwipe, swipesSeen: c.rep.length, swipesSent: profile.swipes.length, report: c.report,
      eventCounts: { sent: events.length, expected: profile.swipes.reduce((n, s) => n + expected(s).length, 0), seen: c.rep.reduce((n, s) => n + seen(s).length, 0) },
      late: lateStats(late), frames: rec.frames.t.length, zoomFrames: rec.zoom?.frames ?? 0,
    };
  } finally {
    await context.close();
  }
}

export function table(run) {
  const rows = ['| kind | rep | profile | swipes seen/sent | events sent/expected/seen | replayMatches | frames >34 ms | frames >50 ms | moving frames | dispatch late p95/max ms |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'];
  for (const p of run.passes) {
    const t = p.report.total;
    rows.push(`| ${p.kind} | ${p.rep} | ${p.profile} | ${p.swipesSeen}/${p.swipesSent} | ${p.eventCounts.sent}/${p.eventCounts.expected}/${p.eventCounts.seen} | ${p.matches} | ${t.over34} | ${t.over50} | ${t.n} | ${p.late.p95}/${p.late.max} |`);
  }
  return `${rows.join('\n')}\n`;
}
