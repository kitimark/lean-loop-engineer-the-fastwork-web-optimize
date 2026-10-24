// The finish-zone table of the toolbar-throttle probe (reduction only; every count and the verdict are finish.mjs, the twin of Lean
// Fw.Device.FinishRuns). A pass record is {arm, round, vm, rec, drag} as finish-probe.mjs returns it.
import { reduce, armOf, reversalSum, verdict } from './finish.mjs';
import { ARMS } from './report.mjs';

const MIN_FRAMES = 60;
const MIN_TRAVEL_TENTHS = 1000;
const MIN_TOOLBAR_TENTHS = 20;

/** Frames of a record as Lean reads them: [scrollY, maxY, open]. */
export const framesOf = (rec) => rec.y.map((y, i) => [y, rec.mx[i], rec.o[i] === 1]);

/** Why a pass cannot count, or null when it can. */
export function excludeReason(p) {
  const r = p.rec;
  if (!p.drag || p.drag.code !== 0) return p.drag?.timedOut ? 'touch driver timed out' : 'touch driver failed';
  if (!r || !r.nav) return 'morph nav not found';
  if (r.frames < MIN_FRAMES) return `fewer than ${MIN_FRAMES} frames`;
  if (Math.max(...r.y) - Math.min(...r.y) < MIN_TRAVEL_TENTHS) return 'page moved less than 100 px';
  if (Math.abs((r.start?.scale ?? 1) - 1) > 0.001) return 'page was zoomed';
  return null;
}

/** The toolbar moved when the visual viewport height changed by 2 px or more during the pass. */
export const toolbarMoved = (r) => r.vh.length > 0 && Math.max(...r.vh) - Math.min(...r.vh) >= MIN_TOOLBAR_TENTHS;

/** Counts of one arm over a list of passes. */
export function armRow(passes) {
  const usable = passes.filter((p) => excludeReason(p) === null);
  const results = usable.map((p) => reduce(framesOf(p.rec)));
  const arm = armOf(results);
  return { passes: passes.length, usable: usable.length, excluded: passes.map(excludeReason).filter(Boolean), arm,
    band: arm.runs, frames: arm.frames, short: results.reduce((a, r) => a + r.short, 0), reversals: reversalSum(results),
    reachedPasses: results.filter((r) => r.reached).length, late: results.map((r) => r.late),
    moved: usable.filter((p) => toolbarMoved(p.rec)).length,
    per1000: arm.frames ? Math.round((arm.runs * 10000) / arm.frames) / 10 : null };
}

/** The verdict of the lift arm against each baseline arm. */
export function verdictsOf(passes) {
  const of = (a) => armRow(passes.filter((p) => p.arm === a));
  const lift = of(ARMS.lift);
  return { rewrite: verdict(of(ARMS.base).arm, lift.arm), original: verdict(of(ARMS.ref).arm, lift.arm) };
}

const lateCell = (late) => (late.length ? late.map((n) => (n === null ? '-' : String(n))).join(' ') : '-');

/** Markdown: a row per VM and arm plus the pooled rows, then the verdict lines. `vms` = [{vm, passes}]. */
export function reportMd(vms) {
  const out = ['| job | arm | passes (usable) | finish frames | band runs (5-6 frames) | per 1000 finish frames | runs of 1-9 | reversals while open | passes at the end | open lateness per pass (frames) | passes with toolbar moved |',
    '|---|---|---|---|---|---|---|---|---|---|---|'];
  const cell = (name, arm, passes) => {
    const r = armRow(passes.filter((p) => p.arm === arm));
    out.push(`| ${name} | ${arm} | ${r.passes} (${r.usable}) | ${r.frames} | ${r.band} | ${r.per1000 ?? '-'} | ${r.short} | ${r.reversals} | ${r.reachedPasses} | ${lateCell(r.late)} | ${r.moved} |`);
  };
  for (const { vm, passes } of vms) for (const a of Object.values(ARMS)) cell(vm, a, passes);
  const all = vms.flatMap((x) => x.passes);
  for (const a of Object.values(ARMS)) cell('all jobs', a, all);
  out.push('');
  const line = (name, passes) => { const v = verdictsOf(passes); out.push(`- ${name}: lift against rewrite ${v.rewrite}; lift against original ${v.original}`); };
  for (const { vm, passes } of vms) line(vm, passes);
  line('all jobs', all);
  const why = [...new Set(all.map(excludeReason).filter(Boolean))];
  if (why.length) out.push('', `Excluded passes: ${why.join('; ')}.`);
  return out.join('\n') + '\n';
}
