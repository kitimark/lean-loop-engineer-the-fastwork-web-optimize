import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('people.deck', {
  ae: (i) => L.ae({ x: i.x as number }),
  ranges: (i) => L.ranges({ vh: i.vh as number, n: i.n as number }),
  progress: (i) => L.progress({ top: i.top as number, total: i.total as number }),
  fit: (i) => L.fit({ vw: i.vw as number, deckW: i.deckW as number }),
  de: (i) => L.de({ left: i.left as number, width: i.width as number, s: i.s as number, o: i.o as number }),
  fe: (i) => L.fe({ deckW: i.deckW as number, left: i.left as number, width: i.width as number, s: i.s as number, o: i.o as number }),
  tgt: (i) => L.tgt({ y: i.y as number, shrink: i.shrink as number, prof: i.prof as number, fit: i.fit as number, delta: i.delta as number }),
  step: (i) => L.step({ snap: i.snap as number, v: i.v as number, t: i.t as number }),
  settled: (i) => L.settled({ snap: i.snap as number, v: i.v as number, t: i.t as number }),
  rnd: (i) => L.rnd({ x: i.x as number }),
  pe: (i) => L.pe({ cnt: i.cnt as number, k: i.k as number, cur: i.cur as number }),
  gotoTop: (i) => L.gotoTop({ showcaseY: i.showcaseY as number, shrink: i.shrink as number, prof: i.prof as number, cnt: i.cnt as number, idx: i.idx as number }),
  nearest: (i) => L.nearest({ target: i.target as number, centers: i.centers as number[] }),
});

describe('people.deck logic', () => {
  it('six professions scroll 3.15 viewport heights in total', () => {
    expect(L.ranges({ vh: 1000, n: 6 }).total).toBeCloseTo(3150, 9);
  });
  it('the shrink ends exactly where the profession range starts', () => {
    const t = L.tgt({ y: 1450, shrink: 1450, prof: 1700, fit: 1.1, delta: -300 });
    expect(t).toEqual({ scale: 1, offset: 0, origin: 100, railIn: true, k: 0 });
    const a = L.tgt({ y: 0, shrink: 1450, prof: 1700, fit: 1.1, delta: -300 });
    expect(a).toEqual({ scale: 1.1, offset: -300, origin: 50, railIn: false, k: 0 });
  });
  it('the pick holds inside the 0.85 band and moves past it', () => {
    expect(L.pe({ cnt: 6, k: 0.16, cur: 0 })).toBe(0);
    expect(L.pe({ cnt: 6, k: 0.17, cur: 0 })).toBe(1);
    expect(L.pe({ cnt: 6, k: 0.2, cur: 1 })).toBe(1);
  });
});
