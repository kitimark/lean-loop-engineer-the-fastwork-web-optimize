// The view stage of a sample (Lean Fw.Gate.Settle.view, Fw.Gate.Freeze.viewRank): a part with a node read in a skipped
// content-visibility subtree is brought into view, settled and read again. Glue only: the rule (the second reading is the one kept) is
// Lean's `view`, passed in as `keep`; the instants are Lean's `instant`/`viewRank`, passed in as `at`.
//
// The set of parts to bring is the UNION over both arms of the parts that either arm read skipped. An arm that did not need a part
// brought still brings it, holds to the same fake instant and reads again there, so the two kept readings of a part are taken
// at one instant and at one scroll state in both arms. (Per-arm sets compared an arm's first reading, taken at the main instant,
// with the other arm's second reading, taken at the view instant.)

/** The plain parts (in `plainIds` order) that have a node flagged skipped in one arm's first reading `parts[pid][role].items[i].skipped`. */
export function skippedParts(parts, plainIds) {
  return plainIds.filter((pid) => parts[pid] && Object.values(parts[pid]).some((r) => r.items.some((it) => it.skipped)));
}

/** The view set: the plain parts, in `plainIds` order, that any arm lists. Order and content do not depend on which arm lists them. */
export function viewUnion(plainIds, lists) {
  return plainIds.filter((pid) => lists.some((l) => l.includes(pid)));
}

/**
 * A rendezvous for the arms of one pair: each arm posts the parts it read skipped and gets the union once every arm has posted.
 * `fail` (an arm threw before it posted) rejects the arms that wait, so a failed arm never leaves the other one hanging.
 */
export function makeViewBarrier(plainIds, sites) {
  const posted = new Map();
  let release, reject;
  const done = new Promise((res, rej) => { release = res; reject = rej; });
  done.catch(() => {});
  return {
    post(site, list) {
      if (!sites.includes(site)) throw new Error(`view barrier: unknown arm ${site}`);
      if (posted.has(site)) throw new Error(`view barrier: arm ${site} posted twice`);
      posted.set(site, list);
      if (sites.every((x) => posted.has(x))) release(viewUnion(plainIds, sites.map((x) => posted.get(x))));
      return done;
    },
    fail(err) { reject(err); },
  };
}

/**
 * Bring each part of `ids` (the union) into view, settle, hold to the part's view instant and read again; the second reading is the
 * one kept (`keep(true, first, again)`, node by node), the first goes under raw.viewFirst. io = { roots(pid), bring(roots) ->
 * { skippedBefore, scrollY }, settle(roots) -> wait | null, at(pid) (holds to the instant), again(pid) -> parts, keep, log(pid, b, still) }.
 * Returns the parts brought, in order.
 */
export async function viewStage(io, raw, ids) {
  if (ids.length === 0) return [];
  raw.viewFirst = {};
  raw.viewed = {};
  for (const pid of ids) {
    const roots = io.roots(pid);
    const b = await io.bring(roots);
    const wait = await io.settle(roots);
    if (wait) (raw.overlaySettle ||= []).push(wait); // the sample is unsettled when this wait is
    await io.at(pid);
    const again = await io.again(pid);
    const first = raw.parts[pid];
    raw.viewFirst[pid] = first;
    raw.parts[pid] = Object.fromEntries(Object.entries(first).map(([role, fr]) => [role, {
      ...fr, items: fr.items.map((it, i) => io.keep(true, it, again[pid][role].items[i] ?? it)),
    }]));
    const still = Object.values(raw.parts[pid]).reduce((n, r) => n + r.items.filter((it) => it.skipped).length, 0);
    raw.viewed[pid] = { skippedBefore: b.skippedBefore, stillSkipped: still, scrollY: b.scrollY, ...(wait ? { settle: wait.outcome } : {}) };
    io.log(pid, b, still);
  }
  return ids;
}
