import { useLayoutEffect, useMemo, type ReactNode } from 'react';
import contracts from '../../../../packages/contracts/golden/parts/contracts.gen.json';
import { Commission } from '../parts/commission';
import { Hero } from '../parts/hero';
import { MorphColumns } from '../parts/morph.columns';
import { MorphCountdown } from '../parts/morph.countdown';
import { MorphMount } from '../parts/morph.mount';
import { MorphPanel } from '../parts/morph.panel';
import { Nav } from '../parts/nav';
import { NavHitTest } from '../parts/nav.hitTest';
import { EngineScene } from '../parts/engine.scene';
import { OverlayDrawer } from '../parts/overlays.drawer';
import { OverlaySignup } from '../parts/overlays.signup';
import { Pain } from '../parts/pain';
import { People } from '../parts/people';
import { Platform } from '../parts/platform';
import type { FwConfig } from '../registry/types';
import { parts } from '../registry';
import type { StageSpec } from '../registry/only';
import { pinEnv } from './fixedEnv';
import { hostOf, hostsOf, SECTION_ANCHOR, SECTIONS, stubHeight, type Host } from './hosts';
import { applyInputs, declaredInputs, type ContractRow } from './inputs';

const rows = contracts.parts as ContractRow[];
const anchorOf = new Map(parts.map((p) => [p.id, p.anchors[0] ?? p.id]));

export interface StageReport {
  target: string;
  members: string[];
  env: StageSpec['env'];
  premise: string;
  /** the real viewport differs from the pinned vw/vh */
  viewportMismatch: boolean;
  /** inputs with no rest value (not invented) */
  unset: string[];
  /** input writes whose owner element was not on the page */
  missing: string[];
}

declare global {
  interface Window {
    __fwStage?: StageReport;
  }
}

function renderHost(h: Host, config: FwConfig): ReactNode {
  const v = (id: string) => config.variants[id] ?? 'faithful';
  switch (h) {
    case 'hero':
      return <Hero variants={config.variants} />;
    case 'people':
      return <People variants={config.variants} />;
    case 'pain':
      return <Pain variant={v('pain')} notesVariant={v('pain.notes')} />;
    case 'commission':
      return <Commission variant={v('commission')} typingVariant={v('commission.typing')} />;
    case 'platform':
      return (
        <>
          <Platform
            variant={v('platform')}
            sub={{
              sweep: config.variants['platform.sweep'],
              glint: config.variants['platform.glint'],
              entries: config.variants['platform.entries'],
              stageBg: config.variants['platform.stageBg'],
              marquee: config.variants['platform.marquee'],
            }}
          />
          <EngineScene variant={v('engine.scene')} selector='[data-fw="platform"]' />
        </>
      );
    case 'columns':
      return <MorphColumns variant={v('morph.columns')} />;
    case 'nav':
      return (
        <>
          <Nav variant={v('nav')} />
          <NavHitTest variant={v('nav.hitTest')} />
        </>
      );
    case 'panel':
      return (
        <>
          <MorphMount variant={v('morph.mount')} />
          <MorphPanel variant={v('morph.panel')} impl={config.impl['morph.panel']} countdown={<MorphCountdown variant={v('morph.countdown')} impl={config.impl['morph.countdown']} />} />
        </>
      );
    case 'drawer':
      return <OverlayDrawer variant={v('overlays.drawer')} />;
    case 'signup':
      return <OverlaySignup variant={v('overlays.signup')} />;
  }
}

const SECTION_HOST: Record<(typeof SECTIONS)[number], Host> = {
  hero: 'hero',
  people: 'people',
  pain: 'pain',
  commission: 'commission',
  platform: 'platform',
  columns: 'columns',
};

/**
 * Mounts one part, or one contract group, in a fixed scroll environment (y, vw, vh from the stage, the real MotionClock).
 * Hosts of staged parts render for real; every other page section is a fixed-height stub in page order, so geometry and
 * a neighbour box exist. Inputs of staged parts that other parts own are set once from the Lean contract rows. Every
 * result carries the contract premise (`declared-rows-unverified`) in `data-fw-premise` and `window.__fwStage`.
 * Page-level parts are refused before this renders (`parseOnly`). No React state, no per-frame value.
 */
export function PartStage({ stage, config }: { stage: StageSpec; config: FwConfig }) {
  const { hosts, inputs } = useMemo(() => ({ hosts: hostsOf(stage.members), inputs: declaredInputs(stage.members, rows) }), [stage.members]);
  const stubbed = SECTIONS.filter((s) => !hosts.includes(SECTION_HOST[s]));

  useLayoutEffect(() => {
    const pinned = pinEnv(window, stage.env);
    window.scrollTo(0, stage.env.y);
    const find = (owner: string) => document.querySelector<HTMLElement>(`[data-fw="${anchorOf.get(owner) ?? owner}"]`);
    const missing = applyInputs(inputs.writes, find);
    window.__fwStage = {
      target: stage.target,
      members: stage.members,
      env: stage.env,
      premise: stage.premise,
      viewportMismatch: pinned.mismatch,
      unset: inputs.unset,
      missing,
    };
    return () => {
      pinned.restore();
      delete window.__fwStage;
    };
  }, [stage, inputs]);

  const owners = [...new Set([...inputs.neighbours, ...inputs.writes.map((w) => w.owner)])];
  const stubFor = (host: Host) => owners.filter((o) => hostOf(o) === host && !hosts.includes(host));

  return (
    <div data-fw-stage={stage.target} data-fw-premise={stage.premise}>
      {SECTIONS.map((s) =>
        hosts.includes(SECTION_HOST[s]) ? (
          <div key={s} data-fw-stage-host={s}>
            {renderHost(SECTION_HOST[s], config)}
          </div>
        ) : (
          <div key={s} data-fw={SECTION_ANCHOR[s]} data-fw-stub="" style={{ height: stubHeight(s, stage.env.vh), position: 'relative' }}>
            {stubFor(SECTION_HOST[s])
              .filter((o) => (anchorOf.get(o) ?? o) !== SECTION_ANCHOR[s])
              .map((o) => (
                <div key={o} data-fw={anchorOf.get(o) ?? o} data-fw-stub="" style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }} />
              ))}
          </div>
        ),
      )}
      {hosts
        .filter((h) => !SECTIONS.some((s) => SECTION_HOST[s] === h))
        .map((h) => (
          <div key={h} data-fw-stage-host={h}>
            {renderHost(h, config)}
          </div>
        ))}
      {(['nav', 'panel'] as const).flatMap((h) =>
        stubFor(h).map((o) => (
          <div key={o} data-fw={anchorOf.get(o) ?? o} data-fw-stub="" style={{ position: 'fixed', top: 0, left: 0, width: '100%', height: h === 'nav' ? 56 : '100%', pointerEvents: 'none' }} />
        )),
      )}
    </div>
  );
}
