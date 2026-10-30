import { copyBlurPx, copyOpacity, copyTranslateYPx, cardOpacity, cardTranslate, cueBlurPx, cueTranslateYPx, exitOpacity, exitRange } from './logic';

/** Variant `threaded` (Lean `Fw.Parts.HeroExitOpt` section Threaded, golden `hero-exit.threaded.jsonl`). */
export const THREADED = 'threaded';
/** Set on the track while the CSS animations run. */
export const LIVE_ATTR = 'data-exit-live';

/** The stage's `data-splash`. */
export type Splash = 'prep' | 'run' | 'done';

/** Lean `live`. */
export function threadedLive(splash: Splash, entranceFinished: boolean, supported: boolean, reduced: boolean): boolean {
  return splash === 'done' && entranceFinished && supported && !reduced;
}

/** Lean `liveNext`: `prev` is the stage's state, `left` that a mutation batch saw the splash leave `done`. */
export function liveNext(prev: boolean, left: boolean, splash: Splash, entranceFinished: boolean, supported: boolean, reduced: boolean): boolean {
  return threadedLive(splash, entranceFinished || (prev && !left), supported, reduced);
}

/** Whether a mutation batch of `data-splash` saw the value leave `done`. */
export function splashLeftDone(records: readonly { oldValue: string | null }[]): boolean {
  return records.some((r) => r.oldValue === 'done');
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

/** The original's value of a settled consumer at exit opacity `e`. */
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

/** The keyframe endpoints of a consumer. */
export function keyframes(name: ConsumerName, le600: boolean): { from: number; to: number } {
  return { from: consumerValue(name, le600, 1), to: consumerValue(name, le600, 0) };
}

/** Timeline progress of the `contain` range at offset `y` (RG11), clamped. */
export function timelineProgress(T: number, trackHeight: number, viewportHeight: number, y: number): number {
  const n = exitRange(trackHeight, viewportHeight);
  return Math.min(1, Math.max(0, (y - T) / n));
}

/** The animated value at offset `y` (Lean `Consumer.anim`). */
export function animatedValue(name: ConsumerName, le600: boolean, T: number, h: number, v: number, y: number): number {
  const k = keyframes(name, le600);
  const p = timelineProgress(T, h, v, y);
  return k.from + (k.to - k.from) * p;
}

/** The original's value at offset `y`. */
export function originalValue(name: ConsumerName, le600: boolean, T: number, h: number, v: number, y: number): number {
  return consumerValue(name, le600, exitOpacity(T - y, h, v));
}

/** Pointer events are off once the sentinel left the viewport through the top. */
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
  supported: boolean;
  /** Whether the entrance animations (the phone cue's `copyIn`) have finished. */
  entranceFinished: () => boolean;
  reduced: () => boolean;
  /** Starts the original's callback; returns its stop. */
  startDriver: () => () => void;
  /** Places the sentinel for the current geometry. */
  placeSentinel: () => void;
  watchSentinel: (pointerNone: (none: boolean) => void) => () => void;
  startPark?: () => { stop(): void; resize(): void };
}

export function createHandoff(deps: HandoffDeps) {
  let stopDriver: (() => void) | null = deps.startDriver();
  let stopSentinel: (() => void) | null = null;
  let live = false;
  let park: { stop(): void; resize(): void } | null = null;
  const splash = (): Splash => {
    const s = deps.stage.getAttribute('data-splash');
    return s === 'done' || s === 'run' ? s : 'prep';
  };
  const handBack = () => {
    live = false;
    park?.stop();
    park = null;
    deps.track.removeAttribute(LIVE_ATTR);
    stopSentinel?.();
    stopSentinel = null;
    deps.stage.style.pointerEvents = '';
    stopDriver = deps.startDriver();
  };
  const handOver = () => {
    live = true;
    stopDriver?.();
    stopDriver = null;
    deps.stage.style.removeProperty('--exit-opacity');
    deps.placeSentinel();
    stopSentinel = deps.watchSentinel((none) => {
      deps.stage.style.pointerEvents = none ? 'none' : '';
    });
    deps.track.setAttribute(LIVE_ATTR, '');
    park = deps.startPark?.() ?? null;
  };
  const sync = (left = false) => {
    if (left && live) handBack();
    const want = liveNext(live, left, splash(), deps.entranceFinished(), deps.supported, deps.reduced());
    if (want === live) return;
    if (want) handOver();
    else handBack();
  };
  sync();
  return {
    sync: () => sync(),
    onMutations: (records: readonly { oldValue: string | null }[]) => sync(splashLeftDone(records)),
    resize() {
      if (live) {
        deps.placeSentinel();
        park?.resize();
      }
    },
    isLive: () => live,
    stop() {
      stopDriver?.();
      stopDriver = null;
      stopSentinel?.();
      stopSentinel = null;
      park?.stop();
      park = null;
      if (live) deps.track.removeAttribute(LIVE_ATTR);
      live = false;
    },
  };
}
