import { UNTHROTTLE_ATTR, installUnthrottle } from './unthrottle';

/** Variant `unthrottle-park` (Lean `Fw.Parts.ScrollPark`, golden `scroll-park.jsonl`): `unthrottle` that cancels its flag animation while the page is still. */
export const UNTHROTTLE_PARK = 'unthrottle-park';
/** Set on the flag while its animation is cancelled. */
export const UT_PARKED_ATTR = 'data-fw-unthrottle-parked';

/** Lean `utStillFrames`: frames without scroll before the flag is parked (the follow lane's `stillMax`). */
export const STILL_FRAMES = 8;
/** Lean `utStillMs`: the timer at the nominal 60 Hz, `ceil(frames * 1000 / 60)`. */
export const STILL_MS = Math.ceil((STILL_FRAMES * 1000) / 60);

export type UtEvent = 'scroll' | 'touch' | 'still';

/** Lean `utStep`: parked after an event. */
export function utStep(_parked: boolean, ev: UtEvent): boolean {
  return ev === 'still';
}

/** The park stylesheet: under the flag's own conditions a parked flag has no animation (unlayered; it holds no value, nothing reads `--fw-ut`). */
export function unthrottleParkCss(): string {
  return [
    '@supports (animation-timeline: scroll()) {',
    '@media (pointer: coarse) {',
    `[${UNTHROTTLE_ATTR}][${UT_PARKED_ATTR}] { animation-name: none; }`,
    '}',
    '}',
  ].join('\n');
}

export interface ParkEnv {
  setParked(on: boolean): void;
  /** A passive listener for scroll and touch start; returns the removal. */
  listen(cb: (ev: Exclude<UtEvent, 'still'>) => void): () => void;
  setTimer(cb: () => void, ms: number): number;
  clearTimer(id: number): void;
}

/**
 * Parks the flag animation after STILL_MS without scroll and restores it at the next touch start or scroll event (Lean
 * `ut_touch_unparks`, `ut_scroll_unparks`). Idle cost: one timer at most, no frame work.
 */
export function createUtPark(env: ParkEnv) {
  let parked = false;
  let timer: number | null = null;
  const apply = (ev: UtEvent) => {
    const next = utStep(parked, ev);
    if (next !== parked) {
      parked = next;
      env.setParked(next);
    }
  };
  const arm = () => {
    if (timer !== null) env.clearTimer(timer);
    timer = env.setTimer(() => {
      timer = null;
      apply('still');
    }, STILL_MS);
  };
  const stopListen = env.listen((ev) => {
    apply(ev);
    arm();
  });
  arm();
  return {
    isParked: () => parked,
    stop() {
      stopListen();
      if (timer !== null) env.clearTimer(timer);
      timer = null;
      if (parked) env.setParked(false);
      parked = false;
    },
  };
}

export function installUnthrottlePark(doc: Document, win: Window): () => void {
  const removeFlag = installUnthrottle(doc);
  const style = doc.createElement('style');
  style.textContent = unthrottleParkCss();
  doc.head.appendChild(style);
  const flag = doc.querySelector(`[${UNTHROTTLE_ATTR}]`);
  const park = createUtPark({
    setParked: (on) => (on ? flag?.setAttribute(UT_PARKED_ATTR, '') : flag?.removeAttribute(UT_PARKED_ATTR)),
    listen: (cb) => {
      const onScroll = () => cb('scroll');
      const onTouch = () => cb('touch');
      win.addEventListener('scroll', onScroll, { passive: true });
      doc.addEventListener('touchstart', onTouch, { passive: true, capture: true });
      return () => {
        win.removeEventListener('scroll', onScroll);
        doc.removeEventListener('touchstart', onTouch, { capture: true });
      };
    },
    setTimer: (cb, ms) => win.setTimeout(cb, ms),
    clearTimer: (id) => win.clearTimeout(id),
  });
  return () => {
    park.stop();
    style.remove();
    removeFlag();
  };
}
