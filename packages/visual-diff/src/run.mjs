// The runner: for each probe (a breakpoint environment of the gate's Lean matrix) and each part, screenshot the part's
// box in the original snapshot and in the rewrite, compare, and write the counts, the Lean verdict and diff images of
// the cells that are not a pass. Reuses the gate's part selectors (anchors.json), probe list (breakpoints.gen.json),
// servers (serve.mjs), init script and readiness wait (page.mjs) by import; none of them is changed.
// Images stay in the output directory (a CI artifact); nothing here writes into git.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PIN_SRC, prepareInPage, waitReady } from '../../gate-breakpoints/src/page.mjs';
import { PKG as GATE_PKG, siteDist, snapshotRoot, startServer } from '../../gate-breakpoints/src/serve.mjs';
import { loadAnchors, loadGen, probeEnv, selectParts } from '../../gate-breakpoints/src/spec.mjs';
import { LAUNCHERS } from './engines.mjs';
import { compare, decode, encodePng, sameImage } from './diff.mjs';
import { DEFAULT_TOL, verdict, within } from './verdict.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const SITES = ['orig', 'rewrite'];
const CAP_MS = { orig: 20000, rewrite: 15000 };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Parts whose first role is the document itself: nothing of their own to look at. Skipped by default. */
export const DEFAULT_SKIP = ['engine.scroll', 'morph.tween'];

export const loadTolerances = (path = join(HERE, '..', 'tolerances.json')) => JSON.parse(readFileSync(path, 'utf8'));
export const tolFor = (tols, pid) => ({ ...DEFAULT_TOL, ...(tols.default ?? {}), ...((tols.parts ?? {})[pid] ?? {}) });

/** In the page: scroll the part's box to the top of the viewport, wait for the frame to settle, return the visible box. */
export async function locateInPage({ selector }) {
  const sleepP = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleepP(250)]);
  const el = document.querySelector(selector);
  if (!el) return { absent: 'no element' };
  const first = el.getBoundingClientRect();
  if (first.width === 0 && first.height === 0) return { absent: 'zero box' };
  window.scrollTo({ top: Math.max(0, first.top + window.scrollY), behavior: 'instant' });
  for (let i = 0; i < 3; i++) await frame();
  await sleepP(250);
  const t0 = performance.now();
  const pending = () => Array.from(document.images).filter((im) => {
    const r = im.getBoundingClientRect();
    return !im.complete && r.bottom > 0 && r.top < window.innerHeight;
  });
  while (pending().length > 0 && performance.now() - t0 < 4000) await sleepP(50);
  const r = el.getBoundingClientRect();
  const vw = document.documentElement.clientWidth;
  const vh = window.innerHeight;
  const x = Math.floor(Math.max(0, r.left));
  const y = Math.floor(Math.max(0, r.top));
  const right = Math.ceil(Math.min(vw, r.right));
  const bottom = Math.ceil(Math.min(vh, r.bottom));
  if (right - x <= 0 || bottom - y <= 0) return { absent: 'outside the viewport' };
  return { clip: { x, y, width: right - x, height: bottom - y }, scrollY: window.scrollY };
}

/** Two screenshots of one box 200 ms apart: the pair is "stable" when their pixels are identical. */
async function shoot(page, selector) {
  const loc = await page.evaluate(locateInPage, { selector });
  if (loc.absent) return { absent: loc.absent };
  const a = await page.screenshot({ clip: loc.clip, animations: 'allow', caret: 'hide' });
  await sleep(200);
  const b = await page.screenshot({ clip: loc.clip, animations: 'allow', caret: 'hide' });
  const ia = decode(a);
  const ib = decode(b);
  const same = sameImage(ia, ib);
  return { img: ia, stable: same, self: same ? null : compare(ia, ib).stats, clip: loc.clip };
}

/** Capture every wanted part in one arm's page, in the gate's order: plain parts, then overlays one by one, then mount parts. */
async function captureArm(page, site, parts, anchors) {
  const steps = (pid, kind) => (((anchors.parts[pid].prepare ?? {})[site]) ?? []).filter((st) => st.kind === kind);
  const sel = (pid) => anchors.parts[pid].roles[0][site];
  const out = {};
  const one = async (pid) => {
    try { out[pid] = await shoot(page, sel(pid)); } catch (e) { out[pid] = { error: String(e.message).split('\n')[0] }; }
  };
  const overlay = parts.filter((p) => steps(p, 'overlay').length > 0);
  const mount = parts.filter((p) => steps(p, 'mount').length > 0 && !overlay.includes(p));
  for (const pid of parts.filter((p) => !overlay.includes(p) && !mount.includes(p))) await one(pid);
  for (const pid of overlay) {
    const st = steps(pid, 'overlay');
    try {
      await page.evaluate(prepareInPage, { stage: 'open', steps: st, capMs: CAP_MS[site] });
      await one(pid);
      await page.evaluate(prepareInPage, { stage: 'close', steps: st, capMs: CAP_MS[site] });
    } catch (e) { out[pid] = { error: String(e.message).split('\n')[0] }; }
  }
  if (mount.length > 0) {
    try { await page.evaluate(prepareInPage, { stage: 'ready', steps: mount.flatMap((p) => steps(p, 'mount')), capMs: CAP_MS[site] }); } catch (e) { log(`  mount ${site}: ${e.message}`); }
    for (const pid of mount) await one(pid);
  }
  return out;
}

/** Reduce the two arms' captures of one part to a cell: counts, verdict, diff image (null when the cell is a pass or nc). */
export function cellOf(pid, tol, a, b) {
  if (a.error || b.error) return { part: pid, status: 'error', error: { orig: a.error ?? null, rewrite: b.error ?? null } };
  if (a.absent && b.absent) return { part: pid, status: 'nc', absent: { orig: a.absent, rewrite: b.absent } };
  const c = compare(a.img ?? null, b.img ?? null);
  // An arm is settled when its own two shots are identical, or differ only within the part's tolerance (the noise floor).
  const calm = (x) => x.absent || x.stable || (x.self != null && within(tol, x.self));
  const stats = { ...c.stats, settled: calm(a) && calm(b) };
  const v = verdict(tol, stats);
  return {
    part: pid, status: 'compared', verdict: v, stats, tol, size: c.size,
    ratioPpm: stats.total === 0 ? null : Math.round(((stats.changed + (tol.countAA ? stats.aa : 0)) * 1e6) / stats.total),
    absent: a.absent || b.absent ? { orig: a.absent ?? null, rewrite: b.absent ?? null } : undefined,
    stable: { orig: a.absent ? null : a.stable, rewrite: b.absent ? null : b.stable },
    selfPpm: { orig: a.self ? Math.round((a.self.changed * 1e6) / a.self.total) : null, rewrite: b.self ? Math.round((b.self.changed * 1e6) / b.self.total) : null },
    images: v === 'pass' ? null : { orig: a.img ?? null, rewrite: b.img ?? null, diff: c.diff },
  };
}

async function pool(items, n, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    for (;;) { const i = next++; if (i >= items.length) return; results[i] = await fn(items[i], i); }
  }));
  return results;
}

/** The page the rewrite arm loads: `/` for the default config, else the prerendered page of the flag set `fw` (e.g. `morph.tween:waapi`, as `?fw=...`; build output configs.json). */
export function rewritePathFor(dist, fw) {
  if (!fw) return { search: '', path: '/' };
  const search = fw.startsWith('?') ? fw : `?fw=${fw}`;
  const cfg = JSON.parse(readFileSync(join(dist, 'configs.json'), 'utf8'));
  const hash = cfg.bySearch[search];
  if (!hash) throw new Error(`fw "${search}" is not prerendered; known: ${Object.keys(cfg.bySearch).join(' | ')}`);
  return { search, path: `/${cfg.byHash[hash]}` };
}

export async function runVisual({ engineName, outDir, probeIds, partFilter = null, fw = '', skip = DEFAULT_SKIP, concurrency = 2, tolerances = loadTolerances() }) {
  const anchors = loadAnchors();
  const all = Object.keys(anchors.parts);
  const sel = selectParts(all, partFilter);
  const parts = sel.covered.filter((p) => partFilter !== null || !skip.includes(p));
  const { gen, sha256: genSha } = loadGen();
  const wanted = probeIds.map((id) => gen.matrix.probes.find((p) => p.id === id) ?? (() => { throw new Error(`unknown probe ${id}`); })());
  const lock = JSON.parse(readFileSync(resolve(GATE_PKG, '../../snapshot.lock.json'), 'utf8'));
  const dist = siteDist();
  const buildInfo = JSON.parse(readFileSync(join(dist, 'build-info.json'), 'utf8'));
  const { search, path: rewritePath } = rewritePathFor(dist, fw);
  const pathOf = { orig: '/', rewrite: rewritePath };
  const servers = { orig: await startServer(snapshotRoot()), rewrite: await startServer(dist) };
  const engine = await LAUNCHERS[engineName]();
  const imgDir = join(outDir, 'img', engineName);

  async function arm(env, site) {
    const s = await engine.open(env, { origin: servers[site].origin, path: pathOf[site], init: PIN_SRC });
    try {
      await s.page.evaluate(waitReady, { site, capMs: CAP_MS[site] });
      return await captureArm(s.page, site, parts, anchors);
    } finally { await s.close().catch(() => {}); }
  }
  let done = 0;
  const probes = await pool(wanted, concurrency, async (p) => {
    const env = probeEnv(p);
    const [a, b] = await Promise.all(SITES.map((site) => arm(env, site).catch((e) => Object.fromEntries(parts.map((pid) => [pid, { error: `load: ${String(e.message).split('\n')[0]}` }])))));
    const cells = parts.map((pid) => cellOf(pid, tolFor(tolerances, pid), a[pid], b[pid]));
    for (const c of cells) {
      if (!c.images) continue;
      const d = join(imgDir, p.id);
      mkdirSync(d, { recursive: true });
      if (c.images.orig) writeFileSync(join(d, `${c.part}.orig.png`), encodePng(c.images.orig));
      if (c.images.rewrite) writeFileSync(join(d, `${c.part}.rewrite.png`), encodePng(c.images.rewrite));
      writeFileSync(join(d, `${c.part}.diff.png`), encodePng(c.images.diff));
      c.images = { dir: `img/${engineName}/${p.id}`, files: [`${c.part}.orig.png`, `${c.part}.rewrite.png`, `${c.part}.diff.png`] };
    }
    log(`  ${engineName}: ${++done}/${wanted.length} probes (${p.id})`);
    return { id: p.id, env, cells };
  });
  const header = {
    schema: 'fw.visual-diff.run/1', engine: engineName, browser: await engine.version(),
    gen: { sha256: genSha }, snapshot: lock.snapshot, site: { buildId: buildInfo.buildId, configHash: buildInfo.configHash }, fw: search,
    parts, skippedParts: all.filter((p) => !parts.includes(p)), probes: probeIds, tolerances,
  };
  await engine.close();
  await Promise.all(SITES.map((s) => servers[s].close()));
  mkdirSync(outDir, { recursive: true });
  const file = join(outDir, `${engineName}.visual.json`);
  writeFileSync(file, JSON.stringify({ header, probes }, null, 1) + '\n');
  log(`wrote ${file}`);
  return file;
}
