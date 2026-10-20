// Verifies the images-at-drawn-size arm against the PL tolerance (packages/visual-diff: pixelmatch counts, Lean verdict twin).
// For every copy the table names, in one engine at the copy's DPR, the source and the copy are each drawn at the same CSS size
// (`scalesOf`: the size the copy was made for, and the smallest size a row serves) on a white page, screenshotted and compared. The
// counts and the verdict are the visual-diff package's (DEFAULT_TOL ppm 2000, delta 64, countAA false); nothing is decided here.
//   node src/cli.mjs arm verify --engine chromium|playwright-webkit --out DIR [--manifest drawn.json] [--dprs 2,3] [--limit N]
//   --site DIR   root that serves the sources (default: the site build)       --copies DIR  root that serves /images-drawn (default: --site)
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { LAUNCHERS } from '../../../visual-diff/src/engines.mjs';
import { compare, decode, encodePng } from '../../../visual-diff/src/diff.mjs';
import { DEFAULT_TOL, verdict } from '../../../visual-diff/src/verdict.mjs';
import { siteDist, startServer } from '../serve.mjs';
import { DEFAULT_MANIFEST, loadDrawn } from './arm.mjs';

const PAGE = '<!doctype html><meta charset="utf-8"><body style="margin:0;background:#fff"><img id="i" alt="" style="position:absolute;left:0;top:0;display:block;max-width:none">';
const LADDER_RATIO = 1.5;
/**
 * The sizes a copy is drawn at, as a fraction of its own device size: a copy holds `oversample` times what its image needs, and the ladder
 * leaves it up to LADDER_RATIO times that, so it is drawn at 1/oversample (the rung is exact) down to 1/(oversample * LADDER_RATIO).
 */
export const scalesOf = (m) => { const o = m.ladder?.oversample ?? 1; return [1 / o, 1 / (o * LADDER_RATIO)]; };

/** The tests of a manifest at one DPR: one per (url, copy file), sized by the copy's device size. */
export function testsOf(m, dpr) {
  const SCALES = scalesOf(m);
  const out = [];
  for (const [url, e] of Object.entries(m.images)) {
    const rows = e.dprs[String(dpr)];
    if (!rows) continue;
    for (const f of new Set(rows.map((r) => r.file).filter(Boolean))) {
      const meta = m.files[f];
      for (const s of SCALES) out.push({ url, file: f, scale: s, cssW: (meta.w * s) / dpr, cssH: (meta.h * s) / dpr });
    }
  }
  return out;
}

export async function verify({ engine, manifest, out, dprs, site, copies, limit = Infinity, log = console.log }) {
  const m = loadDrawn(manifest);
  const dirPage = mkdtempSync(join(tmpdir(), 'fw-img-verify-'));
  writeFileSync(join(dirPage, 'index.html'), PAGE);
  const srvPage = await startServer(dirPage, null);
  const srvSite = await startServer(site, null);
  const srvCopies = copies === site ? srvSite : await startServer(copies, null);
  const eng = await LAUNCHERS[engine]();
  const cells = [];
  try {
    for (const dpr of dprs) {
      const env = { width: 800, height: 700, deviceWidth: 800, deviceHeight: 700, dpr, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
      const s = await eng.open(env, { origin: srvPage.origin, path: '/', init: '' });
      try {
        const shot = async (src, cssW, cssH) => {
          const ok = await s.page.evaluate(async ({ src, cssW, cssH }) => {
            const im = document.getElementById('i');
            im.removeAttribute('src');
            im.style.width = `${cssW}px`;
            im.style.height = `${cssH}px`;
            im.src = src;
            try { await im.decode(); } catch { return { ok: false, w: 0, h: 0 }; }
            await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())));
            return { ok: im.complete && im.naturalWidth > 0, w: im.naturalWidth, h: im.naturalHeight };
          }, { src, cssW, cssH });
          const clip = { x: 0, y: 0, width: Math.max(1, Math.min(790, Math.ceil(cssW))), height: Math.max(1, Math.min(690, Math.ceil(cssH))) };
          const png = await s.page.screenshot({ clip, animations: 'allow', caret: 'hide' });
          return { ...ok, png, clip };
        };
        for (const t of testsOf(m, dpr).slice(0, limit)) {
          const a = await shot(`${srvSite.origin}${t.url}`, t.cssW, t.cssH);
          const b = await shot(`${srvCopies.origin}${t.file}`, t.cssW, t.cssH);
          const imagesLoaded = a.ok && b.ok;
          const { stats } = compare(decode(a.png), decode(b.png));
          const st = { ...stats, settled: true, present: true, fontsLoaded: true, imagesLoaded };
          const v = verdict(DEFAULT_TOL, st);
          const cell = { dpr, url: t.url, file: t.file, scale: t.scale, css: [+t.cssW.toFixed(2), +t.cssH.toFixed(2)], clip: [a.clip.width, a.clip.height], nat: [a.w, a.h], copyNat: [b.w, b.h], changed: stats.changed, aa: stats.aa, total: stats.total, maxDelta: stats.maxDelta, ppm: Math.round((stats.changed * 1e6) / stats.total), verdict: v };
          cells.push(cell);
          if (v !== 'pass') {
            const d = join(out, 'img', engine);
            mkdirSync(d, { recursive: true });
            const base = `${dpr}x-${t.file.replace(/[^A-Za-z0-9]+/g, '_')}-${t.scale}`;
            writeFileSync(join(d, `${base}.orig.png`), a.png);
            writeFileSync(join(d, `${base}.copy.png`), b.png);
            writeFileSync(join(d, `${base}.diff.png`), encodePng(compare(decode(a.png), decode(b.png)).diff));
          }
        }
        log(`${engine} dpr ${dpr}: ${cells.filter((c) => c.dpr === dpr).length} tests`);
      } finally { await s.close().catch(() => {}); }
    }
  } finally {
    await eng.close().catch(() => {});
    await srvPage.close(); await srvSite.close();
    if (srvCopies !== srvSite) await srvCopies.close();
  }
  const version = await eng.version?.().catch(() => null);
  const tally = {};
  for (const c of cells) tally[c.verdict] = (tally[c.verdict] ?? 0) + 1;
  const file = { schema: 'fw.images.verify/1', engine, version: version ?? null, tol: DEFAULT_TOL, scales: scalesOf(m), tally, cells };
  mkdirSync(out, { recursive: true });
  const name = join(out, `verify-${engine}.json`);
  writeFileSync(name, JSON.stringify(file));
  return { name, file };
}

export async function verifyCli(_args, { arg, list }) {
  const engine = arg('engine', 'chromium');
  const out = resolve(arg('out', 'out/images-verify'));
  const site = resolve(arg('site', siteDist()));
  const copies = resolve(arg('copies', site));
  const { name, file } = await verify({
    engine, out, manifest: resolve(arg('manifest', DEFAULT_MANIFEST)), dprs: list(arg('dprs', '2,3')).map(Number), site, copies, limit: Number(arg('limit', 'Infinity')),
  });
  console.log(`wrote ${name} ${JSON.stringify(file.tally)}`);
  const worst = [...file.cells].sort((a, b) => b.ppm - a.ppm).slice(0, 5);
  for (const w of worst) console.log(`  ${w.verdict} ${w.ppm} ppm maxDelta ${w.maxDelta} ${w.dpr}x ${w.file} @${w.scale}`);
  if (!file.tally.pass || Object.keys(file.tally).some((k) => k !== 'pass')) process.exitCode = 1;
}
