export const READY_CFG = Object.freeze({ launches: 3, launchMs: 150000, killMs: 10000, stopWaitMs: 20000 });

export const RESTART_CFG = Object.freeze({ launches: 1, launchMs: 470000, killMs: 10000, stopWaitMs: 20000 });

export const LAUNCH_FAULTS = Object.freeze({ launchStuck: 'driver-launch-stuck', bodyStuck: 'driver-body-stuck', ended: 'driver-ended' });
export const STOP_LATE_BODY = 'driver-stop-late-body';
export const STOP_LATE_TEARDOWN = 'driver-stop-late-teardown';

/** True when xcodebuild's output shows the PushServer test body returned: its `Tear Down` line or the end of the test case. TS stand-in: log parsing, no decision. */
export const bodyEndedIn = (text) => /^\s*t =\s*[\d.]+s Tear Down\s*$/m.test(text) || /Test [Cc]ase\b[^\n]*\btestServe\b[^\n]*\b(?:passed|failed)\b/.test(text);

export const faultOf = (o) => (o.ended ? LAUNCH_FAULTS.ended : o.alive ? LAUNCH_FAULTS.bodyStuck : LAUNCH_FAULTS.launchStuck);

export function verdict(c, n, o) {
  if (o.ready) return 'ready';
  if (o.ended || c.launchMs <= o.elapsed) return `${n < c.launches ? 'relaunch' : 'give'}:${faultOf(o)}`;
  return 'wait';
}

export const stopStep = (c, exited, bodyEnded, waitedMs) => (exited ? 'clean' : c.stopWaitMs <= waitedMs ? (bodyEnded ? STOP_LATE_TEARDOWN : STOP_LATE_BODY) : 'wait');

const reached = (x, at) => x != null && x <= at;

export function replay(c, trajs) {
  const go = (fuel, n, ls) => {
    if (fuel === 0) return { ready: false, faults: [], ms: 0 };
    const t = ls[0] ?? { aliveAt: null, readyAt: null, endedAt: null };
    let x = reached(t.readyAt, c.launchMs) ? t.readyAt : c.launchMs;
    if (t.endedAt != null && t.endedAt < x) x = t.endedAt;
    const o = { ready: reached(t.readyAt, x), alive: reached(t.aliveAt, x), ended: reached(t.endedAt, x), elapsed: x };
    const v = verdict(c, n, o);
    if (v === 'ready') return { ready: true, faults: [], ms: x };
    if (v.startsWith('relaunch:')) {
      const r = go(fuel - 1, n + 1, ls.slice(1));
      return { ready: r.ready, faults: [v.slice(9), ...r.faults], ms: x + c.killMs + r.ms };
    }
    if (v.startsWith('give:')) return { ready: false, faults: [v.slice(5)], ms: x + c.killMs };
    return { ready: false, faults: [], ms: x };
  };
  return go(c.launches, 1, trajs);
}

export function tallyJobs(jobs) {
  const count = (f) => jobs.reduce((a, j) => a + j.faults.filter((x) => x === f).length, 0);
  return {
    jobs: jobs.length, ready: jobs.filter((j) => j.ready).length, firstTry: jobs.filter((j) => j.ready && j.faults.length === 0).length,
    relaunched: jobs.filter((j) => j.faults.length > 0).length,
    [LAUNCH_FAULTS.launchStuck]: count(LAUNCH_FAULTS.launchStuck), [LAUNCH_FAULTS.bodyStuck]: count(LAUNCH_FAULTS.bodyStuck), [LAUNCH_FAULTS.ended]: count(LAUNCH_FAULTS.ended),
  };
}

export const jobOf = (records) => ({ faults: (records ?? []).map((r) => r.fault).filter(Boolean), ready: (records ?? []).length > 0 && records[records.length - 1].fault == null });

export const firstStart = (snap) => snap.touch?.launches?.find((e) => e.tag === 'serve')?.launches ?? snap.push?.launches ?? [];

/**
 * Drive the driver launches until one is ready or the launches are used. `start(n)` begins launch n and returns a handle
 * {exited: Promise, state: {ended, code}, kill()}; `look(h)` returns {alive, ready}. Everything timed comes in through `now` and `sleep`.
 * Resolves {handle, launches}; the handle is null when no launch became ready. Each record: {n, fault, ms, aliveAt, readyAt}.
 */
export async function launchUntilReady({ start, look, now, sleep, cfg = READY_CFG, pollMs = 250, log = () => {}, onCut = null }) {
  const launches = [];
  for (let n = 1; n <= cfg.launches; n++) {
    const handle = start(n);
    const t0 = now();
    const rec = { n, fault: null, ms: 0, aliveAt: null, readyAt: null };
    launches.push(rec);
    for (;;) {
      const seen = look(handle);
      const elapsed = now() - t0;
      if (seen.alive && rec.aliveAt == null) rec.aliveAt = elapsed;
      const v = verdict(cfg, n, { ready: seen.ready, alive: seen.alive, ended: handle.state.ended, elapsed });
      if (v === 'ready') { rec.readyAt = elapsed; rec.ms = elapsed; return { handle, launches }; }
      if (v !== 'wait') {
        rec.fault = v.slice(v.indexOf(':') + 1);
        rec.ms = elapsed;
        log(`launch ${n} of ${cfg.launches}: ${rec.fault} after ${Math.round(elapsed / 1000)} s`);
        onCut?.(rec, handle);
        const ended = handle.state.ended;
        handle.kill();
        if (!ended) await Promise.race([handle.exited, sleep(cfg.killMs)]);
        handle.release?.();
        break;
      }
      await sleep(pollMs);
    }
  }
  return { handle: null, launches };
}
