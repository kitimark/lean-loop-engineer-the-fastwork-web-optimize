import { useEffect } from 'react';
import { registerScroll } from '../../engine/scroll';
import { isBand } from './listen.logic';
import { touchHub } from './listen';
import { armStats, createArm, inBand, isArmLate } from './armLate';
import { gestureOpt, isOverscrollLock, lockOp, lockWanted, step, type Gesture } from './gesture';
import { action, armed, IO_ROOT_MARGIN, isShift, mountNext, mountNextWarm, warmStill, WARM_QUIET_MS, MOUNT_PIN_ORDER, repin, takes, touchDelta, viewportHeight, wanted } from './logic';

export interface MorphMountHandle {
  refresh(): void;
}

export interface MorphMountProps {
  variant: string;
  impl?: 'mui' | 'plain';
  targetSelector?: string;
  isActive?: () => boolean;
  onPush?: (delta: number) => void;
  onMount?: () => void;
  onWake?: () => void;
  onReady?: (h: MorphMountHandle | null) => void;
}

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
    const gopt = gestureOpt(variant);
    let gesture: Gesture = gopt?.first ? 'native' : 'fresh';
    const take = (e: Event, delta: number, touch = false) => {
      lastMotion = performance.now();
      const act = isActive();
      let go: boolean;
      if (gopt && touch) {
        const r = step(gopt, gesture, act, delta, !act && (gesture === 'fresh' || gesture === 'pushing') ? geom() : false, e.cancelable);
        gesture = r.next;
        go = r.take;
      } else go = takes(act, delta, act ? false : geom());
      if (!go) return;
      if (!act) pin = window.scrollY;
      e.preventDefault();
      mount(false, true);
      onPush?.(delta);
    };
    const onWheel = (e: WheelEvent) => take(e, e.deltaY);
    const onTouchStart = (e: TouchEvent) => {
      lastY = e.touches[0]?.clientY ?? 0;
      if (gopt) gesture = 'fresh';
    };
    const onTouchMove = (e: TouchEvent) => {
      const y = e.touches[0]?.clientY ?? lastY;
      const d = touchDelta(lastY, y);
      lastY = y;
      take(e, d, true);
    };
    const hub = isBand(variant) ? touchHub() : undefined;
    const late = isArmLate(variant)
      ? createArm(
          {
            add: (type, fn, passive) => window.addEventListener(type, fn as EventListener, { passive, capture: true }),
            remove: (type, fn) => window.removeEventListener(type, fn as EventListener, true),
          },
          { touchstart: onTouchStart, wheel: onWheel, touchmove: onTouchMove },
        )
      : undefined;
    let band = false;
    const readBand = () => {
      const el = document.querySelector<HTMLElement>(targetSelector);
      if (!el) return false;
      return inBand(viewportHeight(window.visualViewport?.height ?? null, window.innerHeight), el.getBoundingClientRect().bottom);
    };
    const client = { touchstart: onTouchStart, touchmove: onTouchMove, active: isActive };
    const unband = hub && target ? hub.observe(target) : undefined;
    const refresh = () => {
      if (late) {
        const act = isActive();
        band = near || act ? readBand() : false;
        late.set(near, band, act);
        return;
      }
      const a = action(attached, wanted(near, isActive()));
      if (a === 'attach') {
        attached = true;
        window.addEventListener('wheel', onWheel, { passive: false, capture: true });
        if (hub) hub.attach(client);
        else {
          window.addEventListener('touchstart', onTouchStart, { passive: true, capture: true });
          window.addEventListener('touchmove', onTouchMove, { passive: false, capture: true });
        }
      } else if (a === 'detach') {
        attached = false;
        window.removeEventListener('wheel', onWheel, true);
        if (hub) hub.detach(client);
        else {
          window.removeEventListener('touchstart', onTouchStart, true);
          window.removeEventListener('touchmove', onTouchMove, true);
        }
      }
      hub?.refresh();
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
    let locked = false;
    const offLock = isOverscrollLock(variant)
      ? registerScroll('morph.mount.lock', MOUNT_PIN_ORDER - 0.25, () => {
          const act = isActive();
          const want = lockWanted(near, near && !act ? geom() : false, act);
          if (lockOp(locked, want) === 'none') return;
          locked = want;
          return () => {
            document.documentElement.style.overscrollBehaviorY = want ? 'none' : '';
          };
        })
      : undefined;
    const stats = late ? armStats() : undefined;
    const offLate = late
      ? registerScroll('morph.mount.arm', MOUNT_PIN_ORDER - 0.5, () => {
          stats!.frames[late.mode()]++;
          if ((near || isActive()) && readBand() !== band) refresh();
        })
      : undefined;
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
      unband?.();
      offLate?.();
      offLock?.();
      if (locked) document.documentElement.style.overscrollBehaviorY = '';
      off();
      onReady?.(null);
    };
  }, [targetSelector, variant]);
  return <div data-fw="morph-mount" hidden />;
}
