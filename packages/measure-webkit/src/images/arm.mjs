// The images-at-drawn-size arm (task image-audit). An arm is the same page (HTML, CSS and script byte for byte) whose image
// requests are answered with resized copies: one file per (image, DPR, width class), at the size the audit measured it is drawn
// (device pixels), never smaller. The copies are never committed: arm build writes them into the
// gitignored apps/site/dist/aot/images-drawn (the served root) at run time; their table is apps/site/src/flags/images/drawn.json. No markup change, so the arm differs from the
// default build in image bytes only.
//
// This file is pure and dependency free so that both servers can use it: gate-breakpoints (startServer(root, rewrite)) and
// measure-webkit (serveTree(root, { rewrite })). packages/measure-webkit/src/images/arm.mjs is a byte copy; a test keeps them equal.
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
/** apps/site/src/flags/images/drawn.json from either package's src/images directory. */
export const DEFAULT_MANIFEST = resolve(HERE, '../../../../apps/site/src/flags/images/drawn.json');

export function loadDrawn(path = DEFAULT_MANIFEST) {
  const m = JSON.parse(readFileSync(path, 'utf8'));
  if (m.schema !== 'fw.images.drawn/1') throw new Error(`${path}: schema ${m.schema}`);
  return m;
}

/**
 * The served path of the resized copy of `url` for a page of CSS width `width` at DPR `dpr`, or null when the arm leaves the image
 * alone (not in the table, or the table has no entry for that DPR or a larger one). The entry of a DPR is the smallest listed DPR
 * that is at least `dpr` (a copy is never smaller than the device pixels asked for); within it the last entry whose `from` is at
 * most `width`.
 */
export function drawnFile(m, url, width, dpr) {
  const e = m.images[url];
  if (!e) return null;
  const have = Object.keys(e.dprs).map(Number).sort((a, b) => a - b);
  const d = have.find((x) => x >= dpr);
  if (d === undefined) return null;
  const rows = e.dprs[String(d)];
  let pick = null;
  for (const r of rows) if (r.from <= width) pick = r;
  return pick ? pick.file : null;
}

/** A rewrite function for `startServer` / `serveTree`: the arm's copies on top of `base` (another rewrite, or null). */
export function composeRewrite(base, m, { width, dpr }) {
  return (pathname, search = '') => {
    const to = m ? drawnFile(m, pathname, width, dpr) : null;
    if (to) return to;
    return base ? base(pathname, search) : null;
  };
}

/** Absolute path of a manifest file entry under a site root (the served dist/aot). */
export const fileUnder = (root, file) => join(root, file.replace(/^\//, ''));
