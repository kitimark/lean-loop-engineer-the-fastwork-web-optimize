import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('nav.langMenu', {
  step: (i) => L.step({ phase: i.phase as L.Phase, ev: i.ev as L.Ev }),
  flags: (i) => L.flags({ phase: i.phase as L.Phase }),
});

describe('nav.langMenu logic', () => {
  it('toggle cycles closed, open, closing, open', () => {
    expect(L.step({ phase: 'closed', ev: 'toggle' }).phase).toBe('open');
    expect(L.step({ phase: 'open', ev: 'toggle' }).phase).toBe('closing');
    expect(L.step({ phase: 'closing', ev: 'toggle' }).phase).toBe('open');
  });
  it('closed is reached only through the timer', () => {
    for (const phase of ['closed', 'open', 'closing'] as const)
      for (const ev of ['toggle', 'select', 'outside', 'timer'] as const)
        if (L.step({ phase, ev }).phase === 'closed') expect(phase === 'closed' || (phase === 'closing' && ev === 'timer')).toBe(true);
  });
});
