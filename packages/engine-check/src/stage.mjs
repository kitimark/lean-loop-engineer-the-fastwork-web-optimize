// Stages counts runs for `fw engine-check`: each counts.json is copied once per row variant its faithful key answers,
// with meta.variant set to that variant, so apps/runner variantKeys returns that one key and never the bare target.
import { answers, runKey } from './keys.mjs';

/**
 * @param {{path: string, counts: any}[]} runs
 * @param {{variant: string, base?: string}[]} rows
 * @returns {{staged: {name: string, source: string, variant: string, counts: any}[], unkeyed: string[]}}
 */
export function stageRuns(runs, rows) {
  const variants = [...new Set(rows.flatMap((r) => [r.variant, r.base ?? 'original']))].sort();
  const staged = [];
  const unkeyed = [];
  runs.forEach(({ path, counts }, i) => {
    const meta = counts?.meta;
    if (!meta?.target) { unkeyed.push(path); return; }
    const m = { target: meta.target, search: meta.search ?? '' };
    const hit = variants.filter((v) => answers(m, v));
    if (!hit.length) { unkeyed.push(path); return; }
    for (const v of hit) {
      staged.push({
        name: `${String(i).padStart(3, '0')}-${runKey(m).replace(/[^A-Za-z0-9.:@,_=+-]/g, '_')}-as-${v.replace(/[^A-Za-z0-9.:@,_=+-]/g, '_')}`,
        source: path, variant: v, counts: { ...counts, meta: { ...meta, variant: v } },
      });
    }
  });
  return { staged, unkeyed };
}
