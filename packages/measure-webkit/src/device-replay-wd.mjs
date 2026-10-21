import { spawn, execFile } from 'node:child_process';
import { RECORD_JS, POLL_JS } from './device-record.mjs';
import { reducePass, normalize } from './device-session.mjs';
import { compile, pieces, pieceTimeoutMs, w3c, actsMs, simulateEvents, swipesOf, touchesOf, conjuncts, replayMatches, LIM, schedule, makeProfile } from './device-replay.mjs';

const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));

/** A WebDriver call that did not answer in time: the named error of the replay client (`code` wd-timeout). */
export class WdTimeout extends Error {
  constructor(call, timeoutMs) {
    super(`webdriver ${call} did not answer within ${timeoutMs} ms`);
    this.name = 'WdTimeout';
    this.code = 'wd-timeout';
    this.call = call;
    this.timeoutMs = timeoutMs;
  }
}

/**
 * A piece of the replay that did not complete in time: the named error (`code` replay-stall). The pieces before it ran; `call` is the
 * WebDriver call that timed out. On iOS the first suspects are the Safari first-run tip over the page (Simulator: `prepareSimulator`;
 * phone: the named user step in docs/team/tools/device-replay.md) and a swipe whose touch end never reaches the page (see the research note).
 */
export class ReplayStall extends Error {
  constructor({ profile, piece, pieces, call, timeoutMs }) {
    super(`replay of ${profile} stalled at piece ${piece + 1} of ${pieces}: ${call} did not answer within ${timeoutMs} ms`);
    this.name = 'ReplayStall';
    this.code = 'replay-stall';
    Object.assign(this, { profile, piece, pieces, call, timeoutMs });
  }
}

/** Time limits in ms of the calls that have no piece to derive one from. A /actions call takes `pieceTimeoutMs` of its piece. */
export const CALL_MS = Object.freeze({ status: 5000, session: 120000, url: 60000, execute: 30000, release: 15000, quit: 20000 });

const payloadMs = (payload) => payload.actions.reduce((m, src) => Math.max(m, src.actions.reduce((t, a) => t + (a.duration ?? 0), 0)), 0);

export function wdClient(base, fetchImpl = globalThis.fetch) {
  const call = async (method, path, body, timeoutMs) => {
    const name = `${method} ${path.replace(/\/session\/[^/]+/, '/session/_')}`;
    let res, text;
    try {
      res = await fetchImpl(`${base}${path}`, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(timeoutMs) });
      text = await res.text();
    } catch (e) {
      if (e?.name === 'TimeoutError' || e?.name === 'AbortError') throw new WdTimeout(name, timeoutMs);
      throw e;
    }
    let json;
    try { json = text ? JSON.parse(text) : {}; } catch { json = { value: { message: text } }; }
    if (!res.ok || json.value?.error) throw new Error(`webdriver ${name}: ${json.value?.error ?? res.status}: ${String(json.value?.message ?? '').slice(0, 200)}`);
    return json.value;
  };
  return {
    status: () => call('GET', '/status', undefined, CALL_MS.status),
    async newSession(capabilities) { const v = await call('POST', '/session', { capabilities: { alwaysMatch: capabilities } }, CALL_MS.session); return v.sessionId; },
    url: (sid, u) => call('POST', `/session/${sid}/url`, { url: u }, CALL_MS.url),
    execute: (sid, script, args = []) => call('POST', `/session/${sid}/execute/sync`, { script, args }, CALL_MS.execute),
    perform: (sid, payload, timeoutMs = pieceTimeoutMs(payloadMs(payload))) => call('POST', `/session/${sid}/actions`, payload, timeoutMs),
    release: (sid) => call('DELETE', `/session/${sid}/actions`, undefined, CALL_MS.release),
    quit: (sid) => call('DELETE', `/session/${sid}`, undefined, CALL_MS.quit),
  };
}

/** Send `sig` to the process group of `pid` (our own child: the pid is the group id because the child was spawned detached). */
export function killGroup(pid, sig, kill = process.kill) {
  try { kill(-pid, sig); return true; } catch { return false; }
}

/**
 * safaridriver in a process group of its own, so that stopping it takes its helpers with it. It is stopped (SIGTERM to the group, SIGKILL
 * after `graceMs`) when `stop()` is called, when this process exits and when this process gets SIGTERM or SIGINT; only the pid this
 * function spawned is ever signalled.
 */
export async function startSafaridriver(port, { bin = 'safaridriver', args = [], log = () => {}, graceMs = 3000, spawnImpl = spawn, kill = process.kill } = {}) {
  const child = spawnImpl(bin, ['-p', String(port), ...args], { stdio: 'ignore', detached: true });
  let dead = null;
  child.on('exit', (c, sig) => { dead = c ?? sig ?? 'signal'; });
  let killTimer = null;
  const stop = () => {
    if (dead !== null || child.pid === undefined) return;
    killGroup(child.pid, 'SIGTERM', kill);
    if (killTimer === null) { killTimer = setTimeout(() => { if (dead === null) killGroup(child.pid, 'SIGKILL', kill); }, graceMs); killTimer.unref?.(); }
  };
  const onExit = () => { if (child.pid !== undefined) killGroup(child.pid, 'SIGKILL', kill); };
  const handlers = {};
  for (const sig of ['SIGTERM', 'SIGINT']) handlers[sig] = () => { stop(); process.removeListener(sig, handlers[sig]); process.kill(process.pid, sig); };
  process.once('exit', onExit);
  for (const [sig, h] of Object.entries(handlers)) process.on(sig, h);
  child.on('exit', () => { process.removeListener('exit', onExit); for (const [sig, h] of Object.entries(handlers)) process.removeListener(sig, h); });
  const base = `http://127.0.0.1:${port}`;
  const wd = wdClient(base);
  const t0 = Date.now();
  try {
    for (;;) {
      if (dead !== null) throw new Error(`safaridriver exited with ${dead} (is it enabled: safaridriver --enable?)`);
      try { await wd.status(); break; } catch {}
      if (Date.now() - t0 > 15000) throw new Error('safaridriver did not answer within 15 s');
      await sleepMs(300);
    }
  } catch (e) { stop(); throw e; }
  log(`safaridriver up on port ${port} (process group ${child.pid})`);
  return { base, pid: child.pid, stop };
}

/**
 * Before a Simulator session: ask Safari for no first-run tips and end any Safari still paired with an earlier WebDriver session.
 * `run(cmd, args)` is `execFile`-like and resolves `{ err }`; failures are logged and ignored (an app that is not running is fine).
 */
export async function prepareSimulator(udid, { run, log = () => {} } = {}) {
  const exec = run ?? ((cmd, args) => new Promise((ok) => execFile(cmd, args, { timeout: 15000 }, (err, stdout) => ok({ err, stdout }))));
  const steps = [
    ['spawn', udid, 'defaults', 'write', 'com.apple.mobilesafari', 'com.apple.TipKit.HideAllTips', '-bool', 'true'],
    ['terminate', udid, 'com.apple.mobilesafari'],
  ];
  for (const st of steps) { const r = await exec('xcrun', ['simctl', ...st]); if (r?.err) log(`simctl ${st[0]}: ${String(r.err.message).split('\n')[0]}`); }
  return steps.map((st) => ['xcrun', 'simctl', ...st]);
}

export const startRecorderJs = (seconds) =>
  `window.__wkRecOn = true; window.__wkRec = undefined; Promise.resolve(${RECORD_JS(seconds)}).then(v => { window.__wkRec = JSON.stringify(v); }, e => { window.__wkRec = JSON.stringify({err: String(e)}); }); 'started'`;

export const recorderSeconds = (acts) => Math.ceil(actsMs(acts) / 1000) + 8;

export async function replayPass({ wd, caps, url, profile, lim = LIM, settleMs = 6000, pollMs = 2500, session = null, log = () => {}, sleep = sleepMs, prepare = null }) {
  const acts = compile(profile);
  if (acts.length === 0) throw new Error(`profile ${profile.id} compiles to no actions`);
  const fresh = session === null || profile.load === 'cold';
  if (fresh && prepare) await prepare();
  const sid = fresh ? await wd.newSession(caps) : session;
  try {
    await wd.url(sid, url);
    await sleep(settleMs);
    await wd.execute(sid, 'scrollTo({ top: 0, behavior: "instant" }); return 1');
    const seconds = recorderSeconds(acts);
    await wd.execute(sid, `${startRecorderJs(seconds)}; return 'started'`);
    log(`replaying ${profile.id}: ${acts.length} actions, ${(actsMs(acts) / 1000).toFixed(1)} s, recorder ${seconds} s`);
    const ps = pieces(profile);
    for (const [i, pc] of ps.entries()) {
      try {
        await wd.perform(sid, w3c(pc));
        await wd.release(sid).catch((e) => { if (e instanceof WdTimeout) throw e; });
      } catch (e) {
        if (e instanceof WdTimeout) throw new ReplayStall({ profile: profile.id, piece: i, pieces: ps.length, call: e.call, timeoutMs: e.timeoutMs });
        throw e;
      }
    }
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
    if (fresh) await wd.quit(sid).catch((e) => log(`quit: ${e.message}`));
  }
}

export function checkRecord({ rec, profile, lim = LIM }) {
  const rep = swipesOf(touchesOf(rec));
  const perSwipe = profile.swipes.slice(0, rep.length).map((a, i) => conjuncts(lim, a, rep[i]));
  return { rec, rep, perSwipe, matches: replayMatches(lim, profile.swipes, rep), report: reducePass(normalize(rec)) };
}

export function doubleWd(capture = {}) {
  const sessions = new Map();
  let n = 0;
  return {
    status: async () => ({ ready: true }),
    async newSession() { const id = `s${++n}`; sessions.set(id, { rec: null, offset: 0, touches: [] }); return id; },
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
      (capture.payloads ??= []).push(payload);
      const acts = payload.actions[0].actions.map((a) => (a.type === 'pointerMove' ? ['m', a.x, a.y, a.duration] : a.type === 'pointerDown' ? ['d'] : a.type === 'pointerUp' ? ['u'] : ['p', a.duration]));
      const ev = simulateEvents(acts);
      s.touches.push(...ev.map(([t, ph, x, y]) => [1000 + s.offset + t, ph === 'e' ? 'e' : ph, x, y, ph === 'e' ? 0 : 1]));
      s.offset += actsMs(acts);
      s.rec = { zoom: { frames: 0, min: 1, max: 1 }, maxY: 5000, viewport: { w: 390, h: 844, dpr: 3 }, frames: { t: [0, 16.7, 33.4], y: [0, 0, 0], p: { hero: [0, 0, 0], people: [0, 0, 0], fade: [0, 0, 0] } }, touches: s.touches };
      return null;
    },
    release: async () => null,
    quit: async (sid) => { sessions.delete(sid); return null; },
  };
}

export async function runSession({ wd, caps, arms, base, kinds, reps, gen, lim = LIM, settleMs, pollMs, log = () => {}, sleep, prepare = null }) {
  const passes = [];
  for (const run of schedule(kinds, reps, arms.length)) {
    const profile = makeProfile({ profile: base, zone: gen.zone }, run.kind, gen);
    if (profile === null) { log(`kind ${run.kind}: the recorded pass has no swipe for it; skipped`); continue; }
    for (const ai of run.order) {
      let r;
      try { r = await replayPass({ wd, caps, url: arms[ai].url, profile, lim, settleMs, pollMs, log, sleep, prepare }); } catch (e) {
        if (!(e instanceof ReplayStall)) throw e;
        const { piece, pieces: of, call, timeoutMs } = e;
        passes.push({ kind: run.kind, rep: run.rep, arm: arms[ai].name, profile: profile.id, matches: false, perSwipe: [], report: null, swipes: null, stalled: { piece, pieces: of, call, timeoutMs } });
        log(`${run.kind} rep ${run.rep} arm ${arms[ai].name}: ${e.message}; swipes seen unknown (the session no longer answers)`);
        continue;
      }
      passes.push({ kind: run.kind, rep: run.rep, arm: arms[ai].name, profile: profile.id, matches: r.matches, perSwipe: r.perSwipe, report: r.report, swipes: r.rep.length });
      log(`${run.kind} rep ${run.rep} arm ${arms[ai].name}: replayMatches ${r.matches}, ${r.rep.length} of ${profile.swipes.length} swipes seen, total over34 ${r.report.total.over34}/${r.report.total.n}`);
    }
  }
  return { passes };
}
