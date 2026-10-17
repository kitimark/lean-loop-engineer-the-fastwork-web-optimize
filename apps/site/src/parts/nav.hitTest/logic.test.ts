import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as logic from './logic';

goldenConformance('nav.hitTest', {
  hitPoint: (i) => logic.hitPoint(i.rect),
  classifyHit: (i) => logic.classifyHit(i as Parameters<typeof logic.classifyHit>[0]),
  firstOutside: (i) => logic.firstOutside(i.insideNav),
  changed: (i) => logic.changed(i.prev, i.next),
  faithfulHit: (i) => ({
    faithful: logic.faithfulHit(i.stack),
    firstOutside: logic.firstOutside((i.stack as logic.Hit[]).map((h) => h.insideNav)),
  }),
  isOnDark: (i) => logic.isOnDark(i.hit, i.morph),
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
  it('faithful hit reports re-enabled nav boxes; the naive skip does not', () => {
    const stack: logic.Hit[] = [{ insideNav: true, reEnabled: true }, { insideNav: false, reEnabled: false }];
    expect(logic.faithfulHit(stack)).toBe(0);
    expect(logic.firstOutside(stack.map((h) => h.insideNav))).toBe(1);
  });
  it('allow-list equal to reEnabled reproduces the faithful hit', () => {
    const stacks: logic.Hit[][] = [
      [],
      [{ insideNav: true, reEnabled: false }, { insideNav: false, reEnabled: false }],
      [{ insideNav: true, reEnabled: false }, { insideNav: true, reEnabled: true }, { insideNav: false, reEnabled: false }],
      [{ insideNav: true, reEnabled: false }],
    ];
    for (const s of stacks) expect(logic.allowHit((h) => h.reEnabled, s)).toBe(logic.faithfulHit(s));
  });
  it('morph skip: past 0.2 the class ignores the hit answer', () => {
    expect(logic.skipHitTest(0.2)).toBe(false);
    expect(logic.skipHitTest(0.2001)).toBe(true);
    for (const g of [false, true]) expect(logic.isOnDark(g, 0.5)).toBe(true);
  });
});
