/**
 * Declared inputs of a stage, read from the Lean contract rows (`contracts.gen.json`, premise `declared-rows-unverified`).
 * A `cssVar:--x/owner` or `className:n/owner` input whose owner is not staged is set once on the owner's anchor element
 * to a rest value; an owner that is staged writes its own output. `rect:` inputs need the owner's box to exist: those
 * owners get a fixed-size neighbour stub. Nothing here runs per frame.
 */
export interface ContractRow {
  id: string;
  inputs: string[];
}

export interface InputWrite {
  kind: 'cssVar' | 'attr' | 'class';
  owner: string;
  name: string;
  value: string | null;
}

export interface StageInputs {
  writes: InputWrite[];
  /** owners of a `rect:` input that are not staged */
  neighbours: string[];
  /** inputs with no rest value in `REST`: reported, never invented */
  unset: string[];
}

/** Rest value of a custom property or attribute at page top; `null` for a class means absent. */
export const REST: Readonly<Record<string, string>> = {
  '--exit-opacity': '1',
  '--morph': '0',
  '--morph-fade': '0',
};

const SIGNAL = /^(cssVar|className):(.+)\/([^/]+)$/;

export function declaredInputs(members: readonly string[], rows: readonly ContractRow[]): StageInputs {
  const staged = new Set(members);
  const writes: InputWrite[] = [];
  const neighbours = new Set<string>();
  const unset = new Set<string>();
  for (const row of rows) {
    if (!staged.has(row.id)) continue;
    for (const sig of row.inputs) {
      if (sig.startsWith('rect:')) {
        const owner = sig.slice(5);
        if (!staged.has(owner)) neighbours.add(owner);
        continue;
      }
      const m = SIGNAL.exec(sig);
      if (!m || staged.has(m[3]!)) continue;
      const [, type, name, owner] = m as unknown as [string, string, string, string];
      if (type === 'cssVar') {
        const v = REST[name];
        if (v === undefined) unset.add(sig);
        else writes.push({ kind: 'cssVar', owner, name, value: v });
      } else if (name.startsWith('data-')) {
        const v = REST[name];
        if (v === undefined) unset.add(sig);
        else writes.push({ kind: 'attr', owner, name, value: v });
      } else {
        writes.push({ kind: 'class', owner, name, value: null }); // absent at rest
      }
    }
  }
  const key = (w: InputWrite) => `${w.kind}:${w.name}/${w.owner}`;
  const seen = new Set<string>();
  return {
    writes: writes.filter((w) => (seen.has(key(w)) ? false : (seen.add(key(w)), true))),
    neighbours: [...neighbours].sort(),
    unset: [...unset].sort(),
  };
}

/** Apply the writes once. `find(owner)` returns the owner's anchor element or null (counted in the result). */
export function applyInputs(writes: readonly InputWrite[], find: (owner: string) => HTMLElement | null): string[] {
  const missing: string[] = [];
  for (const w of writes) {
    const el = find(w.owner);
    if (!el) {
      missing.push(`${w.kind}:${w.name}/${w.owner}`);
      continue;
    }
    if (w.kind === 'cssVar') el.style.setProperty(w.name, w.value ?? '');
    else if (w.kind === 'attr') el.setAttribute(w.name, w.value ?? '');
    else el.classList.remove(w.name);
  }
  return missing;
}
