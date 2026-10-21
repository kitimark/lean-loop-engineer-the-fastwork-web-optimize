import { planShrink, shrink, shrinking } from './logic';

export interface ShrinkEl {
  /** the card whose bottom is read */
  cardBottom(): number;
  /** writes `--platform-shrink` on the section */
  setShrink(value: number): void;
  /** toggles the `is-platform-shrinking` state */
  setShrinking(on: boolean): void;
}

/**
 * The scroll-driven shrink of the section card (original nodes/2.DyWL8TcE.js:12434-12448): one read of the card bottom
 * and the viewport height per frame, two writes (a custom property and a class). The decision is the pure `shrink` /
 * `shrinking` of logic.ts (Lean `PlatformSection`). Returns the frame function the scroll engine calls.
 *
 * Variant `mq` (`opts.gate`, Lean `PlatformShrinkOpt`): while the gate holds (`mq.c860`, where the CSS pins the card) the
 * custom property is not written; the class still is. The frame also runs from the gate's change handler, so leaving the
 * band writes the current value at once (`lastShrink` only moves on a real write, so the first frame outside writes).
 */
export function createShrink(el: ShrinkEl, env: { reduced(): boolean; vh(): number }, opts: { gate?: () => boolean } = {}) {
  let lastShrink = Number.NaN;
  let lastOn: boolean | null = null;
  return function frame() {
    const bottom = el.cardBottom();
    const vh = env.vh();
    const s = shrink({ reduced: env.reduced(), bottom, vh });
    const on = shrinking({ bottom, vh });
    const plan = planShrink({ gated: opts.gate?.() === true, s, last: lastShrink });
    lastShrink = plan.last;
    if (plan.write) el.setShrink(s);
    if (on !== lastOn) {
      lastOn = on;
      el.setShrinking(on);
    }
  };
}
