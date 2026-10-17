import { describe, expect, it } from 'vitest';
import { mountCommission, type Clock, type Env, type IoEntry } from './driver';

function fakeEl(rect: { top: number; bottom: number }) {
  const props = new Map<string, string>();
  const classes = new Set<string>();
  const attrs = new Map<string, string>();
  return {
    rect,
    props,
    classes,
    attrs,
    style: { setProperty: (n: string, v: string) => void props.set(n, v), height: '' },
    classList: { toggle: (c: string, on: boolean) => void (on ? classes.add(c) : classes.delete(c)) },
    setAttribute: (n: string, v: string) => void attrs.set(n, v),
    getAttribute: (n: string) => attrs.get(n) ?? null,
    getBoundingClientRect: () => ({ top: rect.top, bottom: rect.bottom }),
  };
}

function setup(opts: { cardTop: number; sectionTop?: number; sectionBottom: number; vh?: number; reduced?: boolean; compact?: boolean }) {
  const subs = new Set<() => void>();
  const intervals: Array<{ ms: number; cb: () => void; live: boolean }> = [];
  const clock: Clock = {
    subscribe: (tick) => {
      const f = () => tick(0);
      subs.add(f);
      return () => void subs.delete(f);
    },
    interval: (ms, cb) => {
      const it = { ms, cb, live: true };
      intervals.push(it);
      return () => void (it.live = false);
    },
  };
  const ios: Array<{ target: unknown; cb: (e: IoEntry) => void; opts: unknown }> = [];
  const registered: Array<() => void> = [];
  const env: Env = {
    vh: () => opts.vh ?? 1000,
    reduced: () => opts.reduced ?? false,
    compact: () => opts.compact ?? false,
    onReducedChange: () => () => undefined,
    observe: (target, o, cb) => {
      ios.push({ target, cb, opts: o });
      return () => undefined;
    },
    observeResize: () => () => undefined,
    lineBoxes: () => 2,
  };
  const section = fakeEl({ top: opts.sectionTop ?? 0, bottom: opts.sectionBottom });
  const card = fakeEl({ top: opts.cardTop, bottom: 0 });
  const runway = fakeEl({ top: 0, bottom: 0 });
  const title = fakeEl({ top: 0, bottom: 0 });
  const underline = fakeEl({ top: 0, bottom: 0 });
  const header = {};
  const muted = {};
  const off = mountCommission({
    els: { section, card, runway, header, title, muted, underline },
    classes: { entering: 'entering', shrinking: 'shrinking', titleWrapped: 'wrapped', enter: 'enter', idle: 'idle' },
    engine: { register: (_id, _order, cb) => { registered.push(() => void cb({ vh: 1000 })); return () => undefined; } },
    clock,
    env,
  });
  const runFrames = (max: number) => {
    let n = 0;
    while (subs.size && n < max) {
      for (const f of [...subs]) if (subs.has(f)) f();
      n += 1;
    }
    return n;
  };
  return { section, card, runway, title, underline, ios, intervals, registered, off, runFrames, subs };
}

describe('commission driver', () => {
  it('writes the custom properties, the classes and the runway at mount', () => {
    const t = setup({ cardTop: 5000, sectionTop: 5000, sectionBottom: 6000 });
    expect(t.section.props.get('--commission-enter-shrink')).toBe('1');
    expect(t.section.props.get('--commission-shrink')).toBe('1');
    expect(t.runway.style.height).toBe('60px');
    expect(t.section.classes.has('entering')).toBe(false);
    expect(t.section.attrs.get('data-scene')).toBe('paused'); // 5000 > 2 * vh
    t.off();
  });

  it('settles: the follower stops asking for frames', () => {
    const t = setup({ cardTop: 0, sectionBottom: 1000 });
    const frames = t.runFrames(200);
    expect(frames).toBeGreaterThan(1);
    expect(frames).toBeLessThan(200);
    expect(t.section.props.get('--commission-enter-shrink')).toBe('0');
    expect(t.section.classes.has('entering')).toBe(false);
    t.off();
  });

  it('no runway on compact or reduced motion; reduced lands in one frame', () => {
    const c = setup({ cardTop: 5000, sectionBottom: 6000, compact: true });
    expect(c.runway.style.height).toBe('');
    c.off();
    const r = setup({ cardTop: 0, sectionBottom: 1000, reduced: true });
    r.runFrames(5);
    expect(r.section.props.get('--commission-enter-shrink')).toBe('0');
    expect(r.runway.style.height).toBe('');
    expect(r.subs.size).toBe(0);
    r.off();
  });

  it('title-wrapped follows compact and the line boxes', () => {
    const c = setup({ cardTop: 5000, sectionBottom: 6000, compact: true });
    expect(c.title.classes.has('wrapped')).toBe(true);
    c.off();
    const d = setup({ cardTop: 5000, sectionBottom: 6000, compact: false });
    expect(d.title.classes.has('wrapped')).toBe(false);
    d.off();
  });

  it('the underline fires once at 45 % and settles on idle after 900 ms', () => {
    const t = setup({ cardTop: 0, sectionBottom: 1000 });
    const ul = t.ios.find((o) => (o.opts as { threshold?: number[] }).threshold?.length === 3)!;
    ul.cb({ isIntersecting: true, intersectionRatio: 0.3 });
    expect(t.underline.classes.size).toBe(0);
    ul.cb({ isIntersecting: true, intersectionRatio: 0.5 });
    expect(t.underline.classes.has('enter')).toBe(true);
    expect(t.intervals).toHaveLength(1);
    expect(t.intervals[0]!.ms).toBe(900);
    t.intervals[0]!.cb();
    expect(t.underline.classes.has('idle')).toBe(true);
    expect(t.underline.classes.has('enter')).toBe(false);
    t.off();
  });

  it('the scene observer pauses and resumes the scene', () => {
    const t = setup({ cardTop: 0, sectionBottom: 1000 });
    expect(t.section.attrs.get('data-scene')).toBe('active');
    expect(t.section.attrs.get('data-render')).toBe('active');
    const scene = t.ios.find((o) => (o.opts as { rootMargin?: string }).rootMargin === '100% 0px')!;
    scene.cb({ isIntersecting: false, intersectionRatio: 0 });
    expect(t.section.attrs.get('data-scene')).toBe('paused');
    t.runFrames(5); // two frames later the render is deferred with the measured size
    expect(t.section.attrs.get('data-render')).toBe('deferred');
    expect(t.section.props.get('--start-selling-intrinsic-block-size')).toBe('1000px');
    scene.cb({ isIntersecting: true, intersectionRatio: 1 });
    expect(t.section.attrs.get('data-render')).toBe('active');
    expect(t.subs.size).toBe(1); // a frame is requested when the scene turns active
    t.off();
  });
});
