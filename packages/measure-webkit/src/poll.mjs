// Readiness polling for the I/O glue. A fixed sleep (T(3000), T(1500), T(2000) at scale 8 = 24 s, 12 s, 16 s) waits the
// worst case every time; these helpers wait for the condition itself and stop as soon as it holds, bounded by a
// deadline. No measurement logic: the clock is injectable so the tests run without waiting.
export const realClock = { now: () => Date.now(), sleep: (ms) => new Promise((r) => setTimeout(r, ms)) };

/** Poll `check` (sync or async; a throw counts as "not ready") until it returns a truthy value; throws after `timeoutMs`. */
export async function pollUntil(check, { timeoutMs, intervalMs = 250, clock = realClock, what = 'condition' } = {}) {
  const t0 = clock.now();
  let lastErr = '';
  for (;;) {
    try { const v = await check(); if (v) return v; lastErr = ''; } catch (e) { lastErr = ` (${e.message})`; }
    if (clock.now() - t0 >= timeoutMs) throw new Error(`${what} not ready in ${Math.round(timeoutMs / 1000)} s${lastErr}`);
    await clock.sleep(intervalMs);
  }
}

/**
 * Wait until the proxy lists a tab for the page. Safari drops the first `openurl` (10 of 10 first sessions on the CI
 * runner), so while no tab is listed `ask()` is sent again every `askEveryMs`; it stops asking once a tab is listed
 * (a second `openurl` after the tab exists could open a second tab). The caller has already asked once.
 * @returns {Promise<{tabs:object[], asks:number}>} asks = extra asks sent
 */
export async function ensureTab({ list, ask, askEveryMs = 6000, timeoutMs, intervalMs = 500, clock = realClock, log = () => {} }) {
  const t0 = clock.now();
  let lastAsk = t0, asks = 0, last = 'no tab listed';
  for (;;) {
    try {
      const tabs = await list();
      if (tabs.length) return { tabs, asks };
      last = 'no tab listed';
    } catch (e) { last = e.cause?.code || e.message; }
    const now = clock.now();
    if (now - t0 >= timeoutMs) throw new Error(`no Safari tab listed in ${Math.round(timeoutMs / 1000)} s (${last}; ${asks} extra openurl)`);
    if (now - lastAsk >= askEveryMs) {
      asks++;
      log(`  no tab after ${Math.round((now - t0) / 1000)} s: sending openurl again (extra ask ${asks})`);
      try { ask(); } catch (e) { log(`  openurl failed: ${e.message}`); }
      lastAsk = clock.now(); // an ask can block for a minute on a loaded host: count the next 6 s from its end
    }
    await clock.sleep(intervalMs);
  }
}

/**
 * After a navigation was requested from the old document, attach to the NEW one. The old document carried a marker
 * (`isFresh` is false for it), so a client that attached to the dying old page is released and the attach is repeated;
 * returns the first client whose document is the new one, once `ready` holds for it.
 */
export async function attachFresh({ attach, isFresh, ready, release, timeoutMs, intervalMs = 500, clock = realClock }) {
  const t0 = clock.now();
  const left = () => Math.max(1000, timeoutMs - (clock.now() - t0));
  let lastErr = 'old document still listed';
  for (;;) {
    let c = null;
    try {
      c = await attach(left());
      if (await isFresh(c)) {
        await pollUntil(() => ready(c), { timeoutMs: left(), intervalMs: 100, clock, what: 'document.readyState complete' });
        return c;
      }
      lastErr = 'old document still listed';
    } catch (e) { lastErr = e.message; }
    if (c) { try { await release(c); } catch { /* gone */ } }
    if (clock.now() - t0 >= timeoutMs) throw new Error(`no fresh document after the navigation in ${Math.round(timeoutMs / 1000)} s (${lastErr})`);
    await clock.sleep(intervalMs);
  }
}

/** Call `fn(tryIndex)` up to `tries` times while `retryable(result)`; returns the last result. */
export function retryWhile(fn, { tries = 3, retryable }) {
  let r;
  for (let i = 0; i < tries; i++) { r = fn(i); if (!retryable(r)) return r; }
  return r;
}
