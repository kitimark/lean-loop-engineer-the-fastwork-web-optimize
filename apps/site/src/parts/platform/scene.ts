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

/** Lean `PlatformFadedPause.scene`: paused when the observer says offscreen or the section is faded out. */
export function sceneValue(active: boolean, faded: boolean): SceneValue {
  return active && !faded ? 'active' : 'paused';
}

export interface SceneWriter {
  setActive(active: boolean): void;
  setFaded(faded: boolean): void;
}

/**
 * The one writer of `data-fw-scene` on the section: it ORs the observer's pause with the faded pause (Lean
 * `PlatformFadedPause.scene_*`). `onValue` runs after each write with the value written. Without a faded pause it
 * writes exactly what the observer says, as the original does.
 */
export function createSceneWriter(el: SceneHost, onValue?: (v: SceneValue) => void): SceneWriter {
  let active = true;
  let faded = false;
  const write = () => {
    const v = sceneValue(active, faded);
    el.setAttribute(SCENE_ATTR, v);
    onValue?.(v);
  };
  return {
    setActive(a) {
      active = a;
      write();
    },
    setFaded(f) {
      if (f === faded) return;
      faded = f;
      write();
    },
  };
}

/**
 * The platform section's scene registration (the original's `dE` with `manageAnimations`): the attribute follows the
 * observer's activity and is removed on teardown. The paused CSS rule (platform.module.css) does the pausing.
 * `watch` is `watchActive` (rootMargin `100% 0px`); it reports the initial activity at once.
 */
export function bindScene(el: SceneHost & Element, watch: (el: Element, onChange: (active: boolean) => void) => () => void, writer: SceneWriter = createSceneWriter(el)): () => void {
  const stop = watch(el, (active) => writer.setActive(active));
  return () => {
    stop();
    el.removeAttribute(SCENE_ATTR);
  };
}
