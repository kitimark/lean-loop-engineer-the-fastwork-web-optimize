export const keptIdx = (n, bo, bc) => Array.from({ length: n }, (_, i) => i).filter((i) => bo[i] === true || bc[i] === true);

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
