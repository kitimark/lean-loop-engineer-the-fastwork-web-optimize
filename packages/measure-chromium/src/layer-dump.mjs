// Probe only (task morph-layers, branch ci/morph-layers-probe; never landed): per-frame cc layer list with Blink's
// debug info from a dumped trace. With disabled-by-default-devtools.timeline.layers on, Blink fills cc::LayerDebugInfo
// (local_frame_view.cc UpdatePaintDebugInfoEnabled, frame_viewer_instrumentation.h CategoryLayerTree@f842f52) and
// LayerImpl::AsValueInto writes layer_name, owner_node and compositing_reasons (layer_impl.cc:883-895@f842f52).
// Frame n is the n-th Scheduler::BeginImplFrame window, as in trace.mjs.
//   node layer-dump.mjs <trace.json> > layers.json
import { readFileSync } from 'node:fs';

const raw = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const events = raw.traceEvents ?? raw;
const threadName = new Map();
for (const e of events) if (e.ph === 'M' && e.name === 'thread_name') threadName.set(`${e.pid}:${e.tid}`, e.args?.name);
const rendererPids = new Set();
for (const [k, n] of threadName) if (n === 'CrRendererMain') rendererPids.add(+k.split(':')[0]);
const comp = events.filter((e) => rendererPids.has(e.pid) && threadName.get(`${e.pid}:${e.tid}`) === 'Compositor' && e.ph !== 'M').sort((a, b) => a.ts - b.ts);
const bounds = comp.filter((e) => e.name === 'Scheduler::BeginImplFrame' && e.ph === 'X').map((e) => e.ts);
const frameAt = (ts) => { let lo = 0, hi = bounds.length; while (lo < hi) { const m = (lo + hi) >> 1; if (bounds[m] <= ts) lo = m + 1; else hi = m; } return lo - 1; };
const frames = {};
for (const e of comp) {
  if (e.name !== 'LayerTreeHostImpl:snapshot' || e.ph !== 'I' || !e.args?.snapshot) continue;
  const f = frameAt(e.ts);
  const layers = (e.args.snapshot.active_tree?.layers ?? []).map((l) => ({
    id: l.layer_id, name: l.layer_name ?? null, owner: l.owner_node ?? null, reasons: l.compositing_reasons ?? [], ids: l.compositing_reason_ids ?? [],
    w: l.bounds?.width ?? 0, h: l.bounds?.height ?? 0, draws: !!l.draws_content, opacity: l.opacity, effect: l.effect_tree_index, transform: l.transform_tree_index,
  }));
  (frames[f] ??= []).push(layers);
}
const anims = events.filter((e) => rendererPids.has(e.pid) && e.name === 'Animation' && (e.ph === 'b' || e.ph === 'e' || e.ph === 'n')).sort((a, b) => a.ts - b.ts)
  .map((e) => ({ frame: frameAt(e.ts), ph: e.ph, id: e.id2?.local ?? e.id ?? null, name: e.args?.data?.name ?? null, state: e.args?.data?.state ?? null }));
process.stdout.write(JSON.stringify({ frames: bounds.length, perFrame: frames, animations: anims }) + '\n');
