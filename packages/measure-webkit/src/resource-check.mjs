export const GATED = ['style', 'layout', 'paintRecords', 'script', 'eventDispatch', 'repaintArea', 'framesRequested'];
const CENSUS = new Set(['layers', 'gpuMemory']);

export function measuredSign(base, arm, tol) {
  if (arm.hi + tol < base.lo) return 'down';
  if (base.hi + tol < arm.lo) return 'up';
  return 'same';
}

export function slowWalk(baseHiMs, armLoMs) {
  return 3 * baseHiMs < 2 * armLoMs;
}

export function check(resource, slow, predicted, measured) {
  if (slow && !CENSUS.has(resource)) return 'confounded';
  if (predicted === 'unknown') return 'unpredicted';
  if (predicted === measured) return 'agree';
  if (measured === 'same') return 'unresolved';
  return 'disagree';
}

export function memFit(budget, sign, peak) {
  if (sign === 'down' || sign === 'same') return true;
  if (sign === 'up') return peak == null ? null : peak <= budget;
  return null;
}

export function verdict(signs, budget, peak) {
  const at = (r) => signs[r] ?? 'unknown';
  if (GATED.some((r) => at(r) === 'up')) return 'trade';
  if (GATED.some((r) => at(r) === 'unknown')) return 'open';
  if (!GATED.some((r) => at(r) === 'down')) return 'neutral';
  const fit = memFit(budget, at('gpuMemory'), peak);
  if (fit === true) return 'win';
  if (fit === false) return 'overBudget';
  return 'open';
}

export function footprints(rows) {
  const by = new Map();
  for (const r of rows.filter((x) => x.kind === 'predict')) {
    const key = `${r.flag}|${r.engine}`;
    const fp = by.get(key) ?? { flag: r.flag, engine: r.engine, signs: {}, verdict: r.verdict, budget: null, peak: null };
    fp.signs[r.resource] = r.sign;
    if (r.resource === 'gpuMemory') {
      fp.budget = r.budget;
      fp.peak = r.peak;
    }
    by.set(key, fp);
  }
  return [...by.values()];
}
