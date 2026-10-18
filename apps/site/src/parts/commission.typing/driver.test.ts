import { describe, expect, it } from 'vitest';
import { mountTyping, type Env } from './driver';

function cls() {
  const set = new Set<string>();
  return { set, el: { classList: { toggle: (c: string, on: boolean) => void (on ? set.add(c) : set.delete(c)) } } };
}

function setup(opts: { reduced?: boolean } = {}) {
  const visual = cls();
  const beat = cls();
  const avatar = cls();
  const message = cls();
  const referral = cls();
  const text = { append: (_n: unknown) => undefined };
  const typed = { data: '', caret: null as unknown };
  const amount = { textContent: '$0' as string | null };
  const percent = { textContent: '18%' as string | null };
  const fill = { style: { width: '0%' } };
  const scaleProps = new Map<string, string>();
  let now = 0;
  let tick: ((t: number) => void) | null = null;
  let io: ((e: { isIntersecting: boolean }) => void) | null = null;
  const env: Env = {
    now: () => now,
    reduced: () => opts.reduced ?? false,
    observe: (_t, _o, cb) => {
      io = cb;
      return () => undefined;
    },
    observeResize: () => () => undefined,
    createText: () => ({ get data() { return typed.data; }, set data(v: string) { typed.data = v; }, after: (n: unknown) => { typed.caret = n; } }),
    createCaret: (c) => {
      const node = { cls: c, remove: () => { if (typed.caret === node) typed.caret = null; } };
      return node;
    },
  };
  const off = mountTyping({
    els: {
      scale: { style: { setProperty: (n, v) => void scaleProps.set(n, v) } },
      parent: { clientWidth: 400 },
      visual: visual.el,
      beat: beat.el,
      avatar: avatar.el,
      message: message.el,
      text,
      referral: referral.el,
      amount,
      percent,
      fill,
    },
    classes: { resetting: 'resetting', scrollingOut: 'out', shown: 'shown', caret: 'caret' },
    clock: { subscribe: (t) => { tick = t; return () => { tick = null; }; } },
    env,
  });
  return {
    visual, beat, avatar, message, referral, typed, amount, percent, fill, scaleProps, off,
    enter: () => io!({ isIntersecting: true }),
    leave: () => io!({ isIntersecting: false }),
    at: (t: number) => { now = t; tick?.(t); },
    setNow: (t: number) => { now = t; },
    running: () => tick !== null,
  };
}

describe('commission.typing driver', () => {
  it('sets the visual scale from the column width', () => {
    const t = setup();
    expect(t.scaleProps.get('--visual-scale')).toBe(String(0.8));
    t.off();
  });

  it('types the message one character per 28 ms and shows the caret meanwhile', () => {
    const t = setup();
    t.setNow(1000);
    t.enter(); // run starts at 1000
    expect(t.running()).toBe(true);
    expect(t.visual.set.has('resetting')).toBe(true);
    t.at(1000 + 79);
    expect(t.visual.set.has('resetting')).toBe(true);
    t.at(1000 + 80);
    expect(t.visual.set.has('resetting')).toBe(false);
    expect(t.avatar.set.has('shown')).toBe(true);
    t.at(1000 + 500);
    expect(t.typed.data).toBe('H');
    expect(t.message.set.has('shown')).toBe(true);
    expect(t.typed.caret).not.toBeNull();
    t.at(1000 + 528);
    expect(t.typed.data).toBe('Hi');
    t.at(1000 + 1536);
    expect(t.typed.data).toBe('Hi! I found your profile from Explore.');
    expect(t.typed.caret).not.toBeNull();
    t.at(1000 + 1564);
    expect(t.typed.caret).toBeNull();
    t.off();
  });

  it('counts the numbers, scrolls out, and loops from the reset', () => {
    const t = setup();
    t.setNow(0);
    t.enter();
    t.at(1744);
    expect(t.referral.set.has('shown')).toBe(true);
    t.at(3324);
    expect(t.amount.textContent).toBe('$100');
    expect(t.fill.style.width).toBe('100%');
    t.at(4344);
    expect(t.percent.textContent).toBe('0%');
    t.at(5944);
    expect(t.beat.set.has('out')).toBe(true);
    t.at(6844 + 10);
    expect(t.visual.set.has('resetting')).toBe(true);
    expect(t.beat.set.has('out')).toBe(false);
    expect(t.amount.textContent).toBe('$0');
    expect(t.percent.textContent).toBe('18%');
    t.off();
  });

  it('leaving keeps the picture and stops the clock; entering again restarts from the reset', () => {
    const t = setup();
    t.setNow(0);
    t.enter();
    t.at(700);
    expect(t.typed.data).toBe('Hi! I fo');
    t.setNow(700);
    t.leave();
    expect(t.running()).toBe(false);
    expect(t.typed.data).toBe('Hi! I fo');
    t.setNow(5000);
    t.enter();
    expect(t.running()).toBe(true);
    expect(t.typed.data).toBe('');
    expect(t.visual.set.has('resetting')).toBe(true);
    t.off();
  });

  it('reduced motion shows the finished picture at once and starts no clock', () => {
    const t = setup({ reduced: true });
    t.enter();
    expect(t.running()).toBe(false);
    expect(t.typed.data).toBe('Hi! I found your profile from Explore.');
    expect(t.amount.textContent).toBe('$100');
    expect(t.percent.textContent).toBe('0%');
    expect(t.referral.set.has('shown')).toBe(true);
    t.off();
  });
});
