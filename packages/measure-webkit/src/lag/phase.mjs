export const MIN_FRAMES = Object.freeze({ idle: 5, open: 30, close: 30 });

export const phaseOf = (down, up, t) => (t < down ? 'idle' : t < up ? 'open' : 'close');

export const framePhases = (marks, down, up) => marks.map((t) => phaseOf(down, up, t));

const count = (list, p) => list.filter((x) => x === p).length;

const sorted = (marks) => marks.every((t, i) => i === 0 || marks[i - 1] <= t);

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

export const rangesOf = (c) => ({ idle: [0, c.idle], open: [c.idle, c.idle + c.open], close: [c.idle + c.open, c.idle + c.open + c.close] });

export function phaseRanges(m, fixed) {
  if (!m.phases) return fixed;
  const c = classify(m.marks, m.phases.down, m.phases.up);
  return c.outcome === 'ok' ? rangesOf(c) : null;
}
