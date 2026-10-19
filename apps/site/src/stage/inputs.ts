/**
 * Port of Lean `Fw.Site.Stage.effect` and `rest`, checked against `stage.jsonl`. Declared inputs come from the Lean
 * contract rows (`contracts.gen.json`, premise `declared-rows-unverified`). The inputs of every mounted part are
 * classified: an environment signal is provided by the stage; a `rect:` of an unmounted owner needs a neighbour stub; a
 * `cssVar` or `className` of an unmounted owner is written once at its rest value; anything else (`morphPhase`,
 * `scenePaused`, an input without a rest value) is reported in `unset`, never invented. Nothing here runs per frame.
 */
import { hostOf } from './hosts';

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
  /** owners of a `rect:` input that are not mounted (they get a fixed-size box) */
  neighbours: string[];
  /** inputs the stage cannot provide: reported, never invented */
  unset: string[];
}

/** Lean `rest`: rest value of a custom property or attribute at page top. */
export const REST: Readonly<Record<string, string>> = {
  '--exit-opacity': '1',
  '--morph': '0',
  '--morph-fade': '0',
};
const rest = (name: string): string | undefined => (Object.prototype.hasOwnProperty.call(REST, name) ? REST[name] : undefined);

const ENV_SIGNALS = new Set(['scrollY', 'vw', 'vh', 'clock', 'pointer']);

export type Effect =
  | { kind: 'none' }
  | { kind: 'write'; write: InputWrite }
  | { kind: 'neighbour'; owner: string }
  | { kind: 'unset'; signal: string };

const NONE: Effect = { kind: 'none' };

/** Lean `effect`. */
export function effect(mounted: ReadonlySet<string>, s: string): Effect {
  const unset: Effect = { kind: 'unset', signal: s };
  if (ENV_SIGNALS.has(s)) return NONE;
  if (s === 'morphPhase' || s === 'scenePaused') return unset;
  if (s.startsWith('rect:')) {
    const o = s.slice(5);
    return mounted.has(o) ? NONE : hostOf(o) !== null ? { kind: 'neighbour', owner: o } : unset;
  }
  const isVar = s.startsWith('cssVar:');
  if (!isVar && !s.startsWith('className:')) return unset;
  const parts = s.slice(isVar ? 7 : 10).split('/');
  if (parts.length !== 2) return unset;
  const [name, owner] = parts as [string, string];
  if (mounted.has(owner)) return NONE;
  if (hostOf(owner) === null) return unset;
  if (isVar || name.startsWith('data-')) {
    const v = rest(name);
    return v === undefined ? unset : { kind: 'write', write: { kind: isVar ? 'cssVar' : 'attr', owner, name, value: v } };
  }
  return { kind: 'write', write: { kind: 'class', owner, name, value: null } };
}

export const writeWire = (w: InputWrite): string => `${w.kind}:${w.name}/${w.owner}${w.value === null ? '' : `=${w.value}`}`;

const dedup = <T>(xs: T[], key: (x: T) => string): T[] => {
  const seen = new Set<string>();
  return xs.filter((x) => (seen.has(key(x)) ? false : (seen.add(key(x)), true)));
};

/** Effects of every declared input of every mounted part, deduplicated in order of first appearance. */
export function declaredInputs(mounted: readonly string[], rows: readonly ContractRow[]): StageInputs {
  const set = new Set(mounted);
  const effects = rows.filter((r) => set.has(r.id)).flatMap((r) => r.inputs.map((s) => effect(set, s)));
  return {
    writes: dedup(effects.flatMap((e) => (e.kind === 'write' ? [e.write] : [])), writeWire),
    neighbours: dedup(effects.flatMap((e) => (e.kind === 'neighbour' ? [e.owner] : [])), (x) => x),
    unset: dedup(effects.flatMap((e) => (e.kind === 'unset' ? [e.signal] : [])), (x) => x),
  };
}

/** Apply the writes once. `find(owner)` returns the owner's anchor element or null (counted in the result). */
export function applyInputs(writes: readonly InputWrite[], find: (owner: string) => HTMLElement | null): string[] {
  const missing: string[] = [];
  for (const w of writes) {
    const el = find(w.owner);
    if (!el) {
      missing.push(writeWire(w));
      continue;
    }
    if (w.kind === 'cssVar') el.style.setProperty(w.name, w.value ?? '');
    else if (w.kind === 'attr') el.setAttribute(w.name, w.value ?? '');
    else el.classList.remove(w.name);
  }
  return missing;
}
