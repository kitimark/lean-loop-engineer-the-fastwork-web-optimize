// The drawn-size image arm, v2 (task image-arm-v2): per probe (a breakpoint environment of the Lean matrix, with its own width, DPR,
// hover and pointer) read what every image of the page is drawn at, plan the copies, build them in the CI job, serve them in a copy of
// the site build and run the real visual diff (packages/visual-diff) on the lag parts twice per policy: once with the site as it is
// (base) and once with the copies (drawn). Nothing is decided here. The reach of a 1:1 copy, the control policy `fit`, the decision
// of a part and the decoded saving are lean/Fw/Measure/ImageArm.lean (armplan.mjs is its twin, checked against Lean goldens); the
// verdicts are the visual diff's. What this file does is I/O and glue: audit, sizes in, ImageMagick, a tree, a process per run.
//   policy exact  a copy at the device size of a plain <img> drawn 1:1 (only where the proofs allow it, ImageArm.exactCopy)
//   policy fit    the control: every image at its greatest drawn device size at the file's aspect ratio (ImageArm.fitCopy)
import { copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadAnchors, loadGen, probeEnv } from '../spec.mjs';
import { siteDist } from '../serve.mjs';
import { runAudit } from './audit.mjs';
import { exactFile, fitFile, imgOf, reachWhy, saving, sizedOf } from './armplan.mjs';
import { sniff } from './reduce.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const VISUAL_CLI = fileURLToPath(import.meta.resolve('@fw/visual-diff/src/cli.mjs'));

/** The parts that hold the lag regions' images (data-fw anchors of src/anchors.json). */
export const LAG_PARTS = ['hero', 'hero.orbit', 'hero.deck', 'hero.exit', 'morph.panel', 'morph.columns', 'people.card', 'people.o', 'people.carousel', 'people.deck'];
export const POLICIES = ['exact', 'fit'];
export const PROBES_FILE = join(HERE, 'arm-probes.json');

/** The probe ids a run covers: `--probes` or the committed list, then this shard's share (`i/n`: every n-th, from i). */
export function probeIds({ probes, shard = null, file = PROBES_FILE }) {
  const all = probes ?? JSON.parse(readFileSync(file, 'utf8')).probes;
  if (!shard) return all;
  const [i, n] = shard.split('/').map(Number);
  if (!Number.isInteger(i) || !Number.isInteger(n) || n < 1 || i < 1 || i > n) throw new Error(`bad --shard ${shard} (want i/n, 1 <= i <= n)`);
  return all.filter((_, k) => k % n === i - 1);
}

/** The parts (of `partAnchors`: part -> data-fw values) an item sits in: some data-fw ancestor is one of the part's anchors. */
export const partsOf = (it, partAnchors) => Object.keys(partAnchors).filter((p) => (it.fw ?? []).some((f) => partAnchors[p].includes(f)));

const WHY_ORDER = ['notImg', 'cropped', 'scaled', 'fractional', 'noSaving'];
/** Why a file has no `exact` copy: the first reason (in the Lean order) that some drawing of it has, else `disagree` (they ask for different sizes), else ok. Report only. */
export function whyFile(dpr, imgs) {
  const ws = imgs.map((i) => reachWhy(dpr, i));
  for (const w of WHY_ORDER) if (ws.includes(w)) return w;
  return exactFile(dpr, imgs) === null ? 'disagree' : 'ok';
}

const pathOf = (url) => {
  if (!url.startsWith('/')) return null;
  try { return decodeURIComponent(new URL(url, 'http://x').pathname); } catch { return null; }
};

/**
 * The plan of one probe: for each image file of the page (grouped by URL over every element that draws it), the copy each policy
 * wants. `items` are the merged audit readings of one cell; `srcOf(path)` gives { format, bytes } or null for a file not in the build.
 * Returns [{ url, path, nat, parts, n, why, format, bytes, exact, fit }] with [w, h] or null per policy.
 */
export function planProbe({ items, dpr, partAnchors, srcOf }) {
  const by = new Map();
  for (const it of items) {
    if (it.none || !it.url || /^data:/.test(it.url) || !it.nat || it.nat[0] === 0 || it.nat[1] === 0) continue;
    (by.get(it.url) ?? by.set(it.url, []).get(it.url)).push(it);
  }
  const out = [];
  for (const [url, its] of [...by].sort(([a], [b]) => a.localeCompare(b))) {
    const imgs = its.map(imgOf);
    const parts = [...new Set(its.flatMap((it) => partsOf(it, partAnchors)))].sort();
    const path = pathOf(url);
    const src = path ? srcOf(path) : null;
    const rec = { url, path, nat: its[0].nat, parts, n: its.length, why: whyFile(dpr, imgs), format: src?.format ?? null, bytes: src?.bytes ?? null, exact: null, fit: null };
    if (!src) rec.why = path ? 'sourceMissing' : 'external';
    else if (src.format !== 'jpeg' && src.format !== 'png') rec.why = `format:${src.format}`;
    else {
      rec.exact = exactFile(dpr, imgs);
      // the control must not move the layout: a size taken from the natural size would follow the copy
      rec.fit = its.every(sizedOf) ? fitFile(dpr, imgs) : null;
    }
    out.push(rec);
  }
  return out;
}

/** Decoded bytes a part's files save under one policy: the sum over its files that have a copy. */
export function partSaving(plan, part, policy) {
  let s = 0;
  let n = 0;
  for (const f of plan) {
    if (!f.parts.includes(part) || !f[policy]) continue;
    n++;
    s += saving(f.nat[0], f.nat[1], f[policy][0], f[policy][1]);
  }
  return { files: n, saving: s };
}

let MAGICK = null;
/** ImageMagick 7 (`magick`) or 6 (`convert`), found once. */
export function magickCmd() {
  if (MAGICK) return MAGICK;
  for (const c of ['magick', 'convert']) {
    const r = spawnSync(c, ['-version'], { encoding: 'utf8' });
    if (!r.error && r.status === 0 && /ImageMagick/i.test(r.stdout)) return (MAGICK = c);
  }
  throw new Error('ImageMagick not found (magick or convert); the CI job installs it');
}

/** Resize `src` to exactly w x h (Lanczos, same format; JPEG quality 95, 4:4:4, no metadata stripped) into `dst`. */
export function buildCopy(src, dst, w, h, format) {
  mkdirSync(dirname(dst), { recursive: true });
  const args = [src, '-filter', 'Lanczos', '-resize', `${w}x${h}!`];
  if (format === 'jpeg') args.push('-quality', '95', '-sampling-factor', '4:4:4');
  execFileSync(magickCmd(), [...args, dst], { stdio: ['ignore', 'ignore', 'pipe'] });
  return statSync(dst).size;
}

/** The cells of a visual-diff result file as verdict words: part -> { v, ppm, delta, changed, total }. */
export function cellsOf(file) {
  const j = JSON.parse(readFileSync(file, 'utf8'));
  const by = {};
  for (const p of j.probes) {
    for (const c of p.cells) {
      by[c.part] = c.status === 'compared'
        ? { v: c.verdict, ppm: c.ratioPpm, delta: c.stats.maxDelta, changed: c.stats.changed, total: c.stats.total }
        : { v: 'error', ppm: null, delta: null, changed: null, total: null };
    }
  }
  return { by, browser: j.header?.browser ?? null };
}

const visual = ({ engine, probe, parts, dir, root }) => {
  rmSync(dir, { recursive: true, force: true });
  execFileSync(process.execPath, [VISUAL_CLI, 'run', '--engine', engine, '--out', dir, '--probes', probe, '--parts', parts.join(',')], { env: { ...process.env, FW_SITE_DIST: root }, stdio: ['ignore', 'inherit', 'inherit'] });
  return cellsOf(join(dir, `${engine}.visual.json`));
};

/**
 * Run the arm for the probes `ids` in one engine. Writes `<out>/arm-<engine>-<tag>.json` after every probe (a deadline ends the run
 * early with `truncated`), and returns its path. One tree (a copy of the site build) is reused: the copies of a (probe, policy) are
 * written over their URLs, the visual diff runs on the tree, and the sources are put back.
 */
export async function runProbes({ engine, ids, out, tag = 'run', deadlineMs = Infinity, parts = LAG_PARTS, policies = POLICIES, log = console.log }) {
  const dist = siteDist();
  const { gen } = loadGen();
  const anchors = loadAnchors();
  const partAnchors = Object.fromEntries(parts.map((p) => [p, anchors.parts[p]?.anchors ?? []]));
  const probes = ids.map((id) => gen.matrix.probes.find((p) => p.id === id) ?? (() => { throw new Error(`unknown probe ${id}`); })());
  mkdirSync(out, { recursive: true });
  const t0 = Date.now();
  const tree = mkdtempSync(join(tmpdir(), 'fw-arm-tree-'));
  cpSync(dist, tree, { recursive: true });
  const srcOf = (path) => {
    const abs = join(dist, path.replace(/^\//, ''));
    if (!existsSync(abs)) return null;
    const buf = readFileSync(abs);
    return { format: sniff(buf.subarray(0, 600)), bytes: buf.length };
  };
  const file = join(out, `arm-${engine}-${tag}.json`);
  const doc = { schema: 'fw.images.arm2/1', engine, browser: null, tag, probes: ids, policies, parts, truncated: false, ms: 0, rows: [], files: [], spans: [] };
  const flush = () => { doc.ms = Date.now() - t0; writeFileSync(file, JSON.stringify(doc)); };
  const span = (name, s) => { doc.spans.push({ name, ms: Date.now() - s }); };
  for (const p of probes) {
    if (Date.now() > deadlineMs) { doc.truncated = true; log(`deadline reached before ${p.id}`); break; }
    const env = probeEnv(p);
    let s = Date.now();
    const audit = await runAudit({ engine, arm: 'rewrite', widths: [], dprs: [], out: join(out, 'audit', p.id), pool: 1, extra: [{ key: p.id, w: p.width, d: p.dpr, env }], log });
    span(`audit ${p.id}`, s);
    const cell = audit.file.cells[p.id];
    if (!cell || cell.error) { log(`audit of ${p.id} failed: ${cell?.error}`); doc.rows.push({ probe: p.id, width: p.width, dpr: p.dpr, error: cell?.error ?? 'no cell' }); flush(); continue; }
    const plan = planProbe({ items: cell.items, dpr: p.dpr, partAnchors, srcOf });
    for (const f of plan) doc.files.push({ probe: p.id, ...f });
    s = Date.now();
    const base = visual({ engine, probe: p.id, parts, dir: join(out, 'v', p.id, 'base'), root: dist });
    span(`base ${p.id}`, s);
    doc.browser = base.browser;
    const drawnBy = {};
    for (const policy of policies) {
      const todo = plan.filter((f) => f[policy]);
      if (todo.length === 0) { drawnBy[policy] = base.by; continue; }
      s = Date.now();
      const touched = [];
      for (const f of todo) {
        const [w, h] = f[policy];
        const dst = join(tree, f.path.replace(/^\//, ''));
        (f.copyBytes ??= {})[policy] = buildCopy(join(dist, f.path.replace(/^\//, '')), dst, w, h, f.format);
        touched.push(f.path);
      }
      span(`build ${p.id} ${policy}`, s);
      s = Date.now();
      try { drawnBy[policy] = visual({ engine, probe: p.id, parts, dir: join(out, 'v', p.id, policy), root: tree }).by; }
      finally { for (const t of touched) copyFileSync(join(dist, t.replace(/^\//, '')), join(tree, t.replace(/^\//, ''))); }
      span(`drawn ${p.id} ${policy}`, s);
      for (const f of todo) doc.files.find((x) => x.probe === p.id && x.url === f.url).copyBytes = f.copyBytes;
    }
    for (const policy of policies) {
      for (const part of parts) {
        const sv = partSaving(plan, part, policy);
        doc.rows.push({ probe: p.id, width: p.width, dpr: p.dpr, part, policy, base: base.by[part] ?? { v: 'error' }, drawn: drawnBy[policy][part] ?? { v: 'error' }, files: sv.files, saving: sv.saving });
      }
    }
    // the images of the base run are not kept: only the cells that changed with a copy are worth the artifact bytes
    rmSync(join(out, 'v', p.id, 'base', 'img'), { recursive: true, force: true });
    rmSync(join(out, 'audit', p.id), { recursive: true, force: true });
    flush();
  }
  rmSync(tree, { recursive: true, force: true });
  flush();
  return file;
}

export async function armV2Cli(_args, { arg, list }) {
  const engine = arg('engine', 'chromium');
  const out = resolve(arg('out', 'out/arm'));
  const ids = probeIds({ probes: arg('probes') ? list(arg('probes')) : null, shard: arg('shard', null) });
  const deadlineMin = Number(arg('deadline-min', '0'));
  const file = await runProbes({ engine, ids, out, tag: arg('tag', 'run'), deadlineMs: deadlineMin > 0 ? Date.now() + deadlineMin * 60000 : Infinity });
  console.log(`arm ${engine}: ${ids.length} probes -> ${file}`);
}
