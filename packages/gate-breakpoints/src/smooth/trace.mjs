// Frame counts from a Chromium trace (task smoothness-probe, part B). A descriptive companion to the page's own rAF intervals: it
// says what the compositor did for the page (frames begun, drawn, presented, dropped) and where main-thread and raster time went,
// not whether a frame was bad; the verdict never reads it (it reads main-thread rAF cadence, see reduce.mjs).
// TS stand-in (no Lean twin): it only counts events, and the test replays fixed traces, one with two processes.
import { quantile } from './reduce.mjs';

/** The frame_reporter of a PipelineReporter event (Chromium puts it on the begin of the async pair; MEASURED in a debug run). */
const reporterOf = (e) => e.args?.frame_reporter ?? null;

const FRAME_EVENTS = ['BeginFrame', 'DrawFrame', 'DroppedFrame', 'BeginMainThreadFrame', 'ActivateLayerTree'];
const instant = (e) => e.ph === 'I' || e.ph === 'i' || e.ph === 'X' || e.ph === 'R';

/**
 * The compositor frame sink of the page. A trace holds every process: the browser process draws its own UI frames (its own
 * PipelineReporter pairs and layer tree), the GPU process draws, each renderer draws its page. The page is the renderer
 * process whose main thread began the most frames (`BeginMainThreadFrame`; ties go to the lower pid), and inside it the layer tree
 * with the most `DrawFrame` events. Returns null when the trace has no such process.
 * MEASURED (headless shell 156, debug run): Browser pid holds 6 reporter pairs on layer tree 3 and 6, the Renderer 211 on layer tree 2.
 */
export function pageSink(events) {
  const mainFrames = new Map();
  for (const e of events) if (e.name === 'BeginMainThreadFrame' && instant(e)) mainFrames.set(e.pid, (mainFrames.get(e.pid) ?? 0) + 1);
  let pid = null;
  for (const [p, n] of mainFrames) if (pid === null || n > mainFrames.get(pid) || (n === mainFrames.get(pid) && p < pid)) pid = p;
  if (pid === null) return null;
  const trees = new Map();
  for (const e of events) if (e.pid === pid && e.name === 'DrawFrame' && instant(e)) trees.set(e.args?.layerTreeId, (trees.get(e.args?.layerTreeId) ?? 0) + 1);
  let layerTree = null;
  for (const [t, n] of trees) if (layerTree === null || n > trees.get(layerTree) || (n === trees.get(layerTree) && t < layerTree)) layerTree = t;
  return { pid, layerTree: layerTree ?? null };
}

/**
 * Counts of one traced window, for the page's frame sink only: BeginFrame / DrawFrame / DroppedFrame / main-thread-frame events of
 * the sink's layer tree, and the PipelineReporter pairs of the sink by presentation state with their durations (tenths of ms).
 * One frame (`frame_sequence`) usually has two reporters (the compositor update and the main-thread update), so the per-frame
 * counts reduce each sequence: `dropped` when any of its reporters was dropped, else `presented` when any was presented, else
 * `noUpdate`; `droppedAll` counts the sequences in which every reporter was dropped (INFERRED reading of the states).
 */
export function summariseTrace(events) {
  const sink = pageSink(events);
  const names = Object.fromEntries(FRAME_EVENTS.map((n) => [n, 0]));
  const open = new Map();
  const states = {};
  const durs = [];
  const presentedDurs = [];
  const seqs = new Map();
  const inTree = (e) => sink !== null && e.pid === sink.pid && (sink.layerTree === null || e.args?.layerTreeId === undefined || e.args.layerTreeId === sink.layerTree);
  for (const e of events) {
    if (sink === null) break;
    if (e.name in names && instant(e) && inTree(e)) names[e.name]++;
    if (e.name !== 'PipelineReporter' || e.pid !== sink.pid) continue;
    const id = `${e.cat}|${e.id ?? e.id2?.local ?? e.id2?.global}`;
    if (e.ph === 'b') open.set(id, e);
    else if (e.ph === 'e') {
      const b = open.get(id);
      if (!b) continue;
      open.delete(id);
      const rep = reporterOf(e) ?? reporterOf(b);
      if (sink.layerTree !== null && rep?.layer_tree_host_id !== undefined && rep.layer_tree_host_id !== sink.layerTree) continue;
      const state = rep?.state ?? 'UNKNOWN';
      const d = Math.round((e.ts - b.ts) / 100);
      states[state] = (states[state] ?? 0) + 1;
      durs.push(d);
      if (state.startsWith('STATE_PRESENTED')) presentedDurs.push(d);
      const key = rep?.frame_sequence ?? `${b.ts}`;
      if (!seqs.has(key)) seqs.set(key, []);
      seqs.get(key).push(state);
    }
  }
  let presented = 0;
  let dropped = 0;
  let droppedAll = 0;
  let noUpdate = 0;
  for (const ss of seqs.values()) {
    if (ss.some((s) => s === 'STATE_DROPPED')) dropped++;
    else if (ss.some((s) => s.startsWith('STATE_PRESENTED'))) presented++;
    else noUpdate++;
    if (ss.every((s) => s === 'STATE_DROPPED')) droppedAll++;
  }
  const q = (xs, p) => (xs.length === 0 ? null : quantile(xs, p));
  return {
    sink,
    ...names,
    slow: slowOf(events, sink),
    reporters: durs.length,
    states,
    frames: seqs.size,
    presented,
    dropped,
    droppedAll,
    noUpdate,
    reporterP50: q(durs, 50),
    reporterP95: q(durs, 95),
    presentedP50: q(presentedDurs, 50),
    presentedP95: q(presentedDurs, 95),
    presentedMax: presentedDurs.length === 0 ? null : Math.max(...presentedDurs),
  };
}

/**
 * The fixed set of event names the slow-event table reports per arm, each as (row label, trace names). The set never changes with the
 * data and no row is dropped for being short, so an absent event is a count of 0 in its row, not a missing row.
 * `ProxyMain::BeginMainFrame` is the main thread's BeginMainFrame; the two decode task wrappers are the software and GPU raster worker tasks.
 */
export const SLOW_NAMES = [
  ['BeginMainFrame', ['ProxyMain::BeginMainFrame']],
  ['Paint', ['Paint']],
  ['UpdateLayoutTree', ['UpdateLayoutTree']],
  ['Layout', ['Layout']],
  ['image decode task', ['SoftwareImageDecodeTaskImpl::RunOnWorkerThread', 'GpuImageDecodeTaskImpl::RunOnWorkerThread']],
];

/** Events of this many microseconds or more are listed one by one (15 ms). */
export const LONG_US = 15000;

/**
 * For each row of SLOW_NAMES, over the complete events (ph X) of the page's renderer process (`sink`; all processes when null): the
 * count of all events, the count of 15 ms or more, the longest and the summed duration (tenths of ms) and the durations of the
 * long ones. Every row is always present. It says where main-thread or raster time went in a window with a bad frame; it never
 * enters a verdict. The shape of the events is Chromium's trace format (name, ph, dur in microseconds).
 */
export function slowOf(events, sink = null) {
  const rows = SLOW_NAMES.map(([label, names]) => ({ name: label, names, n: 0, nLong: 0, max: 0, sum: 0, long: [] }));
  const byName = new Map(rows.flatMap((r) => r.names.map((n) => [n, r])));
  for (const e of events) {
    if (e.ph !== 'X' || typeof e.dur !== 'number') continue;
    if (sink && e.pid !== sink.pid) continue;
    const r = byName.get(e.name);
    if (!r) continue;
    const d = Math.round(e.dur / 100);
    r.n++;
    r.sum += d;
    r.max = Math.max(r.max, d);
    if (e.dur >= LONG_US) { r.nLong++; r.long.push(d); }
  }
  return rows.map(({ names: _names, ...r }) => r);
}

/** The events of a trace buffer (Playwright's stopTracing returns the JSON file as a Buffer). */
export const eventsOf = (buf) => {
  const j = JSON.parse(buf.toString('utf8'));
  return Array.isArray(j) ? j : j.traceEvents ?? [];
};
