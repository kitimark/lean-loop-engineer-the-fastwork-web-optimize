// The trajectory reducer against the vectors Lean generates (lean/Fw/Gate/Trajectory.lean, scripts/TrajectoryGolden.lean), and the
// loop around it (reduceWidth) on small synthetic readings whose answers are worked out by hand.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { isDeepStrictEqual } from 'node:util';
import { fileURLToPath } from 'node:url';
import { ALPHA, alphaOk, annotate, armCheck, byM, byMFirst, firstCover, laneOf, byMRule, byMStart, CUT_M, idCheck, idOn, MIX_FROM, MIX_TO, redOk, byStep, bucket, CLOSE_PH, DARK_CUT, durOf, fullOf, settleCheck, START_JITTER, startCheck, startFor, startOn, startTr, judgeEls, judgeOwn, judgeUnit, pickWidths, quantile, readsDominate, reduceRaw, reduceWidth, rel, RULES, runCheck, START_LAG, verdictLines, window as windowOf, windowAt } from '../src/trajectory/reduce.mjs';
import { summaryMd } from '../src/trajectory/cli.mjs';
import { mergeRaws, planOf } from '../src/trajectory/plan.mjs';
import { HERO_NODES, MORPH_NODES, PAGE_PROPS, HERO_STEPS, WIDTHS, MOTION_PROPS } from '../src/trajectory/registry.mjs';

const golden = readFileSync(fileURLToPath(new URL('../../contracts/golden/gate/trajectory.jsonl', import.meta.url)), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
const navCss = readFileSync(fileURLToPath(new URL('../../../apps/site/src/parts/nav/nav.module.css', import.meta.url)), 'utf8');

/** The transition function a golden line names: the table's for (node, prop, width), or none under any class set. */
const durFn = (dur) => (dur === null ? () => null : (cls) => durOf(dur.node, dur.prop, dur.width, cls));

/** An integer as a [num, den] BigInt pair; a pair as the golden { num, den }. */
const qInt = (x) => [BigInt(x), 1n];
const qJson = ([n, d]) => ({ num: String(n), den: String(d) });

/** Milliseconds of a CSS time (`0.7s`, `120ms`). */
const msOf = (t) => (t.endsWith('ms') ? Number(t.slice(0, -2)) : Math.round(Number(t.slice(0, -1)) * 1000));

/** Split at the commas outside parentheses. */
function topSplit(s) {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const c of s) {
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === ',' && depth === 0) { out.push(cur.trim()); cur = ''; } else cur += c;
  }
  out.push(cur.trim());
  return out;
}

/** A `transition` value as [property, duration, delay] in ms; `none` is []. */
function transitionOf(v) {
  if (v.trim() === 'none') return [];
  return topSplit(v).map((item) => {
    const toks = item.replace(/\([^)]*\)/g, '()').split(/\s+/);
    const times = toks.filter((t) => /^[\d.]+m?s$/.test(t)).map(msOf);
    const prop = toks.find((t) => /^[a-z-]+$/.test(t) && !['linear', 'ease', 'ease-in', 'ease-out', 'ease-in-out', 'step-start', 'step-end'].includes(t));
    assert.ok(prop !== undefined && times.length >= 1 && times.length <= 2, `unparsed transition ${item}`);
    return [prop, times[0], times[1] ?? 0];
  });
}

/** One selector of a rule as the table keys it: its node, the nav classes it needs on and off, its specificity in classes. */
function selectorOf(sel) {
  const flat = sel.replace(/:global\(([^()]*)\)/g, '$1');
  const spec = (flat.match(/\.[a-z][a-z-]*/g) ?? []).length;
  const compounds = flat.replace(/\(([^()]*)\)/g, (m) => m.replace(/\s+/g, '')).split(/\s+/);
  const last = compounds[compounds.length - 1];
  const classes = (c) => (c.replace(/:not\([^)]*\)/g, '').match(/\.[a-z][a-z-]*/g) ?? []).map((x) => x.slice(1));
  const subject = classes(last);
  const node = subject.includes('nav') ? 'nav' : subject.includes('logo') ? 'logo' : subject.includes('actions') ? 'actions'
    : subject.includes('btn') && subject.includes('earn') ? 'earn' : null;
  assert.ok(node !== null, `unknown subject ${sel}`);
  const navC = compounds.find((c) => classes(c).includes('nav')) ?? '';
  const on = classes(navC).filter((x) => x !== 'nav');
  const off = [...navC.matchAll(/:not\(([^)]*)\)/g)].flatMap((m) => (m[1].match(/\.[a-z][a-z-]*/g) ?? []).map((x) => x.slice(1)));
  return { node, on, off, spec };
}

/** The rules of the nav's CSS that set `transition` or `transition-delay`, in source order, one per selector. */
function rulesOfCss(css) {
  const text = css.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
  const out = [];
  const stack = [];
  let start = 0;
  let line = 1;
  let startLine = 1;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '\n') line++;
    if (/\S/.test(c) && text.slice(start, i).trim() === '') startLine = line;
    if (c === '{') {
      const prelude = text.slice(start, i).trim();
      stack.push({ prelude, line: startLine, body: '' });
      start = i + 1;
    } else if (c === '}') {
      const top = stack.pop();
      const body = top.body + text.slice(start, i);
      start = i + 1;
      if (top.prelude.startsWith('@')) continue;
      if (stack.some((b) => b.prelude.startsWith('@keyframes'))) continue;
      const decls = Object.fromEntries(body.split(';').map((d) => d.trim()).filter((d) => d.includes(':')).map((d) => [d.slice(0, d.indexOf(':')).trim(), d.slice(d.indexOf(':') + 1).trim()]));
      assert.ok(!Object.keys(decls).some((k) => k.startsWith('transition-') && k !== 'transition-delay'), 'unmodelled transition longhand');
      if (!('transition' in decls) && !('transition-delay' in decls)) continue;
      const media = stack.map((b) => b.prelude).filter((p) => p.startsWith('@media'));
      let minW = null;
      let reduce = false;
      for (const m of media) {
        const w = m.match(/^@media \(width>(\d+)px\)$/);
        if (w) minW = Number(w[1]);
        else if (m === '@media (prefers-reduced-motion: reduce)') reduce = true;
        else assert.fail(`a transition under an unmodelled media query: ${m}`);
      }
      const set = 'transition' in decls ? transitionOf(decls.transition) : null;
      const delay = 'transition-delay' in decls ? msOf(decls['transition-delay']) : null;
      let at = 0;
      for (const sel of topSplit(top.prelude)) {
        at = top.prelude.indexOf(sel, at);
        const selLine = top.line + (top.prelude.slice(0, at).match(/\n/g) ?? []).length;
        out.push({ line: selLine, ...selectorOf(sel), minW, reduce, set, delay });
      }
    } else if (c === ';' && stack.length > 0) {
      stack[stack.length - 1].body += text.slice(start, i + 1);
      start = i + 1;
    }
  }
  return out.map(({ line, node, on, off, minW, reduce, spec, set, delay }) => ({ line, node, on, off, minW, reduce, spec, set, delay }));
}

test('the golden file holds every operation', () => {
  assert.deepEqual([...new Set(golden.map((g) => g.op))].sort(), ['els', 'window', 'bucket', 'byM', 'byStep', 'unit', 'rule', 'dur', 'annotate', 'widths', 'rel', 'arm', 'run', 'quantile', 'dominate', 'plan', 'byMStart', 'start', 'startCheck', 'settleCheck', 'curve', 'byMRule', 'byMFirst', 'idCheck', 'identity', 'firstCover', 'lane', 'laneStep'].sort());
  assert.ok(golden.length >= 200);
  assert.ok(golden.some((g) => g.op === 'byM' && [...g.oSeg, ...g.wSeg].some((x) => x.rep > 0)), 'golden has rows with rep > 0');
});

test('the transition table is the CSS: every rule of nav.module.css that sets a transition, as Lean `rules` and RULES', () => {
  const lean = golden.filter((g) => g.op === 'rule').map((g) => g.rule);
  assert.deepEqual(rulesOfCss(navCss), lean);
  assert.deepEqual(RULES, lean);
});

test('the earn curve is the CSS: every earn opacity and max-width transition of nav.module.css eases on Lean `earnCurve`', () => {
  const g = golden.find((x) => x.op === 'curve');
  const want = g.bez.map((q) => Number(q.num) / Number(q.den));
  const got = [];
  for (const [, body] of navCss.matchAll(/\.btn\.earn[^{}]*\{([^{}]*)\}/g)) {
    for (const [, v] of body.matchAll(/transition:([^;]*);/g)) {
      for (const item of topSplit(v)) {
        const [prop] = item.split(/\s+/);
        if (prop !== 'opacity' && prop !== 'max-width') continue;
        const bez = item.match(/cubic-bezier\(([^)]*)\)/);
        assert.ok(bez, `${item} has no cubic-bezier`);
        got.push(bez[1].split(',').map(Number));
      }
    }
  }
  assert.ok(got.length >= 4, `found ${got.length} earn transitions`);
  for (const c of got) assert.deepEqual(c, want);
});

test('the earn width at rest is the CSS: max-width 11rem, 9.5rem up to 640 px, as the golden `full` rows', () => {
  const g = golden.find((x) => x.op === 'curve');
  const rems = [...navCss.matchAll(/max-width: calc\(var\(--earn-layout\) \* ([\d.]+)rem\)/g)].map((m) => Number(m[1]));
  assert.deepEqual(rems, [11, 9.5]);
  const full = (w) => g.full.find(([p, x]) => p === 'max-width' && x === w)[2];
  assert.deepEqual(full(1280), qJson(qInt(rems[0] * 16 * 1000)));
  assert.deepEqual(full(390), qJson(qInt(rems[1] * 16 * 1000)));
});

test('the identity colours are the ported CSS: the nav background mixes #ffffff1a into #131922 by --morph, as the golden `from` and `to`', () => {
  const g = golden.find((x) => x.op === 'identity');
  const hex = (h, i) => parseInt(h.slice(i, i + 2), 16);
  const m = navCss.replace(/\s+/g, ' ').match(/background: ?color-mix\( ?in srgb, #([0-9a-f]{8}) calc\(\(1 - var\(--morph\)\) \* 100%\), #([0-9a-f]{6}) calc\(var\(--morph\) \* 100%\) ?\)/);
  assert.ok(m, 'no nav background color-mix');
  assert.deepEqual([[hex(m[1], 0), hex(m[1], 6)], [hex(m[2], 0), 255]], [g.from, g.to]);
  const logic = readFileSync(fileURLToPath(new URL('../../../apps/site/src/parts/nav/logic.ts', import.meta.url)), 'utf8');
  assert.equal(Number(logic.match(/MORPHING_CUT = ([\d.]+)/)[1]) * 10000, g.cut);
});

test('the CSS reader keys a rule by its selector and reads its transitions', () => {
  const css = '@layer p {\n  .nav:global(.is-a):not(:global(.is-b)) {\n    transition: width 0.5s ease 0.1s, opacity 80ms;\n  }\n  @keyframes k { 0% { opacity: 0; } }\n  .nav .btn.earn,\n  .logo { transition: none; }\n}\n';
  assert.deepEqual(rulesOfCss(css), [
    { line: 2, node: 'nav', on: ['is-a'], off: ['is-b'], minW: null, reduce: false, spec: 3, set: [['width', 500, 100], ['opacity', 80, 0]], delay: null },
    { line: 6, node: 'earn', on: [], off: [], minW: null, reduce: false, spec: 3, set: [], delay: null },
    { line: 7, node: 'logo', on: [], off: [], minW: null, reduce: false, spec: 1, set: [], delay: null },
  ]);
  assert.throws(() => rulesOfCss('.pill { transition: none; }'), /unknown subject/);
  assert.throws(() => rulesOfCss('@media (width<=640px) { .nav { transition: none; } }'), /unmodelled media/);
});

for (const g of golden) {
  test(`golden ${g.op}: ${g.name}`, () => {
    if (g.op === 'els') assert.equal(judgeEls(g.kind, g.win, g.r), g.verdict);
    else if (g.op === 'window') assert.deepEqual(windowOf(g.ms, g.m), g.idx);
    else if (g.op === 'bucket') assert.equal(bucket(g.m), g.bucket);
    else if (g.op === 'byM') assert.deepEqual(byM(g.phase, g.p, g.kind, durFn(g.dur), g.oSeg, g.wSeg).map((x) => x[1]), g.verdicts);
    else if (g.op === 'unit') assert.equal(judgeUnit(g.kind, durFn(g.dur), g.seg, g.win, g.r), g.verdict);
    else if (g.op === 'rule') assert.ok(RULES.some((r) => isDeepStrictEqual(r, g.rule)), `no RULES entry for ${g.name}`);
    else if (g.op === 'dur') {
      assert.equal(START_LAG, g.lag);
      const got = g.durs.map((_, k) => durOf(g.node, g.prop, g.width, g.classes.filter((_, i) => (k >> i) & 1)));
      assert.deepEqual(got, g.durs);
    } else if (g.op === 'annotate') assert.deepEqual(annotate(g.seg).map((s) => s.ord), g.ords);
    else if (g.op === 'rel') assert.equal(rel(g.cand, g.base), g.rel);
    else if (g.op === 'arm') assert.equal(armCheck(g.arm), g.verdict);
    else if (g.op === 'run') assert.equal(runCheck(g.arms), g.verdict);
    else if (g.op === 'quantile') assert.equal(quantile(g.xs, g.p), g.q);
    else if (g.op === 'dominate') assert.equal(readsDominate(g.read, g.gap), g.dominates);
    else if (g.op === 'byStep') {
      const side = (xs) => xs.map((x) => [x.step, x.s]);
      assert.deepEqual(byStep(g.kind, durFn(g.dur), side(g.orig), side(g.rew)).map(([step, verdict]) => ({ step, verdict })), g.verdicts);
    } else if (g.op === 'widths') {
      const got = pickWidths(g.input);
      assert.deepEqual(got === null ? { ok: false } : { ok: true, widths: got }, g.pick);
    } else if (g.op === 'plan') assert.deepEqual(planOf(g.engines, g.widths), g.legs);
    else if (g.op === 'byMStart') {
      const d = (cls) => durOf(g.node, g.prop, g.width, cls);
      assert.deepEqual(byMStart(g.phase, g.p, g.kind, d, startFor(g.node, g.prop, g.width), g.oSeg, g.wSeg).map((x) => x[1]), g.verdicts);
    } else if (g.op === 'start') {
      assert.equal(startOn(g.node, g.prop), g.on);
      assert.deepEqual(g.trs.map((_, k) => startTr(g.node, g.prop, g.width, g.classes.filter((_, i) => (k >> i) & 1))), g.trs);
    } else if (g.op === 'startCheck') assert.equal(startCheck(g.kind, g.full, g.oSeg, g.prior, g.r), g.check);
    else if (g.op === 'settleCheck') {
      const e = startFor(g.node, g.prop, g.width);
      assert.equal(e === null ? null : settleCheck(g.kind, e, g.seg, g.r), g.check);
    } else if (g.op === 'curve') {
      assert.equal(START_JITTER, g.jitter);
      assert.equal(CLOSE_PH, g.close);
      assert.deepEqual(qJson(qInt(DARK_CUT)), g.darkCut);
      for (const [prop, width, full] of g.full) assert.deepEqual(qJson(qInt(fullOf(prop, width))), full);
    } else if (g.op === 'byMRule') {
      const d = (cls) => durOf(g.node, g.prop, g.width, cls);
      assert.equal(idOn(g.node, g.prop), g.id);
      assert.deepEqual(byMRule(g.phase, g.p, g.kind, d, startFor(g.node, g.prop, g.width), g.id, g.oSeg, g.wSeg).map((x) => x[1]), g.verdicts);
    } else if (g.op === 'byMFirst') {
      const d = (cls) => durOf(g.node, g.prop, g.width, cls);
      assert.equal(idOn(g.node, g.prop), g.id);
      assert.deepEqual(byMFirst(g.phase, g.p, g.kind, d, startFor(g.node, g.prop, g.width), g.id, g.oSeg, g.wSeg).map((x) => x[1]), g.verdicts);
    } else if (g.op === 'idCheck') assert.equal(idCheck((cls) => durOf('nav', 'background-color', g.width, cls), g.q, g.r), g.check);
    else if (g.op === 'identity') {
      assert.equal(CUT_M, g.cut);
      assert.deepEqual(qJson(qInt(CUT_M)), g.cutRat);
      assert.deepEqual([MIX_FROM, MIX_TO], [g.from, g.to]);
      for (const [m, x, a, r, al] of g.rows) assert.deepEqual([redOk(m, x), alphaOk(m, a)], [r, al], `m ${m} red ${x} alpha ${a}`);
    } else if (g.op === 'firstCover') {
      assert.deepEqual({ num: String(ALPHA[0]), den: String(ALPHA[1]) }, g.alpha);
      for (const [no, k, nw, c] of g.rows) assert.equal(firstCover(no, k, nw), c, `no ${no} k ${k} nw ${nw}`);
    } else if (g.op === 'lane') assert.equal(laneOf(g.rels), g.lane);
    else if (g.op === 'laneStep') {
      const at = (o, w) => byMFirst('push', 0, 'geometry', () => null, null, false, o, w).find((x) => x[0] === 1)?.[1] ?? 'pass';
      assert.deepEqual([at(g.oSeg, g.cand), at(g.oSeg, g.base), at(g.oSeg2, g.cand), at(g.oSeg2, g.base)], g.open);
      assert.deepEqual([laneOf([rel(at(g.oSeg, g.cand), at(g.oSeg, g.base))]), laneOf([rel(at(g.oSeg2, g.cand), at(g.oSeg2, g.base))])], g.lanes);
    }
    else assert.fail(`unknown op ${g.op}`);
  });
}

test('envelope: a start another pass of the original had passes, and fails against its own pass (Lean judgeUnit_other_start)', () => {
  const g = golden.find((x) => x.op === 'unit' && x.name === "envelope, another pass's start");
  assert.equal(judgeUnit(g.kind, durFn(g.dur), g.seg, g.win, g.r), 'pass');
  assert.equal(judgeOwn(g.kind, durFn(g.dur), g.seg, g.win, g.r), 'fail:apart');
});

test('envelope scope: past the start the own-pass rule passes a stuck hold and fails another pass\'s curve, the envelope the reverse (Lean judgeScoped_stuck_hold, judgeScoped_other_curve)', () => {
  const g = (name) => golden.find((x) => x.op === 'unit' && x.name === name);
  const stuck = g('envelope, stuck in a hold of a pass the original lacks'), curve = g("envelope, another pass's curve past the start");
  assert.equal(judgeUnit(stuck.kind, durFn(stuck.dur), stuck.seg, stuck.win, stuck.r), 'fail:apart');
  assert.equal(judgeOwn(stuck.kind, durFn(stuck.dur), stuck.seg, stuck.win, stuck.r), 'pass');
  assert.equal(judgeUnit(curve.kind, durFn(curve.dur), curve.seg, curve.win, curve.r), 'pass');
  assert.equal(judgeOwn(curve.kind, durFn(curve.dur), curve.seg, curve.win, curve.r), 'fail:apart');
});

test('envelope: with one pass the judge is the own-pass rule (Lean judgeUnit_agree)', () => {
  const one = golden.filter((x) => x.op === 'unit' && (x.r.rep ?? 0) === 0 && x.seg.every((s) => (s.rep ?? 0) === 0));
  assert.ok(one.length >= 5);
  for (const g of one) assert.equal(judgeUnit(g.kind, durFn(g.dur), g.seg, g.win, g.r), judgeOwn(g.kind, durFn(g.dur), g.seg, g.win, g.r), g.name);
});

test('windowAt: a hold keeps windowOf, a push keeps windowOne for a sampled value or a sample in flight (Lean windowAt_hold, windowPass_sampled, windowPass_in_flight)', () => {
  const s = (rep, ph, m, v, since = null) => ({ m, since, els: [v], rep, cls: [], ph, ord: 0 });
  const seg = [s(0, 0, 1000, 'on'), s(0, 0, 0, 'on'), s(0, 1, 0, 'off')];
  const orig = seg.filter((o) => o.ph === 0);
  const rest = () => null, flight = () => 700;
  assert.deepEqual(windowAt('hold', rest, seg, orig, s(0, 0, 0, 'off')), orig);
  assert.deepEqual(windowAt('push', rest, seg, orig, s(0, 0, 0, 'off')), orig);
  assert.deepEqual(windowAt('push', rest, seg, orig.slice(0, 1), s(0, 0, 0, 'off')), [seg[2]]);
  assert.deepEqual(windowAt('push', flight, seg, orig.slice(0, 1), s(0, 0, 0, 'off', 100)), [seg[0]]);
  assert.equal(windowAt('push', rest, seg, [], s(0, 0, 0, 'off')), null);
});

// ---- the legs of a dispatch (src/trajectory/plan.mjs, the twin of Lean `plan`) ----

test('plan: macOS WebKit joins every WebKit dispatch and walks the morph path; Linux WebKit walks hero only', () => {
  const apple = (p) => p.filter((l) => l.engine === 'mac-webkit');
  assert.deepEqual(apple(planOf('playwright-webkit', '')).map((l) => [l.widths, l.walks]), [[[390, 641], ['hero', 'morph']], [[640, 1280], ['hero', 'morph']]]);
  assert.deepEqual(apple(planOf('chromium', '')), []);
  assert.deepEqual(planOf('both', '').filter((l) => l.engine === 'linux-webkit').map((l) => l.walks), [['hero'], ['hero'], ['hero'], ['hero']]);
  assert.equal(planOf('safari', ''), null);
  assert.equal(planOf('both', '390,500'), null);
});

test('mergeRaws: legs of one engine join in width order; a leg that disagrees on the search or a refused leg is kept visible', () => {
  const leg = (width, extra = {}) => ({ engine: 'chromium', version: '1', search: '?fw=a:b', hash: 'h', baseHash: 'b', paths: ['hero'], reads: 'full', reps: 5, refused: false, runs: [{ width, role: 'orig' }], ...extra });
  const m = mergeRaws([leg(1280), leg(390), leg(641, { refused: true })]);
  assert.deepEqual(m.runs.map((r) => r.width), [390, 641, 1280]);
  assert.equal(m.refused, true);
  assert.throws(() => mergeRaws([leg(390), leg(640, { search: '?fw=c:d' })]), /disagree on search/);
  assert.throws(() => mergeRaws([]), /no leg/);
});

// ---- the loop around the reducer ------------------------------------------------------------------------------------------

const registries = { hero: HERO_NODES, morph: MORPH_NODES, page: PAGE_PROPS };
const propIdx = (nodes, id, prop) => nodes.find((n) => n.id === id).props.findIndex((p) => p.id === prop);

/** A row whose every node has one element and every property the value `fill(kind)`, except `over`. */
function row(nodes, extra, fill, over = {}) {
  const out = {};
  for (const n of nodes) {
    out[n.id] = [n.props.map((p) => {
      const key = `${n.id}.${p.id}`;
      return key in over ? over[key] : fill(p);
    })];
  }
  return { nodes: out, page: [[[5947000]]], y: 0, m: null, since: null, ...extra };
}
const fill = (p) => (p.kind === 'discrete' ? 'off' : p.kind === 'colour' ? [43000, 49000, 59000, 255000] : [0]);

const OK_REWRITE = { config: 'h1', mode: 'hydrate' };
const NO_FW = { config: null, mode: null };

/** One raw run of the hero path; the morph path is empty. */
function heroRun(role, copy, arm) {
  const rows = HERO_STEPS.map((s) => row(HERO_NODES, { step: s.id, frame: 'rest', tag: `${s.id}/rest`, settled: true }, fill, { 'hero.copy.opacity': copy(s.id) }));
  return { width: 390, site: role === 'orig' ? 'orig' : 'rewrite', role, want: role === 'orig' ? null : 'h1', hero: { ready: { ready: true }, arm, rows }, morph: undefined };
}

function raw({ origCopy, baseCopy, candCopy, candArm = OK_REWRITE }) {
  return { engine: 'x', runs: [heroRun('orig', origCopy, NO_FW), heroRun('base', baseCopy ?? origCopy, OK_REWRITE), heroRun('cand', candCopy, candArm)] };
}

test('reduceRaw: equal arms are clean, nothing is new', () => {
  const red = reduceRaw(raw({ origCopy: () => [750], candCopy: () => [750] }), registries);
  assert.equal(red.refused, false);
  assert.equal(red.red, false);
  assert.equal(red.totals.fail, 0);
  assert.ok(red.totals.pass > 0);
});

test('reduceRaw: one stale step is the only new unit (bug A shape)', () => {
  const red = reduceRaw(raw({ origCopy: (s) => (s === 's25' ? [750] : [1000]), candCopy: () => [1000] }), registries);
  const failed = red.units.filter((u) => u.verdict.startsWith('fail:'));
  assert.deepEqual(failed.map((u) => `${u.node}.${u.prop}@${u.step}`), ['hero.copy.opacity@s25']);
  assert.equal(red.red, true);
  assert.match(verdictLines('chromium', '', red).join('\n'), /VERDICT trajectory chromium w=390 hero hero.copy.opacity NEW 1\/10 units: s25=apart/);
});

test('reduceRaw: a failure the faithful arm has too is baseline red, not new', () => {
  const o = (s) => (s === 's25' ? [750] : [1000]);
  const red = reduceRaw(raw({ origCopy: o, baseCopy: () => [1000], candCopy: () => [1000] }), registries);
  assert.equal(red.rels.both, 1);
  assert.equal(red.rels.new, 0);
  assert.equal(red.red, false);
  assert.equal(red.fails, true);
});

test('reduceRaw: a candidate that fixes what the faithful arm fails is cleared', () => {
  const o = (s) => (s === 's25' ? [750] : [1000]);
  const red = reduceRaw(raw({ origCopy: o, baseCopy: () => [1000], candCopy: o }), registries);
  assert.equal(red.rels.cleared, 1);
  assert.equal(red.red, false);
});

test('reduceRaw: a missing faithful arm makes every failure new', () => {
  const r = raw({ origCopy: (s) => (s === 's25' ? [750] : [1000]), candCopy: () => [1000] });
  r.runs = r.runs.filter((x) => x.role !== 'base');
  const red = reduceRaw(r, registries);
  assert.equal(red.rels.new, 1);
  assert.ok(red.notes.some((n) => /no faithful arm/.test(n)));
});

test('reduceRaw: a rewrite that client-rendered the default config is refused, not judged (inc-variant-gate-flags-off)', () => {
  const red = reduceRaw(raw({ origCopy: () => [750], candCopy: () => [750], candArm: { config: 'h0', mode: 'client-render' } }), registries);
  assert.equal(red.refused, true);
  assert.equal(red.units.length, 0);
  assert.equal(red.red, false);
  assert.match(verdictLines('webkit', '?fw=x', red).join('\n'), /REFUSED config: cand w=390 hero: config h0 mode client-render want h1/);
});

test('reduceRaw: no arm is refused', () => {
  assert.equal(reduceRaw({ engine: 'x', runs: [] }, registries).refused, true);
});

test('reduceRaw: the original page with a window.__fw is refused', () => {
  const r = raw({ origCopy: () => [750], candCopy: () => [750] });
  r.runs[0].hero.arm = OK_REWRITE;
  assert.equal(reduceRaw(r, registries).refused, true);
});

/** A morph phase of the nav class `is-expanded`: one sample per morph value, with `cls(m)` as the class. */
function phaseRows(ms, cls, extra = {}) {
  const ci = propIdx(MORPH_NODES, 'nav', 'cls.is-expanded');
  return ms.map((m, i) => {
    const r = row(MORPH_NODES, { m, since: 1000, t0: i * 20, t1: i * 20 + 4, ...extra }, fill);
    r.nodes.nav[0][ci] = cls(m);
    return r;
  });
}
const morphOf = (open, arm, reads) => ({ watched: true, ready: { ready: true }, arm, approach: [], phases: { open }, phaseReads: reads ?? { open: 'full' } });
const runOf = (role, morph) => ({ width: 390, site: role === 'orig' ? 'orig' : 'rewrite', role, want: role === 'orig' ? null : 'h1', morph });
const EVERY = [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000];

test('reduceWidth: a morph class that stays off fails at the buckets where the original has it on (bug B shape)', () => {
  const fine = [...EVERY.slice(0, 10), 9300, 9600, 9900, 10000];
  const orig = { morph: morphOf(phaseRows(fine, (m) => (m >= 9300 ? 'on' : 'off')), NO_FW) };
  const rewrite = { morph: morphOf(phaseRows(fine, () => 'off'), OK_REWRITE) };
  const units = reduceWidth({ width: 390, orig, rewrite, registries }).filter((u) => u.node === 'nav' && u.prop === 'cls.is-expanded' && u.phase === 'open');
  assert.deepEqual(units.filter((u) => u.verdict.startsWith('fail:')).map((u) => u.step), ['open@10']);
  assert.equal(units.find((u) => u.step === 'open@5').verdict, 'pass');
});

test('reduceWidth: an empty bucket 1..9 in a push is fail:coverage, in a hold a skip, outside 1..9 a skip', () => {
  const sparse = [0, 1000, 2000, 8000, 9000, 10000];
  const orig = { morph: morphOf(phaseRows(EVERY, () => 'off'), NO_FW) };
  const rewrite = { morph: morphOf(phaseRows(sparse, () => 'off'), OK_REWRITE) };
  const u = reduceWidth({ width: 390, orig, rewrite, registries }).filter((x) => x.node === 'nav' && x.prop === 'cls.is-expanded' && x.phase === 'open');
  const by = Object.fromEntries(u.map((x) => [x.step, x.verdict]));
  assert.deepEqual([by['open@3'], by['open@4'], by['open@5'], by['open@6'], by['open@7']], Array(5).fill('fail:coverage'));
  assert.equal(by['open@1'], 'pass');
  assert.equal(by['open@11'], 'skip:noSample');
});

const NO_FIRST = [0, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000];
const cellOf = (units, prop, step) => units.find((x) => x.node === 'nav' && x.prop === prop && x.phase === 'open' && x.step === step);

/** `n` passes of the open phase; the first `k` sample open@1. */
const passesWith = (n, k) => Array.from({ length: n }, (_, q) => phaseRows(q < k ? EVERY : NO_FIRST, () => 'off', { rep: q })).flat();
const openAt1 = (o, w) => cellOf(reduceWidth({ width: 390, orig: { morph: morphOf(o, NO_FW) }, rewrite: { morph: morphOf(w, OK_REWRITE) }, registries }), 'cls.is-expanded', 'open@1').verdict;

test('reduceWidth: open@1 empty in the rewrite is judged by Lean firstCover over the original passes (5 rewrite passes)', () => {
  const got = [0, 1, 2, 3, 4, 5].map((k) => openAt1(passesWith(5, k), passesWith(5, 0)));
  assert.deepEqual(got, ['skip:firstLate', 'skip:firstLate', 'skip:firstOpen', 'skip:firstOpen', 'fail:coverage', 'fail:coverage']);
  assert.equal(openAt1(passesWith(5, 0), passesWith(5, 1)), 'pass');
});

test('reduceWidth: one extra original pass never turns skip:firstLate into fail:coverage or back', () => {
  for (let k = 0; k <= 5; k++) {
    const before = openAt1(passesWith(5, k), passesWith(5, 0));
    for (const hit of [0, 1]) {
      const after = openAt1(passesWith(6, k + hit), passesWith(5, 0));
      assert.ok(!(before === 'skip:firstLate' && after === 'fail:coverage') && !(before === 'fail:coverage' && after === 'skip:firstLate'), `k ${k} hit ${hit}: ${before} -> ${after}`);
    }
  }
});

test('reduceWidth: one pass each cannot decide open@1, and only open@1 is judged this way', () => {
  const u = reduceWidth({ width: 390, orig: { morph: morphOf(phaseRows(NO_FIRST, () => 'off'), NO_FW) }, rewrite: { morph: morphOf(phaseRows(NO_FIRST, () => 'off'), OK_REWRITE) }, registries });
  assert.equal(cellOf(u, 'cls.is-expanded', 'open@1').verdict, 'skip:firstOpen');
  assert.equal(cellOf(u, 'cls.is-expanded', 'open@2').verdict, 'pass');
  assert.equal(openAt1(phaseRows(EVERY, () => 'off'), phaseRows(NO_FIRST, () => 'off')), 'skip:firstOpen');
  assert.equal(u.filter((x) => x.phase !== 'open').some((x) => x.verdict.startsWith('skip:first')), false);
});

test('reduceWidth: an empty open@2 stays fail:coverage when the original has no open@2 either', () => {
  const none2 = [0, 1000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000];
  const orig = { morph: morphOf(phaseRows(none2, () => 'off'), NO_FW) };
  const rewrite = { morph: morphOf(phaseRows(none2, () => 'off'), OK_REWRITE) };
  assert.equal(cellOf(reduceWidth({ width: 390, orig, rewrite, registries }), 'cls.is-expanded', 'open@2').verdict, 'fail:coverage');
});

test('reduceRaw: the flag that matches the original at open@1 is not red where the faithful arm sampled it (hero:scene-pause shape)', () => {
  const raw = (candRows) => ({
    engine: 'chromium', search: '?fw=hero:scene-pause', reps: 1, paths: ['morph'], runs: [
      { ...runOf('orig', morphOf(phaseRows(NO_FIRST, () => 'off'), NO_FW)) },
      { ...runOf('base', morphOf(phaseRows(EVERY, () => 'off'), OK_REWRITE)) },
      { ...runOf('cand', morphOf(phaseRows(candRows, () => 'off'), OK_REWRITE)) }] });
  const regs = { hero: [], morph: registries.morph, page: [] };
  const flag = reduceRaw(raw(NO_FIRST), regs), plain = reduceRaw(raw(EVERY), regs);
  assert.equal(flag.refused, false);
  assert.equal(flag.red, false);
  assert.equal(flag.lane, 'undecided');
  assert.ok(flag.totals.firstOpen > 0);
  const lines = verdictLines('chromium', '?fw=hero:scene-pause', flag);
  assert.ok(lines.some((l) => l.startsWith('FIRSTFRAME ')));
  assert.ok(lines.some((l) => / UNDECIDED new=0 /.test(l)));
  const md = summaryMd(raw(NO_FIRST), flag);
  assert.match(md.split('\n')[0], / UNDECIDED$/);
  assert.match(md, new RegExp(`\\| undecided \\(.*\\) \\| ${flag.rels.undecided} \\|`));
  assert.match(summaryMd(raw(EVERY), plain).split('\n')[0], / CLEAN$/);
  assert.equal(plain.red, false);
  assert.equal(plain.lane, 'clean');
  const raw5 = { engine: 'chromium', search: '?fw=hero:scene-pause', reps: 5, paths: ['morph'], runs: [
    runOf('orig', morphOf(passesWith(5, 0), NO_FW)), runOf('base', morphOf(passesWith(5, 5), OK_REWRITE)),
    runOf('cand', morphOf(passesWith(5, 0), OK_REWRITE))] };
  const flag5 = reduceRaw(raw5, regs);
  assert.equal(flag5.lane, 'clean');
  assert.ok(flag5.totals.firstLate > 0);
});

test('reduceWidth: a push sample without a morph value is fail:coverage', () => {
  const orig = { morph: morphOf(phaseRows(EVERY, () => 'off'), NO_FW) };
  const rows = phaseRows(EVERY, () => 'off');
  rows[4].m = null;
  const rewrite = { morph: morphOf(rows, OK_REWRITE) };
  const u = reduceWidth({ width: 390, orig, rewrite, registries }).find((x) => x.node === 'nav' && x.prop === 'cls.is-expanded' && x.step === 'open@11');
  assert.equal(u.verdict, 'fail:coverage');
});

test('reduceWidth: a rewrite sample beyond the original range is fail:coverage', () => {
  const orig = { morph: morphOf(phaseRows([0, 500, 1000, 1500], () => 'off'), NO_FW) };
  const rewrite = { morph: morphOf(phaseRows(EVERY, () => 'off'), OK_REWRITE) };
  const u = reduceWidth({ width: 390, orig, rewrite, registries }).find((x) => x.node === 'nav' && x.prop === 'cls.is-expanded' && x.step === 'open@10');
  assert.equal(u.verdict, 'fail:coverage');
});

test('reduceWidth: with the lean read set only the lean properties are units in a push', () => {
  const orig = { morph: morphOf(phaseRows(EVERY, () => 'off'), NO_FW, { open: 'lean' }) };
  const rewrite = { morph: morphOf(phaseRows(EVERY, () => 'off'), OK_REWRITE, { open: 'lean' }) };
  const props = new Set(reduceWidth({ width: 390, orig, rewrite, registries }).filter((u) => u.phase === 'open').map((u) => `${u.node}.${u.prop}`));
  assert.ok(props.has('nav.cls.is-on-dark') && props.has('logo.rect-in-nav'));
  assert.ok(!props.has('nav.background-color') && !props.has('logo.color') && !props.has('nav.rect'));
});

test('reduceRaw: the timing rows split the read cost from the gap between samples', () => {
  const morph = (arm, ms) => morphOf(phaseRows(ms, () => 'off'), arm);
  const r = { engine: 'x', runs: ['orig', 'base', 'cand'].map((role) => runOf(role, morph(role === 'orig' ? NO_FW : OK_REWRITE, EVERY))) };
  const red = reduceRaw(r, registries);
  const t = red.timing.find((x) => x.role === 'cand' && x.phase === 'open');
  assert.deepEqual([t.n, t.readP50, t.gapP50, t.dominate], [11, 4, 20, false]);
});

/** Rows of a ramping nav class: `is-expanded` is on from m = 0.93 (the original), per pass. */
const rampRows = (ms, rep, cls) => phaseRows(ms, cls).map((r) => ({ ...r, rep }));

test('reps: a rewrite stuck off while the original ramps on fails across two passes (the pooled window was the whole phase)', () => {
  const evens = [0, 2000, 4000, 6000, 8000, 9000, 9300, 9400, 9500, 9600, 9700, 9800, 9900, 10000];
  const on = (m) => (m >= 9300 ? 'on' : 'off');
  const pooledOrig = [...rampRows(evens, 0, on), ...rampRows(evens, 1, on)];
  const mk = (cand) => ({ engine: 'x', runs: [runOf('orig', morphOf(pooledOrig, NO_FW)), runOf('base', morphOf(pooledOrig, OK_REWRITE)), runOf('cand', morphOf(cand, OK_REWRITE))] });
  const stuck = [...rampRows([4000, 9700, 9800], 0, () => 'off'), ...rampRows([4000, 9700, 9800], 1, () => 'off')];
  const red = reduceRaw(mk(stuck), registries);
  const cls = red.units.filter((u) => u.phase === 'open' && u.node === 'nav' && u.prop === 'cls.is-expanded' && u.verdict === 'fail:differs');
  assert.deepEqual(cls.map((u) => u.step), ['open@10']);
  assert.ok(cls.every((u) => u.rel === 'new'));
  // the same rewrite following the ramp is clean on that property
  const follows = [...rampRows([4000, 9700, 9800], 0, on), ...rampRows([4000, 9700, 9800], 1, on)];
  const ok = reduceRaw(mk(follows), registries);
  assert.equal(ok.units.filter((u) => u.phase === 'open' && u.node === 'nav' && u.prop === 'cls.is-expanded' && u.verdict === 'fail:differs').length, 0);
});

test('reps: an empty bucket one pass left is filled by the other, and gaps are taken inside a pass', () => {
  const half = (ms, rep) => phaseRows(ms, () => 'off').map((r) => ({ ...r, rep }));
  const evens = [0, 2000, 4000, 6000, 8000, 10000], odds = [1000, 3000, 5000, 7000, 9000];
  const pooled = [...half(evens, 0), ...half(odds, 1)];
  const r = { engine: 'x', runs: ['orig', 'base', 'cand'].map((role) => runOf(role, morphOf(pooled, role === 'orig' ? NO_FW : OK_REWRITE))) };
  const red = reduceRaw(r, registries);
  const gaps = (x) => x.units.filter((u) => u.phase === 'open' && u.verdict === 'fail:coverage').length;
  assert.equal(gaps(red), 0);
  assert.equal(gaps(reduceRaw({ ...r, runs: r.runs.map((x) => ({ ...x, morph: { ...x.morph, phases: { open: half(evens, 0) } } })) }, registries)) > 0, true);
  const t = red.timing.find((x) => x.role === 'cand' && x.phase === 'open');
  assert.equal(t.n, 11);
  assert.equal(t.gapP90, 20);
});

test('reps: every pass keeps its arm identity, a pass that client-rendered refuses the run', () => {
  const m = morphOf(phaseRows(EVERY, () => 'off'), OK_REWRITE);
  const bad = { ...m, extraArms: [{ config: 'h0', mode: 'client-render' }] };
  const r = { engine: 'x', runs: [runOf('orig', morphOf(phaseRows(EVERY, () => 'off'), NO_FW)), runOf('base', m), runOf('cand', bad)] };
  const red = reduceRaw(r, registries);
  assert.equal(red.refused, true);
  assert.match(red.detail, /cand w=390 morph: config h0 mode client-render/);
});

test('registry: the lane widths and the motion properties are the ones the Lean tolerance table covers', () => {
  assert.deepEqual(WIDTHS, [390, 640, 641, 1280]);
  assert.ok(MOTION_PROPS.every((p) => ['discrete', 'geometry', 'unit', 'colour'].includes(p.kind)));
});
