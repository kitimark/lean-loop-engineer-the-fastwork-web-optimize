// Replaying a profile on the phone through safaridriver's W3C Perform Actions (pointerType touch), and reading back what the page saw.
// I/O glue only: the actions, the check and the profiles are device-replay.mjs (Lean Fw.Device.Replay). The page is the one the
// recorder already measures (RECORD_JS of device-record.mjs, native requestAnimationFrame, passive touch listeners). The address of
// the page comes from the caller and is never printed.
import { spawn } from 'node:child_process';
import { RECORD_JS, POLL_JS } from './device-record.mjs';
import { reducePass, normalize } from './device-session.mjs';
import { compile, w3c, actsMs, simulateEvents, swipesOf, touchesOf, conjuncts, replayMatches, LIM, schedule, makeProfile } from './device-replay.mjs';

const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));

/** A minimal W3C WebDriver client over fetch. `base` is e.g. http://127.0.0.1:4444 . */
export function wdClient(base, fetchImpl = globalThis.fetch) {
  const call = async (method, path, body) => {
    const res = await fetchImpl(`${base}${path}`, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    let json;
    try { json = text ? JSON.parse(text) : {}; } catch { json = { value: { message: text } }; }
    if (!res.ok || json.value?.error) throw new Error(`webdriver ${method} ${path.replace(/\/session\/[^/]+/, '/session/_')}: ${json.value?.error ?? res.status}: ${String(json.value?.message ?? '').slice(0, 200)}`);
    return json.value;
  };
  return {
    status: () => call('GET', '/status'),
    async newSession(capabilities) { const v = await call('POST', '/session', { capabilities: { alwaysMatch: capabilities } }); return v.sessionId; },
    url: (sid, u) => call('POST', `/session/${sid}/url`, { url: u }),
    execute: (sid, script, args = []) => call('POST', `/session/${sid}/execute/sync`, { script, args }),
    perform: (sid, payload) => call('POST', `/session/${sid}/actions`, payload),
    release: (sid) => call('DELETE', `/session/${sid}/actions`),
    quit: (sid) => call('DELETE', `/session/${sid}`),
  };
}

/** Start `safaridriver -p port` as our own child and wait until it answers; resolves {base, stop}. */
export async function startSafaridriver(port, { bin = 'safaridriver', log = () => {} } = {}) {
  const child = spawn(bin, ['-p', String(port)], { stdio: 'ignore' });
  let dead = null;
  child.on('exit', (c) => { dead = c; });
  const base = `http://127.0.0.1:${port}`;
  const wd = wdClient(base);
  const t0 = Date.now();
  for (;;) {
    if (dead !== null) throw new Error(`safaridriver exited with ${dead} (is it enabled: safaridriver --enable?)`);
    try { await wd.status(); break; } catch { /* not up yet */ }
    if (Date.now() - t0 > 15000) { child.kill('SIGTERM'); throw new Error('safaridriver did not answer within 15 s'); }
    await sleepMs(300);
  }
  log(`safaridriver up on port ${port}`);
  return { base, stop: () => { if (dead === null) child.kill('SIGTERM'); } };
}

/** The script that starts the page recorder without blocking the call (as phoneRecord does). */
export const startRecorderJs = (seconds) =>
  `window.__wkRecOn = true; window.__wkRec = undefined; Promise.resolve(${RECORD_JS(seconds)}).then(v => { window.__wkRec = JSON.stringify(v); }, e => { window.__wkRec = JSON.stringify({err: String(e)}); }); 'started'`;

/** Seconds the recorder runs: the replay, a margin for the fling after the last lift, and the call latency. */
export const recorderSeconds = (acts) => Math.ceil(actsMs(acts) / 1000) + 8;

/**
 * One pass: load the page, record, perform the compiled actions, read the page's record, check it. Opts: wd, caps, url, profile,
 * lim, settleMs, pollMs, session (reuse an open session id; a cold profile opens a fresh one), log, sleep.
 * Returns the record, the replay's swipes, the conjuncts per swipe, replayMatches and the frame reduction of the record.
 */
export async function replayPass({ wd, caps, url, profile, lim = LIM, settleMs = 6000, pollMs = 2500, session = null, log = () => {}, sleep = sleepMs }) {
  const acts = compile(profile);
  if (acts.length === 0) throw new Error(`profile ${profile.id} compiles to no actions`);
  const fresh = session === null || profile.load === 'cold';
  const sid = fresh ? await wd.newSession(caps) : session;
  try {
    await wd.url(sid, url);
    await sleep(settleMs);
    await wd.execute(sid, 'scrollTo({ top: 0, behavior: "instant" }); return 1');
    const seconds = recorderSeconds(acts);
    await wd.execute(sid, `${startRecorderJs(seconds)}; return 'started'`);
    log(`replaying ${profile.id}: ${acts.length} actions, ${(actsMs(acts) / 1000).toFixed(1)} s, recorder ${seconds} s`);
    await wd.perform(sid, w3c(acts));
    await wd.release(sid).catch(() => {});
    let rec = null;
    const tEnd = Date.now() + (seconds + 90) * 1000;
    while (rec === null && Date.now() < tEnd) {
      await sleep(pollMs);
      const v = await wd.execute(sid, `return ${POLL_JS}`);
      if (v) rec = JSON.parse(v);
    }
    if (rec === null || rec.err) throw new Error(`recording did not finish: ${rec?.err ?? 'timeout'}`);
    return { sid, ...checkRecord({ rec, profile, lim }) };
  } finally {
    if (fresh) await wd.quit(sid).catch(() => {});
  }
}

/** The check of a page record against the profile it replayed: swipes the page saw, conjuncts per swipe, replayMatches, frame reduction. */
export function checkRecord({ rec, profile, lim = LIM }) {
  const rep = swipesOf(touchesOf(rec));
  const perSwipe = profile.swipes.slice(0, rep.length).map((a, i) => conjuncts(lim, a, rep[i]));
  return { rec, rep, perSwipe, matches: replayMatches(lim, profile.swipes, rep), report: reducePass(normalize(rec)) };
}

/** What a phone (or its double) does with actions, for tests: a WebDriver double whose page sees the events of the simulated touch source. */
export function doubleWd(capture = {}) {
  const sessions = new Map();
  let n = 0;
  return {
    status: async () => ({ ready: true }),
    async newSession() { const id = `s${++n}`; sessions.set(id, { rec: null, actions: null }); return id; },
    url: async () => null,
    async execute(sid, script) {
      const s = sessions.get(sid);
      if (script.includes('window.__wkRecOn = true')) { s.armed = true; return 'started'; }
      if (script.includes('window.__wkRec')) return s.rec ? JSON.stringify(s.rec) : null;
      return 1;
    },
    async perform(sid, payload) {
      const s = sessions.get(sid);
      capture.payload = payload;
      const acts = payload.actions[0].actions.map((a) => (a.type === 'pointerMove' ? ['m', a.x, a.y, a.duration] : a.type === 'pointerDown' ? ['d'] : a.type === 'pointerUp' ? ['u'] : ['p', a.duration]));
      const ev = simulateEvents(acts);
      s.rec = { zoom: { frames: 0, min: 1, max: 1 }, maxY: 5000, viewport: { w: 390, h: 844, dpr: 3 }, frames: { t: [0, 16.7, 33.4], y: [0, 0, 0], p: { hero: [0, 0, 0], people: [0, 0, 0], fade: [0, 0, 0] } },
        touches: ev.map(([t, ph, x, y]) => [1000 + t, ph === 'e' ? 'e' : ph, x, y, ph === 'e' ? 0 : 1]) };
      return null;
    },
    release: async () => null,
    quit: async (sid) => { sessions.delete(sid); return null; },
  };
}

/**
 * A session: every kind of profile, `reps` repeats, the arm order rotated per repeat. `arms` are {name, url}; `base` the recorded
 * profile; `gen` {n, gap, reps, zone: {maxY10, frames, t0}} the generator inputs. Returns the passes in the order they ran.
 */
export async function runSession({ wd, caps, arms, base, kinds, reps, gen, lim = LIM, settleMs, pollMs, log = () => {}, sleep }) {
  const passes = [];
  for (const run of schedule(kinds, reps, arms.length)) {
    const profile = makeProfile({ profile: base, zone: gen.zone }, run.kind, gen);
    if (profile === null) { log(`kind ${run.kind}: the recorded pass has no swipe for it; skipped`); continue; }
    for (const ai of run.order) {
      const r = await replayPass({ wd, caps, url: arms[ai].url, profile, lim, settleMs, pollMs, log, sleep });
      passes.push({ kind: run.kind, rep: run.rep, arm: arms[ai].name, profile: profile.id, matches: r.matches, perSwipe: r.perSwipe, report: r.report, swipes: r.rep.length });
      log(`${run.kind} rep ${run.rep} arm ${arms[ai].name}: replayMatches ${r.matches}, ${r.rep.length} of ${profile.swipes.length} swipes seen, total over34 ${r.report.total.over34}/${r.report.total.n}`);
    }
  }
  return { passes };
}
