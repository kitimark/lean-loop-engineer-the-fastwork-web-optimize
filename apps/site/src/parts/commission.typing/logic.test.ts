import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as logic from './logic';

type St = logic.Trig;
const st = (s: St): St => ({ visible: s.visible, token: s.token, since: s.since, frozen: s.frozen, static: s.static });

goldenConformance('commission.typing', {
  viewAt: (i) => logic.viewAt(i.tau),
  chars: (i) => logic.chars(i.tau),
  caretOpaque: (i) => logic.caretOpaque(i.age),
  boilFrame: (i) => logic.boilFrame(i.age),
  visualScale: (i) => logic.visualScale(i.width),
  observe: (i) => logic.observe(st(i.state), i.isIntersecting, i.now, i.reduced),
  picture: (i) => logic.picture(st(i.state), i.now),
});

describe('commission.typing constants (restated from the original)', () => {
  it('the message has 38 characters and the cycle is 6844 ms', () => {
    expect(logic.MSG_LEN).toBe(38);
    expect(logic.PERIOD).toBe(6844);
    expect(logic.M_MSG).toBe(500);
    expect(logic.M_TYPE_END).toBe(1564);
  });
  it('the counters round half up like Math.round', () => {
    expect(logic.round(0.5)).toBe(1);
    expect(logic.round(17.49)).toBe(17);
  });
});
