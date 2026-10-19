import contracts from '../../../../packages/contracts/golden/parts/contracts.gen.json';

/**
 * `?only=<target>&stage=y:N,vh:N,vw:N`. Port of Lean `Fw.Site.Stage.parse` (lean/Fw/Site/Stage.lean); checked against
 * `packages/contracts/golden/parts/stage.jsonl`. A hand port (parse, parseEnv, pairs, resolve) checked only by the
 * golden vectors; the part list, page-level flags and group members come from the Lean-generated `contracts.gen.json`.
 */
export type StageErr = 'unknownTarget' | 'pageLevel' | 'emptyGroup' | 'duplicate' | 'badStage';
export interface StageEnv {
  y: number;
  vw: number;
  vh: number;
}
export interface StageSpec {
  target: string;
  members: string[];
  env: StageEnv;
  /** the contract table's premise; every stage result carries it */
  premise: string;
}
export type OnlyResult = { kind: 'none' } | { kind: 'ok'; stage: StageSpec } | { kind: 'err'; code: StageErr };

interface Row {
  id: string;
  pageLevel: boolean;
}
const rows = contracts.parts as Row[];
const groups = contracts.groups as Record<string, string[]>;
export const STAGE_PREMISE: string = contracts.premise;
export const DEFAULT_ENV: StageEnv = { y: 0, vw: 1280, vh: 800 };
const GROUP_NAMES = ['g1', 'g2', 'g3', 'g4', 'g5'];

const stageable = (id: string): boolean => rows.some((r) => r.id === id && !r.pageLevel);

function resolve(t: string): { ok: string[] } | { err: StageErr } {
  if (rows.some((r) => r.id === t)) return stageable(t) ? { ok: [t] } : { err: 'pageLevel' };
  if (GROUP_NAMES.includes(t)) {
    const ms = (groups[t] ?? []).filter(stageable);
    return ms.length === 0 ? { err: 'emptyGroup' } : { ok: ms };
  }
  return { err: 'unknownTarget' };
}

function nat(s: string): number | null {
  return s.length >= 1 && s.length <= 7 && /^[0-9]+$/.test(s) ? Number(s) : null;
}

function parseEnv(s: string): StageEnv | null {
  const seen = new Set<string>();
  const e: StageEnv = { ...DEFAULT_ENV };
  for (const kv of s.split(',')) {
    const parts = kv.split(':');
    if (parts.length !== 2) return null;
    const [k, v] = parts as [string, string];
    const n = nat(v);
    if (n === null || (k !== 'y' && k !== 'vh' && k !== 'vw') || seen.has(k)) return null;
    seen.add(k);
    e[k] = n;
  }
  const valid = e.y <= 1_000_000 && e.vw >= 1 && e.vw <= 10_000 && e.vh >= 1 && e.vh <= 10_000;
  return valid ? e : null;
}

function pairs(q: string): [string, string][] {
  const body = q.startsWith('?') ? q.slice(1) : q;
  return body
    .split('&')
    .filter((p) => p !== '')
    .map((p): [string, string] => {
      const i = p.indexOf('=');
      return i < 0 ? [p, ''] : [p.slice(0, i), p.slice(i + 1)];
    });
}

export function parseOnly(search: string): OnlyResult {
  const ps = pairs(search);
  const onlys = ps.filter(([k]) => k === 'only').map(([, v]) => v);
  const stages = ps.filter(([k]) => k === 'stage').map(([, v]) => v);
  if (onlys.length === 0) return { kind: 'none' };
  if (onlys.length > 1 || stages.length > 1) return { kind: 'err', code: 'duplicate' };
  const target = onlys[0]!;
  const r = resolve(target);
  if ('err' in r) return { kind: 'err', code: r.err };
  const stageText = stages[0];
  const env = stageText === undefined ? { ...DEFAULT_ENV } : parseEnv(stageText);
  if (env === null) return { kind: 'err', code: 'badStage' };
  return { kind: 'ok', stage: { target, members: r.ok, env, premise: STAGE_PREMISE } };
}
