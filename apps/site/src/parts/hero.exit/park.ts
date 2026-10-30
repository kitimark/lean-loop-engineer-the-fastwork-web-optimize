import { mediaCondition } from '../../breakpoints';
import {
  cardOpacity,
  copyBlurPx,
  copyOpacity,
  copyTranslateYPx,
  cueBlurPx,
  cueTranslateYPx,
  exitRange,
} from './logic';

/** Variant `threaded-park` (Lean `Fw.Parts.ScrollPark`, golden `scroll-park.jsonl`): `threaded` plus a park of the finished animations. */
export const THREADED_PARK = 'threaded-park';
/** Set on the track while the finished animations are cancelled and the fill values are static style. */
export const PARKED_ATTR = 'data-exit-parked';

/** Lean `marginViewports`: the observed sentinel sits this many viewport heights past the end of the range. */
export const MARGIN_VIEWPORTS = 1;

export type ParkTarget = 'copy' | 'cue' | 'card';
export const PARK_TARGETS: readonly ParkTarget[] = ['copy', 'cue', 'card'];
type Fmt = 'num' | 'translateY' | 'translateNarrow' | 'blur' | 'cardCalc';

/** Lean `cardCalcCss`: the card's `to` keyframe, written with the page's custom properties. */
export const CARD_CALC =
  'calc((1 - var(--entered)) * var(--orbit-enter-x) + var(--scatter-x)) calc((1 - var(--entered)) * var(--orbit-enter-y) + var(--scatter-y))';

export interface ParkRow {
  name: string;
  prop: string;
  fmt: Fmt;
  /** The consumer's value at exit opacity `e` (1 is rest, 0 is fully exited), from the settled `logic.ts` functions. */
  value: (le600: boolean, e: number) => number;
}

const fade: ParkRow = { name: 'exitFade', prop: 'opacity', fmt: 'num', value: (_l, e) => copyOpacity(1, e) };
const cueFade: ParkRow = { name: 'exitFade', prop: 'opacity', fmt: 'num', value: (_l, e) => e };
const blurCopy: ParkRow = { name: 'exitBlur', prop: 'filter', fmt: 'blur', value: (l, e) => copyBlurPx(1, 1 - e, l) };
const blurCue: ParkRow = { name: 'exitBlur', prop: 'filter', fmt: 'blur', value: (_l, e) => cueBlurPx(1 - e) };
const cardRows: ParkRow[] = [
  { name: 'exitCardFade', prop: 'opacity', fmt: 'num', value: (_l, e) => cardOpacity(1 - e) },
  { name: 'exitCardMove', prop: 'translate', fmt: 'cardCalc', value: (_l, e) => 1 - e },
];

/** Lean `rows`: the animations of a target in `animation-name` order. */
export function parkRows(t: ParkTarget, le600: boolean): ParkRow[] {
  switch (t) {
    case 'copy':
      return le600
        ? [fade, { name: 'exitCopyUpNarrow', prop: 'transform', fmt: 'translateNarrow', value: (l, e) => copyTranslateYPx(1, 1 - e, l) }]
        : [fade, { name: 'exitCopyUp', prop: 'transform', fmt: 'translateY', value: (l, e) => copyTranslateYPx(1, 1 - e, l) }, blurCopy];
    case 'cue':
      return le600
        ? [cueFade, { name: 'exitCueUpNarrow', prop: 'transform', fmt: 'translateNarrow', value: (l, e) => cueTranslateYPx(1 - e, l) }, blurCue]
        : [cueFade, blurCue];
    case 'card':
      return cardRows;
  }
}

/** Lean `ratCss` for the values the rows take: integers and hundredths. */
export function ratCss(q: number): string {
  return String(Math.round(q * 100) / 100 + 0);
}

/** Lean `Fmt.render`. */
export function render(fmt: Fmt, q: number): string {
  switch (fmt) {
    case 'num':
      return ratCss(q);
    case 'translateY':
      return `translateY(${ratCss(q)}px)`;
    case 'translateNarrow':
      return `translate(-50%, ${ratCss(q)}px)`;
    case 'blur':
      return `blur(${ratCss(q)}px)`;
    case 'cardCalc':
      return CARD_CALC;
  }
}

/** Lean `Row.toCss`: the value of the finished animation, the keyframe's `to`. */
export const toCss = (r: ParkRow, le600: boolean): string => render(r.fmt, r.value(le600, 0));
/** Lean `Row.fromCss`. */
export const fromCss = (r: ParkRow, le600: boolean): string => render(r.fmt, r.value(le600, 1));
/** Lean `held`: the parked declarations of a target. */
export const held = (t: ParkTarget, le600: boolean): [string, string][] => parkRows(t, le600).map((r) => [r.prop, toCss(r, le600)]);

const LIVE = '[data-exit-live][data-exit-parked]';
const DONE = "[data-splash='done']";
const SELECTORS: Record<ParkTarget, string[]> = {
  copy: [`${LIVE} ${DONE} [data-fw='hero']`],
  cue: [`${LIVE} ${DONE} [data-fw='hero-cue']`],
  card: [`[data-fw='hero-exit']${LIVE} ${DONE} [data-orbit-id]`, `${LIVE} ${DONE} [data-fw='hero-deck'] > article`],
};

/**
 * The park stylesheet, injected once (unlayered, so it wins over the `parts` layer): under the live conditions of
 * `threaded.module.css` a parked target has no animation and holds each fill value as static style.
 */
export function parkCss(): string {
  const rule = (t: ParkTarget, le600: boolean) =>
    `${SELECTORS[t].join(', ')} { animation-name: none; ${held(t, le600)
      .map(([p, v]) => `${p}: ${v};`)
      .join(' ')} }`;
  return [
    `@media ${mediaCondition('mq.rm-nopref')} {`,
    `@media ${mediaCondition('mq.w-gt-600')} {`,
    rule('copy', false),
    rule('cue', false),
    '}',
    `@media ${mediaCondition('mq.w-le-600')} {`,
    rule('copy', true),
    rule('cue', true),
    '}',
    rule('card', false),
    '}',
  ].join('\n');
}

/** Lean `sentinelTopPark`: where the observed sentinel sits below the track top. */
export function parkSentinelTop(trackHeight: number, viewportHeight: number): number {
  return exitRange(trackHeight, viewportHeight) + MARGIN_VIEWPORTS * viewportHeight;
}

/** Lean `ioParked`: parked in a frame exactly when the previous frame's observation saw the sentinel above the viewport top. */
export function ioParked(boundary: number, margin: number, yPrev: number): boolean {
  return boundary + margin < yPrev;
}

/** Lean `scrollParked`: the state after a scroll event of the frame. */
export function scrollParked(parkedBefore: boolean, boundary: number, y: number): boolean {
  return parkedBefore && boundary <= y;
}

export interface ParkDeps {
  setParked(on: boolean): void;
  /** Places the observed sentinel for the current geometry. */
  placeSentinel(): void;
  /** Watches the sentinel; the callback gets `true` while it is above the viewport top. Returns the stop. */
  watch(far: (far: boolean) => void): () => void;
  /** A passive scroll listener; returns the removal. */
  listenScroll(cb: () => void): () => void;
  /** The end of the range in document offset, read where the layout is clean (when the observer fires). */
  readBoundary(): number;
  scrollY(): number;
}

/**
 * Parks the finished animations while the observed sentinel is above the viewport top and restores them as soon as it is
 * not (observer rule, Lean `io_no_stale`), or on a scroll event that reaches the range (scroll rule, `scroll_no_stale`).
 * Idle cost: none; the scroll listener exists only while parked.
 */
export function createPark(deps: ParkDeps) {
  let parked = false;
  let boundary = 0;
  let stopScroll: (() => void) | null = null;
  let stopWatch: (() => void) | null = null;
  const unpark = () => {
    if (!parked) return;
    parked = false;
    deps.setParked(false);
    stopScroll?.();
    stopScroll = null;
  };
  const park = () => {
    if (parked) return;
    boundary = deps.readBoundary();
    parked = true;
    deps.setParked(true);
    stopScroll = deps.listenScroll(() => {
      if (!scrollParked(true, boundary, deps.scrollY())) unpark();
    });
  };
  const start = () => {
    deps.placeSentinel();
    stopWatch = deps.watch((far) => (far ? park() : unpark()));
  };
  start();
  return {
    isParked: () => parked,
    /** A geometry change: restore, place the sentinel again and observe afresh (the observer then reports the state). */
    resize() {
      unpark();
      stopWatch?.();
      start();
    },
    stop() {
      stopWatch?.();
      stopWatch = null;
      unpark();
    },
  };
}
