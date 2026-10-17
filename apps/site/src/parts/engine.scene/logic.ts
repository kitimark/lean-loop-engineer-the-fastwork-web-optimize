/**
 * Hidden pause, decisions (Lean `Fw.Parts.HiddenPause`, lean/Fw/Parts/HiddenPause.lean). Pure; the DOM wiring is in
 * observe.ts. The constants below are pinned to the Lean source by logic.test.ts (it parses the Lean file), so a
 * change in Lean fails the test instead of drifting.
 */

/** `hiddenPause m = decide (m <= 2/25)`: a box is hidden while its visible fraction is at most this (0.08). */
export const HIDDEN_FRACTION = 2 / 25;

/** `scenePaused m = !decide (1/1000 < m)`: the original's scene scheduler runs the marquee only above this. */
export const SCENE_ACTIVE_ABOVE = 1 / 1000;

/** `hiddenPause`: pause exactly while the visible fraction is at most HIDDEN_FRACTION. */
export const hiddenAtFraction = (fraction: number): boolean => fraction <= HIDDEN_FRACTION;

/**
 * `sceneHidden vp R = !vp.meets R`: hidden once the box has no positive-area overlap with the viewport. An
 * IntersectionObserver entry that only touches an edge reports isIntersecting with a zero-size intersection rect.
 */
export const sceneHidden = (isIntersecting: boolean, width: number, height: number): boolean =>
  !(isIntersecting && width > 0 && height > 0);

/** `scenePaused` as the original sets `data-start-selling-scene`: true while the morph is at most 0.001. */
export const scenePausedAtMorph = (morph: number): boolean => !(SCENE_ACTIVE_ABOVE < morph);

/**
 * `origClock`: the local clock of the original's animation. It advances only while the scene is active (not
 * `scenePaused`). The variant seeks its animations to `read(now)` on resume (a plain play-state pause would shift the
 * phase: `naive_pause_shifts`). Times are in ms on one timeline.
 */
export function createSceneClock(t0: number, active: boolean) {
  let acc = 0;
  let since = t0;
  let on = active;
  return {
    setActive(now: number, next: boolean) {
      if (next === on) return;
      if (on) acc += now - since;
      since = now;
      on = next;
    },
    read(now: number): number {
      return on ? acc + (now - since) : acc;
    },
  };
}

/**
 * Holds a stream of writes while hidden and replays only the latest per key on unhide, in the same call (the IO
 * callback runs before paint: Lean `hsync`). While visible every write passes straight through.
 */
export function createWriteGate<K>(write: (key: K, value: string) => void) {
  let hidden = false;
  const pending = new Map<K, string>();
  let skipped = 0;
  return {
    set(key: K, value: string) {
      if (hidden) {
        pending.set(key, value);
        skipped++;
      } else write(key, value);
    },
    setHidden(next: boolean) {
      if (next === hidden) return;
      hidden = next;
      if (!next) {
        for (const [k, v] of pending) write(k, v);
        pending.clear();
      }
    },
    get skipped() {
      return skipped;
    },
    get hidden() {
      return hidden;
    },
  };
}
