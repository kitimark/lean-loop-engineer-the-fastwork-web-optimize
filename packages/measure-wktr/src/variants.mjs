// Harness variants of one lane run; the name is also the file prefix (counts-<name>-<pass>.json).
export const VARIANT_FLAGS = ['warm', 'still', 'trace'];

/**
 * `live` | `vt`, optionally followed by `-warm`, `-still` and/or `-trace` (any order; the name is normalised to this order).
 *   warm  scroll the page once first so lazy loads are done
 *   still diagnostic: internals.suspendAnimations() before the run (CSS animations and transitions stop; not a result)
 *   trace event counters for cause attribution
 */
export function parseVariant(name) {
  const parts = name.split('-');
  const base = parts.shift();
  if (base !== 'live' && base !== 'vt') throw new Error(`variant ${name}: must start with live or vt`);
  const flags = new Set(parts);
  for (const f of flags) if (!VARIANT_FLAGS.includes(f)) throw new Error(`variant ${name}: unknown flag ${f}`);
  return { name: [base, ...VARIANT_FLAGS.filter((f) => flags.has(f))].join('-'), vt: base === 'vt', warm: flags.has('warm'), still: flags.has('still'), trace: flags.has('trace') };
}
