import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { createTweenDriver, type PlatformEl, type TweenEnv } from '../parts/morph.tween/driver';
import { hooksOf, type EndCfg } from '../parts/morph.tween/end.hooks';
import { initEnd, prevented, step, type EndEv } from '../parts/morph.tween/end.logic';
import { active, REST } from '../parts/morph.tween/logic';

type Num = number | { num: string; den: string };
interface GoldEv {
  ev: string;
  y?: Num | null;
  maxY?: Num;
  scrollY?: Num;
  arm?: boolean;
  now?: Num;
  reduced?: boolean;
  cancelable: boolean;
  passive: boolean;
  other: boolean;
}
interface GoldOut {
  prevent: boolean;
  goal: Num | null;
  flip: boolean;
  write: Num | null;
  active: boolean;
  value: { num: string; den: string };
  pin: Num;
  held: boolean;
  defaultPrevented: boolean;
}
interface Row {
  fn: string;
  in: { case: string; cfg: EndCfg; init: Num; events: GoldEv[] };
  out: GoldOut[];
}

const rows: Row[] = readFileSync(new URL('../../../../packages/contracts/golden/parts/combo-scroll.jsonl', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);
const num = (n: Num): number => (typeof n === 'number' ? n : Number(n.num) / Number(n.den));
const opt = (n: Num | null | undefined): number | null => (n === null || n === undefined ? null : num(n));

function toEv(e: GoldEv): EndEv {
  const read = { scrollY: num(e.scrollY ?? 0), arm: e.arm ?? false, now: num(e.now ?? 0), reduced: e.reduced ?? false, cancelable: e.cancelable, passive: e.passive, other: e.other };
  switch (e.ev) {
    case 'touchstart':
      return { ev: 'touchstart', y: opt(e.y) };
    case 'touchmove':
      return { ev: 'touchmove', y: opt(e.y), ...read };
    case 'scroll':
    case 'resize':
      return { ev: e.ev, y: num(e.y ?? 0), maxY: num(e.maxY ?? 0) };
    default:
      return { ev: 'tick', now: num(e.now ?? 0) };
  }
}

describe('combo-scroll golden (Lean ComboScroll.wstep)', () => {
  it('has the 6 traces under all 8 picks', () => {
    expect(rows).toHaveLength(48);
    expect(new Set(rows.map((r) => r.in.case))).toEqual(new Set(['same-touch', 'momentum', 'held-reopen', 'plain-open', 'passive-reopen', 'other-prevented']));
    expect(new Set(rows.map((r) => JSON.stringify(r.in.cfg))).size).toBe(8);
  });
  for (const row of rows) {
    const cfg = row.in.cfg;
    it(`${row.in.case} clamp=${cfg.clamp} flip=${cfg.flip} release=${cfg.release}`, () => {
      const h = hooksOf(cfg);
      let s = initEnd(num(row.in.init), REST);
      row.in.events.forEach((ge, i) => {
        const [next, out] = step(h, s, toEv(ge));
        s = next;
        const w = row.out[i] as GoldOut;
        const dp = ge.ev === 'touchmove' && prevented(out, { cancelable: ge.cancelable, passive: ge.passive, other: ge.other });
        const at = `event ${i} (${ge.ev}, cancelable ${ge.cancelable}, passive ${ge.passive}, other ${ge.other})`;
        expect({ at, prevent: out.prevent, goal: out.goal, flip: out.flip, write: out.write, active: active({ target: s.tw.target, value: s.tw.value }), pin: s.pin, held: s.held, defaultPrevented: dp }).toEqual({
          at,
          prevent: w.prevent,
          goal: opt(w.goal),
          flip: w.flip,
          write: opt(w.write),
          active: w.active,
          pin: num(w.pin),
          held: w.held,
          defaultPrevented: w.defaultPrevented,
        });
        expect(s.tw.value).toBeCloseTo(num(w.value), 9);
      });
    });
  }
  it('no write happens against a native scroll: after a move that is not held, frames write nothing (release on)', () => {
    for (const row of rows.filter((r) => r.in.cfg.release)) {
      let held = true;
      row.in.events.forEach((ge, i) => {
        const o = row.out[i] as GoldOut;
        if (ge.ev === 'touchmove') held = o.held;
        if (ge.ev === 'scroll' || ge.ev === 'resize') if (!held) expect(o.write).toBeNull();
      });
    }
  });
  it('without release the wrapper is the inner reducer: the bit never leaves true', () => {
    for (const row of rows.filter((r) => !r.in.cfg.release)) for (const o of row.out) expect(o.held).toBe(true);
  });
});

interface Delivery {
  cancelable: boolean;
  passive: boolean;
  other: boolean;
}

function harness(cfg: EndCfg) {
  let now = 0;
  let scrollY = 5188;
  let maxY = 5188;
  const frames = new Set<(t: number) => void>();
  const writes: number[] = [];
  const ls = new Map<string, (e: never) => void>();
  const platform: PlatformEl = { getBoundingClientRect: () => ({ height: 800, bottom: 775 }), style: { pointerEvents: '', setProperty() {} } };
  const env: TweenEnv = {
    clock: { subscribe: (t) => (frames.add(t), () => void frames.delete(t)) },
    now: () => now,
    reduced: () => false,
    viewportHeight: () => 775,
    platform: () => platform,
    scrollY: () => scrollY,
    maxScrollY: () => maxY,
    scrollToInstant: (y) => void writes.push(y),
    addListener: (t, fn) => void ls.set(t, fn),
    removeListener: (t) => void ls.delete(t),
    publish: () => {},
    hooks: hooksOf(cfg),
  };
  const d = createTweenDriver(env);
  d.setNear(true);
  const fire = (type: 'touchstart' | 'touchmove', y: number, dlv: Delivery = { cancelable: true, passive: false, other: false }) => {
    let defaultPrevented = dlv.other;
    const e = {
      touches: [{ clientY: y }],
      cancelable: dlv.cancelable,
      get defaultPrevented() {
        return defaultPrevented;
      },
      preventDefault() {
        if (dlv.cancelable && !dlv.passive) defaultPrevented = true;
      },
    };
    (ls.get(type) as unknown as (ev: object) => void)(e);
    return e.defaultPrevented;
  };
  const frame = (t: number) => {
    now = t;
    for (const f of [...frames]) f(t);
  };
  return {
    d,
    writes,
    fire,
    frame,
    at: (y: number, t: number, m = maxY) => {
      scrollY = y;
      now = t;
      maxY = m;
    },
    scroll: (y: number, m: number) => {
      scrollY = y;
      maxY = m;
      const n = writes.length;
      d.pin();
      return writes.length > n ? (writes[writes.length - 1] as number) : null;
    },
  };
}

describe('combo-scroll through the driver', () => {
  function drive(cfg: EndCfg, reopen: Delivery) {
    const h = harness(cfg);
    h.fire('touchstart', 700);
    h.fire('touchmove', 690);
    h.frame(700);
    h.fire('touchmove', 900);
    h.at(4900, 800);
    const prevented = h.fire('touchmove', 850, reopen);
    for (const y of [4950, 4880, 4930]) h.scroll(y, 5188);
    return { writes: h.writes, prevented, state: h.d.state() };
  }
  const std: Delivery = { cancelable: true, passive: false, other: false };
  const USER: EndCfg = { clamp: true, flip: true, release: true };
  it('the Chromium repro: a reopen in the closing touch that the page cannot cancel writes no pin (release on)', () => {
    const r = drive(USER, { ...std, cancelable: false });
    expect(r.writes).toEqual([]);
    expect(r.prevented).toBe(false);
    expect(r.state.target).toBe(1);
  });
  it('a cancelable reopen in a passive listener (arm-late or the band hub outside the band) is ignored by the browser: no pin is written', () => {
    const r = drive(USER, { ...std, passive: true });
    expect(r.writes).toEqual([]);
    expect(r.prevented).toBe(false);
    expect(r.state.target).toBe(1);
  });
  it('a reopen another listener already prevented holds the page even when ours is passive', () => {
    const r = drive(USER, { cancelable: true, passive: true, other: true });
    expect(r.prevented).toBe(true);
    expect(r.writes).toEqual([4900, 4900, 4900]);
  });
  it('with release off the hold rule is inactive: the same moves write the pin as the original does', () => {
    expect(drive({ clamp: true, flip: true, release: false }, { ...std, cancelable: false }).writes.length).toBeGreaterThan(0);
    expect(drive({ clamp: true, flip: true, release: false }, { ...std, passive: true }).writes.length).toBeGreaterThan(0);
  });
  it('a reopen the page can cancel is prevented and pinned where the page is', () => {
    const r = drive(USER, std);
    expect(r.prevented).toBe(true);
    expect(r.writes).toEqual([4900, 4900, 4900]);
  });
  for (const row of rows) {
    const cfg = row.in.cfg;
    it(`golden ${row.in.case} clamp=${cfg.clamp} flip=${cfg.flip} release=${cfg.release}: the driver's writes and defaultPrevented equal the Lean trace`, () => {
      const h = harness(cfg);
      h.at(num(row.in.init), 0);
      row.in.events.forEach((ge, i) => {
        const w = row.out[i] as GoldOut;
        const at = `event ${i} (${ge.ev})`;
        if (ge.ev === 'touchstart') h.fire('touchstart', num(ge.y ?? 0));
        else if (ge.ev === 'touchmove') {
          h.at(num(ge.scrollY ?? 0), num(ge.now ?? 0));
          const dp = h.fire('touchmove', num(ge.y ?? 0), { cancelable: ge.cancelable, passive: ge.passive, other: ge.other });
          expect({ at, dp }).toEqual({ at, dp: w.defaultPrevented });
        } else if (ge.ev === 'tick') h.frame(num(ge.now ?? 0));
        else expect({ at, write: h.scroll(num(ge.y ?? 0), num(ge.maxY ?? 0)) }).toEqual({ at, write: opt(w.write) });
      });
    });
  }
});

describe('waapi and waapi-scoped pin writers (Lean ComboScroll.waapi_pin_eq_base, waapi_trace_eq)', () => {
  const src = (f: string) => readFileSync(new URL(`../parts/morph.tween/${f}`, import.meta.url), 'utf8');
  it('the waapi driver and its logic take no hooks: morph.end.release cannot reach them, so the hold bit stays at its initial true', () => {
    for (const f of ['waapi.driver.ts', 'waapi.logic.ts']) expect(src(f)).not.toMatch(/hooks|release|end\.logic|end\.hooks/i);
  });
  it('the waapi env built in index.tsx copies no hooks from the tween env', () => {
    const idx = src('index.tsx');
    const body = idx.slice(idx.indexOf('function waapiEnv'), idx.indexOf('function waapiEnv') + 2400);
    expect(body).not.toMatch(/hooks/);
  });
});

describe('one pin writer per frame', () => {
  it('the app mounts morph.mount without isActive, so its re-pin never writes; morph.tween is the only writer', () => {
    const app = readFileSync(new URL('../App.tsx', import.meta.url), 'utf8');
    const mount = app.split('\n').find((l) => l.includes('<MorphMount'));
    expect(mount).toBeDefined();
    expect(mount).not.toContain('isActive');
  });
});
