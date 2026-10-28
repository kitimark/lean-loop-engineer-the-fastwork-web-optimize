// Lean Fw.Gate.Consumer (golden/gate/consumer.jsonl) and Fw.Parts.HeroExitScrollOffset.judgedEqual, applied to the hero path rows.

/** Lean `keptIdx`: the positions of `n` that have a box in at least one arm; a missing reading is no box. */
export const keptIdx = (n, bo, bc) => Array.from({ length: n }, (_, i) => i).filter((i) => bo[i] === true || bc[i] === true);

/** Lean `judgedEqual` for a rest row pair: both arms read the same scroll offset. */
export const restEqual = (o, w) => o.y === w.y;

const filterNodes = (row, other, ids) => {
  if (row.box === undefined || other.box === undefined) return row;
  const nodes = { ...row.nodes };
  for (const id of ids) {
    const els = row.nodes?.[id];
    if (els === undefined) continue;
    const keep = new Set(keptIdx(Math.max(els.length, other.nodes?.[id]?.length ?? 0), row.box[id] ?? [], other.box[id] ?? []));
    nodes[id] = els.filter((_, i) => keep.has(i));
  }
  return { ...row, nodes };
};

/**
 * The hero rest rows of the two arms as the reducer compares them: a row pair read at different scroll offsets is dropped from
 * the rewrite arm (its step gets no sample), and in the others the elements without a box in both arms are removed from both.
 * Rows without box bits (older raw runs) are compared whole.
 */
export function consumerRows(oRows, wRows, nodeIds) {
  const wBy = new Map(wRows.map((r) => [r.step, r]));
  const oOut = [], wOut = [];
  for (const o of oRows) {
    const w = wBy.get(o.step);
    if (w === undefined) { oOut.push(o); continue; }
    if (!restEqual(o, w)) { oOut.push(o); continue; }
    oOut.push(filterNodes(o, w, nodeIds));
    wOut.push(filterNodes(w, o, nodeIds));
  }
  return [oOut, wOut];
}
