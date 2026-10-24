// The still-run table of the toolbar-throttle probe (reduction only; every count and the verdict are stillruns.mjs, the twin of
// Lean Fw.Device.StillRuns). A pass record is {arm, round, vm, rec, drag} as probe.mjs returns it.
import { runs, bandRuns, shortRuns, exitFrames, partSeries, verdict } from './stillruns.mjs';

export const ARMS = Object.freeze({ base: 'rewrite', lift: 'lift', ref: 'original' });
export const SHIPPED_ARM = 'unthrottle';
const MIN_FRAMES = 30;
const MIN_TRAVEL_PX = 100;
const MIN_TOOLBAR_TENTHS = 20;

/** Why a pass cannot count, or null when it can. */
export function excludeReason(p) {
  const r = p.rec;
  if (!p.drag || p.drag.code !== 0) return p.drag?.timedOut ? 'touch driver timed out' : 'touch driver failed';
  if (!r || !r.hero) return 'hero value not found';
  if (r.frames < MIN_FRAMES) return `fewer than ${MIN_FRAMES} frames`;
  if (r.maxY < MIN_TRAVEL_PX) return `page moved less than ${MIN_TRAVEL_PX} px`;
  if (Math.abs((r.start?.scale ?? 1) - 1) > 0.001) return 'page was zoomed';
  return null;
}

/** The toolbar moved when the visual viewport height changed by 2 px or more during the pass. */
export const toolbarMoved = (r) => r.vh.length > 0 && Math.max(...r.vh) - Math.min(...r.vh) >= MIN_TOOLBAR_TENTHS;

/** Counts of one arm over a list of passes. */
export function armRow(passes) {
  const usable = passes.filter((p) => excludeReason(p) === null);
  let band = 0, short = 0, frames = 0, moved = 0, jumps = [];
  for (const p of usable) {
    const rows = partSeries(p.rec.y, p.rec.v);
    band += bandRuns(rows); short += shortRuns(rows); frames += exitFrames(rows);
    if (toolbarMoved(p.rec)) moved++;
    jumps = jumps.concat(runs(rows).filter((x) => x.mid && x.k >= 5 && x.k <= 6).map((x) => x.jump));
  }
  const excluded = passes.filter((p) => excludeReason(p) !== null).map((p) => excludeReason(p));
  return { passes: passes.length, usable: usable.length, excluded, band, short, frames, moved,
    per1000: frames ? Math.round((band * 10000) / frames) / 10 : null, heights: usable.map((p) => p.rec.start.vh) };
}

export function verdictOf(passes, flagArm = ARMS.lift) {
  const base = armRow(passes.filter((p) => p.arm === ARMS.base));
  const lift = armRow(passes.filter((p) => p.arm === flagArm));
  const v = verdict([...base.heights, ...lift.heights], { runs: base.band, frames: base.frames }, { runs: lift.band, frames: lift.frames });
  return { verdict: v, base, lift };
}

/** Markdown: one table, a row per VM and arm plus the pooled rows, then the verdict lines. `vms` = [{vm, runId?, passes}]. */
export function reportMd(vms) {
  const out = ['| job | arm | passes (usable) | exit frames | still runs of 5-6 frames | per 1000 exit frames | still runs of 1-9 | passes with toolbar moved |',
    '|---|---|---|---|---|---|---|---|'];
  const cell = (name, arm, passes) => {
    const r = armRow(passes.filter((p) => p.arm === arm));
    out.push(`| ${name} | ${arm} | ${r.passes} (${r.usable}) | ${r.frames} | ${r.band} | ${r.per1000 ?? '-'} | ${r.short} | ${r.moved} |`);
  };
  const all = vms.flatMap((x) => x.passes);
  const shipped = all.some((p) => p.arm === SHIPPED_ARM);
  const arms = shipped ? [...Object.values(ARMS), SHIPPED_ARM] : Object.values(ARMS);
  for (const { vm, passes } of vms) for (const a of arms) cell(vm, a, passes);
  for (const a of arms) cell('all jobs', a, all);
  out.push('');
  for (const { vm, passes } of vms) out.push(`- ${vm}: ${verdictOf(passes).verdict}`);
  out.push(`- all jobs: ${verdictOf(all).verdict}`);
  if (shipped) {
    for (const { vm, passes } of vms) out.push(`- ${vm} (${SHIPPED_ARM}): ${verdictOf(passes, SHIPPED_ARM).verdict}`);
    out.push(`- all jobs (${SHIPPED_ARM}): ${verdictOf(all, SHIPPED_ARM).verdict}`);
  }
  const why = [...new Set(all.map(excludeReason).filter(Boolean))];
  if (why.length) out.push('', `Excluded passes: ${why.join('; ')}.`);
  return out.join('\n') + '\n';
}
