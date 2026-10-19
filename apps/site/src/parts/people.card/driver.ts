import type { MotionClock } from '../../engine/clock';
import { frame } from './logic';

/** What the card driver reads and writes (DOM in the part, a fake in tests). */
export interface CardEnv {
  reduced(): boolean;
  narrow(): boolean;
  vh(): number;
  /** the hero track rect, or null when the page has none */
  track(): { top: number; height: number } | null;
  /** the card's bottom edge, or null when not mounted */
  cardBottom(): number | null;
  /** the heading block's top, or null when the Pain section is absent (its colour is not written then) */
  headerTop(): number | null;
  painPresent(): boolean;
  write: {
    revealed(on: boolean): void;
    shrink(value: number): void;
    shrinking(on: boolean): void;
    painDark(on: boolean): void;
  };
}

/**
 * The faithful per-frame handler of the card (N2:11296-11333): read the hero track, the card and the heading, write
 * `--future-shrink` on the section (a custom property on a subtree: the write the faithful variant keeps), the two state
 * classes and the Pain colour. It asks for another frame while the lerp has not reached its target. Scheduling: the scroll
 * engine's callback only requests one own rAF (`i ||= rAF(l)`, 11332); the body runs in it and re-requests itself.
 */
export function createCardDriver(env: CardEnv, clock: MotionClock, opts: { gate?: () => boolean } = {}) {
  let shrink = 0;
  let cancelOwn: (() => void) | null = null;

  const request = () => {
    cancelOwn ??= clock.subscribe(body, { own: true });
  };

  function body() {
    cancelOwn?.(); // one-shot: `i = 0`, then run
    cancelOwn = null;
    const painPresent = env.painPresent();
    const r = frame({
      reduced: env.reduced(),
      narrow: env.narrow(),
      vh: env.vh(),
      track: env.track(),
      cardBottom: env.cardBottom(),
      headerTop: env.headerTop(),
      shrink,
    });
    // Variant `mq` (Lean PeopleCardOpt `stepV`, ledger n=16): in the c860 band the CSS pins scale 1 and radius 0, so
    // `--future-shrink` is unread: skip its write and the self re-request; the class and the other writes stay.
    const gated = opts.gate?.() === true;
    env.write.revealed(r.revealed);
    if (r.shrink !== null && r.shrinking !== null) {
      if (!gated) {
        shrink = r.shrink;
        env.write.shrink(r.shrink);
      }
      env.write.shrinking(r.shrinking);
    }
    if (painPresent && r.painDark !== null) env.write.painDark(r.painDark);
    if (r.again && !gated) request();
  }

  return {
    /** the scroll engine's callback: request a frame */
    onScroll: request,
    /** the first run on mount (N2:11322 `l()`) */
    runNow: body,
    /** a media query changed (N2:11319-11320) */
    onMediaChange: request,
    get shrink() {
      return shrink;
    },
    dispose() {
      cancelOwn?.();
      cancelOwn = null;
    },
  };
}
