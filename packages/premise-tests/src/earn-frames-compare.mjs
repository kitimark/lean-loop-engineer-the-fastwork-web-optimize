#!/usr/bin/env node
// Frame-by-frame comparison of two earn-frames.mjs captures (task nav-cta-webkit-match). Per frame: the pixels whose largest
// channel difference exceeds the Lean threshold (Fw.Parts.NavEarnWebkit.frameThreshold, golden row frameBound), and the largest
// rect and padding difference. A frame passes when its count is within frameAllowed of its width.
//
//   node src/earn-frames-compare.mjs --chromium DIR --webkit DIR [--out summary.json]
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { decode } from '../../visual-diff/src/diff.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] ? args[i + 1] : d; };
const bound = readFileSync(resolve(here, '../../contracts/golden/parts/nav.earn.webkit.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((g) => g.fn === 'frameBound').out;

export const allowed = (width) => Math.floor((width * bound.bandHeight * bound.permille) / 1000);

export function changed(a, b, threshold = bound.threshold) {
  if (a.width !== b.width || a.height !== b.height) return { count: Infinity, max: 255 };
  let count = 0, max = 0;
  for (let i = 0; i < a.data.length; i += 4) {
    const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]), Math.abs(a.data[i + 2] - b.data[i + 2]));
    if (d > max) max = d;
    if (d > threshold) count++;
  }
  return { count, max };
}

const geom = (x, y) => Math.max(...x.earn.map((v, i) => Math.abs(v - y.earn[i])), ...x.lang.map((v, i) => Math.abs(v - y.lang[i])), ...x.label.map((v, i) => Math.abs(v - y.label[i])));

function load(dir, engine) {
  const idx = JSON.parse(readFileSync(join(dir, `frames-${engine}.json`), 'utf8'));
  return { idx, key: new Map(idx.frames.map((f) => [`${f.width}/${f.scenario}/${f.arm}/${f.t}`, f])), dir };
}

export function compare(a, b) {
  const rows = [];
  for (const [k, fa] of a.key) {
    const fb = b.key.get(k);
    if (!fb) continue;
    const c = changed(decode(readFileSync(join(a.dir, fa.fileNoText))), decode(readFileSync(join(b.dir, fb.fileNoText))));
    const withText = changed(decode(readFileSync(join(a.dir, fa.file))), decode(readFileSync(join(b.dir, fb.file))));
    rows.push({ width: fa.width, scenario: fa.scenario, arm: fa.arm, t: fa.t, changed: c.count, maxChannel: c.max, changedWithText: withText.count, maxRectDelta: Math.round(geom(fa, fb) * 100) / 100,
      ok: c.count <= allowed(fa.width) });
  }
  return rows;
}

const worst = (rows) => rows.reduce((m, r) => (r.changed > m.changed ? r : m), { changed: -1 });

function summarize(rows) {
  const out = {};
  for (const r of rows) {
    const k = `${r.width}/${r.scenario}/${r.arm}`;
    const s = (out[k] ??= { frames: 0, failing: 0, maxChanged: 0, maxWithText: 0, maxChannel: 0, maxRectDelta: 0, allowed: allowed(r.width), worstT: null });
    s.frames++;
    if (!r.ok) s.failing++;
    if (r.changed > s.maxChanged) { s.maxChanged = r.changed; s.worstT = r.t; }
    s.maxChannel = Math.max(s.maxChannel, r.maxChannel);
    s.maxWithText = Math.max(s.maxWithText, r.changedWithText ?? 0);
    s.maxRectDelta = Math.max(s.maxRectDelta, r.maxRectDelta);
  }
  return out;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const cr = load(resolve(opt('chromium', 'out-cr')), 'chromium');
  const wk = load(resolve(opt('webkit', 'out-wk')), 'playwright-webkit');
  const cross = compare(cr, wk);
  const sameCr = [];
  for (const [k, f] of cr.key) {
    if (f.arm !== 'faithful') continue;
    const g = cr.key.get(k.replace('/faithful/', '/logical/'));
    if (!g) continue;
    const c = changed(decode(readFileSync(join(cr.dir, f.fileNoText))), decode(readFileSync(join(cr.dir, g.fileNoText))));
    sameCr.push({ width: f.width, scenario: f.scenario, arm: 'faithful-vs-logical', t: f.t, changed: c.count, maxChannel: c.max, maxRectDelta: 0, ok: c.count <= allowed(f.width) });
  }
  const summary = { bound, chromiumVsWebkit: summarize(cross), chromiumFaithfulVsLogical: summarize(sameCr), chromium: cr.idx.browser, webkit: wk.idx.browser,
    verdict: { fixWithinBound: cross.filter((r) => r.arm === 'logical').every((r) => r.ok), chromiumUnchanged: sameCr.every((r) => r.ok),
      faithfulExceedsBound: cross.some((r) => r.arm === 'faithful' && !r.ok) }, frames: cross };
  for (const [k, s] of Object.entries(summary.chromiumVsWebkit)) console.log(`${k.padEnd(22)} frames ${s.frames} failing ${s.failing} max ${s.maxChanged} (allowed ${s.allowed}) with text ${s.maxWithText} at t=${s.worstT} rect ${s.maxRectDelta}px`);
  for (const [k, s] of Object.entries(summary.chromiumFaithfulVsLogical)) console.log(`chromium ${k.padEnd(22)} max ${s.maxChanged} (allowed ${s.allowed})`);
  console.log(JSON.stringify(summary.verdict));
  if (opt('out', '')) writeFileSync(resolve(opt('out', '')), `${JSON.stringify(summary, null, 1)}\n`);
}
