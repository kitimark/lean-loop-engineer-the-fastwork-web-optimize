// Report of the hero.accent freeze run (TS stand-in for tables and medians; the decisions are the Lean twins in swap.mjs:
// longRuns, frozenCell, sharePct, zoneVerdict, golden kinds swapRuns, swapFrozen, swapShare, swapZone).
import { PERIODS, BUSY_MIN, BUSY_BUCKET, LONG_RUN_MIN, longRuns, median2, frozenCell, sharePct, zoneVerdict } from './swap.mjs';
import { countOf, bgOfCapture, jobKey, jobBase, median } from './swapreport.mjs';

export const ARMS = Object.freeze(['crop', 'faithful']);
export const STATE_NAMES = Object.freeze(['free', 'frozen']);

const SWAP_KEY = { free: 'swap', frozen: 'swapFrozen' };
const SLOTS = ['a', 'b'];

export const passesOf = (docs, state) => docs.flatMap((d) => d.passes.map((p) => p.cost?.[SWAP_KEY[state]]).filter(Boolean));
export const zonesOf = (docs, state) => docs.flatMap((d) => d.passes.flatMap((p) => p.cost?.zone?.[state] ?? []));

/** The samples of one arm, state, kind and window: [rows, background, key] over both capture slots of every pass. */
export function windowSamples(passes, arm, ty, phase, k) {
  const out = [];
  for (const s of passes) {
    for (const slot of SLOTS) {
      const cap = s.captures[`${arm}-${slot}`];
      const n = countOf(cap, k, `${phase}:${k}`, ty);
      if (typeof n !== 'number') continue;
      out.push([n, phase === 'swap' ? bgOfCapture(cap, k) : 'unknown', jobKey(s, slot)]);
    }
  }
  return out;
}

const col = (xs, j) => xs.map((x) => x[j]);
const tally = (bgs) => Object.fromEntries(['idle', 'mixed', 'busy', 'unknown'].map((b) => [b, bgs.filter((x) => x === b).length]));
const orNull = (xs) => (xs.length ? median(xs) : null);

/** Per arm: the idle level of the unfrozen run, every swap window's decision, and the rest windows. */
export function armCells(freePass, frozenPass, arm, periods = PERIODS) {
  const freeIdle = [];
  for (let k = 0; k < periods; k++) freeIdle.push(...windowSamples(freePass, arm, 'Layout', 'swap', k).filter((s) => s[1] === 'idle').map((s) => s[0]));
  const windows = [];
  for (let k = 0; k < periods; k++) {
    const free = windowSamples(freePass, arm, 'Layout', 'swap', k), frozen = windowSamples(frozenPass, arm, 'Layout', 'swap', k);
    const freePaint = windowSamples(freePass, arm, 'Paint', 'swap', k), frozenPaint = windowSamples(frozenPass, arm, 'Paint', 'swap', k);
    windows.push({
      phase: `swap:${k}`, cell: frozenCell(frozen.map((s) => [s[0], s[1]]), freeIdle),
      frozen: frozen.map((s) => ({ n: s[0], bg: s[1], key: s[2] })), free: free.map((s) => ({ n: s[0], bg: s[1], key: s[2] })),
      frozenBg: tally(col(frozen, 1)), freeBg: tally(col(free, 1)),
      frozenMedian: orNull(col(frozen, 0)), freeMedian: orNull(col(free, 0)),
      freeBusyMedian: orNull(free.filter((s) => s[1] === 'busy').map((s) => s[0])), freeIdleMax: free.filter((s) => s[1] === 'idle').length ? Math.max(...free.filter((s) => s[1] === 'idle').map((s) => s[0])) : null,
      frozenPaintMedian: orNull(col(frozenPaint, 0)), freePaintMedian: orNull(col(freePaint, 0)),
    });
  }
  const rest = (pass) => Array.from({ length: periods - 1 }, (_, k) => windowSamples(pass, arm, 'Layout', 'rest', k).map((s) => s[0])).flat();
  const rf = rest(freePass), rz = rest(frozenPass);
  return {
    arm, idleLevel: freeIdle.length ? Math.max(...freeIdle) : null, idleSamples: freeIdle.length, windows,
    rest: { free: { n: rf.length, max: rf.length ? Math.max(...rf) : null, median: orNull(rf) }, frozen: { n: rz.length, max: rz.length ? Math.max(...rz) : null, median: orNull(rz) } },
  };
}

const sum = (xs) => xs.reduce((a, b) => a + b, 0);
const accentAnims = (m) => sum(Object.entries(m ?? {}).filter(([k]) => k.startsWith('hero-accent|')).map(([, v]) => v));

/** The diagnostic captures of one state: per capture the long busy runs and the hero-accent animations before and after. */
export function diagRowsOf(passes) {
  return passes.flatMap((s) => [['crop', s.diag], ...Object.entries(s.diagOther ?? {})].filter(([, d]) => d).map(([arm, d]) => ({
    arm, key: jobKey(s, 'diag'), layoutRows: sum(d.layout), longRuns: longRuns(d.layout), layoutMax: Math.max(...d.layout),
    accentWrites: sum(Object.entries(d.owners).filter(([k]) => k.startsWith('hero-accent:')).map(([, v]) => sum(v))),
    animsBefore: accentAnims(d.before), animsAfter: accentAnims(d.after), probe: d.accent ?? null,
  })));
}

const GROUPS = [['all', () => true], ['aligned (scroll starts in a draw)', (z) => z.align && z.drew], ['natural (start unaligned)', (z) => !z.align]];

function zoneGroup(free, frozen, f) {
  const a = free.filter(f), b = frozen.filter(f);
  const one = (key) => {
    const x = a.map((z) => z[key]), y = b.map((z) => z[key]);
    return { free: { n: x.length, median: orNull(x), min: x.length ? Math.min(...x) : null, max: x.length ? Math.max(...x) : null }, frozen: { n: y.length, median: orNull(y), min: y.length ? Math.min(...y) : null, max: y.length ? Math.max(...y) : null }, verdict: zoneVerdict(x, y), sharePct: x.length && y.length ? sharePct(median2(x), median2(y)) : null };
  };
  return { Layout: one('layout'), Paint: one('paint') };
}

export function freezeAnalysis(docs) {
  const freePass = passesOf(docs, 'free'), frozenPass = passesOf(docs, 'frozen');
  const zf = zonesOf(docs, 'free'), zz = zonesOf(docs, 'frozen');
  const jobs = new Set(docs.flatMap((d) => d.passes.flatMap((p) => [p.cost?.swap, p.cost?.swapFrozen]).filter(Boolean).map(jobBase)));
  return {
    schema: 'fw.webkit.lag.freeze.report/1', jobs: [...jobs].sort(), passes: { free: freePass.length, frozen: frozenPass.length },
    arms: Object.fromEntries(ARMS.map((a) => [a, armCells(freePass, frozenPass, a)])),
    diag: { free: diagRowsOf(freePass), frozen: diagRowsOf(frozenPass) },
    zone: { free: zf, frozen: zz, groups: Object.fromEntries(GROUPS.map(([name, f]) => [name, zoneGroup(zf, zz, f)])) },
  };
}

const cell = (v) => (v === null ? '-' : String(v));
const bgs = (t) => `${t.idle}i ${t.mixed}m ${t.busy}b ${t.unknown}u`;

export function freezeMd(an, sources) {
  const L = [`Sources: ${sources.join('; ')}`, '', `Jobs counted (${an.jobs.length}): ${an.jobs.join(', ')}. Passes: ${an.passes.free} unfrozen, ${an.passes.frozen} frozen. Background of a window: busy = both rest windows next to it have at least ${BUSY_MIN} Layout rows (i idle, m mixed, b busy, u unknown).`, ''];
  for (const arm of ARMS) {
    const a = an.arms[arm];
    L.push(`### ${arm}: Layout rows per swap window, frozen against unfrozen`, '',
      `Idle level (largest unfrozen idle-background Layout count of this arm, all windows): ${cell(a.idleLevel)} (${a.idleSamples} samples). Cell = Lean frozenCell: atIdle when twice the frozen median is not above twice that level.`, '',
      '| window | frozen n | frozen median | frozen bg | unfrozen median | unfrozen busy median | unfrozen idle max | frozen Paint median | unfrozen Paint median | cell |', '|---|---|---|---|---|---|---|---|---|---|');
    for (const w of a.windows) L.push(`| ${w.phase} | ${w.frozen.length} | ${cell(w.frozenMedian)} | ${bgs(w.frozenBg)} | ${cell(w.freeMedian)} | ${cell(w.freeBusyMedian)} | ${cell(w.freeIdleMax)} | ${cell(w.frozenPaintMedian)} | ${cell(w.freePaintMedian)} | ${w.cell} |`);
    L.push('', `Rest windows (Layout rows, all of rest:0..${PERIODS - 2}): frozen n=${a.rest.frozen.n} max ${cell(a.rest.frozen.max)} median ${cell(a.rest.frozen.median)}; unfrozen n=${a.rest.free.n} max ${cell(a.rest.free.max)} median ${cell(a.rest.free.median)}.`, '');
  }
  L.push(`### Diagnostic captures (7 s, 100 ms buckets): long busy runs = runs of at least ${LONG_RUN_MIN} buckets with at least ${BUSY_BUCKET} Layout rows (Lean longRuns)`, '',
    '| state | arm | job/pass/slot | Layout rows | long busy runs | max per bucket | hero-accent writes | hero-accent animations before / after |', '|---|---|---|---|---|---|---|---|');
  for (const st of STATE_NAMES) for (const d of an.diag[st]) L.push(`| ${st} | ${d.arm} | ${d.key} | ${d.layoutRows} | ${d.longRuns} | ${d.layoutMax} | ${d.accentWrites} | ${d.animsBefore} / ${d.animsAfter} |`);
  L.push('', '### hero.exit zone (scroll-A), crop arm: Layout and Paint rows per capture, frozen against unfrozen', '',
    'Share = whole percent of the unfrozen median that the freeze removed (Lean sharePct on twice the medians). Verdict = Lean verdict of the unfrozen against the frozen samples (lower = frozen is lower, ranges separated).', '',
    '| group | kind | unfrozen n | unfrozen median (min..max) | frozen n | frozen median (min..max) | verdict | share |', '|---|---|---|---|---|---|---|---|');
  for (const [name, g] of Object.entries(an.zone.groups)) {
    for (const ty of ['Layout', 'Paint']) {
      const x = g[ty], r = (s) => `${cell(s.median)} (${cell(s.min)}..${cell(s.max)})`;
      L.push(`| ${name} | ${ty} | ${x.free.n} | ${r(x.free)} | ${x.frozen.n} | ${r(x.frozen)} | ${x.verdict} | ${x.sharePct === null ? '-' : `${x.sharePct}%`} |`);
    }
  }
  L.push('', 'Zone captures (every sample):', '', '| state | job/pass/slot | Layout | Paint | accent at start | class changes |', '|---|---|---|---|---|---|');
  for (const st of STATE_NAMES) for (const z of an.zone[st]) L.push(`| ${st} | ${jobKey({ job: z.job }, z.align ? 'aligned' : 'natural')} | ${z.layout} | ${z.paint} | ${z.accentStart} | ${z.accentChanges} |`);
  return L.join('\n');
}
