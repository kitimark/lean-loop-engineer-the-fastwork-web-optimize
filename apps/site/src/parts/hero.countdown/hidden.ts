import { createWriteGate, sceneHidden } from '../engine.scene/logic';
import type { Writable } from './driver';

/**
 * Variant `hidden-pause` of the hero clock (Lean `Fw.Parts.HeroCountdownHidden`, golden
 * packages/contracts/golden/parts/hero.countdown.hidden.jsonl).
 */

/** Lean `grow`: one viewport height of margin above and below. */
export const FAR_ROOT_MARGIN = '100% 0px';

/** Lean `gateHidden`: the written `--exit-opacity` is exactly 0, or the track is far (`farOff`). `null`: not written yet. */
export function countdownHidden(exit: number | null, far: boolean): boolean {
  return exit === 0 || far;
}

/** The stage's inline `--exit-opacity` as hero.exit wrote it; `null` when absent or not a number. */
export function parseExit(value: string): number | null {
  if (value.trim() === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

export interface HiddenGate {
  /** A Writable whose `transform` writes pass through the gate. */
  wrap(el: HTMLElement): Writable;
  stop(): void;
  readonly hidden: boolean;
  readonly skipped: number;
}

/**
 * Hold the face writes while the clock paints nothing. The exit signal is a MutationObserver on the stage's `style`
 * (hero.exit writes `--exit-opacity` there in a rAF callback; the record is delivered at the next microtask checkpoint,
 * so the gate opens before that frame paints). The far signal is an IntersectionObserver on the track with
 * {@link FAR_ROOT_MARGIN}; its callback is a posted task (intersection_observer_controller.cc:90-97@f842f52), so it is
 * one frame late, which the one-viewport margin absorbs unless the page jumps more than a viewport in one frame.
 * Without a stage or track ancestor the matching signal stays open.
 */
export function installHiddenGate(
  root: HTMLElement,
  IO: typeof IntersectionObserver = IntersectionObserver,
  MO: typeof MutationObserver = MutationObserver,
): HiddenGate {
  const gate = createWriteGate<HTMLElement>((el, v) => {
    el.style.transform = v;
  });
  const stage = root.closest<HTMLElement>('[data-splash]');
  const track = root.closest<HTMLElement>('[data-fw="hero-exit"]');
  let exit: number | null = null;
  let far = false;
  const apply = () => gate.setHidden(countdownHidden(exit, far));
  const readExit = () => {
    exit = stage ? parseExit(stage.style.getPropertyValue('--exit-opacity')) : null;
    apply();
  };
  const mo = stage ? new MO(readExit) : null;
  if (stage) mo!.observe(stage, { attributes: true, attributeFilter: ['style'] });
  readExit();
  const io = track
    ? new IO(
        (entries) => {
          for (const e of entries) far = sceneHidden(e.isIntersecting, e.intersectionRect.width, e.intersectionRect.height);
          apply();
        },
        { rootMargin: FAR_ROOT_MARGIN, threshold: [0] },
      )
    : null;
  if (track) io!.observe(track);
  return {
    wrap: (el) => ({
      style: {
        get transform() {
          return el.style.transform;
        },
        set transform(v: string) {
          gate.set(el, v);
        },
      },
    }),
    stop() {
      mo?.disconnect();
      io?.disconnect();
      gate.setHidden(false);
    },
    get hidden() {
      return gate.hidden;
    },
    get skipped() {
      return gate.skipped;
    },
  };
}
