import { afterEach, describe, expect, it, vi } from 'vitest';
import { restoreAnims, saveAnims } from './tree';

// Lean Fw.Parts.MorphGeom moveNew / move_new_keeps: a re-parent restarts a CSS animation at 0 and the saved time is put back.
class FakeEffect {
  constructor(
    public target: object,
    public pseudoElement: string | null = null,
  ) {}
}
class FakeCssAnimation {
  constructor(
    public effect: FakeEffect,
    public animationName: string,
    public currentTime: number | null,
  ) {}
}

const root = (list: () => FakeCssAnimation[]) => ({ getAnimations: () => list() }) as unknown as HTMLElement;

describe('saveAnims and restoreAnims (A3a)', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('restores the time of each CSS animation after the re-parent restarted it', () => {
    vi.stubGlobal('CSSAnimation', FakeCssAnimation);
    vi.stubGlobal('KeyframeEffect', FakeEffect);
    const a = {};
    const b = {};
    let live = [new FakeCssAnimation(new FakeEffect(a), 'earn-unmask', 700), new FakeCssAnimation(new FakeEffect(b), 'marquee', 4200)];
    const r = root(() => live);
    const saved = saveAnims(r);
    expect(saved.map((s) => s[3])).toEqual([700, 4200]);
    live = [new FakeCssAnimation(new FakeEffect(b), 'marquee', 0), new FakeCssAnimation(new FakeEffect(a), 'earn-unmask', 0)];
    restoreAnims(r, saved);
    expect(live.map((x) => [x.animationName, x.currentTime])).toEqual([['marquee', 4200], ['earn-unmask', 700]]);
  });

  it('keys by target and name: an animation with no saved twin keeps its time', () => {
    vi.stubGlobal('CSSAnimation', FakeCssAnimation);
    vi.stubGlobal('KeyframeEffect', FakeEffect);
    const a = {};
    const live = [new FakeCssAnimation(new FakeEffect(a), 'earn-sheen', 10)];
    restoreAnims(root(() => live), [[{} as Element, null, 'earn-sheen', 99]]);
    expect(live[0].currentTime).toBe(10);
  });

  it('does nothing where the Web Animations API is missing', () => {
    expect(saveAnims({} as HTMLElement)).toEqual([]);
  });
});
