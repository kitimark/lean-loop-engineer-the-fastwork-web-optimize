// The glue of the drawn-size arm (armv2.mjs, armdecide.mjs): grouping readings into files, parts, probe lists, and the table of
// decisions. The decisions themselves are Lean's (images-armplan.test.mjs checks the twin against the goldens).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BEGIN, END, cellsOf, checkComplete, decide, splice, tablesMd } from '../src/images/armdecide.mjs';
import { copyArgs, partSaving, partsOf, planProbe, probeIds, whyFile } from '../src/images/armv2.mjs';
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

test('copyArgs: Lanczos to exactly w x h, written as 32-bit PNG (lossless)', () => {
  assert.deepEqual(copyArgs('a.jpg', 'b.jpg', 60, 40), ['a.jpg', '-filter', 'Lanczos', '-resize', '60x40!', 'PNG32:b.jpg']);
});

const row = (o) => ({ probe: 'p', width: 400, dpr: 3, part: 'hero', policy: 'exact', base: { v: 'pass', ppm: 0 }, drawn: { v: 'pass', ppm: 10 }, files: 2, saving: 4096, ...o });
const file = (o) => ({ probe: 'p', url: '/a.jpg', why: 'ok', parts: ['hero', 'hero.orbit'], exact: [60, 60], fit: [60, 60], ...o });
const run = (engine, rows, tag = 'r1-s1', files = [file({})]) => ({ schema: 'fw.images.arm2/1', engine, tag, browser: 'x', probes: ['p'], policies: ['exact', 'fit'], parts: ['hero', 'hero.orbit', 'hero.deck', 'hero.exit'], rows, files });

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
  const md = tablesMd(res, { runId: 42, sha: 'abcdef0123', matrix: [{ width: 400, dpr: 3 }, { width: 400, dpr: 1 }, { width: 401, dpr: 1 }] });
  assert.match(md, /Probed width x DPR pairs: 1 of 3[^]*not probed: DPR 1: 400 401; DPR 2: -; DPR 3: -/);
  assert.match(md, /Decision per part, policy exact \(run 42, commit abcdef01\)/);
  assert.match(md, /\| exact \| chromium \| hero\.orbit \| 1 \| 0 \| 1 \|/);
  assert.match(md, /Cells where the copy fails and the baseline passes[^]*\| exact \| chromium \| p \| 400@3 \| hero\.orbit \| 1\/1 \|/);
  assert.match(md, /Decoded saving per part and probe[^]*\| exact \| chromium \| hero \| admissible \| 2 \| 4\.0 \| 4\.0 \| 4\.0 \| 1 \|/);
});

test('decide: an error row is an error cell for every part, and a part with an error cell is undecided', () => {
  const res = [run('chromium', [row({}), row({ part: 'hero.orbit' })], 'r1-s1'), run('chromium', [{ probe: 'p', width: 400, dpr: 3, error: 'audit failed' }], 'r2-s1')];
  const cells = cellsOf(res).filter((c) => c.rep === 'r2');
  assert.equal(cells.length, 8);
  assert.ok(cells.every((c) => c.error && c.base === 'error' && c.drawn === 'error'));
  const d = (part) => decide(res).find((x) => x.policy === 'exact' && x.engine === 'chromium' && x.part === part).decision;
  assert.equal(d('hero'), 'undecided');
  assert.equal(d('hero.deck'), 'undecided');
  assert.notEqual(d('hero'), 'admissible');
});

test('decide: a copy the reps do not agree on makes its cell not comparable (a copy could be drawn under a transform in one rep)', () => {
  const res = [
    run('chromium', [row({}), row({ part: 'hero.orbit', drawn: { v: 'fail', ppm: 9000 } })], 'r1-s1', [file({})]),
    run('chromium', [row({}), row({ part: 'hero.orbit' })], 'r2-s1', [file({ exact: null, why: 'scaled' })]),
  ];
  const cells = cellsOf(res).filter((c) => c.policy === 'exact' && c.part === 'hero.orbit');
  assert.deepEqual(cells.map((c) => [c.rep, c.disputed]), [['r1', true], ['r2', false]]);
  const d = decide(res).find((x) => x.policy === 'exact' && x.engine === 'chromium' && x.part === 'hero.orbit');
  assert.equal(d.decision, 'undecided');
  assert.equal(d.disputed, 1);
  assert.doesNotMatch(tablesMd(res), /Cells where the copy fails and the baseline passes[^#]*hero\.orbit/);
  assert.match(tablesMd(res), /\| exact \| chromium \| hero\.orbit \| 2 \| 1 \| 0 \| 0 \| 0 \| 0 \| 0 \| 0 \| 0 \| 0 \| 1 \| 0 \|/);
  const agree = [res[0], run('chromium', [row({}), row({ part: 'hero.orbit' })], 'r2-s1', [file({})])];
  assert.equal(decide(agree).find((x) => x.policy === 'exact' && x.engine === 'chromium' && x.part === 'hero.orbit').decision, 'lookChange');
});

test('checkComplete: a missing, truncated, shifted or partial result file is a problem', () => {
  const full = (engine, tag) => run(engine, ['exact', 'fit'].flatMap((policy) => ['hero', 'hero.orbit', 'hero.deck', 'hero.exit'].map((part) => row({ policy, part }))), tag);
  const want = { engines: ['chromium'], reps: ['r1', 'r2'], shards: 1, probesOf: () => ['p'] };
  const ok = [full('chromium', 'r1-s1'), full('chromium', 'r2-s1')];
  assert.deepEqual(checkComplete(ok, want), []);
  assert.match(checkComplete([ok[0]], want)[0], /chromium r2-s1: 0 result files/);
  assert.match(checkComplete([ok[0], { ...ok[1], truncated: true }], want).join(), /truncated/);
  assert.match(checkComplete([ok[0], { ...ok[1], probes: ['q'] }], want).join(), /are not the shard's/);
  assert.match(checkComplete([ok[0], { ...ok[1], rows: ok[1].rows.slice(1) }], want).join(), /0 rows for exact hero/);
  assert.match(checkComplete([...ok, full('playwright-webkit', 'r1-s1')], want).join(), /not an expected result file/);
  assert.deepEqual(checkComplete([ok[0], run('chromium', [{ probe: 'p', error: 'x' }], 'r2-s1')], want), []);
});

test('splice replaces the generated block of the note and nothing else', () => {
  const note = `top\n${BEGIN}\n\nold\n\n${END}\nbottom\n`;
  assert.equal(splice(note, 'new\n'), `top\n${BEGIN}\n\nnew\n\n${END}\nbottom\n`);
  assert.throws(() => splice('no markers', 'x'));
});
