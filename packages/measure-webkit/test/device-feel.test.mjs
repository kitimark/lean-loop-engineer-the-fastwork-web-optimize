import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FEEL, PRESET_FLAGS, presetFlagsOf, ARMS, SAME_ARMS, LOOK_ARMS, armHashes, cellOf, cmdNext, cmdRate, cmdStatus, freshState, orderOf, planOf, reduceArm, reduceLook, summaryText, validScore, verdicts, visitText } from '../src/device-feel.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/feel.jsonl', import.meta.url), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const of = (k) => GOLDEN.filter((l) => l.kind === k);
const scores = [1, 2, 3, 4, 5];

test('the golden holds the arms the task names', () => {
  assert.deepEqual(SAME_ARMS.map((a) => a.id), ['base', 'v2-proved', 'v2-proved-2flag']);
  assert.deepEqual(LOOK_ARMS.map((a) => a.id), ['nav:earn-logical', 'platform.glint:compositor', 'morph.end.nobounce', 'morph.stage']);
  assert.deepEqual(LOOK_ARMS.map((a) => a.flags.join('+')), ['nav:earn-logical', 'platform.glint:compositor', 'morph.end.nobounce:on', 'morph.stage:on']);
  assert.ok(LOOK_ARMS.every((a) => a.text.length > 0 && a.text.length < 120 && !a.text.includes('\n')));
  assert.deepEqual(SAME_ARMS[0].flags, []);
  assert.equal(FEEL.nSame, SAME_ARMS.length);
});

test('the v2-proved arm is the generated preset, the 2flag arm is the preset without platform (the 2026-10-29 arm A)', () => {
  const preset = presetFlagsOf(JSON.parse(readFileSync(new URL('../../contracts/golden/preset/v2-proved.json', import.meta.url), 'utf8')));
  assert.deepEqual(PRESET_FLAGS, preset);
  assert.deepEqual(SAME_ARMS[1].flags, preset);
  assert.deepEqual(SAME_ARMS[2].flags, preset.filter((f) => !f.startsWith('platform:')));
  assert.deepEqual(SAME_ARMS[2].flags, ['engine.scroll:unthrottle', 'hero.exit:threaded']);
  assert.deepEqual(preset.filter((f) => !SAME_ARMS[2].flags.includes(f)), ['platform:faded-pause']);
  assert.equal(of('preset')[0].source, 'packages/contracts/golden/preset/v2-proved.json');
  assert.deepEqual(of('preset')[0].flags, preset);
  assert.equal(new Set(ARMS.map((a) => a.id)).size, ARMS.length);
});

test('order, labels and letters follow the Lean golden for every seed', () => {
  for (const o of of('order')) {
    const got = orderOf(o.seed);
    assert.deepEqual(got.order, o.order);
    assert.equal(got.letters, o.letters);
    assert.equal(orderOf(o.seed + 3).letters, o.letters);
  }
});

test('every same-look arm is shown twice, never twice in a row, once per round; each visit has its own letter', () => {
  for (let seed = 0; seed < 7; seed++) {
    const same = planOf(seed).filter((v) => v.group === 'same');
    assert.equal(same.length, FEEL.repeats * FEEL.nSame);
    for (let a = 0; a < FEEL.nSame; a++) {
      assert.deepEqual(same.filter((v) => v.arm === a).map((v) => v.round), [0, 1]);
      assert.equal(new Set(same.filter((v) => v.arm === a).map((v) => v.label)).size, 2);
    }
    same.slice(1).forEach((v, i) => assert.notEqual(v.arm, same[i].arm));
    assert.equal(same[0].label, 'A');
    assert.deepEqual(same.map((v) => v.label), [...'ABCDEF']);
    const look = planOf(seed).filter((v) => v.group === 'look');
    assert.deepEqual(look.map((v) => v.label), ['L1', 'L2', 'L3', 'L4']);
  }
});

test('cells, reduceArm and reduceLook equal the Lean grids', () => {
  const cells = of('cells')[0].grid;
  scores.forEach((x, i) => scores.forEach((b, j) => assert.equal(cellOf(x, b), cells[i][j])));
  const red = of('reduce')[0].codes;
  let k = 0;
  for (const x1 of scores) for (const x2 of scores) for (const b1 of scores) for (const b2 of scores) assert.equal(reduceArm([x1, x2], [b1, b2]), red[k++]);
  assert.equal(k, red.length);
  const look = of('reduceLook')[0].codes;
  k = 0;
  for (const x of scores) for (const b1 of scores) for (const b2 of scores) assert.equal(reduceLook([x], [b1, b2]), look[k++]);
  assert.equal(k, look.length);
  assert.equal(reduceArm([3], [3, 3]), 'unrated');
  assert.equal(reduceLook([], [3, 3]), 'unrated');
});

test('session verdicts equal the Lean golden', () => {
  for (const s of of('session')) {
    const ratings = [...s.ratings, ...s.look];
    const v = verdicts(s.seed, ratings);
    assert.deepEqual(v.same.map((a) => a.verdict), s.same);
    assert.deepEqual(v.look.map((a) => a.verdict), s.lookVerdicts);
  }
});

test('a rating is a whole number 1 to 5', () => {
  assert.deepEqual([0, 1, 5, 6, 2.5, NaN].map(validScore), [false, true, true, false, false, false]);
});

const deps = (over = {}) => ({ gate: async () => ({ ok: true, reading: { state: 'Serious' } }), open: async () => ({ ok: true, info: { docH: 100, maxY: 50 } }), now: () => 0, ...over });

test('next opens arms in the plan order, one rating at a time, and prints no flag or arm id', async () => {
  const st = freshState({ seed: 1, pin: 'Serious', site: 'x' });
  const plan = planOf(1);
  const seen = [];
  for (let i = 0; i < plan.length; i++) {
    const n = await cmdNext(st, deps({ open: async (v) => { seen.push(v.id); return { ok: true, info: {} }; } }));
    assert.ok(n.ok);
    for (const a of ARMS) assert.ok(!n.text.includes(a.id) && a.flags.every((f) => !n.text.includes(f)), n.text);
    assert.ok(!/engine\.|hero\.|platform\.|morph\.|glint|v2-proved/.test(n.text), n.text);
    assert.ok(n.text.includes(FEEL.doText));
    assert.equal(n.label, plan[i].label);
    const again = await cmdNext(st, deps());
    assert.equal(again.ok, false);
    assert.match(again.text, /rate the open arm first/);
    assert.ok(cmdRate(st, plan[i].label.toLowerCase(), '4').ok);
  }
  assert.deepEqual(seen, plan.map((v) => v.id));
  assert.equal((await cmdNext(st, deps())).ok, false);
  assert.ok(summaryText(st).includes('base: same'));
});

test('next refuses when the pin gate refuses or the page does not open, and does not advance', async () => {
  const st = freshState({ seed: 0, pin: 'Serious', site: 'x' });
  const g = await cmdNext(st, deps({ gate: async () => ({ ok: false, why: 'the phone is locked' }) }));
  assert.deepEqual([g.ok, st.opened], [false, 0]);
  assert.match(g.text, /locked/);
  const o = await cmdNext(st, deps({ open: async () => ({ ok: false, error: 'config mismatch' }) }));
  assert.deepEqual([o.ok, st.opened], [false, 0]);
  assert.ok((await cmdNext(st, deps())).ok);
  assert.equal(st.opened, 1);
});

test('rate checks the open label and the range', async () => {
  const st = freshState({ seed: 0, pin: 'Serious', site: 'x' });
  assert.equal(cmdRate(st, 'A', '3').ok, false);
  await cmdNext(st, deps());
  assert.match(cmdRate(st, 'B', '3').text, /open arm is A/);
  assert.equal(cmdRate(st, 'A', '9').ok, false);
  assert.equal(cmdRate(st, 'A', 'x').ok, false);
  assert.ok(cmdRate(st, 'A', '2').ok);
  assert.ok(cmdRate(st, 'A', '5').ok);
  assert.equal(st.ratings[0], 5);
  assert.match(cmdStatus(st).text, /A=5/);
  assert.ok(!cmdStatus(st).text.includes('base'));
  assert.match(cmdStatus(st, { reveal: true }).text, /A:base/);
});

test('armHashes names an arm the build lacks', () => {
  const bySearch = {}, byHash = {};
  ARMS.slice(1).forEach((a, i) => { bySearch[a.flags.length ? `?fw=${[...a.flags].sort().join(',')}` : ''] = `h${i}`; byHash[`h${i}`] = `c/h${i}.html`; });
  const r = armHashes({ bySearch, byHash });
  assert.deepEqual(r.missing.map((m) => m.id), ['base']);
  assert.equal(r.have.length, ARMS.length - 1);
});

test('visitText of a look change names the change, not the flags', () => {
  const st = freshState({ seed: 0, pin: 'Serious', site: 'x' });
  const v = planOf(0).find((x) => x.label === 'L2');
  assert.ok(visitText(st, v).startsWith(`L2 (visit 8 of 10), a look change: ${LOOK_ARMS[1].text}`));
  assert.ok(!visitText(st, v).includes('platform.glint'));
});
