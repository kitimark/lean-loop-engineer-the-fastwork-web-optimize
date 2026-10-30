import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { exitRange } from './logic';
import {
  createPark,
  fromCss,
  held,
  ioParked,
  MARGIN_VIEWPORTS,
  PARK_TARGETS,
  parkCss,
  parkRows,
  parkSentinelTop,
  scrollParked,
  toCss,
  type ParkDeps,
  type ParkTarget,
} from './park';
import { createHandoff, type HandoffDeps } from './threaded';

interface Row {
  fn: string;
  in: Record<string, unknown>;
  out: unknown;
}
const golden: Row[] = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/scroll-park.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);
const of = (fn: string) => golden.filter((r) => r.fn === fn);
const q = (r: unknown): number => {
  const o = r as { num: number; den: number };
  return o.num / o.den;
};
const band = (b: unknown) => b === 'narrow';

describe('hero.exit:threaded-park against the Lean golden', () => {
  it('constants equal the Lean consts line', () => {
    expect(MARGIN_VIEWPORTS).toBe((of('consts')[0]!.out as { marginViewports: number }).marginViewports);
  });

  it('every row (target, band, name, property, from, to) equals the Lean row, in animation-name order', () => {
    const rows = of('row');
    expect(rows.length).toBe(14);
    let seen = 0;
    for (const t of PARK_TARGETS) {
      for (const le600 of [false, true]) {
        const lean = rows.filter((r) => r.in.target === t && band(r.in.band) === le600);
        const ts = parkRows(t, le600);
        expect(ts.map((r) => r.name)).toEqual(lean.map((r) => r.in.name));
        ts.forEach((r, i) => {
          const o = lean[i]!.out as { prop: string; from: string; to: string };
          expect(r.prop).toBe(o.prop);
          expect(fromCss(r, le600)).toBe(o.from);
          expect(toCss(r, le600)).toBe(o.to);
          seen++;
        });
      }
    }
    expect(seen).toBe(rows.length);
  });

  it('held declarations equal the Lean held lines', () => {
    const lines = of('held');
    expect(lines.length).toBe(6);
    for (const l of lines) expect(held(l.in.target as ParkTarget, band(l.in.band))).toEqual(l.out);
  });

  it('the held text is the `to` keyframe of threaded.module.css, byte for byte (one value, two restatements)', () => {
    const css = readFileSync(resolve(__dirname, 'threaded.module.css'), 'utf8');
    const to = new Map<string, string>();
    for (const m of css.matchAll(/@keyframes\s+(\w+)\s*\{\s*from\s*\{[^}]*\}\s*to\s*\{([^}]*)\}/g)) {
      to.set(m[1]!, m[2]!.trim().replace(/;$/, '').replace(/\s+/g, ' '));
    }
    for (const t of PARK_TARGETS) {
      for (const le600 of [false, true]) {
        for (const r of parkRows(t, le600)) expect(to.get(r.name)).toBe(`${r.prop}: ${toCss(r, le600)}`);
      }
    }
  });

  it('the observer and scroll rules equal the Lean rules on every sample', () => {
    const io = of('ioParked');
    const sc = of('scrollParked');
    expect(io.length).toBe(8);
    expect(sc.length).toBe(8);
    for (const r of io) {
      const T = q(r.in.T);
      const h = q(r.in.h);
      const v = q(r.in.v);
      const out = r.out as { parked: boolean; sentinelTop: unknown };
      expect(ioParked(T + exitRange(h, v), MARGIN_VIEWPORTS * v, q(r.in.yPrev))).toBe(out.parked);
      expect(parkSentinelTop(h, v)).toBe(q(out.sentinelTop));
    }
    for (const r of sc) {
      const T = q(r.in.T);
      const out = r.out as { fromParked: boolean; fromLive: boolean };
      const b = T + exitRange(q(r.in.h), q(r.in.v));
      expect(scrollParked(true, b, q(r.in.y))).toBe(out.fromParked);
      expect(scrollParked(false, b, q(r.in.y))).toBe(out.fromLive);
    }
  });
});

describe('the park stylesheet mirrors the live rules', () => {
  const live = readFileSync(resolve(__dirname, 'threaded.module.css'), 'utf8');
  const body = live.slice(0, live.indexOf('@keyframes'));
  const rules = [...body.matchAll(/([^{}]+)\{([^{}]*animation-name:[^{}]*)\}/g)].map((m) => m[1]!.trim().replace(/\s+/g, ' '));
  const css = parkCss();

  it('every live animated selector has its parked twin with the same tail', () => {
    expect(rules.length).toBe(6);
    for (const sel of rules) {
      const twin = sel.replace('[data-exit-live]', '[data-exit-live][data-exit-parked]');
      expect(css).toContain(twin);
    }
  });

  it('carries the live conditions and no others', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => m[1]!.trim());
    expect(found).toEqual([mediaCondition('mq.rm-nopref'), mediaCondition('mq.w-gt-600'), mediaCondition('mq.w-le-600')]);
  });

  it('cancels the animation and holds each declaration of the golden, wide and narrow', () => {
    for (const l of of('held')) {
      const decls = (l.out as [string, string][]).map(([p, v]) => `${p}: ${v};`).join(' ');
      expect(css).toContain(`animation-name: none; ${decls} }`);
    }
  });
});

function parkHarness(boundary = 2000) {
  const log: string[] = [];
  let far: (f: boolean) => void = () => {};
  let scroll: () => void = () => {};
  let y = 0;
  let parked = false;
  let listeners = 0;
  const deps: ParkDeps = {
    setParked: (on) => {
      parked = on;
      log.push(on ? 'park' : 'unpark');
    },
    placeSentinel: () => log.push('place'),
    watch: (cb) => {
      far = cb;
      log.push('watch');
      return () => log.push('unwatch');
    },
    listenScroll: (cb) => {
      scroll = cb;
      listeners++;
      return () => {
        listeners--;
      };
    },
    readBoundary: () => boundary,
    scrollY: () => y,
  };
  const p = createPark(deps);
  return {
    p,
    log,
    far: (f: boolean) => far(f),
    scrollTo: (v: number) => {
      y = v;
      scroll();
    },
    parked: () => parked,
    listeners: () => listeners,
  };
}

describe('park controller', () => {
  it('places the sentinel and watches it on start', () => {
    const a = parkHarness();
    expect(a.log).toEqual(['place', 'watch']);
  });

  it('parks when the sentinel is far, adds one scroll listener, and restores when it is not', () => {
    const a = parkHarness();
    a.far(true);
    expect(a.parked()).toBe(true);
    expect(a.listeners()).toBe(1);
    a.far(true);
    expect(a.log.filter((x) => x === 'park').length).toBe(1);
    a.far(false);
    expect(a.parked()).toBe(false);
    expect(a.listeners()).toBe(0);
  });

  it('a scroll event that reaches the range restores at once; one at or past the end keeps the park', () => {
    const a = parkHarness(2000);
    a.far(true);
    a.scrollTo(2500);
    expect(a.parked()).toBe(true);
    a.scrollTo(2000);
    expect(a.parked()).toBe(true);
    a.scrollTo(1999);
    expect(a.parked()).toBe(false);
    expect(a.listeners()).toBe(0);
  });

  it('a resize restores and observes afresh; stop restores and stops watching', () => {
    const a = parkHarness();
    a.far(true);
    a.p.resize();
    expect(a.parked()).toBe(false);
    expect(a.log.slice(-3)).toEqual(['unwatch', 'place', 'watch']);
    a.far(true);
    a.p.stop();
    expect(a.parked()).toBe(false);
    expect(a.log.at(-1)).toBe('unpark');
    expect(a.listeners()).toBe(0);
  });
});

describe('the hand-over starts and stops the park with the live state', () => {
  it('starts the park when the stage goes live, resizes it with the sentinel, stops it on hand-back and on stop', () => {
    const log: string[] = [];
    const stage = {
      getAttribute: (n: string) => (n === 'data-splash' ? 'done' : null),
      style: { pointerEvents: '', removeProperty: () => '' },
    };
    const track = { setAttribute: () => undefined, removeAttribute: () => undefined };
    let reduced = false;
    const deps: HandoffDeps = {
      stage,
      track,
      supported: true,
      entranceFinished: () => true,
      reduced: () => reduced,
      startDriver: () => () => undefined,
      placeSentinel: () => undefined,
      watchSentinel: () => () => undefined,
      startPark: () => {
        log.push('start');
        return { stop: () => log.push('stop'), resize: () => log.push('resize') };
      },
    };
    const h = createHandoff(deps);
    expect(log).toEqual(['start']);
    h.resize();
    expect(log).toEqual(['start', 'resize']);
    reduced = true;
    h.sync();
    expect(log).toEqual(['start', 'resize', 'stop']);
    reduced = false;
    h.sync();
    expect(log.at(-1)).toBe('start');
    h.stop();
    expect(log.at(-1)).toBe('stop');
  });
});
