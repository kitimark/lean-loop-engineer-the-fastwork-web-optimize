const MICRO_DEN = 1000000000n;

const norm = (s) => (s === '' || s === undefined ? null : s);

export function identOf(fw, layer) {
  const l = norm(layer), f = norm(fw);
  if (l !== null && l !== undefined) return { kind: 'box', id: l };
  if (f !== null && f !== undefined) return { kind: 'part', id: f };
  return { kind: 'free', id: '' };
}

const identKey = (i) => `${i.kind}:${i.id}`;
export const layerIdent = (l) => identOf(l.fw, l.layer);
export const nBox = (id, layers) => layers.filter((l) => { const i = layerIdent(l); return i.kind === 'box' && i.id === id; }).length;

export const undeclared = (layers) => layers.filter((l) => layerIdent(l).kind === 'free').map((l) => ({ name: l.name, bounds: l.bounds }));

export const RUNNER_STEMS = ['#document', 'span.accent-module_frame_', 'svg.accent-module_svg_', 'div.typing-module_visual_', 'div.typing-module_beat_', 'span.typing-module_avatar_', 'span.frame.', 'svg.accent-svg.', 'button.scroll-cue.', 'section.commission.', 'div.fee-visual', 'div.body.svelte-ty4hd7'];
export const varying = (name) => RUNNER_STEMS.some((s) => name.startsWith(s));
export const gone = (l) => l.reasons?.length === 1 && l.reasons[0] === '(gone)';
export const stable = (layers) => layers.filter((l) => layerIdent(l).kind === 'free' && !gone(l) && !varying(l.name)).map((l) => ({ name: l.name, bounds: l.bounds }));

const boxKey = (b) => `${b.name}\u0000${b.bounds ? b.bounds.join(',') : ''}`;
const countOf = (list, b) => list.reduce((n, x) => n + (boxKey(x) === boxKey(b) ? 1 : 0), 0);

export function firstDiff(a, b) {
  return [...a, ...b].find((x) => countOf(a, x) !== countOf(b, x)) ?? null;
}

const floorDiv = (n, d) => { const q = n / d; return (n % d !== 0n && (n < 0n) !== (d < 0n)) ? q - 1n : q; };

export function gridOk(dpr, o) {
  const n = BigInt(o) * BigInt(dpr);
  const r = floorDiv(2n * n + MICRO_DEN, 2n * MICRO_DEN);
  const e = n - r * MICRO_DEN;
  return (e < 0n ? -e : e) * 10000n <= MICRO_DEN;
}

const countIn = (xs, id) => xs.filter((x) => x === id).length;

function compositeRefusals(side, w, s) {
  const out = [];
  for (const id of [...w.composite, ...w.snap]) {
    const n = countIn(s.rendered, id), k = nBox(id, s.layers);
    if (n === 0 || k < n) out.push({ code: 'notComposited', side, y: s.y, box: id, layers: k, rendered: n });
  }
  return out;
}

function gridRefusals(side, w, dpr, s) {
  const out = [];
  for (const l of s.layers) {
    const i = layerIdent(l);
    if (i.kind !== 'box' || !w.snap.includes(i.id)) continue;
    if (!l.origin) { out.push({ code: 'noOrigin', side, y: s.y, box: i.id }); continue; }
    if (!gridOk(dpr, l.origin[0])) out.push({ code: 'offGrid', side, y: s.y, box: i.id, axis: 'x' });
    if (!gridOk(dpr, l.origin[1])) out.push({ code: 'offGrid', side, y: s.y, box: i.id, axis: 'y' });
  }
  return out;
}

const armRefusals = (side, w, arm) => arm.samples.flatMap((s) => [...compositeRefusals(side, w, s), ...gridRefusals(side, w, arm.dpr, s)]);

function undeclaredRefusals(a, b) {
  const out = [];
  a.samples.forEach((sa, i) => {
    const sb = b.samples[i];
    if (!sb) return;
    const ua = stable(sa.layers), ub = stable(sb.layers);
    const x = firstDiff(ua, ub);
    if (x) out.push({ code: 'undeclared', y: sa.y, box: x.name, bounds: x.bounds, inA: countOf(ua, x), inB: countOf(ub, x) });
  });
  return out;
}

export function refusals(wantA, wantB, a, b) {
  if (a.dpr !== b.dpr) return [{ code: 'viewport', a: a.dpr, b: b.dpr }];
  const ya = a.samples.map((s) => s.y), yb = b.samples.map((s) => s.y);
  if (ya.length !== yb.length || ya.some((y, i) => y !== yb[i])) return [{ code: 'samples', a: ya, b: yb }];
  const n = Math.min(a.samples.length, b.samples.length);
  return [...undeclaredRefusals({ samples: a.samples.slice(0, n) }, { samples: b.samples.slice(0, n) }), ...armRefusals('a', wantA, a), ...armRefusals('b', wantB, b)];
}

export function rows(layers) {
  const seen = new Map();
  for (const l of layers) {
    const i = layerIdent(l);
    if (i.kind === 'free') continue;
    const row = seen.get(identKey(i)) ?? { kind: i.kind, id: i.id, n: 0, bytes: 0 };
    row.n += 1;
    row.bytes += l.bytes ?? 0;
    seen.set(identKey(i), row);
  }
  return [...seen.values()];
}

export function describeRefusal(r) {
  switch (r.code) {
    case 'viewport': return `pixel ratio differs (${r.a} vs ${r.b} thousandths)`;
    case 'samples': return `sample offsets differ (${r.a.join(',')} vs ${r.b.join(',')})`;
    case 'undeclared': return `undeclared layer ${JSON.stringify(r.box)} bounds ${r.bounds ? r.bounds.join(',') : '?'} at y=${r.y}: ${r.inA} in A, ${r.inB} in B`;
    case 'notComposited': return `${r.box} at y=${r.y} (${r.side.toUpperCase()}): ${r.layers} layers for ${r.rendered} rendered nodes`;
    case 'noOrigin': return `${r.box} at y=${r.y} (${r.side.toUpperCase()}): no origin read`;
    case 'offGrid': return `${r.box} at y=${r.y} (${r.side.toUpperCase()}): ${r.axis} origin is off the device-pixel grid`;
    default: return JSON.stringify(r);
  }
}

export const sampleUsable = (c) => !c.error && Number.isFinite(c.dprMilli);

const layerOf = (l) => ({
  name: l.name ?? '?', fw: l.fw ?? null, layer: l.layer ?? null, bounds: l.boundsU ?? null, origin: l.origin ?? null,
  reasons: l.reasons ?? [], bytes: Number.isFinite(l.memory) ? l.memory : null,
});

export const armOf = (samples) => ({
  dpr: samples[0]?.dprMilli ?? null,
  samples: samples.map((c) => ({ y: c.requestedY, rendered: c.rendered ?? [], layers: (c.layers ?? []).map(layerOf) })),
});

export function wantOf(spec, arm) {
  if (!spec || spec === 'none') return [];
  if (spec === 'all') return [...new Set(arm.samples.flatMap((s) => s.rendered))].sort();
  return String(spec).split(',').map((s) => s.trim()).filter(Boolean);
}

export function checkPair(samplesA, samplesB, { composite = 'none', snap = 'none' } = {}) {
  const unavailable = [...samplesA.map((c, i) => ['a', i, c]), ...samplesB.map((c, i) => ['b', i, c])]
    .filter(([, , c]) => !sampleUsable(c)).map(([side, i, c]) => ({ side, index: i, error: c.error ?? 'no pixel ratio' }));
  if (unavailable.length) return { state: 'unavailable', unavailable, refusals: [], lines: unavailable.map((u) => `unavailable ${u.side}[${u.index}]: ${u.error}`) };
  const a = armOf(samplesA), b = armOf(samplesB);
  const want = (arm) => ({ composite: wantOf(composite, arm), snap: wantOf(snap, arm) });
  const rs = refusals(want(a), want(b), a, b);
  return { state: rs.length ? 'refused' : 'accepted', unavailable: [], refusals: rs, lines: rs.map(describeRefusal) };
}

export function declaredTable(samples) {
  return samples.filter(sampleUsable).map((c) => {
    const layers = (c.layers ?? []).map(layerOf);
    const byId = new Map();
    for (const id of c.rendered ?? []) byId.set(id, { id, rendered: (byId.get(id)?.rendered ?? 0) + 1, layers: 0, bytes: 0 });
    for (const r of rows(layers)) if (r.kind === 'box') byId.set(r.id, { id: r.id, rendered: byId.get(r.id)?.rendered ?? 0, layers: r.n, bytes: r.bytes });
    return { y: c.requestedY, declared: [...byId.values()].sort((x, y) => (x.id < y.id ? -1 : 1)), undeclared: undeclared(layers).length, partOnly: rows(layers).filter((r) => r.kind === 'part').length };
  });
}

export function censusVerdict(passes, opts) {
  const samples = passes.map((p) => p.census);
  const pairs = samples.slice(1).map((s, i) => ({ pair: `pass ${i + 2} vs pass 1`, ...checkPair(samples[0], s, opts) }));
  return { pairs, state: pairs.some((p) => p.state === 'refused') ? 'refused' : pairs.some((p) => p.state === 'unavailable') ? 'unavailable' : 'accepted', declared: samples[0] ? declaredTable(samples[0]) : [] };
}
