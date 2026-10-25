// Thin raw Web Inspector protocol client for Mobile Safari behind ios_webkit_debug_proxy. No WKTR, no Playwright.
//
// Wire format (CONFIRMED on the iOS 27.0 Simulator): the proxy's websocket speaks the Target domain. A `page-N`
// target arrives in `Target.targetCreated`; commands go out as `Target.sendMessageToTarget` with a JSON string
// `message`, replies and events come back as `Target.dispatchMessageFromTarget`. Target ids change on navigation,
// so a navigation needs a new connection (see `openTab`).
// Quirks carried over from v1 (read-only reference): `Runtime.evaluate` ignores `awaitPromise`, so async page code
// is run with `runAsync` (stash the result on window, poll). `Page.navigate` is unavailable: navigate with
// `location.href` and reconnect.
import { listTabs, sleep, ports } from './sim.mjs';
import { T } from './timeouts.mjs';
import { attachFresh } from './poll.mjs';
import { capped, waitForTarget } from './target.mjs';
import { remainingMs } from './inspector.mjs';

/**
 * The Target-domain bookkeeping of one connection, as a pure step (TS stand-in; WebKit Target.json and TargetManager.js@862f17dc).
 * A navigation that changes process creates a provisional page target (`isProvisional`), and `Target.didCommitProvisionalTarget`
 * swaps it in for the old one, which is destroyed. Commands go to `targets.page` only once it is committed; a command that
 * was sent to the old target never gets a reply, so the step names those targets in `swapped` and the caller fails them fast.
 * state: { targets: { type: id }, provisional: { id: type } }; returns { state, swapped: { from, to } | null }.
 */
export function targetStep(state, m) {
  const targets = { ...state.targets }, provisional = { ...state.provisional };
  const done = (swapped = null) => ({ state: { targets, provisional }, swapped });
  const p = m.params ?? {};
  if (m.method === 'Target.targetCreated') {
    const { targetId, type, isProvisional } = p.targetInfo;
    if (isProvisional) provisional[targetId] = type; else targets[type] = targetId;
    return done();
  }
  if (m.method === 'Target.didCommitProvisionalTarget') {
    const type = provisional[p.newTargetId] ?? 'page';
    delete provisional[p.newTargetId];
    targets[type] = p.newTargetId;
    return done({ from: p.oldTargetId, to: p.newTargetId });
  }
  if (m.method === 'Target.targetDestroyed') {
    delete provisional[p.targetId];
    for (const k in targets) if (targets[k] === p.targetId) delete targets[k];
    return done();
  }
  return done();
}

export async function connect(wsUrl, { timeoutMs = T(15000) } = {}) {
  const ws = new WebSocket(wsUrl);
  const fail = (e) => { try { ws.close(); } catch { /* already closed */ } throw e; };
  let t;
  try {
    await Promise.race([
      new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('websocket error')); }),
      new Promise((_, rej) => { t = setTimeout(() => rej(new Error('websocket open timeout')), timeoutMs); }),
    ]);
  } catch (e) { fail(e); } finally { clearTimeout(t); }

  let outerId = 0, innerId = 0, closed = null, selfClosed = false;
  let tstate = { targets: {}, provisional: {} };
  const pending = new Map(), listeners = new Set();
  let onClosed;
  const closedP = new Promise((r) => { onClosed = r; });
  const closedError = () => new Error(selfClosed ? 'connection closed by this tool' : `connection closed by the proxy (code ${closed?.code}): another inspector client took the tab?`);
  ws.addEventListener('close', (ev) => {
    closed = { code: ev.code };
    onClosed();
    for (const p of pending.values()) p.rej(closedError());
    pending.clear();
  });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.method === 'Target.targetCreated' || m.method === 'Target.targetDestroyed' || m.method === 'Target.didCommitProvisionalTarget') {
      const r = targetStep(tstate, m);
      tstate = r.state;
      if (r.swapped) {
        for (const [iid, p] of pending) if (p.targetId === r.swapped.from) { pending.delete(iid); p.rej(Object.assign(new Error(`the page target was replaced by a navigation commit (${p.method})`), { swapped: true })); }
      }
      return;
    }
    if (m.method !== 'Target.dispatchMessageFromTarget') return;
    const inner = JSON.parse(m.params.message);
    if (inner.id !== undefined && pending.has(inner.id)) {
      const p = pending.get(inner.id); pending.delete(inner.id);
      inner.error ? p.rej(Object.assign(new Error(inner.error.message || JSON.stringify(inner.error)), { protocol: inner.error })) : p.res(inner.result);
    } else for (const l of listeners) l(inner, m.params.targetId);
  };
  for (let i = 0; i < T(40) && !tstate.targets.page; i++) await sleep(100);
  if (!tstate.targets.page) fail(new Error('no page target (is another inspector client attached to this tab?)'));

  const send = (method, params = {}, { timeoutMs: tmo = T(15000) } = {}) => new Promise((res, rej) => {
    if (closed) return rej(closedError());
    const targetId = tstate.targets.page;
    if (!targetId) return rej(new Error(`${method}: no committed page target (a navigation is between its old and new page)`));
    const iid = ++innerId;
    const timer = setTimeout(() => { pending.delete(iid); rej(new Error(`${method} timed out after ${tmo} ms`)); }, tmo);
    pending.set(iid, { method, targetId, res: (v) => { clearTimeout(timer); res(v); }, rej: (e) => { clearTimeout(timer); rej(e); } });
    ws.send(JSON.stringify({ id: ++outerId, method: 'Target.sendMessageToTarget', params: { targetId, message: JSON.stringify({ id: iid, method, params }) } }));
  });
  const evaluate = async (expression, opts) => {
    const r = await send('Runtime.evaluate', { expression, returnByValue: true }, opts);
    if (r.wasThrown) throw new Error(`page threw: ${JSON.stringify(r.result)}`);
    return r.result.value;
  };
  /** Run an async page expression (Promise) and poll for its result. */
  const runAsync = async (expr, { pollMs = 500, timeoutMs: tmo = T(120000), key = '__wkRes' } = {}) => {
    await evaluate(`window.${key} = undefined; Promise.resolve(${expr}).then(v => { window.${key} = JSON.stringify({ok: v}); }, e => { window.${key} = JSON.stringify({err: String(e && e.stack || e)}); }); 'started'`);
    const t0 = Date.now();
    while (Date.now() - t0 < tmo) {
      await sleep(pollMs);
      const v = await evaluate(`window.${key} || null`);
      if (v) { const o = JSON.parse(v); if (o.err) throw new Error(o.err); return o.ok; }
    }
    throw new Error('runAsync timed out');
  };
  // `Domain.enable` is an error when the domain is already enabled on this connection; send it once.
  const enabled = new Set();
  const enable = async (domain) => {
    if (enabled.has(domain)) return;
    try { await send(`${domain}.enable`); } catch (e) { if (!/already enabled/i.test(e.message)) throw e; }
    enabled.add(domain);
  };
  const disable = async (domain) => { await send(`${domain}.disable`).catch(() => {}); enabled.delete(domain); };
  return {
    send, evaluate, runAsync, enable, disable,
    on: (fn) => { listeners.add(fn); return () => listeners.delete(fn); },
    // resolves when the websocket is closed (or after a bound): a client that is not yet detached keeps the tab's
    // inspector slot, and a new connection to the same tab then sees no page target
    close: () => { selfClosed = true; try { ws.close(); } catch { /* already closed */ } return Promise.race([closedP, sleep(T(3000))]); },
    get closed() { return closed; },
  };
}

/**
 * One poll for the tab whose url starts with `urlPrefix`: list, connect, and see that the page answers. A failed poll closes
 * its own socket and throws the reason (`pauseMs`: how long the caller waits before the next one).
 */
export async function tryTab(urlPrefix, { p = ports() } = {}) {
  const tabs = (await listTabs(p)).filter((x) => x.webSocketDebuggerUrl && String(x.url).startsWith(urlPrefix));
  if (tabs.length !== 1) throw new Error(`${tabs.length} tabs match ${urlPrefix}`);
  const c = await connect(tabs[0].webSocketDebuggerUrl);
  try { await c.evaluate('1', { timeoutMs: T(8000) }); return c; } catch (e) { await c.close(); throw Object.assign(e, { pauseMs: 2000 }); }
}
/** The pause after a failed poll: the old client may still be detaching after "no page target", so do not hammer it. */
const pauseAfter = (e) => e.pauseMs ?? (/no page target/.test(e.cause?.code || e.message) ? 2000 : 500);
const closeLate = (c) => { try { c?.close?.(); } catch { /* gone */ } };

/**
 * Find the tab whose url starts with `urlPrefix` (waits: the proxy lists a fresh tab a few seconds late) and connect.
 * Bounded by `waitMs`, and so is every poll: one that blocks is dropped at the bound (its late socket is closed). Every
 * change of the failure reason is logged (and at most one line per 10 s), so a slow start is visible in the log. A failed
 * poll closes its own socket and waits before the next one (so polls do not pile up as inspector clients).
 */
export async function openTab(urlPrefix, { waitMs = T(30000), p = ports(), log = () => {} } = {}) {
  const t0 = Date.now();
  let last = 'no tab listed', logged = '', loggedAt = 0, tries = 0;
  while (Date.now() - t0 < waitMs) {
    tries++;
    let pause = 500;
    try { return await capped(remainingMs(waitMs, Date.now() - t0), tryTab(urlPrefix, { p }), { late: closeLate }); } catch (e) { last = e.cause?.code || e.message; pause = pauseAfter(e); }
    if (last !== logged || Date.now() - loggedAt > 10000) { log(`  waiting for the Safari tab (${Math.round((Date.now() - t0) / 1000)} s of ${Math.round(waitMs / 1000)} s, try ${tries}): ${last}`); logged = last; loggedAt = Date.now(); }
    await sleep(Math.min(pause, remainingMs(waitMs, Date.now() - t0)));
  }
  throw new Error(`cannot reach a Safari tab at ${urlPrefix}: ${last} (${tries} tries in ${Math.round((Date.now() - t0) / 1000)} s)`);
}

/**
 * Drop the context's client and connect again. The old socket is closed and its close is awaited (so the proxy has
 * released the tab's inspector slot), then the wait for the page target runs (`waitForTarget`, Lean `Fw.Measure.SimBound`):
 * 480 s, then one Safari relaunch (`ctx.relaunchTab`), then 90 s, then the session fails with exit code 5. No fixed pause.
 */
export async function reconnect(ctx, { log = () => {}, openTabFn = null, clock = undefined } = {}) {
  try { await ctx.c.close(); } catch { /* closed */ }
  await ctx.ensureProxy?.();
  const tryOnce = openTabFn ? (cap) => openTabFn(ctx.url, { waitMs: cap, log }) : () => tryTab(ctx.url);
  ctx.setClient(await waitForTarget({ tryOnce, relaunch: ctx.relaunchTab ?? null, relaunched: false, pauseMs: pauseAfter, log, late: closeLate, ...(clock ? { clock } : {}) }));
}

/**
 * Navigate the tab to `url` (Page.navigate is unavailable on Mobile Safari: `location.href`), close `c` (its target
 * dies with the navigation) and return a new connection to the NEW document with readyState complete. No fixed
 * sleep: the old document gets a marker, and a client that attaches to it before the navigation lands is released and
 * the attach repeated until a document without the marker answers and is complete.
 */
export async function navigateTab(c, url, { waitMs = T(60000), log = () => {}, openTabFn = openTab, clock } = {}) {
  await c.evaluate(`window.__fwNav = 1; setTimeout(() => { location.href = ${JSON.stringify(url)}; }, 30); 'nav'`);
  await c.close();
  return attachFresh({
    attach: (ms) => openTabFn(url, { waitMs: Math.min(ms, T(15000)), log }),
    isFresh: async (x) => (await x.evaluate('window.__fwNav === undefined')) === true,
    ready: async (x) => (await x.evaluate('document.readyState')) === 'complete',
    release: (x) => x.close(),
    timeoutMs: waitMs,
    clock,
  });
}
