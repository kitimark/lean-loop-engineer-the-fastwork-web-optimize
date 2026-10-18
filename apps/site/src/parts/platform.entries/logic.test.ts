import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('platform.entries', {
  ease: (i) => L.ease({ x: i.x as number }),
  progress: (i) => L.progress({ entry: i.entry as string, t: i.t as number }),
  countAt: (i) => L.countAt({ n: i.n as number, t: i.t as number }),
  askView: (i) => L.askView({ lens: i.lens as number[], t: i.t as number }),
  const: () => L.constants(),
});

describe('platform.entries css', () => {
  const css = readFileSync(resolve(__dirname, '../platform/visuals.module.css'), 'utf8');
  const camel = (s: string) => s.replace(/-([a-z])/g, (_, c: string) => c.toUpperCase());
  it('every entry uses the spring curve and has its keyframes', () => {
    expect(css).toContain('cubic-bezier(0.16, 1, 0.3, 1)');
    for (const e of Object.values(L.TABLE)) expect(css, e.keyframes).toContain(`@keyframes ${camel(e.keyframes)}`);
  });
});
