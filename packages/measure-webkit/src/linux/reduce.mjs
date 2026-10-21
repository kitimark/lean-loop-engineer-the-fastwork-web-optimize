// Reducers of the Linux WebKit probe: rAF interval distribution and Web Inspector Timeline record counts per settled step.
// Pure functions over the raw run the probe writes (run.mjs). Descriptive only, no verdict.
//
// TS stand-in (listed in docs/team/handoffs/linux-webkit-probe.md): percentile / count reductions are not proved in Lean;
// they feed a research note, not a gate.

/** Nearest-rank percentile of an ascending array (p in 0..100). Empty input gives null. */
export function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  const k = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[k];
}

const round1 = (x) => (x === null ? null : Math.round(x * 10) / 10);

/** n, min, p50, p90, p99, max, mean of a list of numbers (milliseconds), rounded to 0.1. */
export function summarize(values) {
  const s = [...values].sort((a, b) => a - b);
  const n = s.length;
  const mean = n ? s.reduce((a, b) => a + b, 0) / n : null;
  return {
    n, min: round1(s[0] ?? null), p50: round1(percentile(s, 50)), p90: round1(percentile(s, 90)),
    p99: round1(percentile(s, 99)), max: round1(s[n - 1] ?? null), mean: round1(mean),
  };
}

/** Gaps between consecutive timestamps. */
export function intervals(ts) {
  const out = [];
  for (let i = 1; i < ts.length; i++) out.push(ts[i] - ts[i - 1]);
  return out;
}

/** Depth-first flat list of Timeline records: {type, start, end, ms, depth, data}. Times in the protocol are seconds. */
export function flatten(records, depth = 0, out = []) {
  for (const r of records ?? []) {
    const start = Number(r.startTime);
    const end = r.endTime === undefined ? start : Number(r.endTime);
    out.push({ type: String(r.type), start, end, ms: (end - start) * 1000, depth, data: r.data ?? null });
    flatten(r.children, depth + 1, out);
  }
  return out;
}

/** {type: {n, ms}}: record count and inclusive duration (children counted again in their parents) per type. */
export function countByType(flat) {
  const out = {};
  for (const r of flat) {
    const c = (out[r.type] ??= { n: 0, ms: 0 });
    c.n += 1;
    c.ms += r.ms;
  }
  for (const c of Object.values(out)) c.ms = round1(c.ms) ?? 0;
  return out;
}

/** Start time of the `TimeStamp` record whose data names `label` (performance.mark and console.timeStamp both land there); null when absent. */
export function stampTime(flat, label) {
  const hit = flat.find((r) => r.type === 'TimeStamp' && JSON.stringify(r.data).includes(`"${label}"`));
  return hit ? hit.start : null;
}

/** Per-step record counts: the records that start between the stamps `fw-s<i>` and `fw-e<i>`, with the stamps themselves left out. */
export function stepCounts(flat, nSteps) {
  const steps = [];
  for (let i = 0; i < nSteps; i++) {
    const a = stampTime(flat, `fw-s${i}`);
    const b = stampTime(flat, `fw-e${i}`);
    if (a === null || b === null) { steps.push({ i, delimited: false, window_ms: null, counts: {} }); continue; }
    const inside = flat.filter((r) => r.type !== 'TimeStamp' && r.start >= a && r.start <= b);
    steps.push({ i, delimited: true, window_ms: round1((b - a) * 1000), counts: countByType(inside) });
  }
  return steps;
}

/** rAF timestamps inside [t0, t1] (the in-page clock) and the gaps between them. */
export function framesIn(raf, t0, t1) {
  const ts = raf.filter((t) => t >= t0 && t <= t1);
  return { frames: ts.length, gaps: intervals(ts) };
}

/**
 * Reduce one raw run (arm x round) to the numbers the table shows.
 * raw: { idleRaf: number[], scrollRaf: number[], steps: [{i, t0, t1, wheelMs, scrollY}], records: Timeline records, fps: string[], renderer: string|null,
 *        timelineError: string|null }
 */
export function reduceRun(raw) {
  const flat = flatten(raw.records);
  const stepsRaw = raw.steps ?? [];
  const perStep = stepCounts(flat, stepsRaw.length).map((s, k) => {
    const st = stepsRaw[k];
    const f = framesIn(raw.scrollRaf ?? [], st.t0, st.t1);
    return { ...s, wheel_ms: round1(st.wheelMs), settle_ms: round1(st.t1 - st.t0), moved: st.scrollY, frames: f.frames, max_gap_ms: round1(Math.max(0, ...f.gaps)) };
  });
  const total = countByType(flat);
  return {
    idle: summarize(intervals(raw.idleRaf ?? [])),
    scroll: summarize(intervals(raw.scrollRaf ?? [])),
    wheel: summarize(stepsRaw.map((s) => s.wheelMs)),
    timeline: { records: flat.length, total, stepsDelimited: perStep.filter((s) => s.delimited).length, perStep },
    timelineError: raw.timelineError ?? null,
    fps: raw.fps ?? [],
    renderer: raw.renderer ?? null,
  };
}
