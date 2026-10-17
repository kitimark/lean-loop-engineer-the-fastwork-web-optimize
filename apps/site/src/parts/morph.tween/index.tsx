import { useEffect } from 'react';
import { getClock } from '../../engine/clock';
import { registerScroll } from '../../engine/scroll';
import { createTweenDriver, type TweenEnv } from './driver';
import { matchList } from './media';

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
export function MorphTween({ platformSelector = '.start-selling-platform, [data-fw="platform"]', navSelector = '[data-fw="nav"]' }: MorphTweenProps) {
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
    const driver = createTweenDriver(env);
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
  }, [platformSelector, navSelector]);
  return null;
}
