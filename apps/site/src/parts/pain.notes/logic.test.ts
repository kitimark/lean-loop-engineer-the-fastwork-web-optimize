import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

const box = (b: unknown) => b as L.Box;

goldenConformance('pain.notes', {
  clampTo: (i) => L.clampTo({ x: i.x as number, lo: i.lo as number, hi: i.hi as number }),
  overlaps: (i) => L.overlaps({ a: box(i.a), b: box(i.b), gap: i.gap as number }),
  avoidBox: (i) => L.avoidBox({ copyTop: i.copyTop as number, copyH: i.copyH as number, stageTop: i.stageTop as number, stageH: i.stageH as number }),
  baseLeft: (i) => L.baseLeft({ stageW: i.stageW as number, leftPx: i.leftPx as number }),
  baseTop: (i) => L.baseTop({ stageH: i.stageH as number, topPx: i.topPx as number }),
  baseLayout: (i) => L.baseLayout({ narrow: i.narrow as boolean, stageW: i.stageW as number, stageH: i.stageH as number }),
  tick: (i) =>
    L.tick({
      visible: i.visible as boolean,
      dragging: i.dragging as boolean,
      extras: i.extras as number,
      narrow: i.narrow as boolean,
      reduced: i.reduced as boolean,
      cardTop: i.cardTop as number | null,
      vh: i.vh as number,
      stageW: i.stageW as number,
      stageH: i.stageH as number,
    }),
  visible: (i) => L.visible({ intersecting: i.intersecting as boolean, ratio: i.ratio as number }),
  mulberry: (i) => L.mulberry({ seed: i.seed as number }),
  idx: (i) => L.idx({ r: i.r as number, n: i.n as number }),
  permute: (i) => L.permute({ draws: i.draws as number[], xs: i.xs as number[] }),
  jit: (i) => L.jit({ c: i.c as number, r: i.r as number, s: i.s as number }),
  pickText: (i) => L.pickText({ used: i.used as number[], r: i.r as number }),
  sceneActive: (i) => L.sceneActive({ top: i.top as number, bottom: i.bottom as number, h: i.h as number }),
  renderObserves: (i) => L.renderObserves({ active: i.active as boolean }),
  rotation: (i) => L.rotation({ j: i.j as number }),
  dragAllowed: (i) => L.dragAllowed({ c860: i.c860 as boolean, button: i.button as number, mouse: i.mouse as boolean }),
  dragPos: (i) => L.dragPos({ origin: i.origin as number, start: i.start as number, cur: i.cur as number, container: i.container as number, sizePct: i.sizePct as number }),
  keyDelta: (i) => L.keyDelta({ key: i.key as string }),
  keyPos: (i) => L.keyPos({ pos: i.pos as number, delta: i.delta as number, sizePct: i.sizePct as number }),
  stickTiming: () => L.stickTiming(),
  session: (i) =>
    L.session({
      stageW: i.stageW as number,
      stageH: i.stageH as number,
      seed: i.seed as number,
      copyTop: i.copyTop as number,
      copyH: i.copyH as number,
      stageTop: i.stageTop as number,
      ticks: i.ticks as number,
    }),
});

describe('pain.notes logic', () => {
  it('the tick stops at 12 extras and an extra is added per tick until then', () => {
    const notes = L.session({ stageW: 780, stageH: 528, seed: 7, copyTop: 100, copyH: 100, stageTop: 0, ticks: 20 });
    expect(notes.filter((n) => n.extra).length).toBeLessThanOrEqual(12);
    expect(notes.filter((n) => !n.extra).length).toBe(5);
  });
  it('the same seed gives the same notes (the original, on Math.random, would not)', () => {
    const a = L.session({ stageW: 780, stageH: 528, seed: 99, copyTop: 100, copyH: 100, stageTop: 0, ticks: 8 });
    const b = L.session({ stageW: 780, stageH: 528, seed: 99, copyTop: 100, copyH: 100, stageTop: 0, ticks: 8 });
    expect(a).toEqual(b);
  });
  it('the CSS module restates the stick animation constants (Lean PainNotes.stickMs, stickScale0, bezier)', () => {
    const css = readFileSync(resolve(__dirname, 'notes.module.css'), 'utf8').replace(/\s+/g, ' ');
    const t = L.stickTiming();
    expect(css).toContain(`animation: ${t.durationMs / 1000}s cubic-bezier(${0.33}, ${t.y1}, ${0.68}, ${t.y2}) forwards`);
    expect(css).toContain(`scale(${t.scaleFrom})`);
  });
});
