import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('platform.marquee', {
  offsetLeft: (i) => L.offsetLeft({ w: i.w as number, t: i.t as number }),
  offsetRight: (i) => L.offsetRight({ w: i.w as number, t: i.t as number }),
  running: (i) => L.running({ reduce: i.reduce as boolean }),
  const: () => ({ periodMs: L.PERIOD_MS }),
});

describe('platform.marquee css', () => {
  const css = readFileSync(resolve(__dirname, '../platform/visuals.module.css'), 'utf8');
  it('restates the 90 s linear loop from 0 to -50 %', () => {
    expect(css).toContain('animation: 90s linear infinite');
    expect(css).toMatch(/@keyframes marqueeLeft[\s\S]*?translateX\(0\)[\s\S]*?translateX\(-50%\)/);
  });
});
