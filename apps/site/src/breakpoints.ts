import gen from './breakpoints.gen.json';

/**
 * The only place media conditions are read (no hand-written media strings elsewhere in src/).
 * `breakpoints.gen.json` is a placeholder until the Lean-generated file lands (lean-site); swap the import
 * and keep the shape: { conditions: { [id]: "<exact media condition>" } }, ids as in
 * research/kickoff/11-breakpoints/breakpoints.json (e.g. "mq.rm-reduce", the combo860 condition).
 */
const conditions = (gen as { conditions: Record<string, string> }).conditions;

export function mediaCondition(id: string): string {
  const c = conditions[id];
  if (c === undefined) throw new Error(`unknown breakpoint condition "${id}"`);
  return c;
}
