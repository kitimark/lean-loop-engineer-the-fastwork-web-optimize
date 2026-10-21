import { nearViewport } from '../people/shared';

export const HERO_SCENE_ATTR = 'data-fw-hero-scene';

export const SCENE_PAUSE = 'scene-pause';

export type HeroSceneValue = 'active' | 'paused';

/** Lean `HeroScenePause.heroScene`. */
export function heroSceneOf({ top, bottom, vh }: { top: number; bottom: number; vh: number }): HeroSceneValue {
  return nearViewport({ top, bottom }, vh) ? 'active' : 'paused';
}

export interface SceneHost {
  setAttribute(name: string, value: string): void;
  removeAttribute(name: string): void;
}

export function bindHeroScene(
  el: SceneHost & Element,
  watch: (el: Element, onChange: (active: boolean) => void) => () => void,
): () => void {
  const stop = watch(el, (active) => el.setAttribute(HERO_SCENE_ATTR, active ? 'active' : 'paused'));
  return () => {
    stop();
    el.removeAttribute(HERO_SCENE_ATTR);
  };
}
