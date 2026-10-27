import { useEffect, useRef } from 'react';
import { registerScroll } from '../../engine/scroll';
import { PROP_FADE, PROP_MORPH, REGISTRATIONS } from '../morph.tween/waapi.logic';
import { createStageDriver } from './driver';
import { STAGE_ATTR, STAGE_ON } from './logic';

export { jackOn, STAGE_ID, STAGE_ON } from './logic';

export const STAGE_PIN_ORDER = 110;
const NEAR_MARGIN = '200% 0px';

export function stageProps(variant: string): Record<string, string> {
  return variant === STAGE_ON ? { [STAGE_ATTR]: '' } : {};
}

function registerProperties(): void {
  for (const r of REGISTRATIONS) {
    if (r.name !== PROP_MORPH && r.name !== PROP_FADE) continue;
    try {
      CSS.registerProperty({ ...r });
    } catch {
    }
  }
}

export interface MorphStageProps {
  onMount?: () => void;
  platformSelector?: string;
  navSelector?: string;
  trackSelector?: string;
}

export function MorphStage({ onMount, platformSelector = '[data-fw="platform"]', navSelector = '[data-fw="nav"]', trackSelector = '[data-fw="stage-track"]' }: MorphStageProps) {
  const mountRef = useRef(onMount);
  mountRef.current = onMount;
  useEffect(() => {
    const root = document.documentElement;
    const platform = document.querySelector<HTMLElement>(platformSelector);
    const track = document.querySelector<HTMLElement>(trackSelector);
    registerProperties();
    let t = track?.offsetHeight ?? 0;
    const setHeight = (h: number) => platform?.style.setProperty('--stage-h', `${h}px`);
    if (platform) setHeight(platform.getBoundingClientRect().height);
    const ro = new ResizeObserver((entries) => {
      for (const e of entries) {
        if (e.target === track) t = e.contentRect.height;
        else if (e.target === platform) setHeight(e.target.getBoundingClientRect().height);
      }
    });
    if (track) ro.observe(track);
    if (platform) ro.observe(platform);
    let mounted = false;
    const io = platform
      ? new IntersectionObserver(
          ([entry]) => {
            if (!entry?.isIntersecting || mounted) return;
            mounted = true;
            io?.disconnect();
            mountRef.current?.();
          },
          { rootMargin: NEAR_MARGIN },
        )
      : undefined;
    if (platform) io?.observe(platform);
    const driver = createStageDriver({
      read: () => ({ y: window.scrollY, maxY: Math.max(0, root.scrollHeight - window.innerHeight), t }),
      publish: (p) => {
        const nav = document.querySelector<HTMLElement>(navSelector);
        if (nav) nav.dataset.fwMorph = String(p);
      },
      pointer: (none) => {
        if (platform) platform.style.pointerEvents = none ? 'none' : '';
      },
    });
    const off = registerScroll('morph.stage', STAGE_PIN_ORDER, () => driver.frame());
    return () => {
      off();
      io?.disconnect();
      ro.disconnect();
      platform?.style.removeProperty('--stage-h');
      if (platform) platform.style.pointerEvents = '';
      const nav = document.querySelector<HTMLElement>(navSelector);
      if (nav) delete nav.dataset.fwMorph;
    };
  }, [platformSelector, navSelector, trackSelector]);
  return null;
}
