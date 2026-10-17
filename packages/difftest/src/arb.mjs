// fast-check arbitraries for wire requests. Numbers are small integers and halves so that JSON.stringify prints them
// exactly and Lean's decimal parser reads the same rational (no 1e21 forms, no float noise from arithmetic).
import fc from 'fast-check';

/** Integer in [min, max]. */
export const int = (min, max) => fc.integer({ min, max });
/** A multiple of 1/2 in [min, max]. */
export const half = (min, max) => fc.integer({ min: min * 2, max: max * 2 }).map((n) => n / 2);
/** A multiple of 1/10000 (a decimal Lean reads exactly) in [min, max]. */
export const quarterMilli = (min, max) => fc.integer({ min: Math.round(min * 10000), max: Math.round(max * 10000) }).map((n) => n / 10000);

/** Strictly increasing list of halves, length lo..hi. */
export const risingHalves = (lo, hi, span = 10) =>
  fc.array(fc.integer({ min: 1, max: span * 2 }), { minLength: lo, maxLength: hi }).chain((gaps) =>
    fc.integer({ min: 0, max: 20 }).map((s0) => {
      let t = s0;
      return gaps.map((g) => { t += g; return t / 2; });
    }));
