import { useEffect } from 'react';
import { registerScroll } from '../../engine/scroll';
import { action, armed, IO_ROOT_MARGIN, isShift, mountNext, mountNextWarm, warmStill, WARM_QUIET_MS, MOUNT_PIN_ORDER, repin, takes, touchDelta, viewportHeight, wanted } from './logic';

/** Handle given to the owner (morph.tween) so it can re-evaluate the listeners when the morph goes idle or active (`I`). */
export interface MorphMountHandle {
  refresh(): void;
}

export interface MorphMountProps {
  variant: string;
  impl?: 'mui' | 'plain';
  /** The element the observer watches and whose rect arms a push. Default: the sentinel this part renders. */
  targetSelector?: string;
  /** `C()`: the morph is active (tween target or value above 0.001). Owned by morph.tween. */
  isActive?: () => boolean;
  /** A taken push: wheel `deltaY`, or touch `previous y - current y`. Starts the tween (owned by morph.tween). */
  onPush?: (delta: number) => void;
  /** The panel should be mounted (first intersecting entry, or first taken push; `shift`: or a still moment). Called once. */
  onMount?: () => void;
  /** The original's trigger fired (first intersecting entry, or first taken push). Called once. */
  onWake?: () => void;
  onReady?: (h: MorphMountHandle | null) => void;
}

/**
 * Mount and arm of the end-of-page morph. Observes the platform with `rootMargin: 200% 0px`; while it is near, or while
 * the morph is active, attaches the wheel / touchstart / touchmove capture listeners to the window (touchmove and wheel
 * non-passive). A push is taken when active, or when forward and the platform fills >= 45 % of the viewport with its
 * bottom within 8 px of it; a taken push prevents the default scroll and goes to `onPush`. While active the scroll
 * position is held at the y where the morph began (engine callback, the original's `L`). No React state, no CSS.
 *
 * Renders a hidden sentinel that carries the breakpoint-gate anchor and stands in for the platform until that section
 * is ported (the part restates no CSS).
 */
export function MorphMount({ variant, targetSelector = '[data-fw="morph-mount"]', isActive = () => false, onPush, onMount, onWake, onReady }: MorphMountProps) {
  useEffect(() => {
    const target = document.querySelector<HTMLElement>(targetSelector);
    let near = false;
    let attached = false;
    let mounted = false;
    let woken = false;
    let pin = window.scrollY;
    let lastY = 0;

    const shift = isShift(variant);
    let lastMotion = performance.now();
    const mount = (intersecting: boolean, pushed: boolean, warm = false) => {
      const next = mountNextWarm(mounted, intersecting, pushed, warm);
      if (next && !mounted) {
        mounted = true;
        if (shift) window.removeEventListener('scroll', onScrollMotion);
        onMount?.();
      }
      if (!woken && mountNext(woken, intersecting, pushed)) {
        woken = true;
        onWake?.();
      }
    };
    const geom = () => {
      const el = document.querySelector<HTMLElement>(targetSelector);
      if (!el) return false;
      const r = el.getBoundingClientRect();
      return armed({ height: r.height, bottom: r.bottom }, viewportHeight(window.visualViewport?.height ?? null, window.innerHeight));
    };
    const take = (e: Event, delta: number) => {
      lastMotion = performance.now();
      const act = isActive();
      if (!takes(act, delta, act ? false : geom())) return;
      if (!act) pin = window.scrollY;
      e.preventDefault();
      mount(false, true);
      onPush?.(delta);
    };
    const onWheel = (e: WheelEvent) => take(e, e.deltaY);
    const onTouchStart = (e: TouchEvent) => {
      lastY = e.touches[0]?.clientY ?? 0;
    };
    const onTouchMove = (e: TouchEvent) => {
      const y = e.touches[0]?.clientY ?? lastY;
      const d = touchDelta(lastY, y);
      lastY = y;
      take(e, d);
    };
    const refresh = () => {
      const a = action(attached, wanted(near, isActive()));
      if (a === 'attach') {
        attached = true;
        window.addEventListener('wheel', onWheel, { passive: false, capture: true });
        window.addEventListener('touchstart', onTouchStart, { passive: true, capture: true });
        window.addEventListener('touchmove', onTouchMove, { passive: false, capture: true });
      } else if (a === 'detach') {
        attached = false;
        window.removeEventListener('wheel', onWheel, true);
        window.removeEventListener('touchstart', onTouchStart, true);
        window.removeEventListener('touchmove', onTouchMove, true);
      }
    };

    const io = target
      ? new IntersectionObserver(
          ([entry]) => {
            near = !!entry?.isIntersecting;
            mount(near, false);
            refresh();
          },
          { rootMargin: IO_ROOT_MARGIN },
        )
      : undefined;
    if (target) io?.observe(target);
    const off = registerScroll('morph.mount', MOUNT_PIN_ORDER, () => {
      if (!repin(isActive(), window.scrollY, pin)) return;
      return () => window.scrollTo({ top: pin, behavior: 'instant' });
    });
    // shift: warm the panel up at a still moment (idle callback; no scroll, push or morph in progress). Mounts once and
    // starts no animation, timer or phase (PhaseFree), so the state at t depends only on t.
    let warmTimer: number | undefined;
    const onScrollMotion = () => {
      lastMotion = performance.now();
    };
    const idle = (f: () => void) => (window.requestIdleCallback ? window.requestIdleCallback(f) : f());
    const arm = () => {
      warmTimer = window.setTimeout(() => idle(warmCheck), WARM_QUIET_MS);
    };
    const warmCheck = () => {
      warmTimer = undefined;
      if (mounted) return;
      if (warmStill(isActive(), performance.now() - lastMotion)) mount(false, false, true);
      else arm();
    };
    if (shift) {
      window.addEventListener('scroll', onScrollMotion, { passive: true });
      arm();
    }
    onReady?.({ refresh });
    return () => {
      if (shift) window.removeEventListener('scroll', onScrollMotion);
      if (warmTimer !== undefined) window.clearTimeout(warmTimer);
      io?.disconnect();
      near = false;
      refresh();
      off();
      onReady?.(null);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- callbacks are owner-stable; selector/variant changes remount
  }, [targetSelector, variant]);
  return <div data-fw="morph-mount" hidden />;
}
