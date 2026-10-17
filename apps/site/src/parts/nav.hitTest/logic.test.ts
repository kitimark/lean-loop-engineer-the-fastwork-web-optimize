import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import * as logic from './logic';

const GOLDEN = new URL('../../../../../packages/contracts/golden/parts/nav.hitTest.jsonl', import.meta.url);

describe.skipIf(!existsSync(GOLDEN))('nav.hitTest golden conformance', () => {
  const lines = existsSync(GOLDEN) ? readFileSync(GOLDEN, 'utf8').split('\n').filter((l) => l.trim()) : [];
  it.each(lines.map((l, i) => [i + 1, JSON.parse(l) as { fn: string; in: Record<string, unknown>; out: unknown }] as const))(
    'line %i',
    (_i, v) => {
      const f = (logic as Record<string, unknown>)[v.fn] as (...a: unknown[]) => unknown;
      expect(typeof f, `unknown fn ${v.fn}`).toBe('function');
      const i = v.in;
      const out =
        v.fn === 'hitPoint' ? f(i.rect)
        : v.fn === 'classifyHit' ? f(i)
        : v.fn === 'firstOutside' ? f(i.insideNav)
        : v.fn === 'changed' ? f(i.prev, i.next)
        : undefined;
      expect(out).toEqual(v.out);
    },
  );
});

describe('nav.hitTest logic', () => {
  it('probe point: centre x, centre of the first 64 px', () => {
    expect(logic.hitPoint({ left: 10, top: 8, width: 300, height: 56 })).toEqual({ x: 160, y: 36 });
    expect(logic.hitPoint({ left: 0, top: 0, width: 100, height: 800 })).toEqual({ x: 50, y: 32 });
  });
  it('classify: exclude beats include, shrinking last', () => {
    const c = (hasElement: boolean, inExclude: boolean, inInclude: boolean, inShrinking: boolean) =>
      logic.classifyHit({ hasElement, inExclude, inInclude, inShrinking });
    expect(c(false, false, true, true)).toBe(false);
    expect(c(true, true, true, true)).toBe(false);
    expect(c(true, false, true, false)).toBe(true);
    expect(c(true, false, false, true)).toBe(true);
    expect(c(true, false, false, false)).toBe(false);
  });
  it('first element outside the nav', () => {
    expect(logic.firstOutside([true, true, false, false])).toBe(2);
    expect(logic.firstOutside([true])).toBe(-1);
    expect(logic.firstOutside([])).toBe(-1);
  });
  it('write on change', () => {
    expect(logic.changed(false, true)).toBe(true);
    expect(logic.changed(true, true)).toBe(false);
  });
});
