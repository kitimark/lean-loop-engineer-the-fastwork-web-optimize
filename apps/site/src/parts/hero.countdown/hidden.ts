import { createWriteGate } from '../engine.scene/logic';
import type { Writable } from './driver';

/**
 * Variant `hidden-pause` of the hero clock (Lean `Fw.Parts.HeroCountdownHidden`, golden
 * packages/contracts/golden/parts/hero.countdown.hidden.jsonl).
 */

/** Lean `gateHidden`: the written `--exit-opacity` is exactly 0. `null`: not written yet. */
export function countdownHidden(exit: number | null): boolean {
  return exit === 0;
}

/** Lean `gatedInstance`: only the hero instance with variant `hidden-pause` gets the gate. */
export function gatedInstance(variant: string, fwId: string): boolean {
  return variant === 'hidden-pause' && fwId === 'hero-countdown';
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
 * so the gate opens before that frame paints). There is no distance signal: far above is already exit 0 and far below
 * cannot happen for the first section (Lean `farAbove_implies_exitZero`, `farBelow_unreachable`). Without a stage
 * ancestor the gate stays open.
 */
export function installHiddenGate(root: HTMLElement, MO: typeof MutationObserver = MutationObserver): HiddenGate {
  const gate = createWriteGate<HTMLElement>((el, v) => {
    el.style.transform = v;
  });
  const stage = root.closest<HTMLElement>('[data-splash]');
  const readExit = () => {
    gate.setHidden(countdownHidden(stage ? parseExit(stage.style.getPropertyValue('--exit-opacity')) : null));
  };
  const mo = stage ? new MO(readExit) : null;
  if (stage) mo!.observe(stage, { attributes: true, attributeFilter: ['style'] });
  readExit();
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
