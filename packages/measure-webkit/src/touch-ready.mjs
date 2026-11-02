/** Launch, ready and stop decisions of the touch driver; stand-ins checked against lean/Fw/Measure/TouchReady.lean through contracts/golden/measure/touch-ready.jsonl. */
export const READY_CFG = Object.freeze({ launches: 3, launchMs: 150000, killMs: 10000, stopWaitMs: 20000 });

/** After a stalled window the Simulator is slow to start a driver (restarts became ready after 74 to 220 s), so a restart gets one long launch, no relaunch. */
export const RESTART_CFG = Object.freeze({ launches: 1, launchMs: 470000, killMs: 10000, stopWaitMs: 20000 });

export const LAUNCH_FAULTS = Object.freeze({ launchStuck: 'driver-launch-stuck', bodyStuck: 'driver-body-stuck', ended: 'driver-ended' });
export const STOP_LATE = 'driver-stop-late';

export const faultOf = (o) => (o.ended ? LAUNCH_FAULTS.ended : o.alive ? LAUNCH_FAULTS.bodyStuck : LAUNCH_FAULTS.launchStuck);

/** The step for launch number `n` (1-based) given what is seen: 'ready', 'wait', `relaunch:<fault>` or `give:<fault>`. */
export function verdict(c, n, o) {
  if (o.ready) return 'ready';
  if (o.ended || c.launchMs <= o.elapsed) return `${n < c.launches ? 'relaunch' : 'give'}:${faultOf(o)}`;
  return 'wait';
}

export const stopStep = (c, exited, waitedMs) => (exited ? 'clean' : c.stopWaitMs <= waitedMs ? STOP_LATE : 'wait');

const reached = (x, at) => x != null && x <= at;

/** The pure replay of the launch loop over recorded trajectories {aliveAt, readyAt, endedAt}. */
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

/** Count jobs {faults, ready} the way the Lean tally does. */
export function tallyJobs(jobs) {
  const count = (f) => jobs.reduce((a, j) => a + j.faults.filter((x) => x === f).length, 0);
  return {
    jobs: jobs.length, ready: jobs.filter((j) => j.ready).length, firstTry: jobs.filter((j) => j.ready && j.faults.length === 0).length,
    relaunched: jobs.filter((j) => j.faults.length > 0).length,
    [LAUNCH_FAULTS.launchStuck]: count(LAUNCH_FAULTS.launchStuck), [LAUNCH_FAULTS.bodyStuck]: count(LAUNCH_FAULTS.bodyStuck), [LAUNCH_FAULTS.ended]: count(LAUNCH_FAULTS.ended),
  };
}

/** A tally job from the launch records of the first start: ready when the last launch has no fault. */
export const jobOf = (records) => ({ faults: (records ?? []).map((r) => r.fault).filter(Boolean), ready: (records ?? []).length > 0 && records[records.length - 1].fault == null });

/** The launch records of the first start in a touch-lock.json or sim.json snapshot. */
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
