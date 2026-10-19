import { useEffect, useLayoutEffect, useMemo, type ReactNode } from 'react';
import { setHydrated } from '../fw';
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
import type { Pinned } from './fixedEnv';
import { hostOf, SECTION_ANCHOR, SECTIONS, type Host } from './hosts';
import { applyInputs } from './inputs';
import { planStage } from './plan';

const anchorOf = new Map(parts.map((p) => [p.id, p.anchors[0] ?? p.id]));

export interface StageReport {
  target: string;
  members: string[];
  /** every part id under the rendered hosts (a sub-part stage mounts its whole host) */
  mounted: string[];
  /** the shared scroll engine variant (fixed per stage; `?fw=engine.scroll=` is not applied) */
  scrollEngine: string;
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
 * The environment is pinned by the caller before the first render (`pinEnv` in entry-client), so mount-time reads see it.
 * Hosts of staged parts render for real; every other page section is a fixed-height stub in page order, so geometry and
 * a neighbour box exist. Inputs that mounted parts read from unmounted owners are set once from the Lean contract rows.
 * Which hosts, stubs and writes follow `planStage` (a port of Lean `Stage.plan`). Every result carries the contract
 * premise (`declared-rows-unverified`) in `data-fw-premise` and `window.__fwStage`. Page-level parts are refused before
 * this renders (`parseOnly`). No React state, no per-frame value.
 * Accepted limits: stub heights are `stubPx` approximations; the engine.scroll variant is fixed (`scrollEngine`); the panel
 * mounts at once, where the page mounts it after MorphMount's onMount.
 */
export function PartStage({ stage, config, pinned }: { stage: StageSpec; config: FwConfig; pinned: Pinned }) {
  const plan = useMemo(() => planStage(stage), [stage]);
  const { hosts } = plan;
  const stubPxOf = new Map(plan.stubs.map((s) => [s.section, s.px]));
  const stubbed = SECTIONS.filter((s) => stubPxOf.has(s));

  useEffect(() => setHydrated(), []);

  useLayoutEffect(() => {
    window.scrollTo(0, stage.env.y);
    const find = (owner: string) => document.querySelector<HTMLElement>(`[data-fw="${anchorOf.get(owner) ?? owner}"]`);
    const missing = applyInputs(plan.writes, find);
    window.__fwStage = {
      target: stage.target,
      members: stage.members,
      mounted: plan.mounted,
      scrollEngine: plan.scrollEngine,
      env: stage.env,
      premise: stage.premise,
      viewportMismatch: pinned.mismatch,
      unset: plan.unset,
      missing,
    };
    return () => {
      pinned.restore();
      delete window.__fwStage;
    };
  }, [stage, plan, pinned]);

  const owners = [...new Set([...plan.neighbours, ...plan.writes.map((w) => w.owner)])];
  const stubFor = (host: Host) => owners.filter((o) => hostOf(o) === host && !hosts.includes(host));

  return (
    <div data-fw-stage={stage.target} data-fw-premise={stage.premise} data-fw-scroll-engine={plan.scrollEngine}>
      {SECTIONS.map((s) =>
        !stubbed.includes(s) ? (
          <div key={s} data-fw-stage-host={s}>
            {renderHost(SECTION_HOST[s], config)}
          </div>
        ) : (
          <div key={s} data-fw={SECTION_ANCHOR[s]} data-fw-stub="" style={{ height: stubPxOf.get(s), position: 'relative' }}>
            {stubFor(SECTION_HOST[s])
              .filter((o) => (anchorOf.get(o) ?? o) !== SECTION_ANCHOR[s])
              .map((o) => (
                <div key={o} data-fw={anchorOf.get(o) ?? o} data-fw-stub="" style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }} />
              ))}
          </div>
        ),
      )}
      {hosts
        .filter((h) => !SECTIONS.some((s) => s === h))
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
