// The declared property names of a role are the properties of every stylesheet rule that matches the element AT THE TIME OF
// THE SCAN. Parts with a timer-driven state (hero.accent toggles its transition and wave classes on a 3050 ms chain) match
// different rules at different instants, so one scan gave different lists in different shards and merge-gate refused the
// header (run 39057342983, WebKit). Phase 0 therefore scans several times across the longest timer period and takes the UNION,
// which does not depend on the instant the first scan fell on.

/** Spacing of the extra scans and how many: 8 x 400 ms plus the first scan cover one 3050 ms chain period with every state
 *  (the shortest state, 900 ms, is sampled at least twice). */
export const SCAN_GAP_MS = 400;
export const SCAN_EXTRA = 8;

/**
 * Union of scans. Each scan is `{ pid: { role: { count, declared: [names], items } } }`; the result has the first scan's shape,
 * `declared` the sorted union over all scans (and `count` the maximum, a role present in any scan is present).
 */
export function unionDeclared(scans) {
  if (scans.length === 0) throw new Error('unionDeclared: no scan');
  const out = {};
  for (const scan of scans) {
    for (const [pid, roles] of Object.entries(scan)) {
      out[pid] ??= {};
      for (const [role, v] of Object.entries(roles)) {
        const cur = out[pid][role];
        if (!cur) { out[pid][role] = { ...v, declared: [...v.declared] }; continue; }
        cur.count = Math.max(cur.count, v.count);
        cur.declared = [...new Set([...cur.declared, ...v.declared])];
      }
    }
  }
  for (const roles of Object.values(out)) for (const v of Object.values(roles)) v.declared.sort();
  return out;
}
