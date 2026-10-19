import { describe, expect, it } from 'vitest';
import { createRafClock } from '../../engine/clock';
import { createCountdownDriver, onVisibilityChange, startFaithful, type Writable } from './driver';

const TARGET = Date.parse('2026-11-02T12:00:00+07:00');
const node = (): Writable => ({ style: { transform: '' } });
const mk = (variant: 'faithful' | 'strip', nowRef: { v: number }, reduced = false) => {
  // one unit (seconds), ones place
  const nodes = variant === 'strip' ? [node()] : Array.from({ length: 10 }, node);
  const d = createCountdownDriver({
    variant,
    digits: [{ unit: 3, place: 1, nodes }],
    dateNow: () => nowRef.v,
    reduced: () => reduced,
  });
  return { d, nodes };
};

describe('countdown driver', () => {
  it('writes nothing until the cell height is known, then the resting positions', () => {
    const now = { v: TARGET - 5000 };
    const { d, nodes } = mk('faithful', now);
    d.tick(0);
    expect(nodes[0]!.style.transform).toBe('');
    d.setCell(0, 52);
    expect(nodes[5]!.style.transform).toBe('translateY(0px)');
    expect(nodes[6]!.style.transform).toBe('translateY(52px)'); // one cell below
  });
  it('a changed second starts a spring, then settles exactly', () => {
    const now = { v: TARGET - 5000 };
    const { d, nodes } = mk('faithful', now);
    d.setCell(0, 10);
    let t = 0;
    d.tick(t);
    expect(d.snapshot()[0]).toMatchObject({ value: 5, target: 5, animating: false });
    now.v += 1000;
    t += 16;
    d.tick(t);
    expect(d.snapshot()[0]).toMatchObject({ target: 4, animating: true });
    for (let i = 0; i < 300 && d.snapshot()[0]!.animating; i++) d.tick((t += 16.667));
    expect(d.snapshot()[0]).toMatchObject({ value: 4, target: 4, animating: false });
    expect(nodes[4]!.style.transform).toBe('translateY(0px)');
    expect(nodes[5]!.style.transform).toBe('translateY(10px)');
  });
  it('reduced motion jumps', () => {
    const now = { v: TARGET - 5000 };
    const { d } = mk('faithful', now, true);
    d.setCell(0, 10);
    d.tick(0);
    now.v += 1000;
    d.tick(16);
    expect(d.snapshot()[0]).toMatchObject({ value: 4, animating: false });
  });
  it('strip writes one transform per digit', () => {
    const now = { v: TARGET - 3000 };
    const { d, nodes } = mk('strip', now);
    d.setCell(0, 36);
    d.tick(0);
    expect(nodes[0]!.style.transform).toBe(`translateY(${-(1 + 3) * 36}px)`);
  });
  it('visibilitychange re-reads the time at once, hidden or visible (Lean refreshNow_shows)', () => {
    const now = { v: TARGET - 50000 };
    const timers = new Map<number, () => void>();
    let id = 0;
    const env = {
      raf: () => ++id,
      caf: () => {},
      setInterval: (cb: () => void) => (timers.set(++id, cb), id),
      clearInterval: (h: unknown) => void timers.delete(h as number),
    };
    const doc = new EventTarget();
    const { d, nodes } = mk('faithful', now, true);
    d.setCell(0, 10);
    const stop = startFaithful({ clock: createRafClock(env), driver: d, perfNow: () => 0, doc });
    expect(d.snapshot()[0]).toMatchObject({ target: 0 });
    now.v += 33000; // the tab slept: the interval did not fire
    expect(d.snapshot()[0]).toMatchObject({ target: 0 });
    doc.dispatchEvent(new Event('visibilitychange'));
    expect(d.snapshot()[0]).toMatchObject({ target: 7, value: 7 });
    expect(nodes[7]!.style.transform).toBe('translateY(0px)');
    now.v += 1000;
    doc.dispatchEvent(new Event('visibilitychange')); // hidden or visible: the same refresh
    expect(d.snapshot()[0]).toMatchObject({ target: 6 });
    stop();
    now.v += 1000;
    doc.dispatchEvent(new Event('visibilitychange'));
    expect(d.snapshot()[0]).toMatchObject({ target: 6 }); // listener removed
    expect(timers.size).toBe(0);
  });
  it('onVisibilityChange returns its own cleanup', () => {
    const doc = new EventTarget();
    let n = 0;
    const off = onVisibilityChange(doc, () => n++);
    doc.dispatchEvent(new Event('visibilitychange'));
    off();
    doc.dispatchEvent(new Event('visibilitychange'));
    expect(n).toBe(1);
  });
  it('tick reports the second change; shape counts digits per unit', () => {
    const now = { v: TARGET - 3000 };
    const { d } = mk('faithful', now);
    expect(d.tick(0)).toBe(true);
    expect(d.tick(16)).toBe(false);
    expect(d.shape()).toEqual([1, 2, 2, 2]);
  });
});
