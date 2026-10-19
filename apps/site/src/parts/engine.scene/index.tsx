import { useEffect } from 'react';
import { watchActive } from '../people/shared';
import { createResumeSync } from './logic';
import { watchHidden } from './observe';
import './scene.module.css';

export const SCENE_SELECTOR = '[data-fw-scene]';

/** Timeline time in ms (the clock the animations themselves run on). */
export const timelineNow = (): number => Number(document.timeline.currentTime ?? performance.now());

/** Seek every animation under `root` to `ms` (WAAPI `currentTime`; running/paused state stays as CSS set it). */
export function seekAnimations(root: Element, ms: number): void {
  for (const a of root.getAnimations({ subtree: true })) a.currentTime = ms;
}

/** Add `ms` to the current time of every animation under `root` that is in `kept` (WAAPI; play state stays as CSS set it). */
export function advanceAnimations(root: Element, kept: ReadonlySet<Animation>, ms: number): void {
  for (const a of root.getAnimations({ subtree: true })) {
    if (kept.has(a) && a.currentTime !== null) a.currentTime = Number(a.currentTime) + ms;
  }
}

/**
 * engine.scene `hidden-pause`: a selected section stops its CSS animations while it has no positive-area overlap with the
 * viewport (Lean `sceneHidden`, `offscreen_hidden`). The section's own rule (platform `data-fw-scene`) already freezes
 * them while it is not near, so the scene clock runs only while `watchActive` reports it active; on return every animation
 * that existed at the hide is advanced by the clock's advance over the hidden span (Lean `HiddenPausePlatform`,
 * `hsync_platform`). An animation created while hidden is not advanced. `faithful` does nothing. Renders nothing.
 */
export function EngineScene({ variant, selector = SCENE_SELECTOR }: { variant: string; selector?: string }) {
  useEffect(() => {
    if (variant !== 'hidden-pause') return;
    const els = [...document.querySelectorAll(selector)];
    const syncs = new Map(els.map((el) => [el, createResumeSync(timelineNow(), true)]));
    const held = new Map<Element, Set<Animation>>();
    const stops = els.map((el) => watchActive(el, (active) => syncs.get(el)!.setActive(timelineNow(), active)));
    const stopHidden = watchHidden(els, 'rect', (el, hidden) => {
      const sync = syncs.get(el)!;
      if (hidden) {
        el.setAttribute('data-fw-hidden', '');
        sync.hide(timelineNow());
        if (!held.has(el)) held.set(el, new Set(el.getAnimations({ subtree: true })));
      } else {
        el.removeAttribute('data-fw-hidden');
        const ms = sync.unhide(timelineNow());
        const kept = held.get(el);
        held.delete(el);
        if (ms !== null && kept) advanceAnimations(el, kept, ms);
      }
    });
    return () => {
      stopHidden();
      for (const stop of stops) stop();
    };
  }, [variant, selector]);
  return null;
}
