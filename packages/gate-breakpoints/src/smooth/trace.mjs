// Frame counts from a Chromium trace (task smoothness-probe, part B). A descriptive companion to the page's own rAF intervals: it
// says what the compositor did (frames begun, drawn, dropped, presented), not whether a frame was bad; the verdict never reads it.
// TS stand-in (no Lean twin): it only counts events, and the test replays a fixed trace.
import { quantile } from './reduce.mjs';

/** The frame_reporter of a PipelineReporter event (Chromium puts it on the begin of the async pair; MEASURED in a debug run). */
const reporterOf = (e) => e.args?.frame_reporter ?? null;

/**
 * Counts of one traced window: BeginFrame / DrawFrame / DroppedFrame events of the devtools timeline, and the PipelineReporter pairs
 * by presentation state with their durations (tenths of ms, by begin and end timestamp).
 */
export function summariseTrace(events) {
  const names = { BeginFrame: 0, DrawFrame: 0, DroppedFrame: 0, BeginMainThreadFrame: 0, ActivateLayerTree: 0 };
  const open = new Map();
  const states = {};
  const durs = [];
  const presentedDurs = [];
  for (const e of events) {
    if (e.name in names && (e.ph === 'I' || e.ph === 'i' || e.ph === 'X' || e.ph === 'R')) names[e.name]++;
    if (e.name !== 'PipelineReporter') continue;
    const id = `${e.pid}:${e.id ?? e.id2?.local ?? e.id2?.global}`;
    if (e.ph === 'b') open.set(`${e.cat}|${id}`, e);
    else if (e.ph === 'e') {
      const b = open.get(`${e.cat}|${id}`);
      if (!b) continue;
      open.delete(`${e.cat}|${id}`);
      const rep = reporterOf(e) ?? reporterOf(b);
      const state = rep?.state ?? 'UNKNOWN';
      const d = Math.round((e.ts - b.ts) / 100);
      states[state] = (states[state] ?? 0) + 1;
      durs.push(d);
      if (state.startsWith('STATE_PRESENTED')) presentedDurs.push(d);
    }
  }
  const q = (xs, p) => (xs.length === 0 ? null : quantile(xs, p));
  return {
    ...names,
    pipelines: durs.length,
    states,
    pipelineP50: q(durs, 50),
    pipelineP95: q(durs, 95),
    presentedP50: q(presentedDurs, 50),
    presentedP95: q(presentedDurs, 95),
    presentedMax: presentedDurs.length === 0 ? null : Math.max(...presentedDurs),
    dropped: states.STATE_DROPPED ?? 0,
    noUpdate: states.STATE_NO_UPDATE_DESIRED ?? 0,
    presented: (states.STATE_PRESENTED_ALL ?? 0) + (states.STATE_PRESENTED_PARTIAL ?? 0),
  };
}

/** The events of a trace buffer (Playwright's stopTracing returns the JSON file as a Buffer). */
export const eventsOf = (buf) => {
  const j = JSON.parse(buf.toString('utf8'));
  return Array.isArray(j) ? j : j.traceEvents ?? [];
};
