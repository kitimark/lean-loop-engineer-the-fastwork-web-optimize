import { checkPair, declaredTable } from './census-check.mjs';

export function runsOf(name, json) {
  if (Array.isArray(json?.passes)) return json.passes.map((p, i) => ({ label: `${name} pass ${i + 1}`, samples: p.census }));
  const rec = json?.meta?.layerCensus ?? (json?.schema === 'fw.layer-census/1' ? json : null);
  if (rec) return [{ label: name, samples: rec.samples ?? [], error: rec.error ?? null }];
  return [];
}

export function declaredMarkdown(label, table) {
  const out = [`### declared layers, ${label}`, '', '| y | id | rendered | layers | bytes |', '|---|---|---|---|---|'];
  for (const s of table) {
    if (!s.declared.length) out.push(`| ${s.y} | (none declared) | 0 | 0 | 0 |`);
    for (const d of s.declared) out.push(`| ${s.y} | ${d.id} | ${d.rendered} | ${d.layers} | ${d.bytes} |`);
  }
  return out.join('\n');
}

export function reportRuns(runs, opts) {
  if (!runs.length) return { state: 'unavailable', lines: ['no census in the files'] };
  const lines = [];
  let state = 'accepted';
  const first = runs[0];
  const rank = { accepted: 0, unavailable: 1, refused: 2 };
  if (first.error) { lines.push(`${first.label}: census failed: ${first.error}`); state = 'unavailable'; }
  for (const r of runs.slice(1)) {
    const verdict = checkPair(first.samples, r.samples, opts);
    lines.push(`${r.label} vs ${first.label}: ${verdict.state}`, ...verdict.lines.map((l) => `  ${l}`));
    if (rank[verdict.state] > rank[state]) state = verdict.state;
  }
  if (runs.length === 1) {
    const verdict = checkPair(first.samples, first.samples, opts);
    lines.push(`${first.label} vs itself (composite and grid only): ${verdict.state}`, ...verdict.lines.map((l) => `  ${l}`));
    if (rank[verdict.state] > rank[state]) state = verdict.state;
  }
  lines.push('', declaredMarkdown(first.label, declaredTable(first.samples)));
  return { state, lines };
}
