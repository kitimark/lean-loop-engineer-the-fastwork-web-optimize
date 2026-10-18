import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';
import { PIECES } from './data';

goldenConformance('hero.orbit', {
  phase: (i) => L.phase({ e: i.e as number }),
  angleDeg: (i) => L.angleDeg({ e: i.e as number }),
  radius: (i) => L.radius({ e: i.e as number }),
  blur: (i) => L.blur({ e: i.e as number }),
  enterDelay: (i) => L.enterDelay({ k: i.k as number }),
  push: (i) => L.push({ w: i.w as number }),
  scatter: (i) => L.scatter({ left: i.left as number, top: i.top as number }),
  ringScale: (i) => L.ringScale({ width: i.width as number }),
  leftEdge: (i) =>
    L.leftEdge({ isLeft: i.isLeft as boolean, left: i.left as number, right: i.right as number, width: i.width as number, vw: i.vw as number }),
  ringIndex: () => L.ringIndex(PIECES),
  place: (i) =>
    L.place({
      left: i.left as number,
      top: i.top as number,
      width: i.width as number,
      height: i.height as number,
      idx: i.idx as number,
      n: i.n as number,
      e: i.e as number,
      expanded: i.expanded as boolean,
    }),
});

describe('hero.orbit logic', () => {
  it('the timer is the last card end and the expand is the first card start', () => {
    expect(L.enterDelay({ k: 4 }) + 1700).toBe(L.SPLASH_END);
    expect(L.enterDelay({ k: 0 }) + 0.68 * 1700).toBeCloseTo(L.EXPAND_AT, 9);
  });
  it('the move joins continuously', () => {
    expect(L.radius({ e: 1380 })).toBe(248);
    expect(L.blur({ e: 1380 })).toBe(0);
    expect(L.angleDeg({ e: 1380 })).toBeCloseTo(1380 * L.OMEGA + 140, 9);
  });
  it('restates the first prerendered card of the original (start offset 831, -4, 36 deg)', () => {
    const idx = L.ringIndex(PIECES)[0]!;
    const p = PIECES[0]!;
    expect(L.place({ left: p.left, top: p.top, width: p.width, height: p.height, idx, n: 1512, e: 0, expanded: false })).toEqual({
      x: 831,
      y: -4,
      rotTenths: 360,
    });
  });
});
