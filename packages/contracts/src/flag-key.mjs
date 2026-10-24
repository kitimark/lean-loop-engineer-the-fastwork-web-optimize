// The canonical flag-set key (Lean: lean/Fw/Wire/FlagKey.lean; golden packages/contracts/golden/wire/flag-key.jsonl).
// A page is found by the set of "part:variant" flags, never by the order they were typed. Dependency-free on purpose:
// the site build, the gate, the measure servers and the console preview all import this one file.

/** The key of a typed flag list: distinct flags ordered by part, then variant, joined with commas; null when a flag is not `part:variant`. */
export function keyOf(flags) {
  const seen = new Map();
  for (const f of flags) {
    const p = f.split(':');
    if (p.length !== 2) return null;
    seen.set(f, p);
  }
  const ps = [...seen.values()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0));
  return ps.map((p) => `${p[0]}:${p[1]}`).join(',');
}

/**
 * A search string with its `fw` params replaced by one `fw=<key>` at the first `fw` position; every other param keeps
 * its place. A search without `fw`, with a malformed flag or with no flag is returned unchanged.
 */
export function canonSearch(search) {
  if (typeof search !== 'string' || !search.includes('fw')) return search;
  const params = new URLSearchParams(search);
  if (!params.has('fw')) return search;
  const flags = params.getAll('fw').flatMap((v) => v.split(',')).map((s) => s.trim()).filter((s) => s !== '');
  const key = keyOf(flags);
  if (key === null || key === '') return search;
  const out = [];
  let placed = false;
  for (const seg of search.replace(/^\?/, '').split('&')) {
    let name = seg.split('=')[0];
    try { name = decodeURIComponent(name.replace(/\+/g, ' ')); } catch { /* keep the raw name */ }
    if (name !== 'fw') out.push(seg);
    else if (!placed) { out.push(`fw=${key}`); placed = true; }
  }
  return `?${out.join('&')}`;
}
