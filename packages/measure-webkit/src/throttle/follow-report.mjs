// Moving-frame table of the unthrottle-follow comparison (task unthrottle-follow). Counts come from stillruns.mjs (twin of Lean
// Fw.Device.StillRuns: passRows, runsC, countC, exitFramesC); the totals, the per-1000 ratios and the max step are TS stand-ins.
import { passRows, runsC, countC, exitFramesC, BAND_LO, BAND_HI } from './stillruns.mjs';
import { excludeReason } from './report.mjs';

const adapt = (p) => ({ ys: p.rec.y, vs: p.rec.v, vh: p.rec.vh, h: p.rec.start.vh });
const per1000 = (n, d) => (d ? Math.round((n * 10000) / d) / 10 : null);

/** Counts of one arm over its usable passes. Moving = frames of the moving class (toolbar moving); mid-moving = moving frames with the hero value strictly between 0 and 1. */
export function movingRow(passes) {
  const usable = passes.filter((p) => excludeReason(p) === null);
  let moving = 0, mid = 0, stills = 0, band = 0, short = 0, maxStep = 0;
  for (const p of usable) {
    const rows = passRows(adapt(p));
    moving += rows.filter((r) => r[2] === 'moving').length;
    mid += exitFramesC('moving', rows);
    stills += runsC(rows).filter((r) => r.cls === 'moving').length;
    band += countC('moving', BAND_LO, BAND_HI, rows);
    short += countC('moving', 1, 9, rows);
    for (let i = 1; i < rows.length; i++) if (rows[i][2] === 'moving') maxStep = Math.max(maxStep, Math.abs(rows[i][0] - rows[i - 1][0]));
  }
  return { passes: passes.length, usable: usable.length, moving, mid, stills, band, short, maxStepPx: maxStep / 10,
    stillsPer1000Moving: per1000(stills, moving), bandPer1000Mid: per1000(band, mid), shortPer1000Mid: per1000(short, mid) };
}

/** Markdown: a row per job and arm plus the pooled rows. `vms` = [{vm, passes}]. */
export function movingMd(vms, arms) {
  const out = ['', 'Moving-frame table. Moving = frames with the toolbar moving; mid-moving = moving frames with the hero value strictly between 0 and 1.',
    'Still runs = runs of identical scrollY between two moves while moving; band = 5-6 frames, short = 1-9 frames, both counted only inside mid-moving frames.',
    '',
    '| job | arm | passes (usable) | moving frames | mid-moving frames | still runs | per 1000 moving frames | band runs | per 1000 mid-moving frames | short runs | per 1000 mid-moving frames | max step px |',
    '|---|---|---|---|---|---|---|---|---|---|---|---|'];
  const cell = (name, arm, passes) => {
    const r = movingRow(passes.filter((p) => p.arm === arm));
    out.push(`| ${name} | ${arm} | ${r.passes} (${r.usable}) | ${r.moving} | ${r.mid} | ${r.stills} | ${r.stillsPer1000Moving ?? '-'} | ${r.band} | ${r.bandPer1000Mid ?? '-'} | ${r.short} | ${r.shortPer1000Mid ?? '-'} | ${r.maxStepPx} |`);
  };
  for (const { vm, passes } of vms) for (const a of arms) cell(vm, a, passes);
  const all = vms.flatMap((x) => x.passes);
  for (const a of arms) cell('all jobs', a, all);
  return out.join('\n') + '\n';
}
