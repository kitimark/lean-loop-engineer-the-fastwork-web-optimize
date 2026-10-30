import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { withPhone } from './device.mjs';
import { serveTree } from './serve.mjs';
import { pageInfo, scrollHold } from './page.mjs';
import { otherDeviceClis, phoneSense } from './device-phone-run.mjs';
import { pinnedSession } from './device-phone-pin.mjs';
import { ConditionOwner, PIN, WHY_TEXT, fallbackAct, mayKill, pinTarget, pinGate, pinWhy, psInfo } from './device-thermal-pin.mjs';
import { visitCapture } from './device-feel-capture.mjs';
import { armHashes, cmdNext, cmdRate, cmdStatus, freshState, loadFeel, saveFeel, stateFile, summaryText, verdicts } from './device-feel.mjs';

const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };

export async function startControl({ token, handlers }) {
  let chain = Promise.resolve();
  let closing = false;
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (d) => { body += d; });
    req.on('end', () => {
      const send = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj), () => { if (closing) setImmediate(() => server.closeIdleConnections?.()); }); };
      if (req.method !== 'POST' || req.headers['x-feel-token'] !== token) return send(403, { ok: false, text: 'refused' });
      const cmd = (req.url || '').slice(1);
      const h = handlers[cmd];
      if (!h) return send(404, { ok: false, text: `unknown command ${cmd}` });
      let args = {};
      try { args = body ? JSON.parse(body) : {}; } catch { return send(400, { ok: false, text: 'bad body' }); }
      chain = chain.then(() => h(args)).then((r) => send(200, r), (e) => send(500, { ok: false, text: `error: ${e.message}` }));
    });
  });
  await new Promise((ok, bad) => { server.once('error', bad); server.listen(0, '127.0.0.1', ok); });
  return { port: server.address().port, close: () => new Promise((ok) => {
    closing = true;
    const t = setTimeout(() => server.closeAllConnections?.(), 2000);
    server.close(() => { clearTimeout(t); ok(); });
    server.closeIdleConnections?.();
  }) };
}

export async function callControl(dir, cmd, args = {}, { timeoutMs = 600000 } = {}) {
  const st = loadFeel(dir);
  if (!st.control || !alive(st.pid)) throw new Error(`no feel session is running for ${dir} (state: ${st.status})`);
  const r = await fetch(`http://127.0.0.1:${st.control.port}/${cmd}`, { method: 'POST', headers: { 'x-feel-token': st.control.token }, body: JSON.stringify(args), signal: AbortSignal.timeout(timeoutMs) });
  return r.json();
}

export function makeGate({ target, pin, sense, sleep = sleepMs, now = Date.now, onReading = () => {} }) {
  let entered = false;
  return async () => {
    const t0 = now();
    for (;;) {
      let s;
      try { s = sense(); } catch (e) { s = { state: null, lock: 'unknown', error: e.message }; }
      const waitedS = Math.round((now() - t0) / 1000);
      const reading = { at: new Date(now()).toISOString(), state: s.state ?? null, tempC: s.tempC ?? null, lock: s.lock ?? null };
      onReading(reading);
      const why = pinWhy(target, pin.held(), s.lock, s.state, entered, waitedS);
      const verdict = pinGate(target, pin.held(), s.lock, s.state, entered, waitedS);
      if (verdict === 'go') { entered = true; pin.onHeld(); return { ok: true, reading }; }
      if (verdict === 'stop') return { ok: false, why: `${WHY_TEXT[why]}${reading.state ? ` (reads ${reading.state})` : ''}`, reading };
      await sleep(PIN.pinPollS * 1000);
    }
  };
}

export async function openArm({ ctx, setArm, hashes, visit, settleMs, log }) {
  const h = hashes.find((x) => x.id === visit.id);
  setArm(h);
  await ctx.go(`${ctx.base}/${visit.search}`);
  await sleepMs(settleMs);
  const y = await scrollHold(ctx.c, 0, { holdMs: 500 });
  const info = await pageInfo(ctx.c);
  const search = await ctx.c.evaluate('location.search');
  const page = { search, scrollY: y, docH: info.docH, maxY: info.maxY, vw: info.vw, vh: info.vh, configHash: info.fw?.configHash ?? null, hydrated: info.fw?.hydrated ?? null, hydrationErrors: info.fw?.hydrationErrors ?? null, expectHash: h.hash };
  log(`opened ${visit.label}: ${JSON.stringify(page)}`);
  if (page.configHash !== h.hash) return { ok: false, error: `the page reports config ${page.configHash}, not the arm's ${h.hash}`, info: page };
  if (page.hydrated === false) return { ok: false, error: 'the page did not hydrate', info: page };
  return { ok: true, info: page };
}

export async function feelStart({ site, dir, pin: target, seed = 0, resume = false, settleMs = 4000, log, fresh = false }) {
  if (!pinTarget(target)) throw new Error(`--pin must be Fair or Serious, got ${target}`);
  const cfg = JSON.parse(readFileSync(join(site, 'configs.json'), 'utf8'));
  const { have: hashes, missing } = armHashes(cfg);
  if (missing.length > 0) throw new Error(`these arms are not prerendered in ${site}: ${missing.map((m) => `${m.id} ${m.search}`).join(' | ')}`);
  const others = otherDeviceClis().filter((p) => p !== process.pid);
  if (others.length > 0) throw new Error(`another device-cli.mjs is running (pid ${others.join(', ')}); one phone run at a time`);
  let st;
  if (existsSync(stateFile(dir))) {
    const old = loadFeel(dir);
    if (old.pid && alive(old.pid) && old.pid !== process.pid && ['ready', 'starting', 'stopping'].includes(old.status)) throw new Error(`a feel session is running here (pid ${old.pid}, ${old.status})`);
    if (resume) st = { ...old, status: 'starting', pid: null, control: null };
    else if (!fresh) throw new Error(`${stateFile(dir)} exists; pass --resume to continue it or --fresh to start over`);
  }
  st ??= freshState({ seed, pin: target, site: 'dist/aot' });
  st.pid = process.pid;
  st.pidStart = psInfo(process.pid)?.start ?? '';
  const save = () => saveFeel(dir, st);
  save();
  const owner = new ConditionOwner({ dir, log });
  process.on('exit', () => owner.termSync());
  let current = hashes[0];
  const token = randomBytes(16).toString('hex');
  let stopRequested = null;
  const stopped = new Promise((r) => { stopRequested = r; });
  const sense = phoneSense();
  try {
    await withPhone(async (ctx) => pinnedSession({
      target, dir, log, owner, sense, signals: false,
      body: async (pinCtl) => {
        process.removeAllListeners('SIGINT');
        process.removeAllListeners('SIGTERM');
        const onSig = (sig) => { log(`${sig}: ending the session`); stopRequested(sig); };
        process.on('SIGINT', onSig);
        process.on('SIGTERM', onSig);
        const gate = makeGate({ target, pin: pinCtl, sense, onReading: (r) => { st.pinReading = r; } });
        log(`waiting for the reported thermal state to reach ${target}`);
        const g = await gate();
        save();
        if (!g.ok) throw new Error(`the thermal pin did not hold: ${g.why}`);
        let vcap = null;
        const finishCapture = async () => {
          if (!vcap?.cap.open) return;
          const { cap, index } = vcap;
          const r = await cap.finish();
          if (r.capture) { st.captures[index] = r.capture; st.log.find((l) => l.index === index).captureFile = r.file; } else st.log.find((l) => l.index === index).captureError = r.error;
          save();
        };
        const handlers = {
          next: async () => {
            await finishCapture();
            const r = await cmdNext(st, { gate, open: (v) => openArm({ ctx, setArm: (h) => { current = h; }, hashes, visit: v, settleMs, log }), now: Date.now });
            if (r.ok) {
              const visit = st.plan[st.opened - 1];
              const cap = visitCapture({ ctx, visit, dir, log });
              vcap = { cap, index: visit.index };
              if (!(await cap.start())) st.log.find((l) => l.index === visit.index).captureError = 'the capture did not start';
            }
            save();
            return r;
          },
          rate: async ({ label, rating }) => { const r = cmdRate(st, label, rating); if (r.ok) await finishCapture(); save(); return r; },
          status: ({ reveal }) => cmdStatus(st, { reveal }),
          stop: () => { stopRequested('stop'); return { ok: true, text: `${summaryText(st)}\nstopping: the pin clears now` }; },
        };
        const control = await startControl({ token, handlers });
        st.control = { port: control.port, token };
        st.status = 'ready';
        save();
        log(`ready: pin ${target} held, ${st.plan.length} arms, control on 127.0.0.1:${control.port}`);
        await stopped;
        st.status = 'stopping';
        save();
        await finishCapture();
        await control.close();
      },
    }), {
      log,
      serve: (host) => serveTree(site, { host, vendors: 'off', select: () => ({ root: site, rewrite: (p) => (p === '/' || p === '/index.html' ? `/${current.file}` : null) }) }),
      startPath: '/',
    });
    st.status = 'stopped';
    st.pinEnd = loadStatePinEnd(dir);
  } catch (e) {
    st.status = 'failed';
    st.error = e.message;
    st.pinEnd = loadStatePinEnd(dir);
    st.verdicts = verdicts(st.seed, st.ratings);
    save();
    e.feelState = st;
    throw e;
  }
  st.control = null;
  st.verdicts = verdicts(st.seed, st.ratings);
  save();
  return st;
}

function loadStatePinEnd(dir) {
  try { return JSON.parse(readFileSync(join(dir, 'state.json'), 'utf8')).pin?.end ?? null; } catch { return null; }
}

export async function feelCommand(cmd, dir, args = {}) {
  const r = await callControl(dir, cmd, args);
  return r;
}

export async function waitGone(dir, { maxS = 400, sleep = sleepMs } = {}) {
  const st = loadFeel(dir);
  for (let i = 0; i < maxS && st.pid && alive(st.pid); i++) await sleep(1000);
  const end = loadFeel(dir);
  return { gone: !(end.pid && alive(end.pid)), status: end.status, pinEnd: end.pinEnd ?? null };
}

export async function stopFallback(dir, { owner, read = () => null, log = () => {}, ps = psInfo, isAlive = alive, kill = (pid, sig) => process.kill(pid, sig), sleep = sleepMs, now = Date.now }) {
  const st = loadFeel(dir);
  const mine = () => st.pid && isAlive(st.pid) && mayKill(st.pid, st.pid, st.pidStart ?? '', ps(st.pid)?.start ?? '');
  let sent = false;
  let t0 = now();
  for (;;) {
    const act = fallbackAct(Boolean(mine()), sent, Math.floor((now() - t0) / 1000));
    if (act === 'term') {
      log(`no control server: SIGTERM the recorded session (pid ${st.pid})`);
      kill(st.pid, 'SIGTERM');
      sent = true;
      t0 = now();
    } else if (act === 'wait') await sleep(1000);
    else break;
  }
  const gone = !mine();
  const ownerStopped = await owner.recover({ read });
  return { signalled: sent, sessionGone: gone, ownerStopped };
}
