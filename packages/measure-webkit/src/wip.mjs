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

/** Connect to a tab's websocket. Resolves once a page target exists. */
export async function connect(wsUrl, { timeoutMs = 15000 } = {}) {
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
  const targets = {}, pending = new Map(), listeners = new Set();
  const closedError = () => new Error(selfClosed ? 'connection closed by this tool' : `connection closed by the proxy (code ${closed?.code}): another inspector client took the tab?`);
  ws.addEventListener('close', (ev) => {
    closed = { code: ev.code };
    for (const p of pending.values()) p.rej(closedError());
    pending.clear();
  });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.method === 'Target.targetCreated') { targets[m.params.targetInfo.type] = m.params.targetInfo.targetId; return; }
    if (m.method === 'Target.targetDestroyed') { for (const k in targets) if (targets[k] === m.params.targetId) delete targets[k]; return; }
    if (m.method !== 'Target.dispatchMessageFromTarget') return;
    const inner = JSON.parse(m.params.message);
    if (inner.id !== undefined && pending.has(inner.id)) {
      const p = pending.get(inner.id); pending.delete(inner.id);
      inner.error ? p.rej(Object.assign(new Error(inner.error.message || JSON.stringify(inner.error)), { protocol: inner.error })) : p.res(inner.result);
    } else for (const l of listeners) l(inner, m.params.targetId);
  };
  for (let i = 0; i < 40 && !targets.page; i++) await sleep(100);
  if (!targets.page) fail(new Error('no page target (is another inspector client attached to this tab?)'));

  const send = (method, params = {}, { timeoutMs: tmo = 15000 } = {}) => new Promise((res, rej) => {
    if (closed) return rej(closedError());
    const iid = ++innerId;
    const timer = setTimeout(() => { pending.delete(iid); rej(new Error(`${method} timed out after ${tmo} ms`)); }, tmo);
    pending.set(iid, { res: (v) => { clearTimeout(timer); res(v); }, rej: (e) => { clearTimeout(timer); rej(e); } });
    ws.send(JSON.stringify({ id: ++outerId, method: 'Target.sendMessageToTarget', params: { targetId: targets.page, message: JSON.stringify({ id: iid, method, params }) } }));
  });
  const evaluate = async (expression, opts) => {
    const r = await send('Runtime.evaluate', { expression, returnByValue: true }, opts);
    if (r.wasThrown) throw new Error(`page threw: ${JSON.stringify(r.result)}`);
    return r.result.value;
  };
  /** Run an async page expression (Promise) and poll for its result. */
  const runAsync = async (expr, { pollMs = 500, timeoutMs: tmo = 120000, key = '__wkRes' } = {}) => {
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
    close: () => { selfClosed = true; ws.close(); },
    get closed() { return closed; },
  };
}

/** Find the tab whose url starts with `urlPrefix` (waits: the proxy lists a fresh tab a few seconds late) and connect. */
export async function openTab(urlPrefix, { waitMs = 30000, p = ports() } = {}) {
  const t0 = Date.now();
  let last = 'no tab listed';
  while (Date.now() - t0 < waitMs) {
    try {
      const tabs = (await listTabs(p)).filter((x) => x.webSocketDebuggerUrl && String(x.url).startsWith(urlPrefix));
      if (tabs.length === 1) {
        const c = await connect(tabs[0].webSocketDebuggerUrl);
        try { await c.evaluate('1', { timeoutMs: 8000 }); return c; } catch (e) { c.close(); last = e.message; }
      } else last = `${tabs.length} tabs match ${urlPrefix}`;
    } catch (e) { last = e.cause?.code || e.message; }
    await sleep(500);
  }
  throw new Error(`cannot reach a Safari tab at ${urlPrefix}: ${last}`);
}

/**
 * Navigate the tab to `url` (Page.navigate is unavailable on Mobile Safari: `location.href`), close `c` (its target
 * dies with the navigation) and return a new connection with readyState complete.
 */
export async function navigateTab(c, url, opts) {
  await c.evaluate(`setTimeout(() => { location.href = ${JSON.stringify(url)}; }, 30); 'nav'`);
  c.close();
  await sleep(2000);
  const c2 = await openTab(url, opts);
  for (let i = 0; i < 100 && (await c2.evaluate('document.readyState')) !== 'complete'; i++) await sleep(100);
  return c2;
}
