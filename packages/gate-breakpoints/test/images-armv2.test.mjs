// The glue of the drawn-size arm (armv2.mjs, armdecide.mjs): grouping readings into files, parts, probe lists, and the table of
// decisions. The decisions themselves are Lean's (images-armplan.test.mjs checks the twin against the goldens).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decide, tablesMd } from '../src/images/armdecide.mjs';
import { partSaving, partsOf, planProbe, probeIds, whyFile } from '../src/images/armv2.mjs';
import { imgOf } from '../src/images/armplan.mjs';

const reading = (o) => ({ kind: 'img', url: '/a.jpg', nat: [200, 200], box: [30, 30], img: [30, 30], fit: 'fill', vis: 1, visMin: 1, visMax: 1, rw: 30, rh: 30, fw: ['hero-orbit', 'hero'], ...o });
const srcOf = () => ({ format: 'jpeg', bytes: 5000 });
const anchors = { hero: ['hero'], 'hero.orbit': ['hero-orbit'], 'people.card': ['people-card'] };

test('partsOf: a part holds the items under one of its data-fw anchors', () => {
  assert.deepEqual(partsOf({ fw: ['hero-orbit', 'hero'] }, anchors), ['hero', 'hero.orbit']);
  assert.deepEqual(partsOf({ fw: ['people-card'] }, anchors), ['people.card']);
  assert.deepEqual(partsOf({ fw: [] }, anchors), []);
});

test('planProbe: an avatar gets an exact copy at the device size and a fit copy; a scaled one only the fit copy', () => {
  const plan = planProbe({ items: [reading({}), reading({ url: '/b.jpg', visMax: 1.5, vis: 1 })], dpr: 2, partAnchors: anchors, srcOf });
  const a = plan.find((f) => f.url === '/a.jpg');
  const b = plan.find((f) => f.url === '/b.jpg');
  assert.deepEqual(a.exact, [60, 60]);
  assert.deepEqual(a.fit, [60, 60]);
  assert.equal(a.why, 'ok');
  assert.deepEqual(a.parts, ['hero', 'hero.orbit']);
  assert.equal(b.exact, null);
  assert.equal(b.why, 'scaled');
  assert.deepEqual(b.fit, [90, 90]);
});

test('planProbe: a file drawn twice at different sizes has no exact copy; a size from the natural size has no fit copy', () => {
  const plan = planProbe({ items: [reading({}), reading({ box: [20, 20], img: [20, 20], rw: 20, rh: 20 }), reading({ url: '/c.jpg', fit: 'none' })], dpr: 2, partAnchors: anchors, srcOf });
  const a = plan.find((f) => f.url === '/a.jpg');
  assert.equal(a.exact, null);
  assert.equal(a.why, 'disagree');
  assert.deepEqual(a.fit, [60, 60]);
  const c = plan.find((f) => f.url === '/c.jpg');
  assert.equal(c.exact, null);
  assert.equal(c.fit, null);
});

test('planProbe: files that are not served, not jpeg or png, external or not drawn get no copy', () => {
  const src = (p) => (p === '/gone.jpg' ? null : { format: p === '/w.webp' ? 'webp' : 'png', bytes: 1 });
  const items = [reading({ url: '/gone.jpg' }), reading({ url: '/w.webp' }), reading({ url: 'https://x.test/e.jpg' }), reading({ url: '/n.png', none: true }), reading({ url: 'data:image/png;base64,AA' })];
  const plan = planProbe({ items, dpr: 2, partAnchors: anchors, srcOf: src });
  assert.equal(plan.find((f) => f.url === '/w.webp').why, 'format:webp');
  assert.equal(plan.find((f) => f.url === '/w.webp').exact, null);
  assert.equal(plan.find((f) => f.url === '/gone.jpg').why, 'sourceMissing');
  assert.equal(plan.find((f) => f.url === 'https://x.test/e.jpg').why, 'external');
  assert.ok(!plan.some((f) => f.url === '/n.png' || f.url.startsWith('data:')));
});

test('whyFile follows the Lean order of reasons', () => {
  const at = (o) => imgOf(reading(o));
  assert.equal(whyFile(2, [at({})]), 'ok');
  assert.equal(whyFile(2, [at({}), at({ kind: 'bg' })]), 'notImg');
  assert.equal(whyFile(2, [at({ visMax: 2 }), at({ img: [60, 30], fit: 'cover' })]), 'cropped');
});

test('partSaving sums the decoded saving of the part\'s files that have a copy', () => {
  const plan = planProbe({ items: [reading({}), reading({ url: '/p.jpg', fw: ['people-card'] })], dpr: 2, partAnchors: anchors, srcOf });
  assert.deepEqual(partSaving(plan, 'hero', 'exact'), { files: 1, saving: 4 * (200 * 200 - 60 * 60) });
  assert.deepEqual(partSaving(plan, 'people.card', 'fit'), { files: 1, saving: 4 * (200 * 200 - 60 * 60) });
  assert.deepEqual(partSaving(plan, 'hero.deck', 'exact'), { files: 0, saving: 0 });
});

test('probeIds: the committed list, an explicit list and a shard', () => {
  assert.deepEqual(probeIds({ probes: ['a', 'b', 'c', 'd', 'e'], shard: '2/3' }), ['b', 'e']);
  assert.deepEqual(probeIds({ probes: ['a', 'b'], shard: null }), ['a', 'b']);
  assert.ok(probeIds({}).length > 0);
  assert.throws(() => probeIds({ probes: ['a'], shard: '4/3' }));
});

const row = (o) => ({ probe: 'p', width: 400, dpr: 3, part: 'hero', policy: 'exact', base: { v: 'pass', ppm: 0 }, drawn: { v: 'pass', ppm: 10 }, files: 2, saving: 4096, ...o });
const run = (engine, rows, tag = 'r1') => ({ schema: 'fw.images.arm2/1', engine, tag, browser: 'x', probes: ['p'], rows, files: [{ probe: 'p', why: 'ok' }] });

test('decide: each cell of a part is decided on its own, over reps and engines', () => {
  const res = [
    run('chromium', [row({}), row({ part: 'hero.orbit', drawn: { v: 'fail', ppm: 9000 } }), row({ part: 'hero.deck', files: 0 })]),
    run('playwright-webkit', [row({}), row({ part: 'hero.orbit', base: { v: 'fail' }, drawn: { v: 'fail', ppm: 9000 } }), row({ drawn: { v: 'unsettled', ppm: null }, part: 'hero.exit' })]),
  ];
  const d = (policy, engine, part) => decide(res).find((x) => x.policy === policy && x.engine === engine && x.part === part)?.decision;
  assert.equal(d('exact', 'chromium', 'hero'), 'admissible');
  assert.equal(d('exact', 'chromium', 'hero.orbit'), 'lookChange');
  assert.equal(d('exact', 'playwright-webkit', 'hero.orbit'), 'shippedFails');
  assert.equal(d('exact', 'all', 'hero.orbit'), 'lookChange');
  assert.equal(d('exact', 'chromium', 'hero.deck'), 'noCopy');
  assert.equal(d('exact', 'playwright-webkit', 'hero.exit'), 'undecided');
  assert.equal(d('exact', 'all', 'hero'), 'admissible');
  const md = tablesMd(res);
  assert.match(md, /Decision per part, policy exact/);
  assert.match(md, /\| exact \| chromium \| hero\.orbit \| 1 \| 0 \| 1 \|/);
  assert.match(md, /Cells where the copy fails and the baseline passes[^]*\| exact \| chromium \| p \| 400@3 \| hero\.orbit \| 1\/1 \|/);
  assert.match(md, /Decoded saving per part and probe[^]*\| exact \| chromium \| hero \| admissible \| 2 \| 4\.0 \| 4\.0 \| 4\.0 \| 1 \|/);
});
