import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

const st = (o: Record<string, unknown>) => o as unknown as L.St;
const curves: Record<string, L.Bez> = { easeInOut: L.EASE_IN_OUT, easeStandard: L.EASE_STANDARD };

goldenConformance('overlays.drawer', {
  ease: (i) => L.ease(curves[i.curve as string]!, i.t as number),
  layoutOf: (i) => L.layoutOf(i.w as number),
  hidden: (i) => L.hidden(i.layout as L.Layout, i.pw as number, i.ph as number),
  progress: (i) => L.progress(i.elapsed as number, i.reduced as boolean),
  panelPos: (i) => L.panelPos(i.layout as L.Layout, i.pw as number, i.ph as number, i.shown as boolean, i.elapsed as number, i.reduced as boolean),
  backdropAlpha: (i) => L.backdropAlpha(i.shown as boolean, i.elapsed as number, i.reduced as boolean),
  setOpen: (i) => L.setOpen(st(i.state), i.open as boolean, i.now as number, i.reduced as boolean),
  raf: (i) => L.raf(st(i.state)),
  tick: (i) => L.tick(st(i.state), i.now as number),
  escapeCloses: (i) => L.escapeCloses(st(i.state), i.key as string),
});

describe('overlays.drawer logic', () => {
  it('a full cycle ends at rest after 480 ms', () => {
    const open = L.raf(L.setOpen(L.REST, true, 0, false));
    expect(open).toEqual({ mounted: true, shown: true, rafPending: false, timerAt: null });
    const closing = L.setOpen(open, false, 100, false);
    expect(L.tick(closing, 579).mounted).toBe(true);
    expect(L.tick(closing, 580)).toEqual({ mounted: false, shown: false, rafPending: false, timerAt: null });
  });
  it('reduced motion unmounts at the close itself', () => {
    const open = L.raf(L.setOpen(L.REST, true, 0, true));
    expect(L.tick(L.setOpen(open, false, 100, true), 100)).toEqual(L.REST);
  });
  it('keeps the original quirk: a close before the frame leaves shown set after the unmount', () => {
    const s = L.tick(L.raf(L.setOpen(L.setOpen(L.REST, true, 0, false), false, 1, false)), 481);
    expect(s).toEqual({ mounted: false, shown: true, rafPending: false, timerAt: null });
  });
  it('layout bands sit at 640 and 860', () => {
    expect([640, 641, 860, 861].map(L.layoutOf)).toEqual(['sheet', 'mid', 'mid', 'side']);
  });
});
