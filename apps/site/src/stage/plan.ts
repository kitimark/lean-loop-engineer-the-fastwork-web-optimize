import contracts from '../../../../packages/contracts/golden/parts/contracts.gen.json';
import type { StageSpec } from '../registry/only';
import { hostsOf, mountedOf, SECTIONS, stubPx, type Host, type Section } from './hosts';
import { declaredInputs, type ContractRow, type InputWrite } from './inputs';

/** The fixed scroll engine variant of every stage (Lean `Plan.scrollEngine`). */
export const SCROLL_ENGINE = 'faithful';

export interface StagePlan {
  hosts: Host[];
  mounted: string[];
  stubs: { section: Section; px: number }[];
  writes: InputWrite[];
  neighbours: string[];
  unset: string[];
  scrollEngine: string;
}

const rows = contracts.parts as ContractRow[];

/** Port of Lean `Stage.plan`, checked against `stage.jsonl` (plan.test.ts). */
export function planStage(stage: Pick<StageSpec, 'members' | 'env'>, contractRows: readonly ContractRow[] = rows): StagePlan {
  const hosts = hostsOf(stage.members);
  const mounted = mountedOf(
    hosts,
    contractRows.map((r) => r.id),
  );
  const inputs = declaredInputs(mounted, contractRows);
  return {
    hosts,
    mounted,
    stubs: SECTIONS.filter((s) => !hosts.includes(s)).map((section) => ({ section, px: stubPx(section, stage.env.vh) })),
    ...inputs,
    scrollEngine: SCROLL_ENGINE,
  };
}
