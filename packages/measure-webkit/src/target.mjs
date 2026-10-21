// The wait for the page target (glue: the bounds, the actions and the exit code are Lean's, Fw.Measure.SimBound, via
// inspector.mjs). The proxy and the socket can stay up with the tab listed while the inspector has no page target; the
// guard's probe does not see that, so the wait itself is bounded: every poll ends within what is left of the bound, past
// the bound Safari is relaunched once, and a second loss (or a failed relaunch) fails the session with exit code 5.
import { targetAction, targetAfterRelaunch, targetCapMs, TargetLostError } from './inspector.mjs';
import { realClock } from './poll.mjs';

/**
 * `p` with an end: rejects with an error after `ms`. A value that arrives after that is handed to `late` (it closes a
 * connection nobody waits for), and the timer never outlives `p`.
 */
export function capped(ms, p, { late = () => {}, what = 'the poll', after = realAfter } = {}) {
  let cancel, expired = false;
  const end = new Promise((_, rej) => { cancel = after(ms, () => { expired = true; rej(new Error(`${what} took longer than ${Math.round(ms / 1000)} s`)); }); });
  p.then((v) => { if (expired) late(v); }, () => {});
  return Promise.race([p, end]).finally(() => cancel());
}
/** A timer that can be cancelled; the injectable clock of the tests replaces it. */
const realAfter = (ms, fn) => { const t = setTimeout(fn, ms); return () => clearTimeout(t); };

/**
 * Poll for the page target until a poll finds it; follow Lean's `targetAction` after every poll.
 * @param {{tryOnce:(capMs:number)=>Promise<any>, relaunch?:(()=>Promise<void>)|null, relaunched?:boolean, pauseMs?:(err:Error)=>number,
 *   log?:Function, clock?:{now:()=>number, sleep:(ms:number)=>Promise<void>}, late?:Function}} o
 *   tryOnce: one poll; it resolves to the connected client or rejects with the reason. relaunch: Safari once more within
 *   its own bound (rejects when it cannot, e.g. Safari was relaunched already); without it the first loss fails the session.
 * @returns {Promise<any>} what the successful poll resolved to
 */
export async function waitForTarget({ tryOnce, relaunch = null, relaunched = false, pauseMs = () => 500, log = () => {}, clock = realClock, late = () => {} }) {
  let r = relaunched, t0 = clock.now(), tries = 0, last = 'no tab listed', logged = '', loggedAt = 0;
  for (;;) {
    const before = clock.now() - t0;
    const cap = targetCapMs(r, before);
    let found = null, pause = 500;
    if (cap > 0) {
      tries++;
      try { found = await capped(cap, tryOnce(cap), { late, after: clock.after ?? realAfter }); } catch (e) { last = e.cause?.code || e.message; pause = pauseMs(e); }
    }
    const elapsed = clock.now() - t0;
    const act = targetAction(r, elapsed, found !== null);
    if (act === 'connect') return found;
    if (act === 'wait') {
      if (last !== logged || clock.now() - loggedAt > 10000) {
        log(`  waiting for the Safari tab (${Math.round(elapsed / 1000)} s of ${Math.round((elapsed + targetCapMs(r, elapsed)) / 1000)} s, try ${tries}): ${last}`);
        logged = last; loggedAt = clock.now();
      }
      await clock.sleep(Math.min(pause, targetCapMs(r, elapsed)));
      continue;
    }
    const why = `no page target after ${Math.round(elapsed / 1000)} s (${last}; ${tries} tries)`;
    if (act === 'failSession') throw new TargetLostError(`${why}; Safari was relaunched and the page target is still lost`);
    log(`page target lost: ${why}; relaunching Safari once`);
    let ok = true, failure = '';
    try { if (!relaunch) throw new Error('no relaunch available'); await relaunch(); } catch (e) { ok = false; failure = e.message; }
    if (targetAfterRelaunch(ok) === 'failSession') throw new TargetLostError(`${why}; the relaunch failed: ${failure}`);
    r = true; t0 = clock.now(); tries = 0; last = 'no tab listed'; logged = '';
  }
}
