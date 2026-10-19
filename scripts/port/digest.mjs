#!/usr/bin/env node
// Port completeness gate, checks 3 (assets) and 4 (svg skeleton): reads the snapshot page and a built dist/aot at run
// time and writes a report of hashes, skeleton keys, URLs and verdicts; never path data or command letters.
// Decisions mirror lean/Fw/Site/Assets.lean and lean/Fw/Port/Svg.lean and are checked against
// packages/contracts/golden/port/*.jsonl by apps/site/test/port-*.test.mjs. Unproved glue (TS stand-in): the HTML
// tokenizer, the selector matcher, the URL scanner, the data: URI scanner and the hashing of asset identities.
// Run: node scripts/port/digest.mjs --dist apps/site/dist/aot [--snapshot snapshot/site] [--out report.json]
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const golden = path.join(repo, 'packages/contracts/golden/port');
export const sections = JSON.parse(readFileSync(path.join(golden, 'sections.json'), 'utf8'));
const excl = JSON.parse(readFileSync(path.join(golden, 'exclusions.json'), 'utf8'));
export const exclusions = excl.entries;
export const crawlSkip = excl.crawlSkip.map((k) => k.prefix);

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
const RAW = new Set(['script', 'style', 'textarea', 'title']);
const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

export const decode = (s) =>
  s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) =>
    e[0] === '#'
      ? String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10))
      : (ENT[e.toLowerCase()] ?? m));

const attrsOf = (s) => {
  const out = {};
  for (const m of s.matchAll(/([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g))
    out[m[1].toLowerCase()] = decode(m[2] ?? m[3] ?? m[4] ?? '');
  return out;
};

// An element tree: {tag, attrs, kids, parent}; text nodes are {text}.
export function parseHtml(src) {
  const root = { tag: '#root', attrs: {}, kids: [], parent: null };
  let cur = root;
  const re = /<!--[\s\S]*?-->|<![^>]*>|<\/([A-Za-z][\w:-]*)\s*>|<([A-Za-z][\w:-]*)((?:\s*[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*(\/?)>/g;
  let last = 0;
  let m;
  while ((m = re.exec(src))) {
    if (m.index > last) cur.kids.push({ text: decode(src.slice(last, m.index)) });
    last = re.lastIndex;
    if (m[1]) {
      const tag = m[1].toLowerCase();
      let e = cur;
      while (e && e.tag !== tag) e = e.parent;
      if (e && e.parent) cur = e.parent;
    } else if (m[2]) {
      const tag = m[2].toLowerCase();
      const el = { tag, attrs: attrsOf(m[3]), kids: [], parent: cur };
      cur.kids.push(el);
      const inSvg = tag === 'svg' || ancestors(cur).some((a) => a.tag === 'svg');
      if (RAW.has(tag)) {
        const end = src.toLowerCase().indexOf(`</${tag}`, last);
        const stop = end < 0 ? src.length : end;
        el.kids.push({ text: src.slice(last, stop) });
        const close = src.indexOf('>', stop);
        last = re.lastIndex = close < 0 ? src.length : close + 1;
      } else if (!VOID.has(tag) && !(m[4] && inSvg)) cur = el;
    }
  }
  if (last < src.length) cur.kids.push({ text: decode(src.slice(last)) });
  return root;
}

export const ancestors = (el) => {
  const out = [];
  for (let e = el; e && e.tag !== '#root'; e = e.parent) out.push(e);
  return out;
};

export const elements = (el, out = []) => {
  for (const k of el.kids ?? []) if (k.tag) out.push(k), elements(k, out);
  return out;
};

// Selector subset of the section table: tag, #id, .class, [a], [a="v"], :first-child; descendant and child
// combinators; comma lists.
const splitTop = (s, ch) => {
  const out = [];
  let depth = 0;
  let q = '';
  let start = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) q = c === q ? '' : q;
    else if (c === '"' || c === "'") q = c;
    else if (c === '[') depth++;
    else if (c === ']') depth--;
    else if (c === ch && depth === 0) out.push(s.slice(start, i)), (start = i + 1);
  }
  out.push(s.slice(start));
  return out;
};

const compound = (s) => {
  const tests = [];
  for (const m of s.matchAll(/^([a-zA-Z*][\w-]*)|#([\w-]+)|\.([\w-]+)|\[([\w-]+)(?:="([^"]*)")?\]|:(first-child)/g)) {
    if (m[1] && m[1] !== '*') tests.push((e) => e.tag === m[1].toLowerCase());
    else if (m[2]) tests.push((e) => e.attrs.id === m[2]);
    else if (m[3]) tests.push((e) => (e.attrs.class ?? '').split(/\s+/).includes(m[3]));
    else if (m[4]) tests.push((e) => m[4] in e.attrs && (m[5] === undefined || e.attrs[m[4]] === m[5]));
    else if (m[6]) tests.push((e) => e.parent && e.parent.kids.find((k) => k.tag) === e);
  }
  return (e) => tests.every((t) => t(e));
};

export function selector(sel) {
  const alts = splitTop(sel, ',').map((c) => {
    const parts = c.trim().replace(/\s*>\s*/g, ' > ').split(/\s+/);
    const seq = [];
    let comb = ' ';
    for (const p of parts) {
      if (p === '>') comb = '>';
      else seq.push({ comb, test: compound(p) }), (comb = ' ');
    }
    return seq;
  });
  const at = (seq, i, e) => {
    if (!e || e.tag === '#root' || !seq[i].test(e)) return false;
    if (i === 0) return true;
    if (seq[i].comb === '>') return at(seq, i - 1, e.parent);
    for (let a = e.parent; a && a.tag !== '#root'; a = a.parent) if (at(seq, i - 1, a)) return true;
    return false;
  };
  return (e) => alts.some((seq) => at(seq, seq.length - 1, e));
}

// Fw.Port.Sections.owner over the given ancestors' matching part ids.
export const owner = (A) => {
  for (const m of A) if (m.length) return m[0];
  return sections.page;
};

export function owners(arm) {
  const rows = sections.table.filter((r) => !r.pageLevel).map((r) => ({ part: r.part, match: selector(r[arm]) }));
  const memo = new Map();
  const ids = (e) => {
    if (!memo.has(e)) memo.set(e, rows.filter((r) => r.match(e)).map((r) => r.part));
    return memo.get(e);
  };
  return (el) => owner(ancestors(el).map(ids));
}

// Fw.Port.Sections.unmatched.
export function unmatched(o, r) {
  const rest = [...r];
  const out = [];
  for (const a of o) {
    const i = rest.indexOf(a);
    if (i >= 0) rest.splice(i, 1);
    else out.push(a);
  }
  return out;
}

const exclKey = (E, c, k) => E.some((e) => e.check === c && e.key === k);

// Fw.Port.Svg.
export const tagU = ['circle', 'clippath', 'defs', 'ellipse', 'g', 'line', 'lineargradient', 'mask', 'path', 'polygon',
  'polyline', 'radialgradient', 'rect', 'stop', 'text', 'use'];
export const norm = (s) => s.replace(/[ \t\n\f\r]/g, ' ').split(' ').filter((w) => w !== '').join(' ');
export const letters = (d) => [...d].filter((c) => 'MmZzLlHhVvCcSsQqTtAa'.includes(c)).join('');
export function skel({ viewBox, kids }) {
  const counts = tagU.map((u) => kids.filter((k) => k.tag === u).length);
  counts.push(kids.filter((k) => !tagU.includes(k.tag)).length);
  const paths = kids.filter((k) => k.tag === 'path').map((k) => [Buffer.byteLength(k.d, 'utf8'), letters(k.d)]);
  return { viewBox: norm(viewBox), counts, paths };
}
export const canon = (s) => JSON.stringify({ counts: s.counts, paths: s.paths, viewBox: s.viewBox });
export const keyOf = (s) => createHash('sha256').update(canon(s)).digest('hex').slice(0, 16);
export function svgCheck(E, o, r) {
  const keep = (k) => !exclKey(E, 'svg', k);
  const missing = unmatched(o, r).filter(keep);
  const extra = unmatched(r, o).filter(keep);
  return { missing, extra, pass: missing.length === 0 && extra.length === 0 };
}

export function svgUnits(tree, ownerOf) {
  return elements(tree)
    .filter((e) => e.tag === 'svg' && !ancestors(e.parent).some((a) => a.tag === 'svg'))
    .map((e) => {
      const s = skel({ viewBox: e.attrs.viewbox ?? '', kids: elements(e).map((k) => ({ tag: k.tag, d: k.attrs.d ?? '' })) });
      return { key: keyOf(s), owner: ownerOf(e), viewBox: s.viewBox, elements: s.counts.reduce((a, b) => a + b, 0), paths: s.paths.length };
    });
}

// Fw.Site.Assets.
export const exts = ['avif', 'gif', 'ico', 'jpeg', 'jpg', 'mp3', 'mp4', 'otf', 'png', 'svg', 'ttf', 'webm', 'webmanifest',
  'webp', 'woff', 'woff2'];
export function ext(u) {
  const last = u.split('/').at(-1);
  const ps = last.split('.');
  return ps.length === 1 ? '' : ps.at(-1).toLowerCase();
}
export const isAsset = (u) => exts.includes(ext(u));
export const origUrl = (src) => (src.startsWith('snapshot/site/') ? '/' + src.slice('snapshot/site/'.length) : null);
export function rename(F, u) {
  const f = F.find((f) => origUrl(f.src) === u);
  return f ? f.url : u;
}
export function verdict(F, R, E, u) {
  if (R.includes(rename(F, u))) return 'present';
  return exclKey(E, 'assets', u) ? 'excluded' : 'missing';
}
export const assetsMissing = (F, R, E, O) => [...new Set(O)].filter((u) => verdict(F, R, E, u) === 'missing');

// Fw.Site.Assets.inlineNorm: JS trim and \s are the ECMAScript white space set W of the Lean.
export const inlineNorm = (t) => t.trim().replaceAll(/>\s+</g, '><').replaceAll('"', "'").replaceAll(/\s+/g, ' ');
export const inlineName = (i) => 'inline:' + i;
export const firstHit = (W, ids) => W.find((w) => ids.includes(w.id));
export function renameRows(O, W, M) {
  const rows = O.flatMap((o) => {
    const w = firstHit(W, o.ids);
    return w ? [{ url: w.name, src: o.src }] : [];
  });
  return [...rows, ...M];
}

// data: URI scanner: identity bytes:<sha256> of a base64 payload, svgtext:<sha256> of a percent-decoded svg text
// payload (the form svgToDataURL of Vite 8.3.4 writes: no white space, no double quote, % < > # escaped).
const DATA = /data:([a-z]+\/[a-z0-9.+-]+)(?:;charset=[\w-]+)?(;base64)?,([^"`\s\\]*)/gi;
export function dataIdents(text) {
  const out = [];
  for (const m of text.matchAll(DATA)) {
    if (m[2]) {
      const b64 = /^[A-Za-z0-9+/]*={0,2}/.exec(m[3])[0];
      out.push('bytes:' + createHash('sha256').update(Buffer.from(b64, 'base64')).digest('hex'));
    } else if (m[1].toLowerCase() === 'image/svg+xml') {
      try {
        out.push('svgtext:' + createHash('sha256').update(decodeURIComponent(m[3])).digest('hex'));
      } catch {}
    }
  }
  return out;
}

// URL scanner: path-like tokens ending in an asset or code extension, resolved against the referring file's
// directory (root-absolute paths as is); query and fragment dropped; external hosts skipped.
const CODE = ['js', 'mjs', 'css'];
const TOKEN = new RegExp(String.raw`[\w@%~:/.+-]*\.(?:${[...exts, ...CODE].sort((a, b) => b.length - a.length).join('|')})(?![\w-])`, 'gi');
export function scanRefs(text, dir) {
  const out = [];
  for (const [tok] of text.matchAll(TOKEN)) {
    let t = tok;
    if (/^[a-z]+:/i.test(t) || t.startsWith('//')) {
      const m = /^https?:\/\/(?:www\.)?fastwork\.(?:co|com)(\/.*)$/i.exec(t);
      if (!m) continue;
      t = m[1];
    }
    let p;
    try {
      p = decodeURIComponent(t.startsWith('/') ? path.posix.normalize(t) : path.posix.join(dir, t));
    } catch {
      continue;
    }
    out.push(p);
  }
  return out;
}

const isFile = (root, u) => {
  const f = path.join(root, u);
  return f.startsWith(root) && existsSync(f) && statSync(f).isFile();
};

// The asset URLs a built page references: index.html and every script or stylesheet reachable from it, and the
// identities of the data: URIs in those files (an HTML file is read with its character references decoded).
export function crawl(root, skip = []) {
  const assets = new Set();
  const inline = new Set();
  const seen = new Set(['/index.html']);
  const queue = ['/index.html'];
  while (queue.length) {
    const u = queue.shift();
    const raw = readFileSync(path.join(root, u), 'utf8');
    const text = u.endsWith('.html') ? decode(raw) : raw;
    for (const i of dataIdents(text)) inline.add(i);
    const dir = u.endsWith('.html') ? '/' : path.posix.dirname(u);
    for (const r of scanRefs(text, dir)) {
      if (skip.some((s) => r.startsWith(s)) || !isFile(root, r)) continue;
      if (CODE.includes(ext(r))) {
        if (!seen.has(r)) seen.add(r), queue.push(r);
      } else if (isAsset(r)) assets.add(r);
    }
  }
  return { assets: [...assets].sort(), code: [...seen].sort(), inline: [...inline] };
}

const sha = (b) => createHash('sha256').update(b).digest('hex');

// The identities of one original asset (Fw.Site.Assets): bytes:<sha256>, and for an svg also svgtext:<sha256> of
// inlineNorm of its text.
export function origIdents(file) {
  const b = readFileSync(file);
  const ids = ['bytes:' + sha(b)];
  if (ext(file) === 'svg') ids.push('svgtext:' + sha(inlineNorm(b.toString('utf8'))));
  return ids;
}

// The inputs of Fw.Site.Assets.renameRows read from disk: O the original assets with their identities, W the rewrite's
// referenced URLs (identity bytes:<sha256> of the file) then its inlined data: identities; returns the rename map F.
export function renameFiles(manifest, snapshot, origAssets, dist, rw) {
  const O = origAssets.map((u) => ({ src: 'snapshot/site' + u, ids: origIdents(path.join(snapshot, u)) }));
  const W = [
    ...rw.assets.map((u) => ({ name: u, id: 'bytes:' + sha(readFileSync(path.join(dist, u))) })),
    ...rw.inline.map((i) => ({ name: inlineName(i), id: i })),
  ];
  return renameRows(O, W, manifest.files);
}

export function digest({ snapshot, dist }) {
  const manifest = JSON.parse(readFileSync(path.join(repo, 'apps/site/assets.manifest.json'), 'utf8'));
  const orig = crawl(snapshot, crawlSkip);
  const rw = crawl(dist);
  const F = renameFiles(manifest, snapshot, orig.assets, dist, rw);
  const R = [...rw.assets, ...rw.inline.map(inlineName)];
  const oTree = parseHtml(readFileSync(path.join(snapshot, 'index.html'), 'utf8'));
  const rTree = parseHtml(readFileSync(path.join(dist, 'index.html'), 'utf8'));
  const oOwner = owners('orig');
  const rOwner = owners('rewrite');
  const ownerOfUrl = new Map();
  for (const e of elements(oTree))
    for (const v of Object.values(e.attrs))
      for (const r of scanRefs(v, '/')) if (!ownerOfUrl.has(r)) ownerOfUrl.set(r, oOwner(e));

  const verdicts = orig.assets.map((u) => ({ url: u, served: rename(F, u), verdict: verdict(F, R, exclusions, u), owner: ownerOfUrl.get(u) ?? sections.page }));
  const assets = {
    orig: orig.assets.length,
    rewrite: rw.assets.length,
    inline: rw.inline.length,
    inlined: verdicts.filter((v) => v.verdict === 'present' && v.served.startsWith('inline:')),
    missing: verdicts.filter((v) => v.verdict === 'missing'),
    excluded: verdicts.filter((v) => v.verdict === 'excluded'),
    pass: assetsMissing(F, R, exclusions, orig.assets).length === 0,
  };

  const oSvg = svgUnits(oTree, oOwner);
  const rSvg = svgUnits(rTree, rOwner);
  const v = svgCheck(exclusions, oSvg.map((s) => s.key), rSvg.map((s) => s.key));
  const pick = (units, keys) => {
    const left = [...keys];
    return units.filter((s) => {
      const i = left.indexOf(s.key);
      return i >= 0 && left.splice(i, 1);
    });
  };
  const svg = { orig: oSvg.length, rewrite: rSvg.length, missing: pick(oSvg, v.missing), extra: pick(rSvg, v.extra), pass: v.pass };
  return { assets, svg };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const arg = (n, d) => {
    const i = process.argv.indexOf(n);
    return i < 0 ? d : process.argv[i + 1];
  };
  const snapshot = path.resolve(arg('--snapshot', path.join(repo, 'snapshot/site')));
  const dist = path.resolve(arg('--dist', path.join(repo, 'apps/site/dist/aot')));
  const report = digest({ snapshot, dist });
  const text = JSON.stringify(report, null, 1) + '\n';
  const out = arg('--out');
  if (out) writeFileSync(out, text);
  console.log(`assets: ${report.assets.missing.length} missing of ${report.assets.orig}; svg: ${report.svg.missing.length} missing, ${report.svg.extra.length} extra of ${report.svg.orig}/${report.svg.rewrite}`);
  process.exitCode = report.assets.pass && report.svg.pass ? 0 : 1;
}
