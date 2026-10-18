// TS stand-in of Fw.Measure.Retry (lean/Fw/Measure/Retry.lean): which simulator errors are asked again, and the wait
// between attempts. Checked against the Lean goldens (packages/contracts/golden/measure/measure.retry*.jsonl,
// test/fwcore.test.mjs). Glue only: the markers, the rule and the constants are Lean's; nothing is decided here.

/** Lower-case substrings that mark an error as transient (Lean: `transientMarkers`). */
export const TRANSIENT_MARKERS = [
  'etimedout', 'timed out', 'unable to boot', 'device busy', 'device is busy', 'temporarily unavailable', 'eagain', 'ebusy',
  'connection invalid', 'connection interrupted', 'coresimulatorservice',
];
const lowerAscii = (s) => s.replace(/[A-Z]/g, (c) => c.toLowerCase()); // Lean's String.toLower lowercases ASCII only

/** @returns {'transient'|'permanent'} */
export const classify = (error) => {
  const l = lowerAscii(String(error));
  return TRANSIENT_MARKERS.some((m) => l.includes(m)) ? 'transient' : 'permanent';
};
/** Ask again iff transient and fewer than `max` attempts were made (`attempt` = attempts made, the failed one included). */
export const shouldRetry = (cls, attempt, max) => cls === 'transient' && attempt < max;
/** Wait in ms before attempt `attempt + 1` (Lean: `wait`, base 2000, cap 30000). */
export const wait = (attempt) => Math.min(30000, 2000 * 2 ** (Math.max(attempt, 1) - 1));

/** The `measure.retry` reply. */
export function retryReply({ error, attempt, max }) {
  const cls = classify(error);
  const retry = shouldRetry(cls, attempt, max);
  return { class: cls, retry, delayMs: retry ? wait(attempt) : 0 };
}
/** The `measure.retryPlan` reply. */
export function retryPlanReply({ errors, max }) {
  const classes = errors.map(classify);
  const delays = [];
  let outcome = 'succeeded';
  for (let i = 0; i < classes.length; i++) {
    if (!shouldRetry(classes[i], i + 1, max)) { outcome = classes[i] === 'transient' ? 'exhausted' : 'permanent'; break; }
    delays.push(wait(i + 1));
  }
  return { classes, delays, retries: delays.length, outcome };
}

/**
 * Run `call()` (sync; returns {status, error, stderr, stdout}) and ask again while the policy says so. `text(r)` is the
 * error text of a failed result; `sleepSync(ms)` the wait; `onRetry({attempt, delayMs, text})` is told before each wait.
 * Returns the last result. Never loops more than `max` times.
 */
export function withRetry(call, { max = 3, text, sleepSync, onRetry = () => {} }) {
  for (let attempt = 1; ; attempt++) {
    const r = call();
    if (r.status === 0) return r;
    const d = retryReply({ error: text(r), attempt, max });
    if (!d.retry) return r;
    onRetry({ attempt, delayMs: d.delayMs, text: text(r) });
    sleepSync(d.delayMs);
  }
}
