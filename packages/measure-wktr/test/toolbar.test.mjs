import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CONTROL_CSS, FLAGS, PLATFORM, INSETS_DOWN, INSETS_UP, stepList, toolbarHtml } from '../src/toolbar-page.mjs';
import { parseToolbar, serveFlags } from '../src/toolbar-cli.mjs';
import { CONTROL_FLAG, GOLDEN_PATH, HOOK_NAMES, HOOK_SYMBOLS, judgeAll, judgeReport, liftedBy, loadProduction, observedGeom, parseGolden, replay, runKey } from '../src/gate.mjs';

const golden = parseGolden(readFileSync(GOLDEN_PATH, 'utf8'));
const prod = await loadProduction();

function fakeReport(flag, { vh0 = 820, wait, hooks, tweak } = {}) {
  const exempt = flag === 'unthrottle';
  const walk = stepList();
  const mk = (s, k) => {
    const vh = vh0 - s.inset;
    return {
      k, dir: s.dir, inset: s.inset, scroll: s.scroll, setMs: 15, latencyMs: wait ?? (exempt || k === 0 ? 32 : 80), frames: 3,
      before: { vvh: vh0 }, after: { vvh: vh, ih: vh, sy: s.scroll + s.inset }, rect: { height: (vh0 * PLATFORM.heightNum) / PLATFORM.heightDen, bottom: vh0 - PLATFORM.gap },
      events: { resize: 0, vvResize: 1, vvScroll: 0, scroll: 2 },
    };
  };
  const r = {
    flag, params: { platform: PLATFORM, timeoutMs: 600 }, meta: { pass: 1 },
    hooks: hooks ?? Object.fromEntries(HOOK_NAMES.map((n) => [n, 'function'])),
    lift: flag === CONTROL_FLAG ? { animations: 1, timelines: ['DocumentTimeline'], states: ['running'], transform: 'matrix(1, 0, 0, 1, 40, 0)' } : null,
    facts: { base: { vvh: vh0, ih: vh0 }, rect0: { height: (vh0 * PLATFORM.heightNum) / PLATFORM.heightDen, bottom: vh0 - PLATFORM.gap } },
    steps: walk.map(mk),
  };
  if (tweak) tweak(r);
  return r;
}

test('the page walks the golden insets and platform', () => {
  assert.deepEqual([0, ...INSETS_DOWN], golden.walk.down);
  assert.deepEqual(INSETS_UP, golden.walk.up);
  assert.deepEqual(PLATFORM, { heightNum: golden.walk.heightNum, heightDen: golden.walk.heightDen, gap: golden.walk.gap });
  assert.equal(stepList().length, 8);
  assert.ok(stepList().every((s) => Number.isInteger(s.scroll)));
});

test('one page per flag; the unthrottle page carries the production style, the others none', () => {
  for (const f of FLAGS) assert.ok(toolbarHtml({ flag: f }).includes('FWWKTR'));
  assert.throws(() => toolbarHtml({ flag: 'nope' }), /unknown flag/);
  const css = toolbarHtml({ flag: 'unthrottle' });
  assert.ok(css.includes('animation-timeline: scroll(root block)') && css.includes('--fw-ut'));
  assert.equal(toolbarHtml({ flag: 'default' }).split('</script>').length, 2);
  assert.ok(toolbarHtml({ flag: 'default' }).includes('"flag":"default"'));
});

test('the flags of the page are the flags of the golden', () => {
  assert.deepEqual([...golden.exempt.keys()].sort(), [...FLAGS].sort());
});

test('parseToolbar reads the report, the error and the end marker from a WKTR output', () => {
  const out = ['Content-Type: text/plain', 'CONSOLE MESSAGE: FWWKTR toolbar {"flag":"default","steps":[]}', 'CONSOLE MESSAGE: FWWKTR done {}', 'x'].join('\n');
  assert.deepEqual(parseToolbar(out), { report: { flag: 'default', steps: [] }, error: null, done: true });
  assert.deepEqual(parseToolbar('FWWKTR error {"message":"m"}').error, { message: 'm' });
  assert.equal(parseToolbar('nothing').report, null);
});

test('the server serves each flag page and nothing else', async () => {
  const srv = await serveFlags(['default', 'unthrottle']);
  try {
    const ok = await fetch(`${srv.url}/unthrottle`);
    assert.equal(ok.status, 200);
    assert.equal(ok.headers.get('cache-control'), 'no-store');
    assert.ok((await ok.text()).includes('"flag":"unthrottle"'));
    assert.equal((await fetch(`${srv.url}/touch-first`)).status, 404);
  } finally { await srv.close(); }
});

test('production armed agrees with the golden arm per inset', () => {
  assert.ok(golden.geom.length > 0);
  for (const r of golden.geom) {
    const vh0 = r.in.vh0, vh = vh0 - r.in.inset;
    assert.equal(prod.armed({ height: (vh0 * 3) / 5, bottom: vh0 - 15 }, vh), r.out, JSON.stringify(r.in));
  }
});

test('production gesture machine agrees with every golden gate run', () => {
  assert.equal(golden.run.size, 5 * (32 + 16));
  for (const [key, takes] of golden.run) {
    const [flag, phase, bits] = key.split('|');
    const geoms = [...bits].map((c) => c === '1');
    assert.deepEqual(replay(prod, flag, geoms), takes, key);
    assert.equal(runKey(flag, phase, geoms), key);
  }
});

test('the lift comparison agrees with the golden verdicts', () => {
  assert.ok(golden.lifted.length > 0);
  for (const r of golden.lifted) assert.equal(liftedBy(r.in.medianMs, golden.walk.liftedBelowMs), r.out, JSON.stringify(r.in));
});

test('the expected arms of each phase follow from the golden insets', () => {
  assert.deepEqual(golden.expect.get('down').geoms, [true, true, true, false, false]);
  assert.deepEqual(golden.expect.get('up').geoms, [false, true, true, true]);
  for (const vh0 of [600, 820, 844, 932]) {
    const r = fakeReport('default', { vh0 });
    assert.equal(judgeReport(golden, prod, r).ok, true, `vh0 ${vh0}`);
  }
});

test('every flag passes on the model report, with the golden take sequence', () => {
  for (const f of FLAGS) {
    const j = judgeReport(golden, prod, fakeReport(f), Object.fromEntries(HOOK_SYMBOLS.map((s) => [s, 1])));
    assert.equal(j.ok, true, `${f}: ${JSON.stringify(j.checks.filter((c) => !c.ok))}`);
  }
  const once = judgeReport(golden, prod, fakeReport('open-once'));
  assert.match(once.checks.find((c) => c.id === 'takes-down').detail, /production 10000/);
  assert.match(judgeReport(golden, prod, fakeReport('touch-first')).checks.find((c) => c.id === 'takes-up').detail, /production 0000/);
});

test('a flag that is not exempt fails when its wait is short, an exempt one when its wait is long', () => {
  const fast = judgeReport(golden, prod, fakeReport('default', { wait: 32 }));
  assert.equal(fast.checks.find((c) => c.id === 'exempt').ok, false);
  const slow = judgeReport(golden, prod, fakeReport('unthrottle', { wait: 80 }));
  assert.equal(slow.checks.find((c) => c.id === 'exempt').ok, false);
});

test('a missing hook, a wrong walk, a viewport that does not shrink and a missing archive symbol each fail their check', () => {
  const failing = (j) => j.checks.filter((c) => !c.ok).map((c) => c.id);
  const noHook = fakeReport('default', { hooks: { beginInteractiveObscuredInsetsChange: 'function', setObscuredInsets: 'undefined', endInteractiveObscuredInsetsChange: 'function' } });
  assert.deepEqual(failing(judgeReport(golden, prod, noHook)), ['hooks']);
  const badWalk = fakeReport('default', { tweak: (r) => { r.steps[1].inset = 25; } });
  assert.ok(failing(judgeReport(golden, prod, badWalk)).includes('walk'));
  const flat = fakeReport('default', { tweak: (r) => { for (const s of r.steps) s.after.vvh = r.facts.base.vvh; } });
  assert.ok(failing(judgeReport(golden, prod, flat)).includes('geoms-down'));
  const gone = Object.fromEntries(HOOK_SYMBOLS.map((s, i) => [s, i === 0 ? 0 : 1]));
  assert.deepEqual(failing(judgeReport(golden, prod, fakeReport('default'), gone)), ['hooks']);
});

test('the gate holds only when every flag has enough passing reports', () => {
  const all = FLAGS.flatMap((f) => [fakeReport(f), fakeReport(f)]);
  assert.equal(judgeAll(golden, prod, all).ok, true);
  assert.equal(judgeAll(golden, prod, all.slice(1)).ok, false);
  assert.equal(judgeAll(golden, prod, [...all, fakeReport('default', { wait: 10 })]).ok, false);
  assert.equal(observedGeom(prod, { height: 492, bottom: 805 }, { vvh: 790, ih: 790 }), false);
  assert.equal(observedGeom(prod, { height: 492, bottom: 805 }, { vvh: 800, ih: 800 }), true);
});

test('the compositable control: golden exempt false, one time-based page animation, short wait fails, scroll timeline fails', () => {
  assert.equal(CONTROL_FLAG, 'compositable');
  assert.equal(golden.exempt.get(CONTROL_FLAG), false);
  const html = toolbarHtml({ flag: CONTROL_FLAG });
  assert.ok(html.includes('translateX') && CONTROL_CSS.includes('animation: fw-ctl') && !CONTROL_CSS.includes('animation-timeline'));
  assert.equal(toolbarHtml({ flag: 'unthrottle' }).includes('"flag":"compositable"'), false);
  assert.equal(judgeReport(golden, prod, fakeReport(CONTROL_FLAG)).ok, true);
  const fast = judgeReport(golden, prod, fakeReport(CONTROL_FLAG, { wait: 32 }));
  assert.equal(fast.checks.find((c) => c.id === 'exempt').ok, false);
  const scroll = judgeReport(golden, prod, fakeReport(CONTROL_FLAG, { tweak: (r) => { r.lift.timelines = ['ScrollTimeline']; } }));
  assert.equal(scroll.checks.find((c) => c.id === 'control-anim').ok, false);
  const none = judgeReport(golden, prod, fakeReport(CONTROL_FLAG, { tweak: (r) => { r.lift = null; } }));
  assert.equal(none.checks.find((c) => c.id === 'control-anim').ok, false);
});
