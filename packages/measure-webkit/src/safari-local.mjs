import { spawn, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { join, resolve } from 'node:path';
import { serveTree } from './serve.mjs';
import { snapshotRoot } from './session.mjs';
import { RECORDER_SRC, TO_END_JS, heroJs, endJs, intervalsOf } from './profile/recorder.mjs';
import { HERO_BURST, END_PUSH } from '../../gate-breakpoints/src/smooth/schedule.mjs';
import { runCheck } from '../../gate-breakpoints/src/trajectory/reduce.mjs';
import { cadenceOf, runCells } from './safari-local-run.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export const freePort = () => new Promise((ok, bad) => { const s = createServer(); s.once('error', bad); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); }); });

export function webdriver(base) {
  let sid = null;
  const call = async (method, path, body, timeoutMs = 180000) => {
    const r = await fetch(base + path, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(timeoutMs) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${j.value?.error ?? ''} ${String(j.value?.message ?? '').slice(0, 160)}`);
    return j.value;
  };
  const s = (p) => `/session/${sid}${p}`;
  return {
    async newSession(timeoutMs = 120000) {
      const v = await call('POST', '/session', { capabilities: { alwaysMatch: { browserName: 'safari' } } }, timeoutMs);
      sid = v.sessionId;
      return v;
    },
    timeouts: (script) => call('POST', s('/timeouts'), { script, pageLoad: 60000 }),
    setRect: (rect) => call('POST', s('/window/rect'), rect),
    getRect: () => call('GET', s('/window/rect')),
    navigate: (url) => call('POST', s('/url'), { url }),
    sync: (script, args = []) => call('POST', s('/execute/sync'), { script, args }),
    async expr(expression) {
      const v = await call('POST', s('/execute/async'), { script: `const done = arguments[arguments.length - 1]; Promise.resolve(${expression}).then((v) => done({ ok: v }), (e) => done({ err: String(e) }));`, args: [] });
      if (v && v.err) throw new Error(`page: ${v.err}`);
      return v.ok;
    },
    async close() { if (sid) { const id = sid; sid = null; await call('DELETE', `/session/${id}`, undefined, 30000).catch(() => {}); } },
  };
}

export async function armServer(arms) {
  const table = Object.fromEntries(arms.map((a) => {
    if (!a.tree.dir) return [a.id, { root: snapshotRoot(), rewrite: null, hash: null }];
    const root = resolve(a.tree.dir);
    const cfg = JSON.parse(readFileSync(join(root, 'configs.json'), 'utf8'));
    const hash = cfg.bySearch[canonSearch(a.tree.search ?? '')];
    if (!hash) throw new Error(`arm ${a.id}: search "${a.tree.search}" is not prerendered`);
    return [a.id, { root, rewrite: (p) => (p === '/' || p === '/index.html' ? '/' + cfg.byHash[hash] : null), hash }];
  }));
  let now = arms[0].id;
  const srv = await serveTree(table[now].root, { select: () => table[now] });
  return { ...srv, setArm: (id) => { if (!table[id]) throw new Error(`no arm ${id}`); now = id; }, armHash: (id) => table[id].hash };
}

const pids = (name) => spawnSync('pgrep', ['-x', name], { encoding: 'utf8' }).stdout.split('\n').filter(Boolean).map(Number);

const INFO = `return JSON.stringify({ vw: innerWidth, vh: innerHeight, dpr: devicePixelRatio, vis: document.visibilityState, ua: navigator.userAgent, ready: document.readyState, fw: window.__fw ? { configHash: window.__fw.configHash, mode: window.__fw.mode, hydrated: window.__fw.hydrated } : null })`;

export async function runSafariLocal({ arms, read, takeBase, pass = null, passes, maxRounds, deadlineMs, waitMs, everyMs, onRow, settleMs = 2500, width = 430, height = 932, log = (s) => console.error(s) }) {
  const server = await armServer(arms);
  const port = await freePort();
  const safariBefore = new Set(pids('Safari'));
  const driver = spawn('safaridriver', ['-p', String(port)], { detached: true, stdio: 'ignore' });
  driver.unref();
  log(`safaridriver pid ${driver.pid} on port ${port}; serving at ${server.url}`);
  const wd = webdriver(`http://127.0.0.1:${port}`);
  let ua = '', vw = null, rect = null;
  try {
    await sleep(1500);
    await wd.newSession();
    await wd.timeouts(90000);
    rect = await wd.setRect({ x: 0, y: 0, width, height }).catch((e) => ({ error: e.message }));
    const byId = Object.fromEntries(arms.map((a) => [a.id, a]));
    const baseline = await takeBase({ boot: null });
    if (baseline.floorCenti === null) return { rows: [], baseline, ua, vw, rect };
    const rows = await runCells({
      engine: 'safari', pass, arms, passes, maxRounds, deadlineMs, read, floorCenti: baseline.floorCenti, waitMs, everyMs, onRow, log,
      readWindow: async (id, w) => {
        const a = byId[id];
        server.setArm(id);
        await wd.navigate(`${server.url}${a.search}`);
        for (let i = 0; i < 100 && JSON.parse(await wd.sync(INFO)).ready !== 'complete'; i++) await sleep(100);
        await sleep(settleMs);
        const info = JSON.parse(await wd.sync(INFO));
        ua = info.ua; vw = info.vw;
        if (runCheck([{ site: a.site, want: server.armHash(id), config: info.fw?.configHash ?? null, mode: info.fw?.mode ?? null }]) !== 'ok') throw new Error(`arm ${id}: wrong page (${JSON.stringify(info.fw)})`);
        if (info.vis !== 'visible') throw new Error(`the Safari window is ${info.vis}: rAF would be throttled`);
        await wd.sync(RECORDER_SRC);
        if (w === 'end') await wd.expr(TO_END_JS);
        const rec = await wd.expr(w === 'hero' ? heroJs(HERO_BURST) : endJs(END_PUSH));
        return { ...cadenceOf(rec.ts, intervalsOf), config: info.fw?.configHash ?? null, profile: null };
      },
    });
    return { rows, baseline, ua, vw, rect };
  } finally {
    await wd.close();
    try { process.kill(driver.pid); } catch {}
    for (const p of pids('Safari')) if (!safariBefore.has(p)) { try { process.kill(p); } catch {} }
    await server.close();
  }
}
