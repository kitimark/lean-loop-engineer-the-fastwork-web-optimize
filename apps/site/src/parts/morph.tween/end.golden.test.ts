// morph.end bricks A clamp, B flip, C release: replays packages/contracts/golden/parts/morph.end.jsonl (Lean
// `Fw.Parts.MorphEnd`, lean/scripts/MorphEndGolden.lean): 3 cases under all 8 picks, event by event. Also drives the
// real createTweenDriver with the same picks and checks that its writes and prevents are the reducer's.
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { cfgOf, CLAMP_ID, FLIP_ID, hooksOf, ON, RELEASE_ID, type EndCfg } from './end.hooks';
import { FLIP_N, initEnd, step, type EndEv } from './end.logic';
import { createTweenDriver, type PlatformEl, type TweenEnv } from './driver';
import { active, REST } from './logic';

type Num = number | { num: string; den: string };
interface GoldEv {
  ev: string;
  y?: Num | null;
  delta?: Num;
  maxY?: Num;
  scrollY?: Num;
  arm?: boolean;
  now?: Num;
  reduced?: boolean;
}
interface GoldOut {
  prevent: boolean;
  goal: Num | null;
  flip: boolean;
  write: Num | null;
  active: boolean;
  value: { num: string; den: string };
  pin: Num;
}
interface Row {
  fn: string;
  in: { case?: string; cfg?: EndCfg; init?: Num; events?: GoldEv[] };
  out: unknown;
}

const rows: Row[] = readFileSync(new URL('../../../../../packages/contracts/golden/parts/morph.end.jsonl', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);
const num = (n: Num): number => (typeof n === 'number' ? n : Number(n.num) / Number(n.den));
const opt = (n: Num | null | undefined): number | null => (n === null || n === undefined ? null : num(n));

function toEv(e: GoldEv): EndEv {
  const read = { scrollY: num(e.scrollY ?? 0), arm: e.arm ?? false, now: num(e.now ?? 0), reduced: e.reduced ?? false };
  switch (e.ev) {
    case 'touchstart':
      return { ev: 'touchstart', y: opt(e.y) };
    case 'touchmove':
      return { ev: 'touchmove', y: opt(e.y), ...read };
    case 'wheel':
      return { ev: 'wheel', delta: num(e.delta ?? 0), ...read };
    case 'scroll':
    case 'resize':
      return { ev: e.ev, y: num(e.y ?? 0), maxY: num(e.maxY ?? 0) };
    default:
      return { ev: 'tick', now: num(e.now ?? 0) };
  }
}

const cases = rows.filter((r) => r.fn === 'morph.end');

describe('morph.end golden', () => {
  it('constants and ids', () => {
    const c = rows.find((r) => r.fn === 'morph.end.const')?.out as { flipN: number; ids: string[]; on: string };
    expect(c.flipN).toBe(FLIP_N);
    expect(c.ids).toEqual([CLAMP_ID, FLIP_ID, RELEASE_ID]);
    expect(c.on).toBe(ON);
  });
  it('has the 3 cases under all 8 picks', () => {
    expect(cases).toHaveLength(24);
    expect(new Set(cases.map((r) => JSON.stringify(r.in.cfg))).size).toBe(8);
  });
  for (const row of cases) {
    const cfg = row.in.cfg as EndCfg;
    it(`${row.in.case} clamp=${cfg.clamp} flip=${cfg.flip} release=${cfg.release}`, () => {
      const h = hooksOf(cfg);
      let s = initEnd(num(row.in.init ?? 0), REST);
      const want = row.out as GoldOut[];
      (row.in.events ?? []).forEach((ge, i) => {
        const [next, out] = step(h, s, toEv(ge));
        s = next;
        const w = want[i] as GoldOut;
        const at = `event ${i} (${ge.ev})`;
        expect({ at, prevent: out.prevent, goal: out.goal, flip: out.flip, write: out.write, active: active({ target: s.tw.target, value: s.tw.value }), pin: s.pin }).toEqual({
          at,
          prevent: w.prevent,
          goal: opt(w.goal),
          flip: w.flip,
          write: opt(w.write),
          active: w.active,
          pin: num(w.pin),
        });
        expect(s.tw.value).toBeCloseTo(num(w.value), 9);
      });
    });
  }
});

describe('morph.end driver wiring', () => {
  /** The driver on the spring-back case: same prevents and scroll writes as the reducer says. */
  function drive(cfg: EndCfg) {
    let now = 0;
    let scrollY = 5200;
    const frames = new Set<(t: number) => void>();
    const writes: (number | null)[] = [];
    const prevents: boolean[] = [];
    const ls = new Map<string, (e: never) => void>();
    const platform: PlatformEl = { getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty() {} } };
    const env: TweenEnv = {
      clock: { subscribe: (t) => (frames.add(t), () => void frames.delete(t)) },
      now: () => now,
      reduced: () => false,
      viewportHeight: () => 800,
      platform: () => platform,
      scrollY: () => scrollY,
      maxScrollY: () => 5227,
      scrollToInstant: (y) => void writes.push(y),
      addListener: (t, fn) => void ls.set(t, fn),
      removeListener: (t) => void ls.delete(t),
      publish: () => {},
      hooks: hooksOf(cfg),
    };
    const d = createTweenDriver(env);
    d.setNear(true);
    const touch = (type: 'touchstart' | 'touchmove', y: number) => {
      let p = false;
      (ls.get(type) as unknown as (e: object) => void)({ touches: [{ clientY: y }], preventDefault: () => void (p = true) });
      prevents.push(p);
    };
    touch('touchstart', 600);
    scrollY = 5292;
    touch('touchmove', 560);
    d.pin();
    now = 100;
    for (const f of [...frames]) f(now);
    scrollY = 5250;
    d.pin();
    scrollY = 5292;
    d.pin();
    return { writes, prevents };
  }
  it('faithful writes the overscroll pin back, clamp writes the real end', () => {
    expect(drive({ clamp: false, flip: false, release: false })).toEqual({ writes: [5292], prevents: [false, true] });
    expect(drive({ clamp: true, flip: false, release: false }).writes).toEqual([5227, 5227, 5227]);
  });
});
