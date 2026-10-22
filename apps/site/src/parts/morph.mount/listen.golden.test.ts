import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { taken } from '../morph.tween/logic';
import { createHub, type HubEnv, type HubType } from './listen';
import * as L from './listen.logic';
import { takes, touchDelta } from './logic';

interface Ev {
  touches: { clientY: number }[];
}
type Who = 'mount' | 'tween';
type GoldenEv =
  | { ev: 'attach'; who: Who }
  | { ev: 'detach'; who: Who }
  | { ev: 'start'; y: number }
  | { ev: 'move'; y: number; actM: boolean; actT: boolean; geomM: boolean; geomT: boolean };

function fakeEnv() {
  const on = new Map<HubType, { fn: (e: Ev) => void; passive: boolean }>();
  const bands = new Map<Element, (ratio: number) => void>();
  const env: HubEnv<Ev> = {
    add: (type, fn, passive) => {
      expect(on.has(type)).toBe(false);
      on.set(type, { fn, passive });
    },
    remove: (type, fn) => {
      expect(on.get(type)?.fn).toBe(fn);
      on.delete(type);
    },
    observe: (el, cb) => void bands.set(el, cb),
    unobserve: (el) => void bands.delete(el),
  };
  return { env, on, bands };
}

function runCase(events: GoldenEv[]) {
  const { env, on } = fakeEnv();
  const hub = createHub<Ev>(env);
  const out: { delta: number; who: Who }[][] = [];
  let seen = { actM: false, actT: false, geomM: false, geomT: false };
  let took: { delta: number; who: Who }[] = [];
  const client = (who: Who) => {
    let last = 0;
    return {
      touchstart: (e: Ev) => void (last = e.touches[0]!.clientY),
      touchmove: (e: Ev) => {
        const y = e.touches[0]!.clientY;
        const d = touchDelta(last, y);
        last = y;
        const t = who === 'mount' ? takes(seen.actM, d, seen.geomM) : taken({ active: seen.actT, delta: d, armed: seen.geomT });
        if (t) took.push({ delta: d, who });
      },
      active: () => false,
    };
  };
  const clients = { mount: client('mount'), tween: client('tween') };
  for (const e of events) {
    if (e.ev === 'attach') hub.attach(clients[e.who]);
    else if (e.ev === 'detach') hub.detach(clients[e.who]);
    else if (e.ev === 'start') on.get('touchstart')!.fn({ touches: [{ clientY: e.y }] });
    else {
      seen = e;
      took = [];
      on.get('touchmove')?.fn({ touches: [{ clientY: e.y }] });
      out.push(took);
    }
  }
  return out;
}

goldenConformance('morph-listen', {
  takesAny: (i) => L.takesAny(i.actM, i.actT, i.delta, i.geomM, i.geomT),
  want: (i) => L.want(i.attached, i.active, i.inBand),
  next: (i) => L.next(i.cur, i.want, i.down),
  full: (i) => L.full(i.ratio),
  bandRootMargin: () => L.BAND_ROOT_MARGIN,
  run: (i) => runCase(i.events as GoldenEv[]),
});

describe('morph-listen.profiles.jsonl', () => {
  const read = (rel: string) => readFileSync(new URL(`../../../../../packages/${rel}`, import.meta.url), 'utf8');
  it('holds the stroke ys of the replay profiles Lean checks the pan premise on', () => {
    const profile = (id: string) => JSON.parse(read(`measure-chromium/profiles/${id}.json`));
    const swipe = profile('swipe-touch-v1');
    const user = profile('user-fixture');
    const rows = [
      { profile: 'swipe-touch-v1', vh: swipe.viewport.height, strokes: [[swipe.input.startY, swipe.input.minY]] },
      { profile: 'user-fixture', vh: user.viewport.height, strokes: user.input.strokes.map((s: { path: number[][] }) => s.path.map((p) => p[1])) },
    ];
    expect(read('contracts/golden/parts/morph-listen.profiles.jsonl')).toBe(rows.map((r) => JSON.stringify(r)).join('\n') + '\n');
  });
});

describe('touch hub', () => {
  const el = {} as Element;
  const noop = { touchstart: () => {}, touchmove: () => {}, active: () => false };

  it('registers nothing until a part attaches, and everything goes on the last detach', () => {
    const { env, on } = fakeEnv();
    const hub = createHub<Ev>(env);
    expect(on.size).toBe(0);
    hub.attach(noop);
    expect([...on.keys()].sort()).toEqual(['touchcancel', 'touchend', 'touchmove', 'touchstart']);
    expect(on.get('touchstart')!.passive).toBe(true);
    hub.detach(noop);
    expect(on.size).toBe(0);
  });

  it('blocks in the band, watches out of it, and turns passive only after the finger lifts', () => {
    const { env, on, bands } = fakeEnv();
    const hub = createHub<Ev>(env);
    const stop = hub.observe(el);
    hub.attach(noop);
    expect(hub.mode()).toBe('take');
    expect(on.get('touchmove')!.passive).toBe(false);
    on.get('touchstart')!.fn({ touches: [{ clientY: 1 }] });
    bands.get(el)!(0.5);
    expect(hub.mode()).toBe('take');
    on.get('touchend')!.fn({ touches: [] });
    expect(hub.mode()).toBe('watch');
    expect(on.get('touchmove')!.passive).toBe(true);
    bands.get(el)!(1);
    expect(hub.mode()).toBe('take');
    stop();
    expect(bands.size).toBe(0);
  });

  it('blocks out of the band while a part is active', () => {
    const { env, bands } = fakeEnv();
    const hub = createHub<Ev>(env);
    let act = false;
    hub.observe(el);
    hub.attach({ ...noop, active: () => act });
    bands.get(el)!(0);
    expect(hub.mode()).toBe('watch');
    act = true;
    hub.refresh();
    expect(hub.mode()).toBe('take');
  });

  it('skips a part detached during the same dispatch', () => {
    const { env, on } = fakeEnv();
    const hub = createHub<Ev>(env);
    const calls: string[] = [];
    const b = { ...noop, touchmove: () => void calls.push('b') };
    const a = { ...noop, touchmove: () => (calls.push('a'), hub.detach(b)) };
    hub.attach(a);
    hub.attach(b);
    on.get('touchmove')!.fn({ touches: [{ clientY: 0 }] });
    expect(calls).toEqual(['a']);
  });
});
