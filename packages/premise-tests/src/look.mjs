#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PIN_SRC } from '../../gate-breakpoints/src/page.mjs';
import { LIMITS, bound, call, cellsKept, closeBounded, observeCell, takeCell, waitCell } from '../../gate-breakpoints/src/bounded.mjs';
import { siteDist, startServer } from '../../gate-breakpoints/src/serve.mjs';
import { LAUNCHERS } from '../../visual-diff/src/engines.mjs';
import { decode, encodePng } from '../../visual-diff/src/diff.mjs';
import { rewritePathFor } from '../../visual-diff/src/run.mjs';
import { diffMap, elementTable, fadeOf, fadeShows, loadLookGolden, pxRange, regionStats, scrollEq, timedSettled, trackAt, tracksOk, within } from './look-rule.mjs';

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : d; };
const golden = loadLookGolden();
const CELL = golden.cell;
const BANDS = (opt('bands', '320x568,360x640,390x844,430x932,640x360,640x1000,641x700,768x1024,1024x768,1280x800,1440x900,1920x1080')).split(',').map((s) => s.split('x').map(Number));
const MS = opt('ms', CELL.ms.join(',')).split(',').map(Number);
const engineName = opt('engine', 'chromium');
const out = resolve(opt('out', 'out'));
const FW = opt('fw', 'morph.geom:on');
const TIMED = FW.includes('morph.tween:geom-timed');
const IMAGES = opt('images', 'auto') !== 'none';
const PAGE_ARMS_SHARE = 0.01;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function pinNav(m) {
  const nav = document.querySelector('[data-fw="nav"]');
  nav.classList.toggle('is-on-dark', m > 0.2 || !!nav.dataset.fwKeepDark);
  nav.style.setProperty('--morph', String(m));
  nav.dataset.fwMorph = String(m);
  const r = (e) => (e ? e.getBoundingClientRect().toJSON() : null);
  const cols = [...document.querySelectorAll('[data-fw="morph-columns"] > div')].filter((c) => getComputedStyle(c).display !== 'none').map(r);
  const x0 = Math.min(...cols.map((c) => c.left)), y0 = Math.min(...cols.map((c) => c.top));
  const x1 = Math.max(...cols.map((c) => c.right)), y1 = Math.max(...cols.map((c) => c.bottom));
  return { ...nav.getBoundingClientRect().toJSON(), cols: cols.length ? { x: x0, y: y0, width: x1 - x0, height: y1 - y0 } : null, bar: r(nav.querySelector(':scope > div')) };
}

function writeFade({ fade, none }) {
  const p = document.querySelector('[data-fw="platform"]');
  if (!p) throw new Error('no [data-fw="platform"]');
  p.style.setProperty('--morph-fade', fade);
  p.style.pointerEvents = none ? 'none' : '';
}

function readState() {
  const nav = document.querySelector('[data-fw="nav"]');
  const p = document.querySelector('[data-fw="platform"]');
  const tracks = [];
  for (const a of document.getAnimations()) {
    if ((typeof CSSAnimation !== 'undefined' && a instanceof CSSAnimation) || (typeof CSSTransition !== 'undefined' && a instanceof CSSTransition)) continue;
    const t = a.effect && a.effect.target;
    if (!t || !t.hasAttribute || !t.hasAttribute('data-mg')) continue;
    tracks.push({ el: t.getAttribute('data-mg'), dur: a.effect.getComputedTiming().duration, ct: Number(a.currentTime), state: a.playState });
  }
  return {
    scrollY: window.scrollY,
    scrollMax: document.documentElement.scrollHeight - window.innerHeight,
    tracks,
    opacity: p ? Number(getComputedStyle(p).opacity) : null,
    navMorph: nav ? Number(nav.dataset.fwMorph) : null,
    flip: document.documentElement.classList.contains('is-flip'),
    goal: document.documentElement.hasAttribute('data-mg-goal'),
  };
}

function collectBoxes() {
  const boxes = [];
  const add = (key, e) => {
    const r = e.getBoundingClientRect();
    if (r.width > 0 && r.height > 0) boxes.push({ key, x: r.x, y: r.y, width: r.width, height: r.height });
  };
  const seen = {};
  for (const e of document.querySelectorAll('[data-fw]')) {
    const n = e.getAttribute('data-fw');
    seen[n] = (seen[n] || 0) + 1;
    add(seen[n] > 1 ? `${n}#${seen[n]}` : n, e);
  }
  for (const e of document.querySelectorAll('main, footer')) add(e.tagName.toLowerCase(), e);
  const cols = [...document.querySelectorAll('[data-fw="morph-columns"] > div')].filter((c) => getComputedStyle(c).display !== 'none');
  cols.forEach((c, i) => {
    add(`column${i}`, c);
    [...c.querySelectorAll('img')].forEach((im, j) => add(`column${i}.img${j}`, im));
  });
  const bar = document.querySelector('[data-fw="nav"] > div');
  if (bar) {
    add('nav.bar', bar);
    [...bar.children].forEach((c, k) => {
      add(`nav.bar.${k}`, c);
      [...c.children].forEach((d, l) => add(`nav.bar.${k}.${l}`, d));
    });
  }
  return boxes;
}

const unionBoxes = (a, b) => {
  const by = new Map(a.map((x) => [x.key, x]));
  for (const y of b) {
    const x = by.get(y.key);
    if (!x) { by.set(y.key, y); continue; }
    const x0 = Math.min(x.x, y.x), y0 = Math.min(x.y, y.y);
    by.set(y.key, { key: y.key, x: x0, y: y0, width: Math.max(x.x + x.width, y.x + y.width) - x0, height: Math.max(x.y + x.height, y.y + y.height) - y0 });
  }
  return [...by.values()];
};

async function waitFor(page, expr, ms) {
  for (let t = 0; t <= ms; t += 100) {
    if (await page.evaluate(expr)) return true;
    await sleep(100);
  }
  return false;
}

async function settleScroll(page) {
  await page.evaluate(async () => {
    let steady = 0;
    for (let i = 0; i < 40 && steady < 3; i++) {
      window.scrollTo(0, document.documentElement.scrollHeight);
      await new Promise((r) => setTimeout(r, 250));
      steady = document.documentElement.scrollHeight - window.innerHeight - window.scrollY < 2 ? steady + 1 : 0;
    }
  });
}

async function realTween(page, w, h) {
  await page.mouse.move(w / 2, h / 2);
  for (let k = 1; k <= 8; k++) {
    await page.mouse.wheel(0, 120);
    if (await waitFor(page, "document.documentElement.classList.contains('is-flip')", 2500)) {
      await sleep(1800);
      const settled = await waitFor(page, "document.documentElement.hasAttribute('data-mg-goal') && !document.getAnimations().some((a) => a.effect && a.effect.target && a.effect.target.hasAttribute && a.effect.target.hasAttribute('data-mg') && a.playState === 'running')", 4000);
      return { started: true, tries: k, settled };
    }
    await sleep(1000);
  }
  return { started: false, tries: 8, settled: false };
}

const crop = (img, box) => {
  const xr = pxRange(img.width, box.x, box.width), yr = pxRange(img.height, box.y, box.height);
  const width = Math.max(0, xr.hi - xr.lo), height = Math.max(0, yr.hi - yr.lo);
  const data = new Uint8ClampedArray(4 * width * height);
  for (let y = 0; y < height; y++) data.set(img.data.subarray(4 * ((yr.lo + y) * img.width + xr.lo), 4 * ((yr.lo + y) * img.width + xr.lo + width)), 4 * y * width);
  return { width, height, data };
};

const diffImage = (map, W, box, over) => {
  const xr = pxRange(W, box.x, box.width), yr = pxRange(map.length / W, box.y, box.height);
  const width = Math.max(0, xr.hi - xr.lo), height = Math.max(0, yr.hi - yr.lo);
  const data = new Uint8ClampedArray(4 * width * height);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const d = map[(yr.lo + y) * W + xr.lo + x], o = 4 * (y * width + x);
    const c = d > over ? [255, 0, 0] : d > 0 ? [110, 110, 110] : [24, 24, 24];
    data[o] = c[0]; data[o + 1] = c[1]; data[o + 2] = c[2]; data[o + 3] = 255;
  }
  return { width, height, data };
};

const DEADLINE = Date.now() + Number(opt('budget-min', '22')) * 60000;
if (TIMED && engineName !== 'chromium') {
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, `look-${engineName}.json`), JSON.stringify({ fw: FW, over: CELL.over, engine: engineName, ms: MS, complete: false, cells: 0, unverified: 0, skipped: 'geom-timed look: its tween does not start from a wheel on this engine (WebKit); Chromium only', rows: [] }, null, 1) + '\n');
  process.stderr.write(`look ${FW} ${engineName}: skipped (timed look is Chromium only)\n`);
  process.exit(0);
}
const dist = siteDist();
const flag = rewritePathFor(dist, FW);
const server = await startServer(dist);
const engine = await LAUNCHERS[engineName]();
const rows = [];
const faults = [];
const outcomes = [];
let budgetSpent = false;
const flush = (complete) => writeFileSync(join(out, `look-${engineName}.json`), JSON.stringify({ fw: FW, over: CELL.over, engine: engineName, ms: MS, limits: LIMITS, complete, cells: rows.length, unverified: rows.filter((r) => r.verify && !r.verify.ok).length, exhausted: rows.filter((r) => r.exhausted).length, faults, rows }, null, 1) + '\n');
mkdirSync(out, { recursive: true });
const shot = (page) => bound('screenshot', LIMITS.shotMs + 10000, async () => {
  const t0 = Date.now();
  const img = decode(await page.screenshot({ animations: 'allow', caret: 'hide', timeout: LIMITS.shotMs }));
  return { img, ms: Date.now() - t0 };
});
try {
  for (const [w, h] of BANDS) {
    if (Date.now() > DEADLINE) { process.stderr.write(`budget spent: stopped before ${w}x${h}\n`); budgetSpent = true; break; }
    const env = { width: w, height: h, deviceWidth: w, deviceHeight: h, dpr: w <= 640 ? 3 : 1, hover: w <= 1024 ? 'none' : 'hover', pointer: w <= 1024 ? 'coarse' : 'fine', colorScheme: 'light', reducedMotion: 'no-preference' };
    const open = (path) => bound('open page', LIMITS.callMs, async () => {
      const s = await engine.open(env, { origin: server.origin, path, init: PIN_SRC });
      await s.page.evaluate(async () => { for (let i = 0; i < 100 && !(window.__fw && window.__fw.hydrated); i++) await new Promise((r) => setTimeout(r, 50)); });
      await settleScroll(s.page);
      await sleep(1800);
      return s;
    });
    let pair = null;
    const ensure = async () => {
      if (pair) return pair;
      const A = await open('/');
      let B;
      try { B = await open(flag.path + flag.search); } catch (err) { await closeBounded('close base page', A); throw err; }
      pair = { A, B };
      return pair;
    };
    const drop = async () => {
      const p = pair;
      pair = null;
      if (!p) return;
      await closeBounded('close base page', p.A);
      await closeBounded('close flag page', p.B);
    };
    try {
      for (const m of MS) {
        const band = `${w}x${h}`;
        if (TIMED && m !== 0 && m !== 1) {
          rows.push({ band, m, skipped: 'geom-timed rests only at m 0 and 1 (Lean timedSettled); its tracks, published value and end are real-time timers, so no page is pinned between' });
          continue;
        }
        if (Date.now() > DEADLINE) { process.stderr.write(`budget spent: stopped before ${band} m=${m}\n`); budgetSpent = true; break; }
        const taken = await takeCell(`${band} m=${m}`, async () => {
          const { A, B } = await ensure();
          const f = fadeOf(golden, m);
          const fails = [];
          const note = {};
          const ra = await call('pin base', A.page, pinNav, m);
          await call('fade base', A.page, writeFade, { fade: String(f.fade), none: f.pointerNone });
          if (TIMED) {
            if (m === 1) {
              note.tween = await bound('wheel tween', 120000, () => realTween(B.page, w, h));
              if (!note.tween.started) fails.push('the wheel did not start a tween');
              else if (!note.tween.settled) fails.push('the tween did not settle');
            }
          } else {
            await call('pin flag', B.page, pinNav, m);
            await sleep(900);
            if (m > 0) await call('morph flag', B.page, (v) => { const n = document.querySelector('[data-fw="nav"]'); n.dataset.fwMorph = String(v); }, m);
          }
          const darkFlip = TIMED && m === 0 ? await call('dark flag', B.page, () => document.querySelector('[data-fw="nav"]').classList.contains('is-on-dark')) : null;
          Object.assign(ra, await call('pin base again', A.page, pinNav, m));
          if (darkFlip !== null) {
            await call('dark base', A.page, (d) => document.querySelector('[data-fw="nav"]').classList.toggle('is-on-dark', d), darkFlip);
            note.navOnDark = darkFlip;
          }
          await sleep(900);
          const freeze = () => { for (const a of document.getAnimations()) if (a instanceof CSSAnimation) { a.pause(); a.currentTime = 4000; } };
          await call('freeze base', A.page, freeze);
          await call('freeze flag', B.page, freeze);
          await sleep(200);
          if (!TIMED) {
            const base0 = await call('columns base', A.page, observeCell);
            const ready = await waitCell(A.page, B.page, base0.cols);
            note.ready = { step: ready.step, waitedMs: ready.waitedMs };
          }
          const sta = await call('state base', A.page, readState);
          const stb = await call('state flag', B.page, readState);
          if (!scrollEq(CELL, sta.scrollY, stb.scrollY)) fails.push(`scrollY differs: base ${sta.scrollY}, flip ${stb.scrollY}`);
          if (!fadeShows(CELL, golden, sta.opacity, m)) fails.push(`base platform opacity ${sta.opacity}, expected the fade of m`);
          if (!TIMED || m === 1) if (!fadeShows(CELL, golden, stb.opacity, m)) fails.push(`flip platform opacity ${stb.opacity}, expected the fade of m`);
          if (TIMED) {
            if (!timedSettled(m, stb.flip, stb.goal, stb.tracks.length)) fails.push(`timed page not at rest ${m}: flip ${stb.flip}, goal ${stb.goal}, tracks ${stb.tracks.length}`);
          } else {
            if (!within(CELL, stb.navMorph, m)) fails.push(`flip nav data-fw-morph ${stb.navMorph}, expected ${m}`);
            if (!tracksOk(m, stb.tracks.length)) fails.push(`flip holds ${stb.tracks.length} tracks at m=${m}`);
            for (const t of stb.tracks) if (!trackAt(CELL, t.dur, t.ct, m)) fails.push(`track ${t.el} (duration ${t.dur}) at ${t.ct} does not show m=${m}`);
          }
          const verify = { ok: fails.length === 0, fails: fails.slice(0, 8), failCount: fails.length, scrollBase: sta.scrollY, scrollFlip: stb.scrollY, scrollMax: [sta.scrollMax, stb.scrollMax], opacityBase: sta.opacity, opacityFlip: stb.opacity, tracks: stb.tracks.length, navMorph: stb.navMorph, ...note };
          const boxesA = await call('boxes base', A.page, collectBoxes);
          const boxesB = await call('boxes flag', B.page, collectBoxes);
          const rb = await call('nav flag', B.page, () => document.querySelector('[data-fw="nav"]').getBoundingClientRect().toJSON());
          const shotA = await shot(A.page);
          const shotB = await shot(B.page);
          const imgA = shotA.img;
          const imgB = shotB.img;
          verify.shotMs = { base: shotA.ms, flag: shotB.ms };
          if (imgA.width !== imgB.width || imgA.height !== imgB.height) {
            const bad = { band, m, verify: { ...verify, ok: false, fails: [...verify.fails, `screenshot sizes differ ${imgA.width}x${imgA.height} vs ${imgB.width}x${imgB.height}`] } };
            return { ok: false, value: { row: bad, line: null } };
          }
          const k = imgA.width / w;
          const px = (r) => ({ x: r.x * k, y: r.y * k, width: r.width * k, height: r.height * k });
          const nav = { x: Math.min(ra.x, rb.x) * k, y: Math.min(ra.y, rb.y) * k, width: Math.max(ra.width, rb.width) * k, height: Math.max(ra.height, rb.height) * k };
          const whole = { x: 0, y: 0, width: imgA.width, height: imgA.height };
          const clip = (r, q) => { const x = Math.max(r.x, q.x), y = Math.max(r.y, q.y); return { x, y, width: Math.max(0, Math.min(r.x + r.width, q.x + q.width) - x), height: Math.max(0, Math.min(r.y + r.height, q.y + q.height) - y) }; };
          const cols = ra.cols ? clip(px(ra.cols), nav) : nav;
          const bar = ra.bar ? px(ra.bar) : nav;
          const map = diffMap(imgA, imgB);
          const st = (r) => regionStats(CELL, map, imgA.width, imgA.height, r);
          const row = { band, m, nav: st(nav), cols: st(cols), bar: st(bar), page: st(whole), flagBox: px(rb), verify };
          const table = elementTable(CELL, map, imgA.width, imgA.height, unionBoxes(boxesA, boxesB).map((b) => ({ key: b.key, ...px(b) })));
          row.elements = { total: table.total, unowned: table.unowned, rows: table.rows.filter((r) => r.over > 0).slice(0, 14).map((r) => ({ ...r, shareOfBox: +r.shareOfBox.toFixed(4), shareOfDiff: +r.shareOfDiff.toFixed(4) })) };
          if (IMAGES) {
            const dir = join(out, 'img', band, `m${m}`);
            mkdirSync(dir, { recursive: true });
            for (const [name, box, always] of [['nav', nav, true], ['cols', cols, true], ['page', whole, false]]) {
              const s = st(box);
              if (s.over === 0 && !always) continue;
              writeFileSync(join(dir, `${name}-diff.png`), encodePng(diffImage(map, imgA.width, box, CELL.over)));
              if (always || s.share >= PAGE_ARMS_SHARE) {
                writeFileSync(join(dir, `${name}-base.png`), encodePng(crop(imgA, box)));
                writeFileSync(join(dir, `${name}-flip.png`), encodePng(crop(imgB, box)));
              }
            }
          }
          const top = row.elements.rows[0];
          const line = `${band} m=${m} ${verify.ok ? 'ok' : `UNVERIFIED(${verify.failCount}): ${verify.fails[0]}`} nav ${row.nav.share.toFixed(4)} bar ${row.bar.share.toFixed(4)} cols ${row.cols.share.toFixed(4)} page ${row.page.share.toFixed(4)} top ${top ? `${top.key} ${top.own}` : '-'} shot ${shotA.ms}+${shotB.ms} ms${note.ready && note.ready.step === 'late' ? ` [ready wait ran out after ${note.ready.waitedMs} ms]` : ''}`;
          return { ok: verify.ok, value: { row, line } };
        }, { onFault: drop });
        faults.push(...taken.faults);
        outcomes.push(taken.outcome);
        if (taken.outcome === 'exhausted') {
          const last = taken.faults[taken.faults.length - 1];
          const why = `no reading in ${taken.attempts} attempts (${last ? last.error : 'no fault noted'})`;
          rows.push({ band, m, exhausted: true, verify: { ok: false, fails: [why], failCount: 1 } });
          process.stderr.write(`${band} m=${m} ${why}\n`);
        } else {
          rows.push(taken.value.row);
          if (taken.value.line) process.stderr.write(`${taken.value.line}\n`);
        }
      }
    } finally { await drop(); }
    flush(false);
    if (budgetSpent) break;
  }
} finally { await closeBounded('close browser', engine); server.close?.(); }
const bad = rows.filter((r) => r.verify && !r.verify.ok).length;
const kept = cellsKept(outcomes);
flush(!budgetSpent);
process.stderr.write(`look ${FW} ${engineName}: ${rows.length} rows, ${bad} unverified${kept ? ' (exit 0: reported only)' : `, ${outcomes.filter((o) => o === 'exhausted').length} cells with no reading (exit 1)`}\n`);
process.exit(kept ? 0 : 1);
