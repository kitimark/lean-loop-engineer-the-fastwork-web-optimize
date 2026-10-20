import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';
import { createTweenDriver, type PlatformEl, type TweenEnv } from './driver';
import { active } from './logic';
import { engage, lockAllowed, lockOn, lockWrite, overlayOf, readsAt } from './scroll-lock.logic';

type Row = Record<string, unknown>;
const rows: Row[] = readFileSync(new URL('../../../../../packages/contracts/golden/parts/morph-tween-scroll-lock.jsonl', import.meta.url), 'utf8')
  .split('\n')
  .filter((l) => l.trim() !== '')
  .map((l) => decodeRat(JSON.parse(l)) as Row);
const ofKind = (k: string) => rows.filter((r) => r.kind === k);
const byCase = (rs: Row[]) => {
  const m = new Map<string, Row[]>();
  for (const r of rs) m.set(String(r.case), [...(m.get(String(r.case)) ?? []), r]);
  return m;
};

function arm(overlay: boolean | null) {
  let now = 0;
  let reduced = false;
  let scrollY = 1200;
  const frames = new Set<(t: number) => void>();
  const listeners = new Map<string, (e: never) => void>();
  const sets: boolean[] = [];
  const scrolls: number[] = [];
  let reads = 0;
  const log: string[] = [];
  const platform: PlatformEl = { getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty: () => {} } };
  const env: TweenEnv = {
    clock: { subscribe: (tick) => (frames.add(tick), () => void frames.delete(tick)) },
    now: () => now,
    reduced: () => reduced,
    viewportHeight: () => 800,
    platform: () => platform,
    scrollY: () => scrollY,
    scrollToInstant: (y) => {
      scrolls.push(y);
      scrollY = y;
    },
    addListener: (t, fn) => void listeners.set(t, fn),
    removeListener: (t) => void listeners.delete(t),
    publish: () => void log.push('publish'),
    lock:
      overlay === null
        ? undefined
        : { overlay: () => (reads++, log.push('read'), overlay), set: (on) => void (sets.push(on), log.push('set')) },
  };
  const d = createTweenDriver(env);
  d.setNear(true);
  const wheel = (deltaY: number) => (listeners.get('wheel') as unknown as (e: { deltaY: number; preventDefault(): void }) => void)({ deltaY, preventDefault: () => {} });
  const run = (r: Row) => {
    now = Number(r.t);
    if (r.ev === 'tick') for (const f of [...frames]) f(now);
    else {
      reduced = r.reduced === true;
      wheel(r.goal === 1 ? 50 : -50);
    }
  };
  return { d, run, wheel, sets, scrolls, log, reads: () => reads, scrollY: () => scrollY, setY: (y: number) => void (scrollY = y) };
}

describe('morph.tween:scroll-lock against Lean (MorphTweenOpt MT-L)', () => {
  it('overlayOf, lockOn and lockWrite give the Lean rows', () => {
    const ov = ofKind('overlay');
    expect(ov.length).toBe(5);
    for (const r of ov) expect(overlayOf(Number(r.innerWidth), Number(r.clientWidth))).toBe(r.overlay);
    for (const o of [false, true]) for (const a of [false, true]) {
      expect(lockOn(o, a)).toBe(o && a);
      for (const l of [false, true]) expect(lockWrite(o, l, a)).toBe(lockOn(o, a) === l ? null : lockOn(o, a));
      expect(readsAt(o, a)).toBe(!o && a);
    }
  });
  it('lockAllowed and engage give the Lean rows (touch-only input never installs the lock)', () => {
    const en = ofKind('engage');
    expect(en.length).toBe(4);
    for (const r of en) {
      expect(lockAllowed(r.hoverNone === true)).toBe(r.allowed);
      expect(engage(r.hoverNone === true, r.overlay === true)).toBe(r.engage);
    }
  });
  it('the driver writes the root lock and reads overlay() exactly on the Lean rows', () => {
    const cases = byCase(ofKind('lock'));
    expect([...cases.keys()]).toEqual(['open-close', 'open-close-classic', 'reduced', 'retarget']);
    for (const [c, rs] of cases) {
      const a = arm(rs[0]!.overlay === true);
      for (const r of rs) {
        const n = a.sets.length;
        const m = a.reads();
        a.run(r);
        expect(a.reads() - m, `${c} ${String(r.i)} reads`).toBe(r.read === true ? 1 : 0);
        if (r.ev === 'tick') expect(a.reads() - m, `${c} ${String(r.i)} tick`).toBe(0);
        const st = a.d.state();
        expect(active({ target: st.target, value: st.value }), `${c} ${String(r.i)}`).toBe(r.active);
        expect(a.sets.slice(n), `${c} ${String(r.i)}`).toEqual(r.write === null ? [] : [r.write]);
        expect(a.sets.at(-1) ?? false, `${c} ${String(r.i)}`).toBe(r.locked);
      }
    }
  });
  it('the activating push reads overlay() before any style write of that push', () => {
    for (const reduced of [false, true]) {
      const a = arm(true);
      a.run({ ev: 'push', goal: 1, reduced, t: 0 });
      expect(a.log[0], String(reduced)).toBe('read');
      expect(a.log.filter((x) => x === 'read').length).toBe(1);
    }
  });
  it('dispose releases a held lock', () => {
    const a = arm(true);
    a.run({ ev: 'push', goal: 1, reduced: false, t: 0 });
    a.d.dispose();
    expect(a.sets).toEqual([true, false]);
  });
  it('pin() calls scrollTo exactly on the Lean span rows and leaves scrollY at p (Gest.gated is a model input)', () => {
    const cases = byCase(ofKind('span'));
    expect([...cases.keys()]).toEqual(['still', 'trackpad-in-flight', 'ios-pan-in-flight', 'mixed']);
    for (const [c, rs] of cases) for (const lock of [true, false]) {
      const a = arm(lock ? true : null);
      const p = Number(rs[0]!.p);
      a.setY(p);
      a.wheel(50);
      for (const r of rs.filter((x) => x.lock === lock)) {
        const n = a.scrolls.length;
        a.setY(Number(r.shown));
        a.d.pin();
        expect(a.scrolls.slice(n), `${c} ${String(lock)} ${String(r.i)}`).toEqual(r.scrollTo ? [p] : []);
        expect(a.scrollY(), `${c} ${String(lock)} ${String(r.i)} scrollY`).toBe(p);
        a.setY(p);
      }
    }
  });
});
