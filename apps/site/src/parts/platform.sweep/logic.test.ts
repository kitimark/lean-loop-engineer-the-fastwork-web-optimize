import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('platform.sweep', {
  pos: (i) => L.pos({ t: i.t as number }),
  phase: (i) => L.phase({ t: i.t as number }),
  color: (i) => [...L.color({ u: i.u as number })],
  active: (i) => L.active({ reduce: i.reduce as boolean }),
  const: () => ({ periodMs: L.PERIOD_MS, stops: [...L.STOPS] }),
});

describe('platform.sweep css', () => {
  const css = readFileSync(resolve(__dirname, '../platform/sweep.module.css'), 'utf8');
  it('restates the 4 s linear loop and the 300 % gradient', () => {
    expect(css).toContain('animation: 4s linear infinite');
    expect(css).toContain('background-size: 300% 100%');
    expect(css).toContain('linear-gradient(90deg, #fff 0 33.33%, #82bcff 40%, #2483ff 45%, #ff66f4 50%, #ff3029 55%, #fe7b02 60%, #fff 66.67% 100%)');
    expect(css).toContain('background-position: 100%');
  });
  it('the pass starts and ends white', () => {
    for (const v of [0, 0.5, 1]) {
      for (const c of [L.color({ u: (v + 2 * 1) / 3 }), L.color({ u: (v + 2 * 0) / 3 })]) for (const ch of c) expect(ch).toBeGreaterThanOrEqual(254);
    }
  });
});
