// Harness variants of one lane run; the name is also the file prefix (counts-<name>-<pass>.json).
/** `live` | `vt`, optionally followed by `-warm` and/or `-trace` (any order): the harness variants, also the file prefix. */
export function parseVariant(name) {
  const parts = name.split('-');
  const base = parts.shift();
  if (base !== 'live' && base !== 'vt') throw new Error(`variant ${name}: must start with live or vt`);
  const flags = new Set(parts);
  for (const f of flags) if (f !== 'warm' && f !== 'trace') throw new Error(`variant ${name}: unknown flag ${f}`);
  return { name: [base, ...['warm', 'trace'].filter((f) => flags.has(f))].join('-'), vt: base === 'vt', warm: flags.has('warm'), trace: flags.has('trace') };
}

