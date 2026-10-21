// Frame capture for a visual review of a look change: the faithful rewrite (no flag) and one flagged rewrite walk the same
// end-of-page path as the trajectory probe (kit approach, a wheel push open, a hold, a wheel push close), and the nav band is
// screenshotted as fast as the engine allows from the wheel event on. Real time, native rAF, no animation seeking. The output
// is review material for a person: it decides nothing. Glue only.
//
//   node src/trajectory/frames.mjs capture --engine chromium --widths 390,1280 --search '?fw=nav:earn-no-transition' --out DIR [--source screenshot|screencast]
//   node src/trajectory/frames.mjs strips --in DIR[,DIR2] --out DIR3 [--run ID] [--cols 40]
// A shot is one image with the interval of ms from the wheel event it stands for: a screenshot, the time its capture took; a screencast
// frame, the time from its swap until the next frame's.
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { chromium, webkit } from 'playwright-core';
import { LAUNCHERS } from '../engines.mjs';
import { PIN_SRC, waitReady } from '../page.mjs';
import { startServer, snapshotRoot, siteDist, rewriteFor } from '../serve.mjs';
import { MORPH_NODES, envFor, resolveNodes } from './registry.mjs';
import { installKit } from './kit.mjs';

const INIT = `${PIN_SRC}\n(${installKit.toString()})();`;
const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const now = () => performance.now();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** The two pushes and how long each is captured after its wheel event; the hold between them lets the open push settle. */
export const PUSHES = [
  { push: 'open', dy: 120, ms: 1500, holdMs: 900 },
  { push: 'close', dy: -120, ms: 1500, holdMs: 900 },
];

/** Fewest shots an arm needs in one push for its strip to show the motion (TS stand-in of Lean Fw.Gate.Frames.usable). */
export const MIN_SHOTS = 10;
export const usable = (faithful, flag) => Math.min(faithful, flag) >= MIN_SHOTS;

/** The label under a shot: its interval in ms from the wheel event. */
export const labelOf = (s) => `#${s.i} ${s.from}-${s.to} ms`;

/**
 * The shots of a screencast over one push. `frames` are { ts, data } in swap order (ts: wall-clock ms), `tw` the wall-clock ms of the
 * wheel event, `endMs` how long the push is captured. The frame in effect at the wheel event comes first, from 0; each frame lasts
 * until the next one; the last until `endMs`. Frames before that one or after the end are not shots.
 */
export function shotsOfFrames(frames, tw, endMs) {
  const at = (f) => Math.round(f.ts - tw);
  let first = -1;
  frames.forEach((f, k) => { if (f.ts <= tw) first = k; });
  const kept = frames.map((f, k) => ({ f, k })).filter(({ f, k }) => k >= Math.max(first, 0) && at(f) <= endMs);
  return kept.map(({ f, k }, n) => {
    const from = Math.max(0, at(f));
    const to = n + 1 < kept.length ? Math.max(from, at(kept[n + 1].f)) : Math.max(from, endMs);
    return { frame: k, from, to };
  }).filter((x, n, all) => x.to > x.from || n === all.length - 1);
}

/** In-page recorder: per rendering frame, the rects of the nav, its actions group and the earn button, and the earn opacity
 * and max-width, with times from the last wheel event. */
function recorder() {
  const st = (window.__frames = { rows: [], loop: false, wheelAt: null, gen: 0 });
  addEventListener('wheel', () => { st.wheelAt = performance.now(); }, { capture: true, passive: true });
  const rect = (el) => { if (!el) return null; const r = el.getBoundingClientRect(); return [r.left, r.top, r.width, r.height].map((v) => Math.round(v * 10) / 10); };
  return {
    start(sel) {
      st.rows = []; st.loop = true; st.wheelAt = null;
      const mine = ++st.gen;
      const tick = () => {
        if (!st.loop || st.gen !== mine) return;
        const earn = document.querySelector(sel.earn);
        const cs = earn ? getComputedStyle(earn) : null;
        const t = performance.now();
        st.rows.push({ t: st.wheelAt === null ? null : Math.round((t - st.wheelAt) * 10) / 10, nav: rect(document.querySelector(sel.nav)),
          actions: rect(document.querySelector(sel.actions)), earn: rect(earn), opacity: cs ? cs.opacity : null, maxWidth: cs ? cs.maxWidth : null });
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
      return true;
    },
    stop() { st.loop = false; st.gen++; return st.rows; },
  };
}
const REC = `window.__rec = (${recorder.toString()})();`;

const forArm = (site) => Object.fromEntries(resolveNodes(MORPH_NODES).filter((n) => ['nav', 'actions', 'earn'].includes(n.id)).map((n) => [n.id, site === 'orig' ? n.orig : n.rewrite]));

/** The nav band at rest: the full width, from above the nav's top to below its bottom, clamped to the viewport. */
async function bandOf(s, sel, env) {
  const r = await s.evaluate((q) => { const b = document.querySelector(q).getBoundingClientRect(); return { top: b.top, bottom: b.bottom }; }, sel.nav);
  const y = Math.max(0, Math.floor(r.top) - 16);
  return { x: 0, y, width: env.width, height: Math.min(env.height - y, Math.ceil(r.bottom) + 16 - y) };
}

const even = (n) => n - (n % 2);

/** One arm at one width: approach, rest, then each push captured from its wheel event for `ms`, by `source`. */
async function captureArm(engine, width, arm, outDir, source) {
  const env = envFor(width);
  const s = await engine.open(env, { origin: arm.origin, path: '/' + arm.search, init: `${INIT}\n${REC}`, frozen: false });
  try {
    const ready = await s.evaluate(waitReady, { site: 'rewrite', capMs: 20000 });
    const self = await s.evaluate(() => (window.__fw ? { config: window.__fw.configHash ?? null, mode: window.__fw.mode ?? null } : null));
    const sel = forArm('rewrite');
    await s.evaluate((a) => window.__traj.approach(a), { arm: 'rewrite', nodes: [], pageProps: [], navSel: sel.nav, restMs: 600, settleCapMs: 4000 });
    const clip = await bandOf(s, sel, env);
    const pushes = [];
    const cast = [];
    const stopCast = source === 'screencast' ? await s.screencast((f) => { cast.push({ ts: f.timestamp, data: f.data }); }, { width: even(env.width), height: even(env.height) }) : null;
    for (const p of PUSHES) {
      if (source === 'screenshot') await s.shot(clip); // warm-up: the first screenshot of a page costs several frames
      await s.evaluate((q) => window.__rec.start(q), sel);
      const shots = [];
      await s.mouse(env.width / 2, env.height / 2);
      const wall = Date.now();
      const tw = now();
      await s.wheel(env.width / 2, env.height / 2, p.dy);
      if (source === 'screenshot') {
        while (now() - tw < p.ms) {
          const a = now();
          const buf = await s.shot(clip);
          const b = now();
          const file = `${arm.role}-${width}-${p.push}-${String(shots.length).padStart(3, '0')}.png`;
          writeFileSync(join(outDir, file), buf);
          shots.push({ i: shots.length, file, ms: Math.round((a + b) / 2 - tw), from: Math.round(a - tw), to: Math.round(b - tw), offY: 0 });
        }
      } else {
        await sleep(p.ms);
        for (const x of shotsOfFrames(cast.slice(), wall, p.ms)) {
          const file = `${arm.role}-${width}-${p.push}-${String(shots.length).padStart(3, '0')}.jpg`;
          writeFileSync(join(outDir, file), cast[x.frame].data);
          shots.push({ i: shots.length, file, ms: x.from, from: x.from, to: x.to, offY: clip.y });
        }
      }
      const rows = await s.evaluate(() => window.__rec.stop());
      pushes.push({ push: p.push, dy: p.dy, shots, rows });
      await sleep(p.holdMs);
    }
    if (stopCast) await stopCast();
    return { role: arm.role, search: arm.search, width, ready, self, clip, pushes };
  } finally { await s.close().catch(() => {}); }
}

async function capture({ engineName, widths, search, out, source }) {
  mkdirSync(out, { recursive: true });
  const env = process.env;
  const variant = rewriteFor(siteDist(env), { ...env, FW_SEARCH: search });
  const configs = JSON.parse(readFileSync(join(siteDist(env), 'configs.json'), 'utf8'));
  const faithful = await startServer(siteDist(env));
  const flagged = variant.rewrite ? await startServer(siteDist(env), variant.rewrite) : faithful;
  const engine = await LAUNCHERS[engineName]();
  const arms = [
    { role: 'faithful', search: '', want: configs.bySearch[''], origin: faithful.origin },
    { role: 'flag', search, want: variant.hash ?? null, origin: flagged.origin },
  ];
  const runs = [];
  try {
    for (const width of widths) for (const arm of arms) {
      log(`frames ${engineName} ${source} ${width} ${arm.role}`);
      const r = await captureArm(engine, width, arm, out, source);
      r.want = arm.want;
      r.identity = r.self && r.self.config === arm.want && r.self.mode === 'hydrate' ? 'ok' : 'mismatch';
      runs.push(r);
      log(`frames ${engineName} ${source} ${width} ${arm.role}: ${r.pushes.map((p) => `${p.push} ${p.shots.length} shots`).join(', ')}, identity ${r.identity}`);
    }
    const head = { engine: engineName, version: await engine.version(), source, search, runs };
    writeFileSync(join(out, `frames-${engineName}.json`), JSON.stringify(head, null, 1));
    if (runs.some((r) => r.identity !== 'ok')) { log('frames: an arm is not the page it was asked for'); process.exitCode = 2; }
  } finally {
    await engine.close().catch(() => {});
    await faithful.close();
    if (flagged !== faithful) await flagged.close();
  }
}

/** The x range shown: the union of the actions group over every recorded frame of both arms, padded, clamped to the band. */
export function cropOf(a, b) {
  let lo = Infinity, hi = -Infinity;
  for (const r of [a, b]) for (const p of r.pushes) for (const row of p.rows) for (const k of ['actions', 'earn']) {
    const q = row[k];
    if (q && q[2] > 0) { lo = Math.min(lo, q[0]); hi = Math.max(hi, q[0] + q[2]); }
  }
  const w = a.clip.width;
  if (!Number.isFinite(lo)) return { x: 0, width: w };
  const x = Math.max(0, Math.floor(lo) - 24);
  return { x, width: Math.min(w, Math.ceil(hi) + 24) - x };
}

/** Up to `cols` columns: evenly spaced times over the capture; each arm shows its shot nearest in time (a screencast: the frame in
 * effect at that time); a column whose two shots equal the previous column's is dropped. */
export function columnsOf(fa, fl, cols, source = 'screenshot') {
  const end = Math.max(fa.shots.at(-1)?.ms ?? 0, fl.shots.at(-1)?.ms ?? 0);
  const near = (shots, t) => (source === 'screencast'
    ? shots.findLast((s) => s.from <= t) ?? shots[0]
    : shots.reduce((m, s) => (Math.abs(s.ms - t) < Math.abs(m.ms - t) ? s : m), shots[0]));
  const out = [];
  for (let k = 0; k < cols; k++) {
    const t = cols === 1 ? 0 : (end * k) / (cols - 1);
    const c = { a: near(fa.shots, t), b: near(fl.shots, t) };
    const last = out.at(-1);
    if (!last || last.a.i !== c.a.i || last.b.i !== c.b.i) out.push(c);
  }
  return out;
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

/** The HTML of one strip: blocks of `per` columns, each the faithful row above the flag row, frame index and ms under each
 * image. */
function stripHtml({ title, crop, height, cols, dirOf, per = 10 }) {
  const img = (dir, s) => `<div class="c"><div class="i" style="width:${crop.width}px;height:${height}px"><img src="data:image/${s.file.endsWith('.jpg') ? 'jpeg' : 'png'};base64,${readFileSync(join(dir, s.file)).toString('base64')}" style="left:${-crop.x}px;top:${-(s.offY ?? 0)}px"></div><div class="l">${labelOf(s)}</div></div>`;
  const blocks = [];
  for (let k = 0; k < cols.length; k += per) {
    const part = cols.slice(k, k + per);
    blocks.push(`<div class="b"><div class="r"><div class="n">no flag</div>${part.map((c) => img(dirOf.a, c.a)).join('')}</div>` +
      `<div class="r"><div class="n">flag</div>${part.map((c) => img(dirOf.b, c.b)).join('')}</div></div>`);
  }
  return `<!doctype html><meta charset="utf-8"><style>
body{margin:0;padding:8px;background:#fff;font:12px/1.3 monospace;color:#111;display:inline-block}
h1{font-size:13px;margin:0 0 6px}.b{margin:0 0 10px;padding:4px;border:1px solid #bbb}.r{display:flex;align-items:flex-start;margin:2px 0}
.n{width:56px;flex:none;padding-top:4px}.c{margin-right:4px}.i{position:relative;overflow:hidden;outline:1px solid #ddd}
.i img{position:absolute}.l{text-align:center;color:#444;white-space:nowrap}
</style><h1>${esc(title)}</h1>${blocks.join('')}`;
}

async function strips({ ins, out, run, cols }) {
  mkdirSync(out, { recursive: true });
  const browser = process.env.CHROME_PATH ? await chromium.launch({ executablePath: process.env.CHROME_PATH }) : await webkit.launch();
  const index = { run: run ?? null, strips: [] };
  try {
    for (const dir of ins) {
      const files = ['frames-chromium.json', 'frames-playwright-webkit.json'].filter((f) => existsSync(join(dir, f)));
      for (const f of files) {
        const head = JSON.parse(readFileSync(join(dir, f), 'utf8'));
        const widths = [...new Set(head.runs.map((r) => r.width))];
        for (const width of widths) {
          const a = head.runs.find((r) => r.width === width && r.role === 'faithful');
          const b = head.runs.find((r) => r.width === width && r.role === 'flag');
          if (!a || !b) continue;
          const crop = cropOf(a, b);
          const height = Math.min(a.clip.height, b.clip.height);
          for (const p of PUSHES.map((x) => x.push)) {
            const fa = a.pushes.find((x) => x.push === p), fl = b.pushes.find((x) => x.push === p);
            const cs = columnsOf(fa, fl, cols, head.source);
            const source = head.source ?? 'screenshot';
            const title = `${head.engine} (${head.version}) width ${width}, ${p} push, ${source}; top: no flag, bottom: ${head.search}; from-to ms after the wheel event${run ? `; run ${run}` : ''}`;
            const page = await browser.newPage({ viewport: { width: 400, height: 300 } });
            await page.setContent(stripHtml({ title, crop, height, cols: cs, dirOf: { a: dir, b: dir } }));
            const name = `${head.engine}-${width}-${p}${source === 'screencast' ? '-screencast' : ''}.png`;
            await page.locator('body').screenshot({ path: join(out, name) });
            await page.close();
            index.strips.push({ file: name, engine: head.engine, version: head.version, source, width, push: p, search: head.search,
              columns: cs.length, crop: { ...crop, y: a.clip.y, height }, shots: { faithful: fa.shots.length, flag: fl.shots.length },
              usable: usable(fa.shots.length, fl.shots.length), identity: { faithful: a.identity, flag: b.identity } });
            log(`strip ${name}: ${cs.length} columns`);
          }
        }
      }
    }
  } finally { await browser.close(); }
  writeFileSync(join(out, 'index.json'), JSON.stringify(index, null, 1) + '\n');
}

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(`--${k}`); return i >= 0 ? args[i + 1] : d; };
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (args[0] === 'capture' && ['screenshot', 'screencast'].includes(opt('source', 'screenshot'))) {
    await capture({ engineName: opt('engine'), widths: opt('widths', '390,1280').split(',').map(Number), search: opt('search', ''), out: opt('out'), source: opt('source', 'screenshot') });
  } else if (args[0] === 'strips') {
    await strips({ ins: opt('in').split(','), out: opt('out'), run: opt('run'), cols: Number(opt('cols', '40')) });
  } else {
    log('usage: frames.mjs capture --engine E --widths 390,1280 --search ?fw=... --out DIR [--source screenshot|screencast] | strips --in DIR --out DIR [--run ID] [--cols 40]');
    process.exitCode = 2;
  }
}
