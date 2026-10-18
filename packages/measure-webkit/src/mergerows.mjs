// `merge` of the class tables of several determinism sessions (VMs, sessions), keyed by row. GLUE ONLY: which rows pair
// across sessions and which are left out is Lean's (`Fw.Measure.StepAlign.pairedRows` / `unpairedRows`, fwcore op
// `measure.webkit.pairRows`); this file builds the request, reads the reply and takes the worse class per paired row.
//
// Why: some row labels depend on the page. The census states are labelled by the offset the browser measured, and the
// document height differs by a pixel on some VMs (`census|layerCount|y=5268` on one VM, `y=5267` on the others). Rows are
// therefore matched by key, not by position; a row some sessions lack is reported as unpaired and is not in the table.
import { fwcoreCall } from './handoff.mjs';
import { classifyPasses, reasonNames } from './determinism.mjs';

const RANK = { deterministic: 0, stable: 1, quarantined: 2 };

/** `family|metric|level`, with `#n` appended to the n-th repeat in one session so keys are unique within it. */
export function rowKeys(rows) {
  const seen = new Map();
  return rows.map((r) => {
    const k = `${r.family}|${r.metric}|${r.level}`;
    const n = seen.get(k) ?? 0;
    seen.set(k, n + 1);
    return n ? `${k}#${n + 1}` : k;
  });
}

/**
 * Classes of every session (recomputed from its raw passes), then the paired rows with the worst class.
 * @param {object[][]} rawSessions the `passes` of each determinism file
 * @returns {Promise<{sessions: object[][], keys: string[][], out: object[], unpaired: object[]}>}
 *   out[i] = {key, ...row of the first session, classes, cls (worst), agree, at: per-session row index}
 */
export async function mergeSessions(rawSessions, call = fwcoreCall) {
  const reasons = [...new Set(rawSessions.flatMap(reasonNames))].sort(); // same reason rows in every session
  const sessions = rawSessions.map((passes) => classifyPasses(passes, { reasons }));
  const keys = sessions.map(rowKeys);
  const [reply] = await call([{ id: 'pair-rows', op: 'measure.webkit.pairRows', sessions: keys }]);
  if (reply.error) throw new Error(`fwcore: ${reply.error}`);
  const index = keys.map((ks) => new Map(ks.map((k, i) => [k, i])));
  const out = reply.paired.map((key) => {
    const at = index.map((m) => m.get(key));
    const classes = at.map((i, s) => sessions[s][i].cls);
    const first = sessions[0][at[0]];
    return { key, ...first, classes, cls: classes.reduce((w, x) => (RANK[x] > RANK[w] ? x : w)), agree: new Set(classes).size === 1, at };
  });
  return { sessions, keys, out, unpaired: reply.unpaired };
}

/** Markdown of the rows left out: one line per row with the sessions that have it and Lean's reason. */
export function unpairedTable(unpaired) {
  if (!unpaired.length) return '';
  const lines = [`\nUnpaired rows (${unpaired.length}), excluded from the table above:\n`, '| row | sessions with it | reason |', '|---|---|---|'];
  for (const u of unpaired) lines.push(`| ${u.key} | ${u.sessions} of ${u.of} | ${u.reason} |`);
  return lines.join('\n');
}
