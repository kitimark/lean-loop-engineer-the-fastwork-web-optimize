import { passRows, runsC, countC, exitFramesC, BAND_LO, BAND_HI } from './stillruns.mjs';
import { excludeReason } from './report.mjs';

const adapt = (p) => ({ ys: p.rec.y, vs: p.rec.v, vh: p.rec.vh, h: p.rec.start.vh });
const per1000 = (n, d) => (d ? Math.round((n * 10000) / d) / 10 : null);

export function movingRow(passes) {
  const usable = passes.filter((p) => excludeReason(p) === null);
  let moving = 0, mid = 0, stills = 0, band = 0, short = 0, maxStep = 0, evFrames = 0, evTotal = 0, evSeen = true, pStills = 0, pBand = 0;
  for (const p of usable) {
    const rows = passRows(adapt(p));
    moving += rows.filter((r) => r[2] === 'moving').length;
    mid += exitFramesC('moving', rows);
    stills += runsC(rows).filter((r) => r.cls === 'moving').length;
    band += countC('moving', BAND_LO, BAND_HI, rows);
    short += countC('moving', 1, 9, rows);
    const vrows = rows.map((r) => [r[1], r[1], r[2]]);
    pStills += countC('moving', 1, 1e9, vrows);
    pBand += countC('moving', BAND_LO, BAND_HI, vrows);
    for (let i = 1; i < rows.length; i++) if (rows[i][2] === 'moving') maxStep = Math.max(maxStep, Math.abs(rows[i][0] - rows[i - 1][0]));
    const ev = p.rec.ev;
    if (!Array.isArray(ev) || ev.length !== p.rec.y.length) { evSeen = false; continue; }
    for (let i = 1; i < rows.length; i++) if (rows[i][2] === 'moving') { evTotal += ev[i] - ev[i - 1]; if (ev[i] > ev[i - 1]) evFrames++; }
  }
  return { passes: passes.length, usable: usable.length, moving, mid, stills, band, short, maxStepPx: maxStep / 10, partStills: pStills, partBand: pBand,
    partStillsPer1000Mid: per1000(pStills, mid), partBandPer1000Mid: per1000(pBand, mid),
    evFrames: evSeen ? evFrames : null, evTotal: evSeen ? evTotal : null, evFramesPer1000Moving: evSeen ? per1000(evFrames, moving) : null,
    stillsPer1000Moving: per1000(stills, moving), bandPer1000Mid: per1000(band, mid), shortPer1000Mid: per1000(short, mid) };
}

export function movingMd(vms, arms) {
  const out = ['', 'Moving-frame table. Moving = frames with the toolbar moving; mid-moving = moving frames with the hero value strictly between 0 and 1.',
    'Still runs = runs of identical scrollY between two moves while moving; part still runs = runs of an unchanged hero value (the part output) among mid-moving frames; band = 5-6 frames, short = 1-9 frames, both counted only inside mid-moving frames.',
    '',
    '| job | arm | passes (usable) | moving frames | mid-moving frames | still runs | per 1000 moving frames | band runs | per 1000 mid-moving frames | short runs | per 1000 mid-moving frames | max step px | part still runs | per 1000 mid-moving frames | part band runs | per 1000 mid-moving frames | scroll events | moving frames with a scroll event | per 1000 moving frames |',
    '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'];
  const cell = (name, arm, passes) => {
    const r = movingRow(passes.filter((p) => p.arm === arm));
    out.push(`| ${name} | ${arm} | ${r.passes} (${r.usable}) | ${r.moving} | ${r.mid} | ${r.stills} | ${r.stillsPer1000Moving ?? '-'} | ${r.band} | ${r.bandPer1000Mid ?? '-'} | ${r.short} | ${r.shortPer1000Mid ?? '-'} | ${r.maxStepPx} | ${r.partStills} | ${r.partStillsPer1000Mid ?? '-'} | ${r.partBand} | ${r.partBandPer1000Mid ?? '-'} | ${r.evTotal ?? '-'} | ${r.evFrames ?? '-'} | ${r.evFramesPer1000Moving ?? '-'} |`);
  };
  for (const { vm, passes } of vms) for (const a of arms) cell(vm, a, passes);
  const all = vms.flatMap((x) => x.passes);
  for (const a of arms) cell('all jobs', a, all);
  return out.join('\n') + '\n';
}
