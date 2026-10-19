import { plan } from './steps';

/** The slice of `Element.animate` the boil needs (a fake in tests). */
export interface BoilTarget {
  animate(keyframes: { opacity: number }[], options: { duration: number; delay: number; fill: 'forwards' }): { cancel(): void };
}

/**
 * Variant `steps` driver (Lean `HeroAccentOpt.chain`): puts the step chain on the three boil boxes. `begin(elapsed)` is
 * called when the idle window opens (elapsed 0, or the CSS animation's age when taken over at mount) and again when the
 * section comes back into view while idle (the chain covers 2.4 s, longer than one idle wait); `end` cancels the chain
 * when the draw starts (the draw rules set the boxes' opacity themselves). No script runs between steps.
 */
export function createBoil(targets: readonly BoilTarget[]) {
  let live: { cancel(): void }[] = [];
  const end = () => {
    for (const a of live) a.cancel();
    live = [];
  };
  return {
    begin(elapsed: number) {
      end();
      targets.forEach((t, j) => {
        for (const s of plan(j, elapsed)) live.push(t.animate([{ opacity: s.opacity }, { opacity: s.opacity }], { duration: 0, delay: s.delay, fill: 'forwards' }));
      });
    },
    end,
    count: () => live.length,
  };
}
