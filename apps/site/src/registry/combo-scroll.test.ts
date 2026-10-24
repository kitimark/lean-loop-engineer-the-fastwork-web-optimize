import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { createTweenDriver, type PlatformEl, type TweenEnv } from '../parts/morph.tween/driver';
import { hooksOf, type EndCfg } from '../parts/morph.tween/end.hooks';
import { initEnd, step, type EndEv } from '../parts/morph.tween/end.logic';
import { active, REST } from '../parts/morph.tween/logic';

// Golden of Lean Fw.Parts.ComboScroll (wstep, the hold rule): packages/contracts/golden/parts/combo-scroll.jsonl.
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
  const read = { scrollY: num(e.scrollY ?? 0), arm: e.arm ?? false, now: num(e.now ?? 0), reduced: e.reduced ?? false, cancelable: e.cancelable };
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
  it('has the 4 traces under all 8 picks', () => {
    expect(rows).toHaveLength(32);
    expect(new Set(rows.map((r) => r.in.case))).toEqual(new Set(['same-touch', 'momentum', 'held-reopen', 'plain-open']));
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
        const at = `event ${i} (${ge.ev}, cancelable ${ge.cancelable})`;
        expect({ at, prevent: out.prevent, goal: out.goal, flip: out.flip, write: out.write, active: active({ target: s.tw.target, value: s.tw.value }), pin: s.pin, held: s.held }).toEqual({
          at,
          prevent: w.prevent,
          goal: opt(w.goal),
          flip: w.flip,
          write: opt(w.write),
          active: w.active,
          pin: num(w.pin),
          held: w.held,
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

describe('combo-scroll through the driver', () => {
  function drive(cfg: EndCfg, reopenCancelable: boolean) {
    let now = 0;
    let scrollY = 5188;
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
      maxScrollY: () => 5188,
      scrollToInstant: (y) => void writes.push(y),
      addListener: (t, fn) => void ls.set(t, fn),
      removeListener: (t) => void ls.delete(t),
      publish: () => {},
      hooks: hooksOf(cfg),
    };
    const d = createTweenDriver(env);
    d.setNear(true);
    const fire = (type: 'touchstart' | 'touchmove', y: number, cancelable = true) => {
      let prevented = false;
      (ls.get(type) as unknown as (e: object) => void)({ touches: [{ clientY: y }], cancelable, preventDefault: () => void (prevented = true) });
      return prevented;
    };
    const frame = (t: number) => {
      now = t;
      for (const f of [...frames]) f(t);
    };
    fire('touchstart', 700);
    fire('touchmove', 690);
    frame(700);
    fire('touchmove', 900);
    scrollY = 4900;
    now = 800;
    const prevented = fire('touchmove', 850, reopenCancelable);
    for (const y of [4950, 4880, 4930]) {
      scrollY = y;
      d.pin();
    }
    return { writes, prevented, state: d.state() };
  }
  it('the Chromium repro: a reopen in the closing touch that the page cannot cancel writes no pin (release on)', () => {
    const r = drive({ clamp: true, flip: true, release: true }, false);
    expect(r.writes).toEqual([]);
    expect(r.prevented).toBe(false);
    expect(r.state.target).toBe(1);
  });
  it('with release off the hold rule is inactive: the same moves write the pin as the original does', () => {
    expect(drive({ clamp: true, flip: true, release: false }, false).writes.length).toBeGreaterThan(0);
  });
  it('a reopen the page can cancel is prevented and pinned where the page is', () => {
    const r = drive({ clamp: true, flip: true, release: true }, true);
    expect(r.prevented).toBe(true);
    expect(r.writes).toEqual([4900, 4900, 4900]);
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
