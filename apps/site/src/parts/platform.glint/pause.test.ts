import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { createGlintDriver } from './driver';
import { AWAY_RATIO, createPause, pauseStep, ticks, type SvgClock } from './pause';

/**
 * Test-only twin of the WebKit time container (SMILTimeContainer.cpp:94-194), driven by a manual document clock. It is a
 * TS stand-in for Lean `Cont`; its readings are checked against the Lean golden below.
 */
class FakeSvg implements SvgClock {
  accum = 0;
  last: number;
  paused = false;
  constructor(
    begin: number,
    private readonly clock: { t: number },
  ) {
    this.last = begin;
  }
  elapsedMs(t = this.clock.t): number {
    return this.paused ? this.accum : t + this.accum - this.last;
  }
  pauseAnimations(): void {
    if (this.paused) return;
    this.accum += this.clock.t - this.last;
    this.paused = true;
  }
  unpauseAnimations(): void {
    if (!this.paused) return;
    this.last = this.clock.t;
    this.paused = false;
  }
  getCurrentTime(): number {
    return this.elapsedMs() / 1000;
  }
  setCurrentTime(seconds: number): void {
    const x = seconds * 1000;
    this.accum = this.paused ? x : 0;
    this.last = this.clock.t - x;
  }
}

interface Ev {
  kind: 'hide' | 'reveal';
  t: number;
  frames: number[];
}
interface JointEv {
  kind: 'ratio' | 'reduced' | 'fire';
  t: number;
  ratio?: number;
  value?: boolean;
}

function joint(b: number, reduced: boolean, events: JointEv[]) {
  const clock = { t: 0 };
  const svgs = [new FakeSvg(b, clock), new FakeSvg(b, clock)];
  const subs = new Set<(t: number) => void>();
  const glint = createGlintDriver({
    clock: { subscribe: (tick) => (subs.add(tick), () => void subs.delete(tick)) },
    now: () => clock.t,
    reduced: () => reduced,
    onState: () => undefined,
  });
  const pause = createPause(() => svgs, () => clock.t);
  let away = false;
  const out: Array<{ v: boolean; h: boolean; paused: boolean; away: boolean; running: boolean }> = [];
  for (const e of events) {
    clock.t = e.t;
    if (e.kind === 'ratio') {
      away = e.ratio === AWAY_RATIO;
      pause.ratio(e.ratio!);
      glint.ratio(e.ratio!);
    } else if (e.kind === 'reduced') glint.reducedChanged(e.value!);
    else for (const tick of [...subs]) tick(e.t);
    const playing = glint.state.v;
    // a visible frame reads the uninterrupted clock; an away frame fires no timer
    const running = svgs.every((s) => !s.paused && Math.abs(s.elapsedMs(e.t + 7) - (e.t + 7 - b)) < 1e-6);
    if (playing) expect(running, `playing at ${e.t} reads s - b`).toBe(true);
    if (away) expect(svgs.every((s) => ticks({ paused: s.paused, armed: true }) === 0)).toBe(true);
    out.push({ v: glint.state.v, h: glint.state.h, paused: svgs.some((s) => s.paused), away, running });
  }
  return out.map(({ running: _r, ...x }) => x);
}

goldenConformance('platform-glint-pause', {
  'glint.pause.const': () => ({ awayRatio: AWAY_RATIO, events: ['hide', 'reveal'], acts: ['none', 'pause', 'resume-seek'] }),
  'glint.pause.step': (i) => {
    const o = pauseStep({ state: { paused: i.paused as boolean, off: i.off as number }, ev: i.ev as 'hide' | 'reveal', t: i.t as number, read: i.read as number });
    return { act: o.act, seek: o.seekMs, paused: o.state.paused, off: o.state.off };
  },
  'glint.pause.run': (i) => {
    const b = i.b as number;
    const clock = { t: 0 };
    const svg = new FakeSvg(b, clock);
    const pause = createPause(() => [svg], () => clock.t);
    const elapsed: number[][] = [];
    for (const e of i.events as Ev[]) {
      clock.t = e.t;
      if (e.kind === 'hide') pause.away();
      else pause.back();
      elapsed.push(e.frames.map((f) => svg.elapsedMs(f)));
    }
    return { elapsed, paused: svg.paused };
  },
  'glint.pause.joint': (i) => joint(i.b as number, i.reduced as boolean, i.events as JointEv[]),
  'glint.pause.ticks': (i) => ticks({ paused: i.paused as boolean, armed: i.armed as boolean }),
});

describe('platform.glint offscreen-pause', () => {
  it('after any hide and reveal sequence a running clock reads the uninterrupted value', () => {
    const clock = { t: 0 };
    const svg = new FakeSvg(250, clock);
    const pause = createPause(() => [svg], () => clock.t);
    for (const [t, ev] of [[1000, 'away'], [1200, 'away'], [4000, 'back'], [4100, 'back'], [9000, 'away'], [31337, 'back']] as const) {
      clock.t = t;
      if (ev === 'away') pause.away();
      else pause.back();
    }
    expect(svg.paused).toBe(false);
    for (const s of [31337, 31400, 40000]) expect(svg.elapsedMs(s)).toBeCloseTo(s - 250, 6);
  });

  it('a paused clock fires no tick and a running one with nothing scheduled fires none either', () => {
    expect(ticks({ paused: true, armed: true })).toBe(0);
    expect(ticks({ paused: false, armed: false })).toBe(0);
    expect(ticks({ paused: false, armed: true })).toBe(1);
  });

  it('pauseStep stores the offset at the pause and seeks to now + offset', () => {
    const a = pauseStep({ state: { paused: false, off: 0 }, ev: 'hide', t: 1000, read: 750 });
    expect(a).toEqual({ state: { paused: true, off: -250 }, act: 'pause', seekMs: null });
    expect(pauseStep({ state: a.state, ev: 'reveal', t: 4000, read: 0 })).toEqual({ state: { paused: false, off: -250 }, act: 'resume-seek', seekMs: 3750 });
  });
});

describe('platform.glint offscreen-pause wiring (source level: the site tests have no DOM)', () => {
  const part = JSON.parse(readFileSync(resolve(__dirname, 'part.json'), 'utf8')) as { variants: Record<string, { kind: string }> };
  const visuals = readFileSync(resolve(__dirname, '../platform/Visuals.tsx'), 'utf8');
  const index = readFileSync(resolve(__dirname, '../platform/index.tsx'), 'utf8');
  it('the variant is its own optimized brick', () => {
    expect(part.variants['offscreen-pause']?.kind).toBe('optimized');
  });
  it('the observer callback pauses before the glint driver sees the ratio', () => {
    expect(visuals).toMatch(/pause\?\.ratio\(ratio\);\s*glint\?\.ratio\(ratio\);/);
    expect(visuals).toMatch(/createPause\(\(\) => Array\.from\(el\.querySelectorAll<SVGSVGElement>\('\[data-fw-dash\] svg'\)\)/);
  });
  it('only the flag installs the pause, and both arms play the glint', () => {
    expect(index).toMatch(/glintPause: sub\.glint === 'offscreen-pause'/);
    expect(index).toMatch(/glint: faithful\(sub\.glint\) \|\| sub\.glint === 'offscreen-pause'/);
  });
});
