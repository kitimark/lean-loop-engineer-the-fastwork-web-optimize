import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { nominal, validAt, countCells, KINDS, PERIODS, SWAP_US, LANE_BUDGET_MIN, busyFrozen, busyWindows, perCaptureTenths, perFrameMilli, unitFits, armOrder, laneUnits, pooled } from '../src/lag/swap.mjs';
import { parseFreeze, FREEZE_DRAW_CSS, FREEZE_CSS, FREEZE_JS, DRAW_READ_JS, freezeApply, freezeProbe, freezeDrawRead, freezeStep } from '../src/lag/freeze.mjs';
import { accentSetup, ACCENT_FLAGS } from '../src/lag/costmode.mjs';
import { accentSession, parseUnit, ESTIMATE_MS } from '../src/lag/accentsession.mjs';
import { accentAnalysis, accentMd, recordsOf, STATES } from '../src/lag/accentreport.mjs';
import { armLabel, pooledSummary, swapMd, windowCells } from '../src/lag/swapreport.mjs';
import { statesOf } from '../src/lag/freezesession.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/measure/wkcost.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every accent-lane golden kind has lines', () => {
  for (const k of ['swapLaneConst', 'swapBusyFrozen', 'swapPooled', 'swapPerFrame', 'swapUnitFits', 'swapLaneUnits']) assert.ok(of(k).length > 0, k);
});

test('lane budget (Lean laneBudgetMin) stays below the step timeout', () => {
  const [c] = of('swapLaneConst');
  assert.equal(LANE_BUDGET_MIN, c.budgetMin);
  assert.ok(c.budgetMin < c.stepMin);
});

test('unfrozen busy samples against frozen samples (Lean busyFrozen), one case per branch', () => {
  const seen = new Set();
  for (const g of of('swapBusyFrozen')) { assert.equal(busyFrozen(g.busy, g.frozen), g.cell, JSON.stringify(g)); seen.add(g.cell); }
  assert.deepEqual([...seen].sort(), ['noBusy', 'noFrozen', 'overlap', 'raised', 'removed']);
});

test('pooled numbers (Lean busyWindows, perCaptureTenths, median2)', () => {
  for (const g of of('swapPooled')) {
    const p = pooled(g.rows, g.captures);
    assert.deepEqual([p.windows, busyWindows(g.rows), p.tenthsPerCapture, p.median2], [g.windows, g.busyWindows, g.tenthsPerCapture, g.median2], JSON.stringify(g));
    assert.equal(perCaptureTenths(g.rows.reduce((a, b) => a + b, 0), g.captures), g.tenthsPerCapture);
  }
});

test('rows per scroll frame in thousandths (Lean perFrameMilli)', () => {
  for (const g of of('swapPerFrame')) assert.equal(perFrameMilli(g.rows, g.frames), g.milli, JSON.stringify(g));
});

test('a unit starts only when it fits the lane budget (Lean unitFits)', () => {
  for (const g of of('swapUnitFits')) assert.equal(unitFits(g.elapsedMs, g.estimateMs), g.fits, JSON.stringify(g));
});

test('units of a job in order, arm order shifted by the VM number (Lean laneUnits)', () => {
  for (const g of of('swapLaneUnits')) {
    assert.deepEqual(laneUnits(g.shift), g.units, `shift ${g.shift}`);
    assert.equal(new Set(g.units).size, 13);
  }
  assert.deepEqual([0, 1, 2, 3].map((s) => armOrder(s)[0]), ['faithful', 'nolayout', 'full', 'faithful']);
  assert.ok(laneUnits(0)[0].startsWith('swap:'), 'a swap capture comes first, so a job that dies early still has swap windows');
});

test('the draw-only freeze is a named option, and the default freeze is unchanged', () => {
  assert.deepEqual(parseFreeze('hero-accent-draw'), { part: 'hero-accent-draw', mode: 'draw' });
  assert.deepEqual(parseFreeze('hero-accent'), { part: 'hero-accent' });
  assert.deepEqual(statesOf(undefined), { free: { on: false }, frozen: { on: true } });
  assert.deepEqual(statesOf('draw'), { free: { on: false, mode: 'draw' }, frozen: { on: true, mode: 'draw' } });
});

test('premise: every rule of the draw-only style sheet is scoped to the hero.accent root and leaves the idle boil running', () => {
  for (const rule of FREEZE_DRAW_CSS.split('\n')) {
    const sel = rule.slice(0, rule.indexOf('{'));
    for (const part of sel.split(',')) assert.ok(part.trim().startsWith('[data-fw="hero-accent"]'), part);
    assert.ok(/!important/.test(rule), rule);
  }
  assert.match(FREEZE_DRAW_CSS, /drawingIn/);
  assert.match(FREEZE_DRAW_CSS, /drawingOut/);
  assert.match(FREEZE_DRAW_CSS, /transition: none/);
  assert.doesNotMatch(FREEZE_DRAW_CSS, /opacity/, 'the idle boil animates opacity and is not touched');
  assert.doesNotMatch(FREEZE_DRAW_CSS, /idle/);
  assert.ok(FREEZE_CSS.includes('opacity'), 'the full freeze still hides the boil frames');
});

function drawPage({ anims = 2 } = {}) {
  const sheets = [], seen = { replaced: null }, listeners = [];
  const target = { closest: (s) => (s === '[data-fw="hero-accent"]' ? {} : null) };
  const sandbox = {
    document: {
      querySelectorAll: () => [{}],
      get adoptedStyleSheets() { return sheets; },
      set adoptedStyleSheets(v) { sheets.splice(0, sheets.length, ...v); },
      getAnimations: () => Array.from({ length: anims }, () => ({ effect: { target } })),
      addEventListener: (type, fn) => listeners.push([type, fn]),
    },
    CSSStyleSheet: class { replaceSync(css) { seen.replaced = css; } },
    requestAnimationFrame: (cb) => setImmediate(() => cb(0)),
    RegExp,
  };
  sandbox.window = sandbox;
  return { sandbox, seen, sheets, fire: (type, e) => listeners.filter(([t]) => t === type).forEach(([, fn]) => fn({ target, ...e })) };
}
const clientOf = (sandbox) => ({ runAsync: async (src) => JSON.parse(JSON.stringify(await vm.runInNewContext(src, sandbox))) });

test('the draw-only freeze adopts its style sheet, keeps the other animations, and counts draw starts', async () => {
  const { sandbox, seen, fire } = drawPage();
  const r = await freezeApply(clientOf(sandbox), 'draw');
  assert.equal(r.mode, 'draw');
  assert.equal(r.on, true);
  assert.equal(seen.replaced, FREEZE_DRAW_CSS);
  assert.equal(r.accentAnims, 2, 'the idle boil is still there: the draw freeze does not demand zero');
  const c = clientOf(sandbox);
  assert.deepEqual(await freezeDrawRead(c, { on: true, mode: 'draw' }), { animations: 0, transitions: 0 });
  fire('animationstart', { animationName: '_strokeIn_x7fa2' });
  fire('animationstart', { animationName: '_idle0_x7fa2' });
  fire('animationstart', { animationName: 'accent-module__clipOut___3kd9' });
  fire('animationstart', { animationName: 'clipInset' });
  fire('transitionrun', { propertyName: 'width' });
  fire('transitionrun', { propertyName: 'opacity' });
  assert.deepEqual(await freezeDrawRead(c, { on: true, mode: 'draw' }), { animations: 2, transitions: 1 });
  assert.equal(await freezeDrawRead(c, { on: true }), null);
  assert.ok(DRAW_READ_JS.includes('__fwDraw'));
});

test('the unfrozen twin of a draw capture only counts, and the full freeze installs no counter', async () => {
  const { sandbox, seen } = drawPage();
  const r = await freezeProbe(clientOf(sandbox), 'draw');
  assert.deepEqual([r.on, r.mode], [false, 'draw']);
  assert.equal(seen.replaced, null);
  const { sandbox: s2 } = drawPage();
  s2.document.addEventListener = () => assert.fail('the full freeze does not listen');
  await freezeStep(clientOf(s2), { on: false });
  assert.ok(!FREEZE_JS(true).includes('__fwDraw'));
});

test('accent setup names the three arms, all on one build, and needs the site and cost', () => {
  assert.deepEqual(accentSetup({ accent: false, cost: true, site: 'd' }), { accent: null, arms: null });
  assert.deepEqual(accentSetup({ accent: true, cost: false, site: 'd' }), { accent: null, arms: null });
  const s = accentSetup({ accent: true, cost: true, site: 'dist/aot' });
  assert.deepEqual(Object.keys(s.arms), ['faithful', 'nolayout', 'full']);
  assert.deepEqual(Object.values(s.arms).map((a) => a.search), ['', ACCENT_FLAGS.nolayout, ACCENT_FLAGS.full]);
  assert.ok(Object.values(s.arms).every((a) => a.dir === 'dist/aot'));
  assert.equal(s.accent.home.id, 'faithful');
});

test('a lane unit names a kind, an arm, a state and a slot', () => {
  assert.deepEqual(parseUnit('swap:faithful-frozen-a'), { kind: 'swap', arm: 'faithful', frozen: true, slot: 'a', name: 'faithful-frozen-a' });
  assert.deepEqual(parseUnit('zone:full-b'), { kind: 'zone', arm: 'full', frozen: false, slot: 'b', name: 'full-b' });
  assert.throws(() => parseUnit('zone:crop-a'), /unknown lane unit/);
});

function sessionStubs({ clock = null } = {}) {
  const calls = [];
  const setup = accentSetup({ accent: true, cost: true, site: 'd' });
  const ctx = { setArm: (a) => calls.push(['arm', a]), c: { evaluate: async () => 1 }, check: async () => {} };
  let t = 0;
  const deps = {
    retrying: async (_c, _n, _l, fn) => fn(),
    now: () => (clock ? clock() : t),
    swapCapture: async (_c, arm, o) => { calls.push(['swap', arm.id, o.freeze ? o.freeze.on : null]); t += 1000; return { ws: [], valid: [], cells: [], why: 'full' }; },
    zoneCapture: async (_c, arm, o) => { calls.push(['zone', arm.id, o.freeze.on, o.freeze.mode, o.align]); t += 1000; return { layout: 4, paint: 9, frames: 40, accentStart: 'idle', accentChanges: 1, align: o.align, drew: true }; },
  };
  return { calls, ctx, deps, base: { passes: 1, clock: 'pinned', settleMs: 1, step: 50, framesPerStep: 2, log: () => {}, accent: setup.accent }, tick: (ms) => { t += ms; } };
}

test('the accent session runs the 13 units in lane order; hero-exit zones are aligned in slot a and natural in slot b', async () => {
  const { calls, ctx, deps, base } = sessionStubs();
  const res = await accentSession(ctx, base, { ...deps, shift: 0 });
  const ran = calls.filter((c) => c[0] !== 'arm');
  assert.equal(ran.length, 13);
  assert.deepEqual(ran.slice(0, 3).map((c) => [c[0], c[1]]), [['swap', 'faithful'], ['swap', 'nolayout'], ['swap', 'full']]);
  const rec = res.passes[0].cost.accent;
  assert.deepEqual(Object.keys(rec.captures).sort(), ['faithful-a', 'faithful-b', 'faithful-frozen-a', 'full-a', 'nolayout-a']);
  assert.deepEqual(Object.keys(rec.zones).sort(), ['faithful-a', 'faithful-b', 'faithful-frozen-a', 'faithful-frozen-b', 'full-a', 'full-b', 'nolayout-a', 'nolayout-b']);
  assert.deepEqual(calls.filter((c) => c[0] === 'zone').map((c) => [c[2], c[3], c[4]]).filter((x) => x[0]).length, 2, 'only the two frozen zone captures are frozen');
  assert.ok(calls.filter((c) => c[0] === 'zone').every((c) => c[3] === 'draw'), 'every zone capture installs the draw counter');
  assert.deepEqual(calls.filter((c) => c[0] === 'swap').map((c) => c[2]), [null, null, null, null, true].slice(0, 3).concat([true, null]));
  assert.deepEqual(rec.skipped, []);
  assert.equal(res.passes.length, 1);
  assert.equal(calls.at(-1)[0], 'arm');
});

test('the VM number shifts the arm order and a swap capture still comes first', async () => {
  const { calls, ctx, deps, base } = sessionStubs();
  await accentSession(ctx, base, { ...deps, shift: 2 });
  assert.deepEqual(calls.filter((c) => c[0] === 'swap').slice(0, 3).map((c) => c[1]), ['full', 'faithful', 'nolayout']);
});

test('a unit that no longer fits the lane budget stops the pass green, and the rest is listed as skipped', async () => {
  const { calls, ctx, deps, base } = sessionStubs();
  let t = 0;
  const saves = [];
  const slow = { ...deps, now: () => t, swapCapture: async (c, a, o) => { t += 7 * 60000; return deps.swapCapture(c, a, o); } };
  const res = await accentSession(ctx, { ...base, save: (d) => saves.push(d) }, { ...slow, shift: 0 });
  const rec = res.passes[0].cost.accent;
  const ran = Object.keys(rec.captures).length + Object.keys(rec.zones).length;
  assert.ok(ran >= 1 && ran < 13);
  assert.equal(rec.skipped.length, 13 - ran);
  assert.deepEqual([...laneUnits(0)].slice(ran), rec.skipped);
  assert.ok(saves.length >= ran, 'saved after every unit');
  assert.equal(res.failed.length, 0);
  assert.ok(ESTIMATE_MS > 0);
  assert.equal(calls.filter((c) => c[0] !== 'arm').length, ran);
});

test('a failed unit is recorded and the pass goes on', async () => {
  const { ctx, deps, base } = sessionStubs();
  const bad = { ...deps, zoneCapture: async (c, a, o) => { if (a.id === 'full') throw new Error('marks missing'); return deps.zoneCapture(c, a, o); } };
  const res = await accentSession(ctx, base, { ...bad, shift: 0 });
  const rec = res.passes[0].cost.accent;
  assert.equal(rec.failed.length, 2);
  assert.match(rec.failed[0], /zone:full-a: marks missing/);
  assert.equal(Object.keys(rec.zones).length, 6);
  await assert.rejects(accentSession(ctx, { ...base, accent: null }, deps), /needs the accent setup/);
});

function capOf(layout, { rest = 1, paint = 1 } = {}) {
  const ws = nominal(0, PERIODS);
  const recs = ws.flatMap(([s], k) => [
    ...Array.from({ length: layout }, (_, i) => ['Layout', s + 1000 * i]), ...Array.from({ length: paint }, (_, i) => ['Paint', s + 500 + i]),
    ...Array.from({ length: typeof rest === 'function' ? rest(k) : rest }, (_, i) => ['Layout', s + SWAP_US + 1000 * i])]);
  return { ws, valid: ws.map((_, k) => validAt(ws, k)), cells: countCells(ws, recs, KINDS) };
}
const zone = (layout, { align, drew = align, draws = { animations: 1, transitions: 1 } } = {}) => ({ layout, paint: layout * 2, frames: 40, align, drew, draws, accentStart: 'idle', accentChanges: 0 });
const record = (n, { fa = 12, fb = 12, nl = 12, full = 12, frozen = 2, rest = { fa: 40, nl: 5, full: 3, frozen: 1 } } = {}) => ({
  job: { jobId: `j${n}`, pass: 1 },
  captures: {
    'faithful-a': capOf(fa, { rest: rest.fa }), 'faithful-b': capOf(fb, { rest: rest.fa }), 'nolayout-a': capOf(nl, { rest: rest.nl }),
    'full-a': capOf(full, { rest: rest.full }), 'faithful-frozen-a': capOf(frozen, { rest: rest.frozen }),
  },
  zones: {
    'faithful-a': zone(80 + n, { align: true }), 'faithful-b': zone(70 + n, { align: false }), 'nolayout-a': zone(50 + n, { align: true }), 'nolayout-b': zone(45 + n, { align: false }),
    'full-a': zone(40 + n, { align: true }), 'full-b': zone(38 + n, { align: false }), 'faithful-frozen-a': zone(20 + n, { align: true, draws: { animations: 0, transitions: 0 } }),
    'faithful-frozen-b': zone(18 + n, { align: false, draws: { animations: 0, transitions: 0 } }),
  },
  failed: [], skipped: [],
});
const docOf = (recs) => ({ passes: recs.map((r) => ({ cost: { accent: r } })) });

test('the accent report decides each window of each arm against the faithful floor, and prints the pooled numbers', () => {
  const an = accentAnalysis([docOf([record(1), record(2), record(3)])]);
  assert.equal(an.records, 3);
  assert.deepEqual(an.jobs, ['j1', 'j2', 'j3']);
  const p = an.pooled;
  assert.deepEqual([p.faithful.rest.captures, p.faithful.rest.windows, p.faithful.rest.busyWindows], [6, 42, 42]);
  assert.deepEqual([p.nolayout.rest.captures, p.nolayout.rest.windows, p.nolayout.rest.busyWindows], [3, 21, 0]);
  assert.equal(p.nolayout.rest.tenthsPerCapture, 350, 'seven rest windows of 5 rows per capture');
  assert.equal(p['faithful-frozen'].rest.median2 / 2, 1);
  const rest = an.windows.nolayout.filter((x) => x.phase === 'rest:0' && x.kind === 'Layout')[0];
  assert.equal(rest.cell, 'win');
  const swapL = an.windows.full.filter((x) => x.phase === 'swap:0' && x.kind === 'Layout')[0];
  assert.equal(swapL.cell.startsWith('unresolved'), true, 'equal swap rows do not decide');
  assert.deepEqual(an.tally.nolayout.rest.Layout, [7, 0, 0]);
});

test('the accent report compares the unfrozen busy samples with the frozen ones, window by window', () => {
  const an = accentAnalysis([docOf([record(1), record(2), record(3)])]);
  const s0 = an.frozen.find((x) => x.phase === 'swap:0' && x.kind === 'Layout');
  assert.equal(s0.basis, 'busy');
  assert.deepEqual([s0.cell, s0.unfrozen.length, s0.frozen.length], ['removed', 6, 3], 'rest windows of 40 rows make every unfrozen faithful swap window busy');
  const r0 = an.frozen.find((x) => x.phase === 'rest:0' && x.kind === 'Layout');
  assert.deepEqual([r0.basis, r0.cell, r0.unfrozen.length, r0.frozen.length], ['all', 'removed', 6, 3]);
});

test('the accent report gives Layout per hero-exit scroll frame per state, a verdict per pair, and the draw starts seen', () => {
  const an = accentAnalysis([docOf([record(1), record(2), record(3)])]);
  const st = an.zone.stats;
  assert.equal(st.faithful.aligned.captures, 3);
  assert.equal(st.faithful.aligned.frames, 120);
  assert.equal(st.faithful.aligned.layoutPerFrameMilli, perFrameMilli(81 + 82 + 83, 120));
  assert.equal(st.nolayout.natural.layout.median, 47);
  assert.deepEqual(st['faithful-frozen'].aligned.drawStarts, { captures: 3, animations: 0, transitions: 0 });
  assert.deepEqual(st.faithful.aligned.drawStarts, { captures: 3, animations: 3, transitions: 3 });
  const v = (group, from, to, kind) => an.zone.verdicts.find((x) => x.group === group && x.from === from && x.to === to && x.kind === kind);
  assert.equal(v('aligned', 'faithful', 'nolayout', 'Layout').verdict, 'lower');
  assert.equal(v('aligned', 'nolayout', 'full', 'Layout').verdict, 'lower');
  assert.equal(v('natural', 'faithful', 'faithful-frozen', 'Paint').verdict, 'lower');
  assert.equal(v('aligned', 'faithful', 'nolayout', 'Layout').share, 36);
});

test('the accent report prints every section and the arm names', () => {
  const an = accentAnalysis([docOf([record(1), record(2), record(3)])]);
  const md = accentMd(an, ['run 1']);
  for (const h of ['### Units per job', '### Pooled Layout rows', '### nolayout against faithful', '### full against faithful', '### Faithful, draw-only freeze', '### hero.exit zone (scroll-A)', 'hero.accent:draw-nolayout-full']) assert.ok(md.includes(h), h);
  assert.ok(STATES.every((s) => md.includes(`| ${s} |`)));
  assert.equal(recordsOf([{ passes: [{ cost: {} }, { cost: { accent: { x: 1 } } }] }]).length, 1);
});

test('a unit the lane skipped shows in the report instead of vanishing', () => {
  const r = { ...record(1), skipped: ['zone:full-b', 'zone:faithful-frozen-b'], zones: {} };
  const md = accentMd(accentAnalysis([docOf([r])]), ['run 1']);
  assert.ok(md.includes('zone:full-b, zone:faithful-frozen-b'));
});

test('the swap report names the arm column from the FW flag of the run, and prints the pooled numbers', () => {
  assert.equal(armLabel([{ search: '?fw=people.carousel:crop' }]), 'people.carousel:crop');
  assert.equal(armLabel([{ search: '?fw=hero.accent:draw-nolayout-full&x=1' }]), 'hero.accent:draw-nolayout-full');
  assert.equal(armLabel([{}]), 'arm');
  assert.equal(armLabel([{ search: '?fw=a:b' }], 'mine'), 'mine');
  const passes = [0, 1].map(() => ({ captures: { 'faithful-a': capOf(14, { rest: 40 }), 'faithful-b': capOf(14, { rest: 40 }), 'crop-a': capOf(14, { rest: 3 }), 'crop-b': capOf(14, { rest: 3 }) } }));
  const md = swapMd(windowCells(passes), ['run 1'], { label: 'hero.accent:draw-nolayout', model: false, passes });
  assert.ok(md.includes('| window | faithful a | faithful b (A/A floor) | hero.accent:draw-nolayout | dropped | verdict |'));
  assert.ok(!md.includes('| crop |'));
  assert.ok(md.includes('### Pooled Layout rows'));
  assert.ok(md.includes('| rest | hero.accent:draw-nolayout | 4 | 28 | 0 of 28 | 21.0 | 3 |'));
  assert.ok(md.includes('| rest | faithful-a | 2 | 14 | 14 of 14 | 280.0 | 40 |'));
  const pool = pooledSummary(passes);
  assert.deepEqual([pool.rest.arm.windows, pool.swap.arm.captures], [28, 4]);
});

test('the diagnostic heading names the arm column', () => {
  const diag = { layout: [1, 0], paint: [1, 1], owners: { 'hero-accent:class': [1, 0] }, before: {}, after: {}, buckets: 2 };
  const passes = [0, 1].map(() => ({ captures: { 'faithful-a': capOf(14), 'faithful-b': capOf(14), 'crop-a': capOf(2), 'crop-b': capOf(2) }, diag }));
  const named = swapMd(windowCells(passes), ['run 1'], { label: 'hero.accent:draw-nolayout-full', model: false, passes });
  assert.ok(named.includes('### Diagnostic captures (hero.accent:draw-nolayout-full arm, no swap marks, 100 ms buckets)'));
  assert.ok(!named.includes('(crop arm'));
  assert.ok(swapMd(windowCells(passes), ['run 1']).includes('### Diagnostic captures (crop arm, no swap marks, 100 ms buckets)'));
});

test('without options the swap report keeps its crop wording', () => {
  const passes = [0, 1].map(() => ({ captures: { 'faithful-a': capOf(14), 'faithful-b': capOf(14), 'crop-a': capOf(2), 'crop-b': capOf(2) } }));
  const md = swapMd(windowCells(passes), ['run 1']);
  assert.ok(md.includes('the crop none.'));
  assert.ok(md.includes('| crop | dropped | verdict |'));
});
