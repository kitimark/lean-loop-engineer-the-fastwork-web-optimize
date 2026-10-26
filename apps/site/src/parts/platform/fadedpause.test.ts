import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance, readGolden } from '../../engine/golden.testutil';
import { createPause, type SvgClock } from '../platform.glint/pause';
import * as Sweep from '../platform.sweep/pause';
import { FADE_END, fade } from '../morph.tween/logic';
import { createFadedBus, createFadedPause, type TimedAnim } from './fade.driver';
import { FADED_PAUSE, FADED_PAUSE_FLAG, fadedZero } from './fade.logic';
import { createSceneWriter, sceneValue, SCENE_ATTR } from './scene';

interface Fr {
  d: number;
  m: number;
}

/** The CSS clock the controller drives, simulated: held while the scene value is paused, running otherwise. */
function cssRig(off: number) {
  let now = 0;
  let paused = false;
  let hold = 0;
  const attrs = new Map<string, string>();
  const anim: TimedAnim & { cur(): number } = {
    get playState() {
      return paused ? 'paused' : 'running';
    },
    startTime: 0 - off,
    cur: () => (paused ? hold : now - (anim.startTime as number)),
  };
  const fin: TimedAnim = { playState: 'finished', startTime: 5 };
  const engine = (v: string) => {
    // the engine's reaction to the attribute: hold at the pause, restart with the held time at the resume
    if (v === 'paused' && !paused) {
      hold = now - (anim.startTime as number);
      paused = true;
    } else if (v === 'active' && paused) {
      paused = false;
      anim.startTime = now - hold;
    }
  };
  let ctl: ReturnType<typeof createFadedPause> | null = null;
  const writer = createSceneWriter(
    {
      setAttribute: (n, v) => {
        attrs.set(n, v);
        engine(v);
      },
      removeAttribute: (n) => void attrs.delete(n),
    },
    (v) => ctl?.onScene(v),
  );
  ctl = createFadedPause(
    {
      animations: () => [anim, fin],
      restore: (saved) => {
        for (const a of [anim, fin]) {
          const t = saved.get(a);
          if (t != null) a.startTime = t;
        }
      },
      svg: null,
    },
    writer.setFaded,
  );
  writer.setActive(true);
  return {
    anim,
    fin,
    attrs,
    frame(f: Fr) {
      ctl!.set(fadedZero(f.m));
      now += f.d;
    },
    cur: () => anim.cur(),
    at: () => now,
  };
}

goldenConformance('platform-faded-pause', {
  const: () => ({ fadeEnd: FADE_END, flag: FADED_PAUSE_FLAG, variant: FADED_PAUSE }),
  fade: (i) => ({ fade: fade({ m: i.m as number }), zero: fadedZero(i.m as number) }),
  scene: (i) => sceneValue(i.active as boolean, i.faded as boolean),
  css: (i) => {
    let s = Sweep.init(i.off as number);
    return (i.frames as Fr[]).map((f) => {
      const rep = fadedZero(f.m);
      const a = Sweep.seek(s, rep);
      s = Sweep.tick(a, f.d, rep);
      return { loc: a.loc, phase: Sweep.phase({ t: a.loc }), ticks: Sweep.ticks(rep), paused: a.paused };
    });
  },
  orig: (i) => Sweep.orig(i.off as number, (i.frames as Fr[]).map((f) => f.d)),
  glint: (i) => {
    const b = i.birth as number;
    let now = 0;
    let held: number | null = null;
    let seeks: number[] = [];
    const svg: SvgClock = {
      pauseAnimations() {
        held = now - b;
      },
      unpauseAnimations() {
        held = null;
      },
      getCurrentTime: () => (held ?? now - b) / 1000,
      setCurrentTime: (sec) => void seeks.push(sec * 1000),
    };
    const p = createPause(() => [svg], () => now);
    return (i.frames as Fr[]).map((f) => {
      now = f.d; // the golden's glint frames carry absolute times
      seeks = [];
      if (fadedZero(f.m)) p.away();
      else p.back();
      return { seek: seeks.length ? seeks[0]! : null, paused: p.paused };
    });
  },
});

describe('platform:faded-pause controller against the golden css trace', () => {
  const cases = readGolden('platform-faded-pause', 'main').filter((l) => l.fn === 'css');
  it.each(cases.map((l) => [l.in.case as string, l] as const))('%s: every shown frame reads the faithful phase', (_n, l) => {
    const off = l.in.off as number;
    const rig = cssRig(off);
    let clk = 0;
    for (const f of l.in.frames as Fr[]) {
      const zero = fadedZero(f.m);
      const prev = clk;
      rig.frame({ d: 0, m: f.m });
      if (!zero) expect(rig.cur()).toBeCloseTo(off + prev, 6);
      rig.frame({ d: f.d, m: f.m });
      clk += f.d;
    }
    expect(rig.fin.startTime).toBe(5);
  });

  it('a long fade is seeked past the time the engine held', () => {
    const rig = cssRig(100);
    rig.frame({ d: 50, m: 0.6 });
    rig.frame({ d: 1000, m: 0.6 });
    expect(rig.attrs.get(SCENE_ATTR)).toBe('paused');
    rig.frame({ d: 0, m: 0.1 });
    expect(rig.attrs.get(SCENE_ATTR)).toBe('active');
    expect(rig.cur()).toBeCloseTo(1050 + 100, 6);
  });
});

describe('scene writer', () => {
  const host = () => {
    const attrs = new Map<string, string>();
    return { attrs, el: { setAttribute: (n: string, v: string) => void attrs.set(n, v), removeAttribute: (n: string) => void attrs.delete(n) } };
  };
  it('ORs the observer and the faded pause', () => {
    const h = host();
    const w = createSceneWriter(h.el);
    w.setActive(true);
    expect(h.attrs.get(SCENE_ATTR)).toBe('active');
    w.setFaded(true);
    expect(h.attrs.get(SCENE_ATTR)).toBe('paused');
    w.setActive(true);
    expect(h.attrs.get(SCENE_ATTR)).toBe('paused');
    w.setActive(false);
    w.setFaded(false);
    expect(h.attrs.get(SCENE_ATTR)).toBe('paused');
    w.setActive(true);
    expect(h.attrs.get(SCENE_ATTR)).toBe('active');
  });
  it('without a faded input it writes the observer value alone', () => {
    const h = host();
    const w = createSceneWriter(h.el);
    for (const a of [true, false, true]) {
      w.setActive(a);
      expect(h.attrs.get(SCENE_ATTR)).toBe(a ? 'active' : 'paused');
    }
  });
});

describe('fade bus', () => {
  it('drops repeats and replays the last zero to a late subscriber', () => {
    const bus = createFadedBus();
    const seen: boolean[] = [];
    bus.set(true);
    const off = bus.subscribe((z) => seen.push(z));
    bus.set(true);
    bus.set(false);
    bus.set(false);
    off();
    bus.set(true);
    expect(seen).toEqual([true, false]);
  });
});

describe('census: no descendant escapes the section opacity group (Lean faded_same_pixels premise)', () => {
  const root = resolve(__dirname, '..');
  const files: string[] = [];
  const walk = (d: string) => {
    for (const n of readdirSync(d)) {
      const p = join(d, n);
      if (statSync(p).isDirectory()) walk(p);
      else if (/\.(tsx?|css)$/.test(n) && !/\.test\./.test(n)) files.push(p);
    }
  };
  for (const d of readdirSync(root).filter((n) => n === 'platform' || n.startsWith('platform.'))) walk(join(root, d));
  it('reads the platform parts', () => expect(files.length).toBeGreaterThan(10));
  it('uses no portal, dialog, popover, fullscreen or backdrop', () => {
    const bad = /createPortal|<dialog|showModal|popover|requestFullscreen|::backdrop|top-layer|view-transition/;
    const hits = files.filter((f) => bad.test(readFileSync(f, 'utf8')));
    expect(hits).toEqual([]);
  });
});
