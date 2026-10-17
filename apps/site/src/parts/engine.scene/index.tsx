import { useEffect } from 'react';
import { createSceneClock } from './logic';
import { watchHidden } from './observe';
import './scene.module.css';

export const SCENE_SELECTOR = '[data-fw-scene]';

/** Timeline time in ms (the clock the animations themselves run on). */
export const timelineNow = (): number => Number(document.timeline.currentTime ?? performance.now());

/** Seek every animation under `root` to `ms` (WAAPI `currentTime`; running/paused state stays as CSS set it). */
export function seekAnimations(root: Element, ms: number): void {
  for (const a of root.getAnimations({ subtree: true })) a.currentTime = ms;
}

/**
 * engine.scene `hidden-pause`: a section marked `data-fw-scene` stops its CSS animations while it has no positive-area
 * overlap with the viewport (Lean `sceneHidden`, `offscreen_hidden`: its moving boxes paint nothing). On return the
 * animations are seeked to the clock a never-paused animation would show (`hsync`; here the free-running clock, since
 * this site does not port the original's 100 %-margin scheduler pause). `faithful` does nothing. Renders nothing.
 */
export function EngineScene({ variant, selector = SCENE_SELECTOR }: { variant: string; selector?: string }) {
  useEffect(() => {
    if (variant !== 'hidden-pause') return;
    const els = [...document.querySelectorAll(selector)];
    const clocks = new Map(els.map((el) => [el, createSceneClock(timelineNow(), true)]));
    const seen = new Set<Element>();
    return watchHidden(els, 'rect', (el, hidden) => {
      if (hidden) {
        el.setAttribute('data-fw-hidden', '');
        seen.add(el);
      } else {
        el.removeAttribute('data-fw-hidden');
        if (seen.delete(el)) seekAnimations(el, clocks.get(el)!.read(timelineNow()));
      }
    });
  }, [variant, selector]);
  return null;
}
