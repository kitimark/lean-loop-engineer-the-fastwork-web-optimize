import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import * as L from './logic';
import { createExitDriver } from './driver';

describe('hero.exit logic', () => {
  it('exitOpacity maps track scroll to 1..0 and clamps', () => {
    // track 200vh at vh=800: range 800
    expect(L.exitOpacity(0, 1600, 800)).toBe(1);
    expect(L.exitOpacity(100, 1600, 800)).toBe(1); // below the top: clamped
    expect(L.exitOpacity(-400, 1600, 800)).toBe(0.5);
    expect(L.exitOpacity(-800, 1600, 800)).toBe(0);
    expect(L.exitOpacity(-5000, 1600, 800)).toBe(0);
    expect(L.exitRange(100, 800)).toBe(1); // degenerate track: n >= 1
    expect(L.exitOpacity(-3, 100, 800)).toBe(0);
  });
  it('pointer threshold is strict at 0.05', () => {
    expect(L.pointerOff(0.0499)).toBe(true);
    expect(L.pointerOff(0.05)).toBe(false);
  });
  it('reduced motion ignores the rect', () => {
    expect(L.exitFrame(true, -9999, 1600, 800)).toEqual({ opacity: 1, pointerNone: false });
    expect(L.exitFrame(false, -800, 1600, 800)).toEqual({ opacity: 0, pointerNone: true });
  });
  it('geometry', () => {
    expect(L.trackHeightPx(800, false)).toBe(1600);
    expect(L.trackHeightPx(800, true)).toBeNull();
    expect(L.heroHeightPx(600, false)).toBe(680);
    expect(L.heroHeightPx(600, true)).toBe(600);
    expect(L.heroHeightPx(900, false)).toBe(900);
  });
  it('calc() consumers', () => {
    expect(L.exitScatter(0.25)).toBe(0.75);
    expect(L.copyOpacity(1, 0.4)).toBeCloseTo(0.4);
    expect(L.copyBlurPx(1, 0.5, false)).toBe(9);
    expect(L.copyBlurPx(0, 0, false)).toBe(16);
    expect(L.copyBlurPx(0, 1, true)).toBe(0);
    expect(L.copyTranslateYPx(1, 1, false)).toBe(-10);
    expect(L.copyTranslateYPx(1, 1, true)).toBe(-8);
    expect(L.cueTranslateYPx(1, false)).toBe(0);
    expect(L.cueTranslateYPx(1, true)).toBe(-10);
    expect(L.cueBlurPx(0.5)).toBe(9);
    expect(L.cardOpacity(1)).toBeCloseTo(0.65);
    expect(L.cardTranslate(1, 50, 0.5, 100)).toBe(50);
    expect(L.cardTranslate(0, 50, 0, 100)).toBe(50);
  });
});

describe('exit driver', () => {
  const mk = (rect: { top: number; height: number }, reduced: boolean) => {
    const writes: [string, string][] = [];
    let reads = 0;
    const hero = { style: { pointerEvents: 'x', setProperty: (n: string, v: string) => void writes.push([n, v]) } };
    const d = createExitDriver({
      track: { getBoundingClientRect: () => (reads++, rect) },
      hero,
      reduced: () => reduced,
    });
    return { d, writes, hero, reads: () => reads };
  };
  it('reads in read(), writes only in the returned writer', () => {
    const t = mk({ top: -400, height: 1600 }, false);
    const w = t.d.read(800);
    expect(t.reads()).toBe(1);
    expect(t.writes).toEqual([]);
    w();
    expect(t.writes).toEqual([['--exit-opacity', '0.5']]);
    expect(t.hero.style.pointerEvents).toBe('');
  });
  it('past the end disables pointer events; reduced skips the rect read', () => {
    const a = mk({ top: -900, height: 1600 }, false);
    a.d.read(800)();
    expect(a.hero.style.pointerEvents).toBe('none');
    const b = mk({ top: -900, height: 1600 }, true);
    b.d.read(800)();
    expect(b.reads()).toBe(0);
    expect(b.writes).toEqual([['--exit-opacity', '1']]);
  });
});

describe('hero.exit golden conformance', () => {
  const file = resolve(__dirname, '../../../../../packages/contracts/golden/parts/hero.exit.jsonl');
  it.skipIf(!existsSync(file))('every golden line matches', () => {
    const fns = L as unknown as Record<string, (...a: unknown[]) => unknown>;
    for (const line of readFileSync(file, 'utf8').split('\n').filter(Boolean)) {
      const { fn, in: input, out } = JSON.parse(line) as { fn: string; in: Record<string, unknown>; out: unknown };
      expect(fns[fn], `unknown fn ${fn}`).toBeTypeOf('function');
      expect(fns[fn]!(...L.GOLDEN_ARGS[fn]!.map((k) => input[k])), line).toEqual(out);
    }
  });
});
