// The ONLY reduction in the TS harness: raw per-frame counts -> per-zone sums. Pure, total, no decisions.
// To be specified in Lean (Fw/Spec/Frames) with golden vectors; everything past this (per-100px normalisation, landing
// class, dominance screening, verdicts) is Lean's, not computed here.
//
// zoneSums(frames, zoneHeightPx): frames are { n, phase, scrollY, counts: {name: number} }. A frame belongs to zone
// floor(scrollY / zoneHeightPx) when phase is "swipe", else to the zone named by its phase ("rest", "tail").
// Each zone reports: frames, scrolledPx (sum of the scrollY increments of its frames), firstFrame, lastFrame and the
// sum of every count over its frames. Zones are listed in order of first appearance.
export function zoneSums(frames, zoneHeightPx) {
  const zones = new Map();
  let prevY = 0;
  for (const f of frames) {
    const id = f.phase === 'swipe' ? `y${String(Math.floor(f.scrollY / zoneHeightPx) * zoneHeightPx).padStart(5, '0')}` : f.phase;
    if (!zones.has(id)) zones.set(id, { id, frames: 0, scrolledPx: 0, firstFrame: f.n, lastFrame: f.n, sums: {} });
    const z = zones.get(id);
    z.frames += 1; z.scrolledPx += f.scrollY - prevY; z.lastFrame = f.n; prevY = f.scrollY;
    for (const [k, v] of Object.entries(f.counts)) z.sums[k] = (z.sums[k] ?? 0) + v;
  }
  return [...zones.values()].map((z) => ({ ...z, sums: Object.fromEntries(Object.entries(z.sums).sort(([a], [b]) => (a < b ? -1 : 1))) }));
}
