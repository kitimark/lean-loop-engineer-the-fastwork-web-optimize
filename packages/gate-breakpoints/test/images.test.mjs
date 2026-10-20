// The image audit (src/images): pure helpers, the reducer, the arm table rules and the two byte copies of arm.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { composeRewrite, drawnFile } from '../src/images/arm.mjs';
import { copyPath, fitDims, LADDER, needW, requirements, rowsFor, rungFor } from '../src/images/arm-build.mjs';
import { stopsFor, mergeStops } from '../src/images/audit.mjs';
import { bgDrawn, fitDrawn, splitTop } from '../src/images/inpage.mjs';
import { aggregate, effectClasses, regionOf, rowsOfCell, sniff, totals } from '../src/images/reduce.mjs';
import { canon, stability } from '../src/images/cli.mjs';
import { sideBySide } from '../src/images/pages.mjs';

test('splitTop keeps commas inside parentheses', () => {
  assert.deepEqual(splitTop('url(a,b), linear-gradient(red, blue), none'), ['url(a,b)', 'linear-gradient(red, blue)', 'none']);
});

test('bgDrawn and fitDrawn: cover, contain, lengths, auto', () => {
  assert.deepEqual(bgDrawn('cover', 1000, 500, 100, 100), [200, 100]);
  assert.deepEqual(bgDrawn('contain', 1000, 500, 100, 100), [100, 50]);
  assert.deepEqual(bgDrawn('128px 128px', 1000, 500, 10, 10), [128, 128]);
  assert.deepEqual(bgDrawn('50% auto', 1000, 500, 200, 10), [100, 50]);
  assert.deepEqual(bgDrawn('auto', 1000, 500, 200, 10), [1000, 500]);
  assert.deepEqual(fitDrawn('cover', 100, 200, 50, 50), [50, 100]);
  assert.deepEqual(fitDrawn('fill', 100, 200, 50, 40), [50, 40]);
  assert.deepEqual(fitDrawn('scale-down', 10, 10, 50, 50), [10, 10]);
});

test('sniff reads the magic bytes', () => {
  assert.equal(sniff(Buffer.from([0xff, 0xd8, 0xff, 0xe0])), 'jpeg');
  assert.equal(sniff(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), 'png');
  assert.equal(sniff(Buffer.from('<svg xmlns="x"/>')), 'svg');
  assert.equal(sniff(Buffer.from('RIFF\0\0\0\0WEBPVP8 ')), 'webp');
  assert.equal(sniff(Buffer.from('\0\0\0\x1cftypavif')), 'avif');
});

test('regionOf: the innermost named ancestor wins (the morph panel mounts inside the hero tree)', () => {
  assert.equal(regionOf({ fw: ['morph-panel', 'hero-exit', 'page-root'] }), 'morph');
  assert.equal(regionOf({ fw: ['hero-orbit', 'hero-exit'] }), 'hero');
  assert.equal(regionOf({ fw: [], cls: ['deck-module_x', 'people-module_y'] }), 'people');
  assert.equal(regionOf({ fw: ['platform-row'] }), 'platform');
  assert.equal(regionOf({}), 'other');
});

test('effectClasses sorts the effects of the ancestors and keeps the nearest distance', () => {
  const c = effectClasses({
    effects: [
      { at: 'a', up: 5, e: 'filter=blur(3px)' }, { at: 'b', up: 2, e: 'filter=blur(1px)' }, { at: 'c', up: 1, e: 'opacity=0.5' },
      { at: 'c', up: 1, e: 'animation(opacity+transform):running' }, { at: 'd', up: 0, e: 'backdrop-filter=blur(8px)' },
    ],
  });
  assert.deepEqual(c, ['backdrop-filter@d', 'filter@b^2', 'opacity-anim@c^1', 'opacity<1@c^1', 'transform-anim@c^1']);
});

const cell = (items) => ({ dpr: 2, items });
const item = (over) => ({ kind: 'img', id: 'e1', url: '/selling/a.jpg', nat: [1000, 500], box: [100, 50], img: [100, 50], none: false, fw: ['hero-orbit'], effects: [], visMin: 1, visMax: 1, ...over });

test('rowsOfCell: device pixels, waste ratio, decoded bytes; svg has no decoded cost', () => {
  const [r] = rowsOfCell(cell([item({})]), () => ({ bytes: 1000, format: 'jpeg' }));
  assert.equal(r.devW, 200);
  assert.equal(r.devH, 100);
  assert.equal(r.drawnPx, 20000);
  assert.equal(r.decodedBytes, 2_000_000);
  assert.equal(r.neededBytes, 80_000);
  assert.equal(r.waste, 25);
  assert.equal(r.wastedBytes, (500_000 - 20_000) * 4);
  const [s] = rowsOfCell(cell([item({ url: '/x.svg' })]), () => ({ bytes: 10, format: 'svg' }));
  assert.equal(s.decodedBytes, 0);
  assert.equal(s.waste, null);
  const [n] = rowsOfCell(cell([item({ none: true })]), () => ({ bytes: 1, format: 'jpeg' }));
  assert.equal(n.drawnPx, 0);
  assert.equal(n.wastedBytes, 0);
});

test('aggregate counts a file once and totals add up', () => {
  const rows = rowsOfCell(cell([item({ id: 'a' }), item({ id: 'b', img: [200, 100] }), item({ id: 'c', url: '/selling/b.jpg', nat: [100, 100], img: [100, 100], box: [100, 100] })]), () => ({ bytes: 10, format: 'jpeg' }));
  const ag = aggregate(rows);
  assert.equal(ag.length, 2);
  const a = ag.find((x) => x.url === '/selling/a.jpg');
  assert.equal(a.count, 2);
  assert.equal(a.drawnPx, 400 * 200);
  const t = totals(ag);
  assert.equal(t.files, 2);
  assert.equal(t.decoded, 1000 * 500 * 4 + 100 * 100 * 4);
});

test('stopsFor: quarter viewports through two viewports, half after, the bottom last', () => {
  const s = stopsFor(5000, 800);
  assert.deepEqual(s.slice(0, 4), [0, 200, 400, 600]);
  assert.equal(s[s.length - 1], 4200);
  assert.ok(s.includes(1600) && s.includes(2000));
  assert.equal(new Set(s).size, s.length);
  assert.deepEqual(stopsFor(500, 800), [0]);
});

test('mergeStops: an effect set one frame late still shows, in-view stops are counted', () => {
  const base = { kind: 'img', id: 'e1', url: '/a.jpg', complete: true, nat: [10, 10], box: [5, 5], img: [5, 5], vis: 1, none: false, top: 0, fw: ['hero-orbit'], cls: [] };
  const m = mergeStops([
    { items: [{ ...base, inView: true, effects: [{ at: 'c', up: 1, e: 'transform' }] }] },
    { items: [{ ...base, inView: false, effects: [{ at: 'c', up: 1, e: 'filter=blur(2px)' }] }] },
    { items: [{ ...base, inView: true, effects: [{ at: 'c', up: 1, e: 'filter=blur(2px)' }] }] },
  ]);
  assert.equal(m.length, 1);
  assert.equal(m[0].stopsInView, 2);
  assert.equal(m[0].everInView, true);
  assert.deepEqual(m[0].effects.map((e) => e.e).sort(), ['filter=blur(2px)', 'transform']);
});

test('canon hashes which images sit where, not drawn sizes or effect kinds; stability counts the rest', () => {
  const mk = (w, kind, ids) => ({ cells: { 'w1@2': { docHeight: 10, items: ids.map((i) => ({ kind: 'img', url: `/${i}.jpg`, nat: [4, 4], box: [w, w], img: [w, w], none: false, fw: ['hero-orbit'], effects: [{ at: 'c', up: 0, e: `animation(${kind}):running` }] })) } } });
  assert.equal(canon(mk(10, 'opacity', ['a', 'b'])), canon(mk(11, 'transform', ['b', 'a'])));
  assert.notEqual(canon(mk(10, 'opacity', ['a', 'b'])), canon(mk(10, 'opacity', ['a'])));
  const s = stability([mk(10, 'opacity', ['a', 'b']), mk(11, 'transform', ['a', 'b']), mk(14, 'opacity', ['a'])]);
  assert.deepEqual({ keys: s.keys, absent: s.absentInSomeRep, over: s.sizeOver1px, kinds: s.kindSetDiffers }, { keys: 2, absent: 1, over: 1, kinds: 1 });
});

test('rungFor: smallest ladder rung that holds the need; the natural size when it would be nearly as large', () => {
  assert.ok(LADDER.every((r, i) => i === 0 || r > LADDER[i - 1]) && LADDER.every((r) => r % 8 === 0));
  assert.equal(rungFor(100, 1200), LADDER.find((r) => r >= 100));
  assert.equal(rungFor(1100, 1200), Infinity);
  assert.equal(rungFor(10_000, 20_000), Infinity);
  assert.equal(needW(100, 100, 100, 50, 1.1, 2), Math.ceil(200 * 1.1 * 2));
});

test('rowsFor: rows follow the width, a probe is sized with the next one unless they are 1 px apart', () => {
  const widths = [400, 401, 800];
  const mkcells = (a, b, c) => new Map([[400, { cssW: a, cssH: a, scale: 1 }], [401, { cssW: b, cssH: b, scale: 1 }], [800, { cssW: c, cssH: c, scale: 1 }]]);
  const req = { nat: [2000, 2000], cells: mkcells(100, 100, 400) };
  const rows = rowsFor(req, widths, 2);
  assert.equal(rows[0].from, 0);
  // 400 and 401 are 1 px apart: 400 is sized by itself, 401 by the larger of itself and 800
  assert.equal(rows[0].w, rungFor(200, 2000));
  assert.equal(rows[1].from, 401);
  assert.equal(rows[1].w, rungFor(800, 2000));
  assert.equal(rows.length, 2);
  const keep = rowsFor({ nat: [300, 300], cells: mkcells(100, 100, 100) }, widths, 3);
  assert.deepEqual(keep, [{ from: 0, w: null }]);
});

test('rowsFor: a width no audit saw the image at takes the larger need of the widths around it', () => {
  const widths = [400, 500, 600, 700];
  const cells = new Map([[400, { cssW: 100, cssH: 100, scale: 1 }], [700, { cssW: 300, cssH: 300, scale: 1 }]]);
  const rows = rowsFor({ nat: [4000, 4000], cells }, widths, 2);
  assert.deepEqual(rows.map((r) => r.w), [rungFor(600, 4000)]);
  assert.equal(rows.length, 1);
});

test('requirements: the largest reading over several audit files', () => {
  const item = (w) => ({ kind: 'img', url: '/a.jpg', nat: [100, 100], box: [w, w], img: [w, w], none: false, fw: ['hero-orbit'], fit: 'cover', vis: 1, effects: [] });
  const f = (w) => ({ cells: { 'w400@2': { width: 400, dpr: 2, items: [item(w)] } } });
  const r = requirements([f(10), f(30), f(20)]).get('/a.jpg');
  assert.equal(r.cells.get(400).cssW, 30);
  assert.equal(r.maxCssW, 30);
});

test('fitDims: a rung keeps the aspect ratio within a fraction of a CSS pixel at the largest drawn size', () => {
  const d = fitDims(1035, 1400, 64, 300, 405);
  assert.ok(d.w >= 64 && d.w <= Math.ceil(64 * 1.15) && d.err < 0.2, JSON.stringify(d));
  const plain = Math.abs(Math.round(64 * 1400 / 1035) / 64 - 1400 / 1035) * 300;
  assert.ok(plain > d.err);
  assert.deepEqual(fitDims(100, 100, 40, 50, 50), { w: 40, h: 40, err: 0 });
  assert.ok(fitDims(70, 100, 64, 10, 10).w <= 70);
});

const manifest = { images: { '/s/a.jpg': { dprs: { 2: [{ from: 0, file: '/images-drawn/s/a-160.jpg' }, { from: 600, file: null }, { from: 900, file: '/images-drawn/s/a-480.jpg' }], 3: [{ from: 0, file: '/images-drawn/s/a-248.jpg' }] } } } };

test('drawnFile: smallest listed DPR at least the asked one, last row whose from is at most the width, null keeps', () => {
  assert.equal(drawnFile(manifest, '/s/a.jpg', 400, 2), '/images-drawn/s/a-160.jpg');
  assert.equal(drawnFile(manifest, '/s/a.jpg', 400, 1), '/images-drawn/s/a-160.jpg');
  assert.equal(drawnFile(manifest, '/s/a.jpg', 700, 2), null);
  assert.equal(drawnFile(manifest, '/s/a.jpg', 1000, 2), '/images-drawn/s/a-480.jpg');
  assert.equal(drawnFile(manifest, '/s/a.jpg', 1000, 3), '/images-drawn/s/a-248.jpg');
  assert.equal(drawnFile(manifest, '/s/a.jpg', 1000, 4), null);
  assert.equal(drawnFile(manifest, '/s/other.jpg', 400, 2), null);
});

test('composeRewrite puts the arm on top of a base rewrite', () => {
  const base = (p) => (p === '/' ? '/index-x.html' : null);
  const f = composeRewrite(base, manifest, { width: 1000, dpr: 2 });
  assert.equal(f('/s/a.jpg'), '/images-drawn/s/a-480.jpg');
  assert.equal(f('/'), '/index-x.html');
  assert.equal(f('/x.css'), null);
  assert.equal(composeRewrite(null, null, { width: 1, dpr: 1 })('/s/a.jpg'), null);
});

test('copyPath', () => {
  assert.equal(copyPath('/selling/hero/p.JPG', 216), '/images-drawn/selling/hero/p-216.jpg');
  assert.throws(() => copyPath('/noext', 8));
});

test('sideBySide pairs baseline and arm cells and flags a changed verdict', () => {
  const cellsOf = (list) => new Map(list.map(([id, part, verdict, ppm]) => [`${id}|${part}`, { status: 'compared', verdict, ratioPpm: ppm, stats: { changed: 1, total: 1e6, maxDelta: 3 } }]));
  const rows = sideBySide({ by: cellsOf([['p', 'hero', 'pass', 100], ['p', 'x', 'pass', 5]]) }, { by: cellsOf([['p', 'hero', 'fail', 3000], ['p', 'x', 'pass', 9]]) }, ['p'], ['hero', 'x', 'none']);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].sameVerdict, false);
  assert.equal(rows[0].dPpm, 2900);
  assert.equal(rows[1].sameVerdict, true);
});

test('the two copies of arm.mjs are byte-equal', () => {
  const a = readFileSync(new URL('../src/images/arm.mjs', import.meta.url));
  const b = readFileSync(new URL('../../measure-webkit/src/images/arm.mjs', import.meta.url));
  assert.ok(a.equals(b));
});

test('tablesMd: one row per file, ranked by the larger wasted decoded bytes of the headline cells, waste ratio per cell, effects of the headline cells only', async () => {
  const { tablesMd, rowOf, gather } = await import('../src/images/table.mjs');
  const row = (url, nat, dev, effects, over = {}) => ({ region: 'hero', kind: 'img', prop: null, url, none: false, format: 'jpeg', bytes: 2048, natW: nat[0], natH: nat[1], natPx: nat[0] * nat[1], devW: dev[0], devH: dev[1], drawnPx: dev[0] * dev[1], decodedBytes: nat[0] * nat[1] * 4, neededBytes: dev[0] * dev[1] * 4, wastedBytes: Math.max(0, nat[0] * nat[1] - dev[0] * dev[1]) * 4, cssW: dev[0] / 2, cssH: dev[1] / 2, fit: 'cover', effects, fw: 'hero-orbit', ...over });
  const file = (cells) => ({ rows: cells });
  const f1 = file({
    'w1512@2': [row('/selling/a.jpg', [1000, 1000], [100, 100], ['opacity<1@x']), row('/selling/b.jpg', [200, 200], [100, 100], [])],
    'w1512@1': [row('/selling/a.jpg', [1000, 1000], [50, 50], ['filter@y']), row('/selling/b.jpg', [200, 200], [50, 50], [])],
  });
  const g = gather([f1]);
  const a = rowOf(g.get('hero').get('/selling/a.jpg|img'));
  assert.equal(a.waste['w1512@2'], 100);
  assert.equal(a.waste['w1512@1'], 400);
  assert.equal(a.waste['w430@3'], null);
  assert.equal(a.effects, 'O', 'the filter was seen only at 1512@1, which is not a headline effects cell');
  assert.equal(a.lo.cell, 'w1512@2');
  assert.equal(a.hi.cell, 'w1512@1');
  const md = tablesMd([f1]);
  assert.ok(md.indexOf('a.jpg') < md.indexOf('b.jpg'), 'a wastes more than b');
  assert.match(md, /\*\*hero.*2 files/);
});
