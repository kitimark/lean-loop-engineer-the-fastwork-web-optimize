// Twin of Fw.Measure.WebKitLagPhase (lean/Fw/Measure/WebKitLagPhase.lean), checked against the `phase` lines of
// packages/contracts/golden/measure/webkit-lag.jsonl in test/lag-phase.test.mjs.
export const MIN_FRAMES = Object.freeze({ idle: 5, open: 30, close: 30 });

export const phaseOf = (down, up, t) => (t < down ? 'idle' : t < up ? 'open' : 'close');

export const framePhases = (marks, down, up) => marks.map((t) => phaseOf(down, up, t));

const count = (list, p) => list.filter((x) => x === p).length;

const sorted = (marks) => marks.every((t, i) => i === 0 || marks[i - 1] <= t);

/** Frame counts per phase of one run, or the first reason it is not used (`outcome` is 'ok' or a refusal name). */
export function classify(marks, down, up) {
  if (!sorted(marks)) return { outcome: 'unsorted' };
  if (down === null || down === undefined) return { outcome: 'noDown' };
  if (up === null || up === undefined) return { outcome: 'noUp' };
  if (up < down) return { outcome: 'order' };
  const ph = framePhases(marks, down, up);
  const idle = count(ph, 'idle'), open = count(ph, 'open'), close = count(ph, 'close');
  if (idle < MIN_FRAMES.idle) return { outcome: 'idleShort' };
  if (open < MIN_FRAMES.open) return { outcome: 'openShort' };
  if (close < MIN_FRAMES.close) return { outcome: 'closeShort' };
  return { outcome: 'ok', idle, open, close };
}

/** Step index ranges [from, to) of the three phases of a used run (a phase is a block of frames: `framePhases_blocks`). */
export const rangesOf = (c) => ({ idle: [0, c.idle], open: [c.idle, c.idle + c.open], close: [c.idle + c.open, c.idle + c.open + c.close] });

/** The phase ranges of a recorded morph run (`marks` and `phases: {down, up}` as `probe.mjs` writes them), or null when the rule refuses it. */
export function phaseRanges(m, fixed) {
  if (!m.phases) return fixed;
  const c = classify(m.marks, m.phases.down, m.phases.up);
  return c.outcome === 'ok' ? rangesOf(c) : null;
}
