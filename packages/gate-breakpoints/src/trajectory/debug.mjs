// The debug recorders of the trajectory probe (task waapi-tail-webkit). A debug run loads the rewrite arms (role base and cand, never the
// original, which has no recorder) with `&fw-debug=<name>` and saves what the page recorded (`window.__fwDebug.<field>`) next to the
// readings, in `runs[].morph.debugReps`. The recorder lives in the page (apps/site/src/debug/nav-transition.ts) and is off in every
// other run. The recorder request is a TS/JS stand-in with no Lean spec (a run's identity is still decided by armCheck on the search WITHOUT the debug param).

/** The recorders a page can run: `name` is the `fw-debug` value, `field` the key under `window.__fwDebug`. */
export const DEBUGS = [{ name: 'nav-transition', field: 'navTransition' }, { name: 'root-events', field: 'rootEvents' }];

/**
 * Which recorder a run asks for: the env var `FW_DEBUG`, nothing else. On CI the workflow (trajectory-probe.yml) sets it from the
 * `debug=` key of the push commit line, which Lean decides (`Fw.Ci.Trigger.pushProbe`, allowlist `probeDebugs`); a local debug run
 * sets it by hand. No file of the repo requests a recorder, so nothing that lands on `main` turns one on.
 * Returns the recorder name, or '' (no recorder). An unknown name is an error, never a silent fallback.
 */
export function debugFor(env = process.env) {
  const name = env.FW_DEBUG ?? '';
  if (name !== '' && !DEBUGS.some((d) => d.name === name)) throw new Error(`debug: unknown recorder "${name}"; known: ${DEBUGS.map((d) => d.name).join(', ')}`);
  return name;
}

/** The URL search of a rewrite arm that runs recorder `name` (the arm's own search stays as it is for the config lookup). */
export function withDebug(search, name) {
  if (name === '') return search;
  return search === '' ? `?fw-debug=${name}` : `${search}&fw-debug=${name}`;
}

/** What the page recorded, read in the page: `null` when the recorder did not install (a stale build, a wrong flag). */
export function readDebug(field) {
  const bag = window.__fwDebug;
  return bag && bag[field] ? bag[field] : null;
}

export const fieldOf = (name) => DEBUGS.find((d) => d.name === name)?.field;

// ---- Classifier of the nav recorder rows. Twin of lean/Fw/Parts/MorphTweenWebkit.lean, checked against its golden
// (packages/contracts/golden/parts/morph-tween-webkit-rows.jsonl in test/debug.test.mjs). A row is the golden's list form:
// ["data"|"base", t, v], ["cls", t, on], ["read", t], ["size", t, w], ["raf", t, ts], ["tr", t, "run"|"start"|"end"|"cancel", width];
// t and ts in whole ms, w in thousandths of a px (the Lean `scaled`: half up, a negative number drops the row).

const SLACK = 2;
const WIDTH_TOL = 40;
const scaled = (s, x) => (typeof x === 'number' && x >= 0 ? Math.floor(x * s + 0.5) : null);
const TR = { transitionrun: 'run', transitionstart: 'start', transitionend: 'end', transitioncancel: 'cancel' };

/** One raw recorder row as a golden row, or null (unknown kind, bad number). */
export function normalizeRow(r) {
  const t = scaled(1, r?.t);
  if (t === null || typeof r.k !== 'string') return null;
  const v = typeof r.v === 'string' ? r.v : '';
  switch (r.k) {
    case 'data': case 'base': return [r.k, t, v];
    case 'cls': return ['cls', t, r.on === true];
    case 'read': return ['read', t];
    case 'size': { const w = scaled(1000, r.w); return w === null ? null : ['size', t, w]; }
    case 'raf': { const ts = scaled(1, r.ts); return ts === null ? null : ['raf', t, ts]; }
    case 'tr': return TR[r.type] ? ['tr', t, TR[r.type], r.prop === 'width'] : null;
    default: return null;
  }
}

/** The golden rows of a raw log. */
export const normalizeRows = (raw) => (Array.isArray(raw) ? raw.map(normalizeRow).filter((r) => r !== null) : []);

const kind = (rs, k) => rs[k]?.[0];
const flipIdx = (rs) => { const i = rs.findIndex((r) => r[0] === 'cls' && r[2] === false); return i < 0 ? null : i; };
const carrier = (rs, i) => { for (let k = i; k >= 0; k--) if (kind(rs, k) === 'data') return k; return null; };
const ownBase = (rs, i, v) => {
  let best = null;
  rs.forEach((r, k) => { if (r[0] === 'base' && r[2] === v && (best === null || Math.abs(k - i) < Math.abs(best - i))) best = k; });
  return best;
};
const between = (rs, lo, hi, p) => rs.some((r, k) => lo < k && k < hi && p(r));

/** The split of the first close flip: noFlip, noBase, probe, c1, c2 or c0. */
export function splitRep(rs) {
  const i = flipIdx(rs);
  if (i === null) return 'noFlip';
  const d = carrier(rs, i);
  const b = d === null ? null : ownBase(rs, i, rs[d][2]);
  if (b === null) return 'noBase';
  const lo = Math.min(d, i, b);
  const hi = Math.max(d, i, b);
  const t0 = rs[lo][1];
  if (between(rs, lo, hi, (r) => r[0] === 'read')) return 'probe';
  if (between(rs, lo, hi, (r) => r[0] === 'size' || (r[0] === 'raf' && t0 + SLACK < r[2]))) return b < d ? 'c2' : 'c1';
  return 'c0';
}

const causedAt = (rs, k) => {
  let w = null;
  for (let j = k - 1; j >= 0; j--) if (rs[j][0] === 'data' || rs[j][0] === 'base') { w = j; break; }
  if (w === null) return false;
  return rs.filter((r, j) => w < j && j < k && r[0] === 'read').length <= 1;
};

/** The transition class after the first close flip: none, c3 (a cancel no write explains) or c4 (two cancels by writes). */
export function transRep(rs) {
  const i = flipIdx(rs);
  if (i === null) return 'none';
  let c = 0;
  let u = 0;
  rs.forEach((r, k) => { if (i < k && r[0] === 'tr' && r[2] === 'cancel' && r[3]) { if (causedAt(rs, k)) c++; else u++; } });
  return u >= 1 ? 'c3' : c >= 2 ? 'c4' : 'none';
}

/** The class of a rep: noFlip, noBase, cProbe, c3, c4, c1, c2 or c0. */
export function classifyRep(rs) {
  const s = splitRep(rs);
  if (s === 'noFlip' || s === 'noBase') return s;
  if (s === 'probe') return 'cProbe';
  const t = transRep(rs);
  return t === 'none' ? s : t;
}

const sizeW = (r) => (r[0] === 'size' ? r[2] : null);

/** Whether the width after the flip's writes keeps the width before: unseen, held or jumped. */
export function holdRep(rs) {
  const i = flipIdx(rs);
  const d = i === null ? null : carrier(rs, i);
  if (d === null) return 'unseen';
  const lo = Math.min(d, i);
  const hi = Math.max(d, i);
  let rest = null;
  let prev = null;
  let next = null;
  for (let k = rs.length - 1; k >= 0 && rest === null; k--) rest = sizeW(rs[k]);
  for (let k = lo - 1; k >= 0 && prev === null; k--) prev = sizeW(rs[k]);
  for (let k = hi + 1; k < rs.length && next === null; k++) next = sizeW(rs[k]);
  if (rest === null || prev === null || next === null) return 'unseen';
  if (prev <= rest + 2 * WIDTH_TOL) return 'unseen';
  return prev - rest <= 2 * Math.max(0, next - rest) && rest <= next ? 'held' : 'jumped';
}

/** The verdict on the base window from the number of runs and the hold of each hit rep: needMore, keep or drop. */
export function windowVerdict(runs, holds) {
  if (runs < 3) return 'needMore';
  if (holds.includes('held')) return 'keep';
  return holds.includes('jumped') ? 'drop' : 'needMore';
}

/** Per rep of a saved raw file (`runs[].morph.debugReps`): role, rep, class, hold. */
export function classifyRaw(raw) {
  return (raw.runs ?? []).flatMap((run) => (run.morph?.debugReps ?? []).map((d) => {
    const rs = normalizeRows(d.rows?.rows);
    return { role: run.role, rep: d.rep, cls: classifyRep(rs), hold: holdRep(rs) };
  }));
}
