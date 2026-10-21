import { copyBlurPx, copyOpacity, copyTranslateYPx, cardOpacity, cardTranslate, cueBlurPx, cueTranslateYPx, exitOpacity, exitRange } from './logic';

/**
 * Variant `threaded` (Lean `Fw.Parts.HeroExitOpt`, section Threaded; golden `hero-exit.threaded.jsonl`). The per-frame
 * callback gives way to scroll-driven CSS animations (`threaded.module.css`) once the entrance is settled. This file
 * holds the pure rules (the endpoints, the hand-over, the sentinel) and the glue that hands over.
 */
export const THREADED = 'threaded';
/** Set on the track while the CSS animations run; the CSS rules start from it. */
export const LIVE_ATTR = 'data-exit-live';

/** The stage's `data-splash` (set by hero.orbit). */
export type Splash = 'prep' | 'run' | 'done';

/** Lean `live`: the animations replace the callback only for a settled entrance, a browser that knows the timeline and unreduced motion. */
export function threadedLive(splash: Splash, supported: boolean, reduced: boolean): boolean {
  return splash === 'done' && supported && !reduced;
}

/** Lean `sentinelTop`: where the pointer-events sentinel sits below the track top, `19/20` of the exit range. */
export function sentinelTop(trackHeight: number, viewportHeight: number): number {
  return (19 / 20) * exitRange(trackHeight, viewportHeight);
}

/** A settled consumer the CSS animates, by its Lean golden name. */
export type ConsumerName =
  | 'copyOpacity'
  | 'copyTranslateY'
  | 'copyBlur'
  | 'cueBlur'
  | 'cueTranslateY'
  | 'cardOpacity'
  | 'cardTranslate';
export const CONSUMERS: readonly ConsumerName[] = [
  'copyOpacity',
  'copyTranslateY',
  'copyBlur',
  'cueBlur',
  'cueTranslateY',
  'cardOpacity',
  'cardTranslate',
];

/**
 * The original's value of a settled consumer (entrance amount 1, card entered 1, scatter offset 1) at exit opacity `e`,
 * from the faithful restated maths. The keyframe endpoints are this at `e = 1` (`0%`) and `e = 0` (`100%`).
 */
export function consumerValue(name: ConsumerName, le600: boolean, e: number): number {
  const s = 1 - e;
  switch (name) {
    case 'copyOpacity':
      return copyOpacity(1, e);
    case 'copyTranslateY':
      return copyTranslateYPx(1, s, le600);
    case 'copyBlur':
      return copyBlurPx(1, s, le600);
    case 'cueBlur':
      return cueBlurPx(s);
    case 'cueTranslateY':
      return cueTranslateYPx(s, le600);
    case 'cardOpacity':
      return cardOpacity(s);
    case 'cardTranslate':
      return cardTranslate(1, 0, s, 1);
  }
}

/** The keyframe endpoints of a consumer: `from` is the rest value, `to` the fully exited one. */
export function keyframes(name: ConsumerName, le600: boolean): { from: number; to: number } {
  return { from: consumerValue(name, le600, 1), to: consumerValue(name, le600, 0) };
}

/** Timeline progress of a `contain` view range over a track whose top meets the viewport top at offset `T` (RG11), clamped, `fill: both`. */
export function timelineProgress(T: number, trackHeight: number, viewportHeight: number, y: number): number {
  const n = exitRange(trackHeight, viewportHeight);
  return Math.min(1, Math.max(0, (y - T) / n));
}

/** What the two-keyframe linear animation shows at offset `y` (Lean `Consumer.anim` at `prog y`). */
export function animatedValue(name: ConsumerName, le600: boolean, T: number, h: number, v: number, y: number): number {
  const k = keyframes(name, le600);
  const p = timelineProgress(T, h, v, y);
  return k.from + (k.to - k.from) * p;
}

/** The original's value at offset `y`: the exit opacity from the track top `T - y`. */
export function originalValue(name: ConsumerName, le600: boolean, T: number, h: number, v: number, y: number): number {
  return consumerValue(name, le600, exitOpacity(T - y, h, v));
}

/** Pointer events are off when the sentinel has left the viewport through the top (the observer entry's reading). */
export function pointerNoneFromEntry(entry: { isIntersecting: boolean; boundingClientRect: { top: number } }): boolean {
  return !entry.isIntersecting && entry.boundingClientRect.top < 0;
}

export interface HandoffStage {
  getAttribute(name: string): string | null;
  style: { pointerEvents: string; removeProperty(name: string): string };
}
export interface HandoffTrack {
  setAttribute(name: string, value: string): void;
  removeAttribute(name: string): void;
}

export interface HandoffDeps {
  stage: HandoffStage;
  track: HandoffTrack;
  /** Whether the browser knows `animation-timeline` (read once). */
  supported: boolean;
  reduced: () => boolean;
  /** Start the original's per-frame callback; returns its stop. */
  startDriver: () => () => void;
  /** Place the sentinel for the current geometry (once at hand-over, again on resize). */
  placeSentinel: () => void;
  /** Watch the sentinel; the callback gets whether pointer events are off. Returns its stop. */
  watchSentinel: (pointerNone: (none: boolean) => void) => () => void;
}

/**
 * Switches between the original's callback and the CSS animations by Lean `live`. `sync` is called at mount and when the
 * splash state or reduced motion changes; it does nothing between changes (no per-frame work). Handing over clears the
 * inline `--exit-opacity` (the animations replace what it fed) and lets the sentinel own `pointer-events`; handing back
 * restarts the callback, whose first run writes both again.
 */
export function createHandoff(deps: HandoffDeps) {
  let stopDriver: (() => void) | null = deps.startDriver();
  let stopSentinel: (() => void) | null = null;
  let live = false;
  const splash = (): Splash => {
    const s = deps.stage.getAttribute('data-splash');
    return s === 'done' || s === 'run' ? s : 'prep';
  };
  const sync = () => {
    const want = threadedLive(splash(), deps.supported, deps.reduced());
    if (want === live) return;
    live = want;
    if (want) {
      stopDriver?.();
      stopDriver = null;
      deps.stage.style.removeProperty('--exit-opacity');
      deps.placeSentinel();
      stopSentinel = deps.watchSentinel((none) => {
        deps.stage.style.pointerEvents = none ? 'none' : '';
      });
      deps.track.setAttribute(LIVE_ATTR, '');
    } else {
      deps.track.removeAttribute(LIVE_ATTR);
      stopSentinel?.();
      stopSentinel = null;
      deps.stage.style.pointerEvents = '';
      stopDriver = deps.startDriver();
    }
  };
  sync();
  return {
    sync,
    /** The geometry changed: move the sentinel while live. */
    resize() {
      if (live) deps.placeSentinel();
    },
    isLive: () => live,
    stop() {
      stopDriver?.();
      stopDriver = null;
      stopSentinel?.();
      stopSentinel = null;
      if (live) deps.track.removeAttribute(LIVE_ATTR);
      live = false;
    },
  };
}
