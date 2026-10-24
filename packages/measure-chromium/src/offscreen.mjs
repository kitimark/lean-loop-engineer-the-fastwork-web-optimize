// Offscreen lane: per-run window sums of the frames in which one section is offscreen, and the verdict of a flag.
// The rules (hidden frame, settle mask, window sums, spread comparison, verdict) are specified and proved in Lean
// (lean/Fw/Measure/Offscreen.lean); the functions below up to `verdictAll` are a copy of them, checked against the
// golden vectors packages/contracts/golden/measure/offscreen.jsonl by test/offscreen.test.mjs.
// Everything after them is glue: trace attribution of the three counters the shared trace reducer does not have, file
// reading, the markdown table, and the commit-line reader of the workflow (a TS stand-in, listed in the tool doc).
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

export const SETTLE = 3;
export const MIN_RUNS = 3;
export const SLACK = 0;
export const KEYS = [
  'metric.RecalcStyleCount', 'metric.LayoutCount', 'trace.UpdateLayoutTree', 'trace.Layout', 'trace.PrePaint', 'trace.Paint',
  'trace.Commit', 'trace.cc.Draw', 'trace.cc.BeginMainFrame', 'trace.cc.NeedsTick', 'trace.cc.TickAnimations', 'trace.FireAnimationFrame',
];
// Read next to the verdict counters in the table, never by the verdict.
export const INFO_KEYS = ['trace.blink.ServiceScriptedAnimations', 'trace.cc.MainFrameAborted', 'busy.mainUs'];

// ---- copy of Fw.Measure.Offscreen (milli-px integers)
export const hidden = ({ top, height, vh }) => height === 0 || vh === 0 || top + height <= 0 || vh <= top;

export function runLen(hid) {
  let c = 0;
  return hid.map((b) => (c = b ? c + 1 : 0));
}
export const steady = (k, hid) => runLen(hid).map((n) => k < n);

export const sumWhere = (mask, xs) => xs.reduce((s, x, i) => s + (mask[i] ? x : 0), 0);

export function blockSums(mask, xs) {
  const out = [];
  let cur = null;
  for (let i = 0; i < mask.length && i < xs.length; i++) {
    if (mask[i]) cur = (cur ?? 0) + xs[i];
    else if (cur !== null) { out.push(cur); cur = null; }
  }
  if (cur !== null) out.push(cur);
  return out;
}

// recs: [{top, height, vh}] per frame; cols: {key: [per-frame counts]}. Returns the run's Vec {n, vals}.
export function windowVec(k, recs, cols) {
  const m = steady(k, recs.map(hidden));
  const vals = {};
  for (const [key, xs] of Object.entries(cols)) vals[key] = sumWhere(m, xs);
  return { n: m.filter(Boolean).length, vals };
}

export const reduction = (base, flag) => base - flag;

// b, f: [min, max] of the per-run window sums of one counter.
export function cmp(sl, b, f) {
  if (f[1] + sl < b[0]) return 'less';
  if (b[1] + sl < f[0]) return 'more';
  return 'same';
}

const spread = (xs) => [Math.min(...xs), Math.max(...xs)];

export function sameWindow(rs) {
  return rs.length > 0 && rs[0].n > 0 && rs.every((r) => r.n === rs[0].n);
}
export const hasKeys = (rs) => KEYS.every((k) => rs.every((r) => Number.isInteger(r.vals[k])));

export function usable(base, flag) {
  const all = [...base, ...flag];
  return MIN_RUNS <= base.length && MIN_RUNS <= flag.length && sameWindow(all) && hasKeys(all);
}

// Why a pair has no data, the first reason by the order of the Lean theorems; null when usable.
export function noDataWhy(base, flag) {
  const all = [...base, ...flag];
  if (base.length < MIN_RUNS) return `fewBase(${base.length})`;
  if (flag.length < MIN_RUNS) return `fewFlag(${flag.length})`;
  if (!sameWindow(all)) return all.some((r) => r.n === 0) ? 'emptyWindow' : 'windowDiffers';
  if (!hasKeys(all)) return 'missingKey';
  return null;
}

export function cmpKeys(base, flag) {
  const out = {};
  for (const k of KEYS) {
    const b = spread(base.map((r) => r.vals[k]));
    const f = spread(flag.map((r) => r.vals[k]));
    out[k] = { base: b, flag: f, cmp: cmp(SLACK, b, f), reduction: reduction(b[0], f[1]) };
  }
  return out;
}

export function judge(cs) {
  return cs.includes('more') ? 'noGain' : cs.includes('less') ? 'gain' : 'noGain';
}

export function verdict(base, flag) {
  if (!usable(base, flag)) return 'noData';
  return judge(Object.values(cmpKeys(base, flag)).map((c) => c.cmp));
}

export const verdictAll = (base, flags) => flags.map((f) => verdict(base, f));

// ---- glue: the counters the shared trace reducer (trace.mjs) does not count, attributed the same way
const MAIN_EXTRA = {
  'ProxyMain::BeginMainFrame': 'trace.cc.BeginMainFrame',
  MainFrameAborted: 'trace.cc.MainFrameAborted',
  'PageAnimator::serviceScriptedAnimations': 'trace.blink.ServiceScriptedAnimations',
  'AnimationHost::TickAnimations': 'trace.cc.TickAnimations',
  NeedsTickAnimations: 'trace.cc.NeedsTick',
};
const COMP_EXTRA = {
  'AnimationHost::TickAnimations': 'trace.cc.TickAnimations',
  NeedsTickAnimations: 'trace.cc.NeedsTick',
};
const COUNTED_PH = new Set(['B', 'X', 'I', 'i', 'R']);

// Per-frame counts of the extra keys. Main thread: console.timeStamp('F<n>') marks; compositor: Scheduler::BeginImplFrame windows.
// `seen` is the run total of every event name looked at, so a name that does not exist in this Chromium shows up as 0.
export function extraTraceCounts(events, nFrames) {
  const tn = new Map();
  for (const e of events) if (e.ph === 'M' && e.name === 'thread_name') tn.set(`${e.pid}:${e.tid}`, e.args?.name);
  const mainKeys = new Set(), rendererPids = new Set();
  for (const [k, n] of tn) if (n === 'CrRendererMain') { mainKeys.add(k); rendererPids.add(+k.split(':')[0]); }
  const perFrame = Array.from({ length: nFrames }, () => ({}));
  const seen = {};
  const bump = (o, k, v = 1) => { o[k] = (o[k] ?? 0) + v; };
  const byTs = (a, b) => a.ts - b.ts;
  let cur = -1;
  for (const e of events.filter((x) => mainKeys.has(`${x.pid}:${x.tid}`) && x.ph !== 'M').sort(byTs)) {
    if (e.name === 'TimeStamp' && /^F\d+$/.test(e.args?.data?.message ?? '')) { cur = +e.args.data.message.slice(1); continue; }
    const key = MAIN_EXTRA[e.name];
    if (key && COUNTED_PH.has(e.ph)) bump(seen, `main.${e.name}`);
    if (cur < 0 || cur >= nFrames) continue;
    if (key && COUNTED_PH.has(e.ph)) bump(perFrame[cur], key);
    if (e.name === 'RunTask' && e.ph === 'X') bump(perFrame[cur], 'busy.mainUs', Math.round(e.dur ?? 0));
  }
  const comp = events.filter((e) => rendererPids.has(e.pid) && tn.get(`${e.pid}:${e.tid}`) === 'Compositor' && e.ph !== 'M').sort(byTs);
  const bounds = comp.filter((e) => e.name === 'Scheduler::BeginImplFrame' && e.ph === 'X').map((e) => e.ts);
  const frameAt = (ts) => { let lo = 0, hi = bounds.length; while (lo < hi) { const m = (lo + hi) >> 1; if (bounds[m] <= ts) lo = m + 1; else hi = m; } return lo - 1; };
  for (const e of comp) {
    const key = COMP_EXTRA[e.name];
    if (!key || !COUNTED_PH.has(e.ph)) continue;
    bump(seen, `compositor.${e.name}`);
    const f = frameAt(e.ts);
    if (f >= 0 && f < nFrames) bump(perFrame[f], key);
  }
  return { perFrame, seen, beginImplFrames: bounds.length };
}

// One run: counts.json (with cardProbe frames) and the extra trace counts -> the run record the summary reads.
export function reduceRun(counts, extra, { label = null, run = null, settle = SETTLE } = {}) {
  const frames = counts.frames;
  const probe = counts.cardProbe;
  if (!probe || probe.error) throw new Error(`no section rects: cardProbe ${probe ? probe.error : 'missing'}`);
  if (probe.frames.length !== frames.length) throw new Error(`cardProbe has ${probe.frames.length} frames, counts ${frames.length}`);
  const vh = Math.round(counts.meta.viewport.height * 1000);
  const recs = probe.frames.map((p, n) => {
    if (!p.found || !Array.isArray(p.rect)) throw new Error(`frame ${n}: no element ${probe.selector}`);
    return { top: Math.round(p.rect[1] * 1000), height: Math.round(p.rect[3] * 1000), vh };
  });
  const cols = {};
  for (const key of [...KEYS, ...INFO_KEYS]) {
    cols[key] = frames.map((f, n) => f.counts[key] ?? extra?.perFrame?.[n]?.[key] ?? 0);
  }
  const verdictCols = Object.fromEntries(KEYS.map((k) => [k, cols[k]]));
  const mask = steady(settle, recs.map(hidden));
  const vec = windowVec(settle, recs, verdictCols);
  const info = windowVec(settle, recs, Object.fromEntries(INFO_KEYS.map((k) => [k, cols[k]]))).vals;
  const hiddenFrames = recs.filter(hidden).length;
  return {
    schema: 'fw.offscreen/1',
    label, run, target: counts.meta.target ?? null, search: counts.meta.search ?? null, selector: probe.selector, settle,
    frames: frames.length, hiddenFrames, vec, info,
    blocks: Object.fromEntries(KEYS.map((k) => [k, blockSums(mask, cols[k])])),
    phases: [...new Set(frames.map((f) => f.phase))],
    seen: extra?.seen ?? {}, beginImplFrames: extra?.beginImplFrames ?? null,
    rect: { topMin: Math.min(...recs.map((r) => r.top)), topMax: Math.max(...recs.map((r) => r.top)), height: recs[0].height, vh },
    mask,
  };
}

// ---- glue: the summary over a directory of run records
const fmt = (b) => (b[0] === b[1] ? `${b[0]}` : `${b[0]}..${b[1]}`);

export function groupRuns(records) {
  const arms = new Map();
  for (const r of records) {
    if (!arms.has(r.label)) arms.set(r.label, []);
    arms.get(r.label).push(r);
  }
  return arms;
}

// base label `rewrite`, `original` is the reference, every other label is a flag arm decided on its own.
export function summarize(records, { base = 'rewrite', reference = 'original', armmap = {} } = {}) {
  const arms = groupRuns(records);
  const runs = (l) => (arms.get(l) ?? []).map((r) => ({ n: r.vec.n, vals: r.vec.vals }));
  const flags = [...arms.keys()].filter((l) => l !== base && l !== reference).sort();
  const out = { base, reference, armmap, arms: {}, flags: {} };
  for (const [label, rs] of arms) {
    out.arms[label] = { runs: rs.length, runIds: rs.map((r) => r.run), n: rs.map((r) => r.vec.n), hiddenFrames: rs.map((r) => r.hiddenFrames), info: rs.map((r) => r.info) };
  }
  const baseRuns = runs(base);
  for (const f of flags) {
    const fr = runs(f);
    const why = noDataWhy(baseRuns, fr);
    out.flags[f] = { verdict: verdict(baseRuns, fr), why, keys: why === null ? cmpKeys(baseRuns, fr) : null };
  }
  if (arms.has(reference)) {
    const rr = runs(reference);
    out.reference = { label: reference, window: why0(rr), perFrame: perFrame(rr) };
  }
  out.basePerFrame = perFrame(baseRuns);
  return out;
}
const why0 = (rs) => (rs.length ? fmt(spread(rs.map((r) => r.n))) : '0');
function perFrame(rs) {
  const o = {};
  if (rs.length === 0 || rs.some((r) => r.n === 0)) return o;
  for (const k of KEYS) o[k] = fmt(spread(rs.map((r) => Math.round((r.vals[k] / r.n) * 1000) / 1000)));
  return o;
}

export function markdown(sum) {
  const L = [];
  L.push(`Window sums over the steady offscreen frames of one run (settle ${SETTLE} frames per offscreen stretch), min..max over the runs of an arm.`);
  const name = (l) => (sum.armmap?.[l] ? `${l} (${sum.armmap[l]})` : l);
  L.push('', '| arm | runs | window frames | run ids |', '|---|---|---|---|');
  for (const [l, a] of Object.entries(sum.arms)) L.push(`| ${name(l)} | ${a.runs} | ${[...new Set(a.n)].join(', ')} | ${a.runIds.join(', ')} |`);
  for (const [f, v] of Object.entries(sum.flags)) {
    L.push('', `### ${name(f)} vs ${sum.base}: ${v.verdict}${v.why ? ` (${v.why})` : ''}`);
    if (!v.keys) continue;
    L.push('', `| counter | ${sum.base} | ${f} | cmp | guaranteed reduction |`, '|---|---|---|---|---|');
    for (const [k, c] of Object.entries(v.keys)) L.push(`| ${k} | ${fmt(c.base)} | ${fmt(c.flag)} | ${c.cmp} | ${c.reduction} |`);
  }
  if (sum.reference && sum.reference.perFrame) {
    L.push('', `### per frame, window sum divided by window frames (not in the verdict)`, '', `| counter | ${sum.base} | ${sum.reference.label} |`, '|---|---|---|');
    for (const k of KEYS) L.push(`| ${k} | ${sum.basePerFrame[k] ?? '-'} | ${sum.reference.perFrame[k] ?? '-'} |`);
  }
  return L.join('\n') + '\n';
}

// ---- glue: the commit-line reader (TS stand-in, tested in offscreen.test.mjs)
export const LINE_KEYS = ['profile', 'runs', 'target', 'arms', 'preset', 'fw'];
export function parseLine(message) {
  const m = /\[counts ([^\]]*)\]/.exec(message ?? '');
  if (!m) return {};
  const out = {};
  for (const tok of m[1].split(/\s+/).filter(Boolean)) {
    const i = tok.indexOf('=');
    if (i < 1) throw new Error(`counts line: "${tok}" is not key=value`);
    const k = tok.slice(0, i), v = tok.slice(i + 1);
    if (!LINE_KEYS.includes(k)) throw new Error(`counts line: unknown key "${k}"`);
    if (!/^[A-Za-z0-9.:,_@|-]+$/.test(v)) throw new Error(`counts line: bad value for ${k}`);
    out[k] = v;
  }
  return out;
}

// ---- CLI
function arg(args, name) { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; }

function findRecords(dir) {
  const out = [];
  const walk = (d) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      if (e.isDirectory()) walk(join(d, e.name));
      else if (e.name === 'offscreen.json') out.push(JSON.parse(readFileSync(join(d, e.name), 'utf8')));
    }
  };
  walk(dir);
  return out;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [cmd, ...rest] = process.argv.slice(2);
  if (cmd === 'reduce') {
    const counts = JSON.parse(readFileSync(rest[0], 'utf8'));
    const tracePath = arg(rest, '--trace');
    let extra = null;
    if (tracePath && existsSync(tracePath)) {
      const t = JSON.parse(readFileSync(tracePath, 'utf8'));
      extra = extraTraceCounts(t.traceEvents ?? t, counts.frames.length);
    }
    const rec = reduceRun(counts, extra, { label: arg(rest, '--label') ?? null, run: arg(rest, '--run') ?? null });
    writeFileSync(arg(rest, '--out') ?? 'offscreen.json', JSON.stringify(rec) + '\n');
    console.error(`offscreen: ${rec.label}/${rec.run}: ${rec.frames} frames, ${rec.hiddenFrames} hidden, window ${rec.vec.n}; seen ${JSON.stringify(rec.seen)}`);
  } else if (cmd === 'summarize') {
    const dir = rest[0];
    const sum = summarize(findRecords(dir), { armmap: arg(rest, '--armmap') ? JSON.parse(arg(rest, '--armmap')) : {} });
    const md = markdown(sum);
    if (arg(rest, '--json')) writeFileSync(arg(rest, '--json'), JSON.stringify(sum, null, 1) + '\n');
    if (arg(rest, '--md')) writeFileSync(arg(rest, '--md'), md);
    process.stdout.write(md);
  } else if (cmd === 'line') {
    const p = parseLine(readFileSync(rest[0] ?? 0, 'utf8'));
    for (const [k, v] of Object.entries(p)) console.log(`${k}=${v}`);
  } else {
    console.error('usage: offscreen.mjs reduce <counts.json> [--trace trace.json] [--label L] [--run R] [--out f] | summarize <dir> [--armmap json] [--json f] [--md f] | line <message file>');
    process.exit(2);
  }
}
