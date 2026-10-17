// Pure reduction of the page's raw samples to per-step counts, and the parser of WKTR's output. No I/O.
// TS STAND-IN (CLAUDE.md "Lean first"): this is pure counting arithmetic and needs a Lean spec and golden vectors
// (lean/Fw/Measure); nothing here classifies or decides. The class of a count type is Lean's (fwcore, mode `frames`).
//
// Raw schema (what harness.mjs prints): for step k, `b` is the sample S(k,0) taken at the start of the animation-frame
// callback that issues the scroll, `mids` are the samples of the following frames of the step (frames-1 of them), and
// the next step's `b` closes the window. A sample is { rc, sr, ls, si, lf, lu, cu }:
//   rc renderingUpdateCount(), sr styleRecalcCount(), ls lastStyleUpdateSize, si styleInvalidationTraversalCount,
//   lf layerFlushCount(), lu layoutUpdateCount(), cu compositingUpdateCount().
//
// Per step the samples S0 (b), S1.., Sn (next b) are consecutive animation frames, so each interval (Si, Si+1) holds
// the rendering work of ONE rendering update (renderingUpdateCount moves by 1 when native rAF fires once per update).
// For an interval, lastStyleUpdateSize read at its end is the size of the last style recalc inside it, valid only when
// styleRecalcCount moved: if it moved by exactly 1 the size is that recalc's; by more than 1 the earlier recalcs of the
// interval are not visible (Document.cpp:2914@862f17d overwrites the value) and the step is flagged `undercounted`.

const NUM = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);

/**
 * Count types of one step (all integers).
 *   styleUpdateSizeSum sum over the step's intervals of (recalc moved ? lastStyleUpdateSize : 0): elements AND text nodes
 *                      that got a new style (Style::Update::size, StyleUpdate.h:88@862f17d)
 *   lastStyleUpdateSize the raw value read at the step's end (stale when no recalc happened in the last interval)
 *   styleRecalcs       styleRecalcCount delta over the step
 *   undercountedRecalcs  sum over intervals of max(0, recalc delta - 1): recalcs whose size was lost
 *   renderingUpdates   renderingUpdateCount delta over the step (== frames when one rendering update per frame)
 *   layerFlushes, layoutUpdates, compositingUpdates, styleInvalidations  deltas
 */
export function stepCounts(samples) {
  if (samples.length < 2) throw new Error('a step needs at least 2 samples');
  let restyled = 0, under = 0;
  for (let i = 1; i < samples.length; i++) {
    const dsr = NUM(samples[i].sr) - NUM(samples[i - 1].sr);
    if (dsr > 0) restyled += NUM(samples[i].ls);
    if (dsr > 1) under += dsr - 1;
  }
  const a = samples[0], z = samples[samples.length - 1];
  const d = (key) => NUM(z[key]) - NUM(a[key]);
  // cause trace (variant flag `trace`): monotone event counters `ev` in the samples become `ev_<name>` deltas
  const evCounts = {};
  if (a.ev || z.ev) for (const k of new Set([...Object.keys(a.ev || {}), ...Object.keys(z.ev || {})])) evCounts[`ev_${k}`] = NUM(z.ev?.[k]) - NUM(a.ev?.[k]);
  return {
    ...evCounts,
    styleUpdateSizeSum: restyled,
    lastStyleUpdateSize: NUM(z.ls),
    styleRecalcs: d('sr'),
    undercountedRecalcs: under,
    renderingUpdates: d('rc'),
    layerFlushes: d('lf'),
    layoutUpdates: d('lu'),
    compositingUpdates: d('cu'),
    styleInvalidations: d('si'),
  };
}

/** Frames for the class policy: one per scroll step, { n, phase, scrollY, counts } (Fw.Measure.Wire frame shape). */
export function framesOf(steps, endSample) {
  const frames = steps.map((s, i) => {
    const next = i + 1 < steps.length ? steps[i + 1].b : endSample;
    return { n: i, phase: 'scroll', scrollY: s.y, counts: stepCounts([s.b, ...(s.mids || []), next]) };
  });
  // every frame carries every count type that any frame of the run has (a trace counter only exists after its first event)
  const keys = new Set(frames.flatMap((f) => Object.keys(f.counts)));
  for (const f of frames) for (const k of keys) if (!(k in f.counts)) f.counts[k] = 0;
  return frames;
}

/** Parse the `FWWKTR <tag> <json>` console lines out of WKTR's stdout text. */
export function parseOutput(text) {
  const got = { steps: [], error: null, done: false, meta: null, params: null, end: null, consoleLines: 0 };
  for (const line of text.split('\n')) {
    const m = /^(?:CONSOLE MESSAGE:\s*)?(?:line \d+: )?FWWKTR (\w+) (.*)$/.exec(line.trim());
    if (!m) { if (line.startsWith('CONSOLE MESSAGE')) got.consoleLines++; continue; }
    const v = JSON.parse(m[2]);
    if (m[1] === 'step') got.steps.push(v);
    else if (m[1] === 'meta') got.meta = v;
    else if (m[1] === 'params') got.params = v;
    else if (m[1] === 'end') got.end = v;
    else if (m[1] === 'error') got.error = v;
    else if (m[1] === 'done') got.done = true;
  }
  return got;
}

/** A run object for `classify.mjs` / fwcore from a parsed output. Throws on an incomplete run. */
export function buildRun(parsed, info) {
  if (parsed.error) throw new Error(`page reported an error: ${JSON.stringify(parsed.error)}`);
  if (!parsed.done || !parsed.meta || !parsed.end) throw new Error('incomplete page output (no done/meta/end line)');
  parsed.steps.forEach((s, i) => { if (s.k !== i) throw new Error(`step ${i} has k=${s.k}`); });
  return { schema: 'fw.wktr.scroll/1', meta: { ...info, page: parsed.meta, params: parsed.params, steps: parsed.steps.length },
    frames: framesOf(parsed.steps, parsed.end.b) };
}
