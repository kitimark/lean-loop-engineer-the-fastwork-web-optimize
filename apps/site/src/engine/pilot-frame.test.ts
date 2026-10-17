import { describe, expect, it } from 'vitest';
import { createRafClock, type ClockEnv } from './clock';
import { createScrollEngine, type ScrollEnv } from './scroll';
import { createExitDriver, mountExit } from '../parts/hero.exit/driver';
import { navFrame, type NavVariant, type ProbeEnv } from '../parts/nav.hitTest/probe';
import { NAV_ACCESSES, PILOT_FRAME, forcedCounts, forcedCountsBatched, type Access } from '../parts/engine.scroll/logic';
import type { ScrollVariant } from '../parts/engine.scroll/logic';

/**
 * Steady scrolling frame of the two pilot callbacks against the original's access order (Lean `pilotFrame`):
 * the hero exit body in its own rAF (queued first), then the engine callback with the nav's
 * ee() reads, F() (rect, pointer-events write, elementFromPoint, restore) and the hero-track rect.
 * Accesses are logged by fakes: RS style read, RL layout read, WS style write.
 */
function rig(engineVariant: ScrollVariant, navVariant: NavVariant) {
  const log: Access[] = [];
  const rects = (a: Access) => () => (log.push(a), { top: -300, bottom: 400, height: 1600, left: 0, width: 390 });
  const navEl = {
    getBoundingClientRect: rects('RL'),
    contains: () => false,
    style: {
      _pe: '',
      get pointerEvents() {
        return this._pe;
      },
      set pointerEvents(v: string) {
        this._pe = v;
        log.push('WS');
      },
    },
  } as unknown as HTMLElement;
  const section = { getBoundingClientRect: rects('RL') };
  const sticky = {
    closest: () => section,
    getBoundingClientRect: rects('RL'),
  };
  const track = { getBoundingClientRect: rects('RL') };
  const env: ProbeEnv = {
    doc: {
      querySelector: ((sel: string) => (sel.includes('profile-sticky') ? sticky : track)) as unknown as Document['querySelector'],
      elementFromPoint: () => (log.push('RL'), null),
      elementsFromPoint: () => (log.push('RL'), []),
    },
    win: {
      innerHeight: 800,
      getComputedStyle: (() => ({
        get position() {
          log.push('RS');
          return 'sticky';
        },
        get top() {
          log.push('RS');
          return '0px';
        },
      })) as unknown as Window['getComputedStyle'],
    },
  };

  const raf = new Map<number, (t: number) => void>();
  let id = 0;
  const cenv: ClockEnv = {
    raf: (cb) => (raf.set(++id, cb), id),
    caf: (h) => void raf.delete(h),
    setInterval: () => 0,
    clearInterval: () => {},
  };
  const frame = (t: number) => {
    const cbs = [...raf.values()];
    raf.clear();
    cbs.forEach((cb) => cb(t));
  };
  const clock = createRafClock(cenv);
  const listeners = new Set<() => void>();
  const senv: ScrollEnv = {
    addEventListener: (type, fn) => type === 'scroll' && listeners.add(fn),
    removeEventListener: (type, fn) => type === 'scroll' && listeners.delete(fn),
    readY: () => 0,
    readVw: () => 390,
    readVh: () => 800,
  };
  const engine = createScrollEngine(clock, senv, engineVariant);
  const heroStyle = {
    setProperty: () => void log.push('WS'),
    set pointerEvents(_v: string) {
      log.push('WS');
    },
    get pointerEvents() {
      return '';
    },
  };
  const driver = createExitDriver({ track, hero: { style: heroStyle }, reduced: () => false });
  mountExit({ driver, engine, clock, readVh: () => 800 });
  engine.register('nav.hitTest', 100, () => void navFrame(navVariant, navEl, 0, env));
  return { log, frame, scroll: () => listeners.forEach((f) => f()) };
}

function steadyFrame(engineVariant: ScrollVariant, navVariant: NavVariant): Access[] {
  const r = rig(engineVariant, navVariant);
  r.frame(16); // first frame after mount
  r.scroll();
  r.frame(32); // steady frame
  r.log.length = 0;
  r.scroll();
  r.frame(48); // measured steady frame
  return [...r.log];
}

describe('pilot steady frame', () => {
  it('faithful engine + faithful nav reproduces the original order (3-4 forced style passes)', () => {
    const log = steadyFrame('faithful', 'faithful');
    expect(log).toEqual([...PILOT_FRAME]);
    expect(forcedCounts(log, true).style).toBe(4);
    expect(forcedCounts(log, false).style).toBe(3);
  });
  it('nav alone is the original ee/F/track order', () => {
    const log = steadyFrame('faithful', 'faithful');
    expect(log.slice(3)).toEqual([...NAV_ACCESSES]);
  });
  it('batched engine + elements-skip nav forces at most one style pass', () => {
    const log = steadyFrame('batched', 'elements-skip');
    const reorder = forcedCounts(log, true).style;
    expect(reorder).toBeLessThanOrEqual(1);
    expect(forcedCountsBatched(log, true).style).toBeLessThanOrEqual(1);
  });
  it('batched engine with the faithful nav probe still pays the nav-internal write/read pairs', () => {
    const log = steadyFrame('batched', 'faithful');
    expect(forcedCounts(log, true).style).toBeGreaterThan(1);
  });
});
