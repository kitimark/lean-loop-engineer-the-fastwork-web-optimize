// sim-end-floor: the end-of-page idle style-recalc rate per arm on the iOS Simulator (task sim-end-floor).
//
// TS STAND-IN of lean/Fw/Device/SimEndFloor.lean: BAND, WIN_RAF, MIN_RENDERED, MIN_ROUNDS, rate, readable, flagV, pair, cmp and the
// overall lines are checked against packages/contracts/golden/device/sim-end-floor.jsonl (test/sim-end-floor.test.mjs). The page script
// and the Timeline tally only count; they decide nothing.
import { markTime } from './reduce.mjs';

export const BAND = 10;
export const WIN_RAF = 360;
export const MIN_RENDERED = 288;
export const MIN_ROUNDS = 2;

const V2P = 'engine.scroll:unthrottle,hero.exit:threaded,platform:faded-pause';
/** The four arms, in the Lean `Round` order. `search` is the query the prerendered build is asked for ('' = the default config). */
export const ARMS = Object.freeze([
  { id: 'base', fw: '', search: '' },
  { id: 'v2p', fw: V2P, search: `?fw=${V2P}` },
  { id: 'minusT', fw: 'engine.scroll:unthrottle,platform:faded-pause', search: '?fw=engine.scroll:unthrottle,platform:faded-pause' },
  { id: 'minusU', fw: 'hero.exit:threaded,platform:faded-pause', search: '?fw=hero.exit:threaded,platform:faded-pause' },
]);
/** The two reads of one load: at the end of the page after the jump there settled (`end`), and after a scroll up by one viewport and back to the end settled (`back`). */
export const STAGES = Object.freeze(['end', 'back']);
/** The `--config` queries the site build needs (the default config is always built). */
export const BUILD_SEARCHES = Object.freeze(ARMS.filter((a) => a.search !== '').map((a) => a.search));

export const rate = (w) => (w.raf === 0 ? 0 : Math.floor((w.recalcs * 100) / w.raf));
export const readable = (w) => w.raf === WIN_RAF && MIN_RENDERED <= w.rendered;

export function flagV(full, minusF, base) {
  if (!(readable(full) && readable(minusF) && readable(base))) return 'unreadable';
  if (rate(full) <= BAND) return 'noFloor';
  if (BAND < rate(base)) return 'baseFloor';
  if (rate(minusF) <= BAND) return 'carries';
  if (rate(minusF) + BAND < rate(full)) return 'partial';
  return 'none';
}

export function pair(vt, vu) {
  if (vt === 'unreadable' || vu === 'unreadable') return 'unreadable';
  if (vt === 'noFloor' || vu === 'noFloor') return 'noFloor';
  if (vt === 'baseFloor' || vu === 'baseFloor') return 'baseFloor';
  if (vt === 'carries' && vu === 'carries') return 'both';
  if (vt === 'carries' && vu === 'none') return 'threaded';
  if (vt === 'none' && vu === 'carries') return 'unthrottle';
  if (vt === 'none' && vu === 'none') return 'sharedOrOther';
  return 'mixed';
}

/** The WKTR result (threaded-animations pref off): the floor with v2p, neither removal cut it. */
export const WKTR_PAIR = 'sharedOrOther';
export const cmp = (p) => (p === 'unreadable' ? 'unread' : p === WKTR_PAIR ? 'same' : 'different');

/** TS stand-in of EndWktr.overallNames. */
export function overallNames(ns) {
  if (ns.length < MIN_ROUNDS) return 'inconclusive';
  return ns.every((n) => n === ns[0]) ? ns[0] : 'mixed';
}
export const overallFlag = (vs) => overallNames(vs.filter((v) => v !== 'unreadable'));
export const overallPair = (ps) => overallNames(ps.filter((p) => p !== 'unreadable'));

/** The verdicts of one round (arms `base`, `v2p`, `minusT`, `minusU` of one stage, each a window). */
export function roundVerdict(r) {
  const vt = flagV(r.v2p, r.minusT, r.base);
  const vu = flagV(r.v2p, r.minusU, r.base);
  const p = pair(vt, vu);
  return { threaded: vt, unthrottle: vu, pair: p, cmp: cmp(p) };
}

const TALLY = ['RecalculateStyles', 'RenderingFrame', 'Layout', 'Paint', 'Composite', 'ScheduleStyleRecalculation', 'FireAnimationFrame'];

/**
 * The window of one stage from the Timeline rows and the page result: rows whose start lies in [mark a, mark b) of the stage. The marks are
 * the page's `performance.mark('ef:a-<stage>')` and `ef:b-<stage>` (TimeStamp records on the Timeline clock). `raf` is what the page counted.
 */
export function windowOf(rows, stage, raf) {
  const a = markTime(rows, `ef:a-${stage}`);
  const b = markTime(rows, `ef:b-${stage}`);
  const t = Object.fromEntries(TALLY.map((k) => [k, 0]));
  if (a === null || b === null || !(b > a)) return { raf, rendered: 0, recalcs: 0, marks: false, tally: t, spanMs: null };
  for (const [type, start] of rows) if (type in t && start >= a && start < b) t[type]++;
  return { raf, rendered: t.RenderingFrame, recalcs: t.RecalculateStyles, marks: true, tally: t, spanMs: Math.round((b - a) * 1000) };
}

/** The in-page script of one load: scroll to the end, settle, read the `end` window, go up one viewport and back, settle, read the `back` window, then list the animations. */
export const endFloorJs = ({ raf = WIN_RAF, settleMs = 2500, backMs = 1500 } = {}) => `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => new Promise((r) => requestAnimationFrame(r));
  const mark = (n) => { performance.clearMarks(n); performance.mark(n); return performance.getEntriesByName(n).pop().startTime; };
  const root = document.documentElement;
  const win = async (stage) => {
    await frame();
    const a = mark('ef:a-' + stage);
    let n = 0;
    for (; n < ${raf}; n++) await frame();
    const b = mark('ef:b-' + stage);
    return { raf: n, pageMs: Math.round(b - a), cls: root.className, y: Math.round(scrollY) };
  };
  const out = {};
  scrollTo({ top: root.scrollHeight - innerHeight, behavior: 'instant' });
  await frame(); await frame();
  await sleep(${settleMs});
  out.end = await win('end');
  scrollTo({ top: Math.max(0, root.scrollHeight - 2 * innerHeight), behavior: 'instant' });
  await frame(); await frame();
  await sleep(${backMs});
  scrollTo({ top: root.scrollHeight - innerHeight, behavior: 'instant' });
  await frame(); await frame();
  await sleep(${settleMs});
  out.back = await win('back');
  const kind = (t) => (!t ? 'none' : window.ViewTimeline && t instanceof ViewTimeline ? 'view' : window.ScrollTimeline && t instanceof ScrollTimeline ? 'scroll' : 'document');
  const an = document.getAnimations();
  const by = {};
  for (const a of an) { const k = kind(a.timeline) + ':' + a.playState; by[k] = (by[k] || 0) + 1; }
  out.anims = { total: an.length, by, viewTimeline: !!window.ViewTimeline, scrollTimeline: !!window.ScrollTimeline };
  out.maxY = Math.round(root.scrollHeight - innerHeight);
  return out;
})()`;

/** The rows file: one line per round, arm and stage. */
export function rowLines(raw) {
  const out = [];
  for (const r of raw.rounds) {
    for (const stage of STAGES) {
      for (const a of ARMS) {
        const w = r.arms[a.id]?.[stage];
        if (!w) { out.push(`round ${r.round} ${stage} ${a.id}: unread`); continue; }
        const t = w.tally;
        out.push(`round ${r.round} ${stage} ${a.id}: raf ${w.raf} rendered ${w.rendered} recalcs ${w.recalcs} rate ${rate(w)} per 100 (layout ${t.Layout} paint ${t.Paint} composite ${t.Composite} schedule ${t.ScheduleStyleRecalculation} rafFire ${t.FireAnimationFrame}) html "${w.cls ?? ''}" y ${w.y ?? '-'} anims ${JSON.stringify(r.arms[a.id].anims ?? null)}`);
      }
    }
  }
  return out;
}

/** The verdict file: per stage and round the flag verdicts, the pair and the WKTR comparison, then the overall lines. */
export function verdictLines(raw) {
  const out = [];
  out.push(`sim-end-floor band ${BAND} per 100, window ${WIN_RAF} rAF callbacks, rendered frames at least ${MIN_RENDERED}, rounds ${raw.rounds.length}`);
  const meta = raw.meta ?? {};
  out.push(`runtime ${meta.runtime ?? '-'} ua ${meta.ua ?? '-'}`);
  for (const stage of STAGES) {
    const per = [];
    for (const r of raw.rounds) {
      const arm = (id) => r.arms[id]?.[stage] ?? { raf: 0, rendered: 0, recalcs: 0 };
      const v = roundVerdict({ base: arm('base'), v2p: arm('v2p'), minusT: arm('minusT'), minusU: arm('minusU') });
      per.push(v);
      out.push(`${stage} round ${r.round}: rates base ${rate(arm('base'))} v2p ${rate(arm('v2p'))} minusT ${rate(arm('minusT'))} minusU ${rate(arm('minusU'))}; hero.exit:threaded ${v.threaded}; engine.scroll:unthrottle ${v.unthrottle}; pair ${v.pair}; vs WKTR ${v.cmp}`);
    }
    out.push(`${stage} overall hero.exit:threaded: ${overallFlag(per.map((x) => x.threaded))}`);
    out.push(`${stage} overall engine.scroll:unthrottle: ${overallFlag(per.map((x) => x.unthrottle))}`);
    const op = overallPair(per.map((x) => x.pair));
    out.push(`${stage} overall pair: ${op}`);
    out.push(`${stage} overall vs WKTR: ${op === 'inconclusive' || op === 'mixed' ? op : cmp(op)}`);
  }
  return out;
}
