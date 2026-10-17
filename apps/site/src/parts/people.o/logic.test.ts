import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('people.o', {
  phase: (i) => L.phase({ reduced: i.reduced as boolean, standalone: i.standalone as boolean, t: i.t as number }),
  cardWidth: (i) => L.cardWidth({ vw: i.vw as number }),
  cardLeft: (i) => L.cardLeft({ vw: i.vw as number, x: i.x as number, s: i.s as number }),
  cardTop: (i) => L.cardTop({ vh: i.vh as number, y: i.y as number, z: i.z as number }),
  faceDelay: (i) => L.faceDelay({ i: i.i as number }),
});

describe('people.o plan', () => {
  it('the row opens 120 ms after the stack', () => {
    expect(L.plan({ reduced: false, standalone: false })).toEqual({ stackAt: 1300, expandAt: 1420 });
    expect(L.plan({ reduced: false, standalone: true })).toEqual({ stackAt: null, expandAt: 120 });
    expect(L.plan({ reduced: true, standalone: false })).toEqual({ stackAt: null, expandAt: null });
  });
  it('plan and phase agree', () => {
    const p = L.plan({ reduced: false, standalone: false });
    expect(L.phase({ reduced: false, standalone: false, t: p.stackAt! - 1 }).stack).toBe(false);
    expect(L.phase({ reduced: false, standalone: false, t: p.stackAt! }).stack).toBe(true);
    expect(L.phase({ reduced: false, standalone: false, t: p.expandAt! }).expanded).toBe(true);
  });
});
