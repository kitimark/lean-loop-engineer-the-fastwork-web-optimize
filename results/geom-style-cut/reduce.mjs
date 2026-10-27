// usage: node reduce.mjs <artifact dir of one chromium-counts run> > summary.json
// Sums the style counters of every frame of each run, per arm: rewrite = base, f1 = morph.geom:on, f2 = morph.geom:on + morph.tween:geom-timed.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const KEYS = ['metric.RecalcStyleCount', 'trace.UpdateLayoutTree', 'trace.UpdateLayoutTree.elementCount', 'trace.ScheduleStyleRecalculation', 'trace.Animation.instant'];
const dir = process.argv[2];
const out = {};
for (const d of readdirSync(dir).filter((x) => x.startsWith('chromium-counts-'))) {
  const [, arm, run] = /^chromium-counts-(.+)-(r\d+)$/.exec(d) ?? [];
  if (!arm) continue;
  const c = JSON.parse(readFileSync(join(dir, d, 'counts.json'), 'utf8'));
  const sums = Object.fromEntries(KEYS.map((k) => [k, c.frames.reduce((a, f) => a + (f.counts?.[k] ?? 0), 0)]));
  const peak = c.frames.reduce((a, f) => Math.max(a, f.counts?.['trace.UpdateLayoutTree.elementCount'] ?? 0), 0);
  (out[arm] ??= {})[run] = { frames: c.frames.length, ...sums, peakElementCount: peak };
}
const label = { rewrite: 'base', f1: 'morph.geom:on', f2: 'morph.geom:on,morph.tween:geom-timed' };
console.log(JSON.stringify(Object.fromEntries(Object.entries(out).map(([k, v]) => [label[k] ?? k, v])), null, 1));
