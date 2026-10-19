import { nearViewport } from '../people/shared';

export const SCENE_ATTR = 'data-fw-scene';

export type SceneValue = 'active' | 'paused';

/** Lean `PlatformScene.sceneOf`: the scene value for an element rect (the original's `lE` then `data-start-selling-scene`). */
export function sceneOf({ top, bottom, vh }: { top: number; bottom: number; vh: number }): SceneValue {
  return nearViewport({ top, bottom }, vh) ? 'active' : 'paused';
}

export interface SceneHost {
  setAttribute(name: string, value: string): void;
  removeAttribute(name: string): void;
}

/**
 * The platform section's scene registration (the original's `dE` with `manageAnimations`): the attribute follows the
 * observer's activity and is removed on teardown. The paused CSS rule (platform.module.css) does the pausing.
 * `watch` is `watchActive` (rootMargin `100% 0px`); it reports the initial activity at once.
 */
export function bindScene(el: SceneHost & Element, watch: (el: Element, onChange: (active: boolean) => void) => () => void): () => void {
  const stop = watch(el, (active) => el.setAttribute(SCENE_ATTR, active ? 'active' : 'paused'));
  return () => {
    stop();
    el.removeAttribute(SCENE_ATTR);
  };
}
