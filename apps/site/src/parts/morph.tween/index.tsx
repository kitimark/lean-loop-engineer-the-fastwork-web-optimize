import { useEffect } from 'react';
import { getClock } from '../../engine/clock';
import { registerScroll } from '../../engine/scroll';
import { createTweenDriver, type TweenEnv } from './driver';
import { matchList } from './media';
import { createWaapiDriver, type AnimLike, type AnimTarget, type WaapiEnv } from './waapi.driver';
import { fadeCss, registrationsOf, type WaapiArm } from './waapi.logic';

/** Where the scroll pin sits on the engine: after the nav's hit test (order 100), as the original's pin callback follows it. */
export const MORPH_PIN_ORDER = 110;

export interface MorphTweenProps {
  variant: string;
  impl?: 'mui' | 'plain';
  /** the section whose rect arms the tween; the original's `.start-selling-platform` */
  platformSelector?: string;
  /** the element that receives the value as `--morph` and `data-fw-morph` (read by nav.hitTest) */
  navSelector?: string;
}

/**
 * morph.tween (`faithful`): the 680 ms scroll-jacked tween of `--morph`. Renders nothing (no MUI, so `impl: plain` is
 * the same path). Wheel and touch pushes at the end of the page open and close the morph; the value is written to
 * the nav element straight from the frame (a style property, never React state). Wiring: the driver in driver.ts,
 * decisions in logic.ts (Lean `Fw.Parts.MorphTween`).
 */
export function MorphTween({ variant, platformSelector = '.start-selling-platform, [data-fw="platform"]', navSelector = '[data-fw="nav"]' }: MorphTweenProps) {
  useEffect(() => {
    const root = document.documentElement;
    // Anchor for the breakpoint parity gate: one attribute write at mount, never per frame; absent in the prerendered HTML.
    root.setAttribute('data-fw-morph-tween', '');
    const reduce = matchList('mq.rm-reduce');
    const platform = () => document.querySelector<HTMLElement>(platformSelector);
    const env: TweenEnv = {
      clock: getClock(),
      now: () => performance.now(),
      reduced: () => reduce?.matches ?? false,
      viewportHeight: () => window.visualViewport?.height ?? window.innerHeight,
      platform,
      scrollY: () => window.scrollY,
      scrollToInstant: (top) => window.scrollTo({ top, behavior: 'instant' }),
      addListener: (type, fn, passive) => window.addEventListener(type, fn as EventListener, { passive, capture: true }),
      removeListener: (type, fn) => window.removeEventListener(type, fn as EventListener, true),
      publish: (value) => {
        const nav = document.querySelector<HTMLElement>(navSelector);
        if (!nav) return;
        nav.style.setProperty('--morph', String(value));
        nav.dataset.fwMorph = String(value);
      },
    };
    const arm: WaapiArm | null = variant === 'waapi' || variant === 'waapi-scoped' ? variant : null;
    const driver = arm ? createWaapiDriver(waapiEnv(env, platform, navSelector, arm), arm) : createTweenDriver(env);
    const target = platform();
    const io = target ? new IntersectionObserver(([entry]) => driver.setNear(!!entry?.isIntersecting), { rootMargin: '200% 0px' }) : undefined;
    if (target && io) io.observe(target);
    const off = registerScroll('morph.tween', MORPH_PIN_ORDER, () => driver.pin());
    return () => {
      off();
      io?.disconnect();
      driver.dispose();
      root.removeAttribute('data-fw-morph-tween');
    };
  }, [variant, platformSelector, navSelector]);
  return null;
}

/** `CSS.registerProperty` for the arm's animated properties (once; a second call throws and is ignored). */
function registerProperties(arm: WaapiArm): void {
  for (const r of registrationsOf(arm)) {
    try {
      CSS.registerProperty({ ...r });
    } catch {
      /* already registered */
    }
  }
}

/** The environment of a waapi arm on the window; shares the faithful variant's listener and viewport wiring. */
function waapiEnv(base: TweenEnv, platform: () => HTMLElement | null, navSelector: string, arm: WaapiArm): WaapiEnv {
  registerProperties(arm);
  const fade = fadeCss(arm);
  const nav = () => document.querySelector<HTMLElement>(navSelector);
  return {
    timelineNow: () => {
      const t = document.timeline.currentTime;
      return t === null ? null : Number(t);
    },
    reduced: base.reduced,
    viewportHeight: base.viewportHeight,
    nav: () => nav() as unknown as AnimTarget | null,
    platform: () => platform() as unknown as ReturnType<WaapiEnv['platform']>,
    scrollY: base.scrollY,
    scrollToInstant: base.scrollToInstant,
    addListener: base.addListener,
    removeListener: base.removeListener,
    hint: (value) => {
      const n = nav();
      if (n) n.dataset.fwMorph = String(value);
    },
    marker: (durationMs, startTime) => {
      const a = new Animation(new KeyframeEffect(null, null, { duration: durationMs }), document.timeline);
      if (startTime === null) a.play();
      else a.startTime = startTime;
      return a as unknown as AnimLike;
    },
    everyFrame: (cb) => base.clock.subscribe(() => cb()),
    settle: (value, props) => {
      const n = nav();
      if (n) {
        for (const [k, v] of Object.entries(props.nav)) n.style.setProperty(k, v);
        n.dataset.fwMorph = String(value);
      }
      const p = platform();
      if (p) {
        for (const [k, v] of Object.entries(props.platform)) p.style.setProperty(k, v);
        p.style.pointerEvents = props.pointerEvents;
      }
    },
    preparePlatform: () => {
      const p = platform();
      if (p && p.style.getPropertyValue('--morph-fade') !== fade) p.style.setProperty('--morph-fade', fade);
    },
    onActivate: base.onActivate,
  };
}
