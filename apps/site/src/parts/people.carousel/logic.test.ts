import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('people.carousel', {
  restWindow: (i) => L.restWindow({ x: i.x as number }),
  swapWindow: (i) => L.swapWindow({ x: i.x as number }),
  afterRest: (i) => L.afterRest({ x: i.x as number, swapping: i.swapping as boolean, active: i.active as boolean }),
  afterSwap: (i) => L.afterSwap({ x: i.x as number, swapping: i.swapping as boolean, active: i.active as boolean }),
  stateAt: (i) => L.stateAt({ t: i.t as number }),
  rowPx: (i) => L.rowPx({ k: i.k as number }),
});

describe('people.carousel loop', () => {
  it('a continuously active run follows the closed form', () => {
    let s = L.START;
    for (let k = 0; k < 14; k++) {
      expect(L.stateAt({ t: L.PERIOD_MS * k })).toEqual(s);
      s = L.afterSwap({ ...L.afterRest({ ...s, active: true }), active: true });
    }
  });
  it('the swap drops the exit avatar and lands on the next rest window', () => {
    for (let x = 0; x < 12; x++) expect(L.swapWindow({ x }).slice(1)).toEqual(L.restWindow({ x: (x + 1) % L.RING }));
  });
  it('a lost activity never advances the ring', () => {
    expect(L.afterRest({ x: 2, swapping: false, active: false })).toEqual({ x: 2, swapping: false });
    expect(L.afterSwap({ x: 2, swapping: true, active: false })).toEqual({ x: 2, swapping: false });
  });
});
