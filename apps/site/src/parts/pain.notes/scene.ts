import { sceneActive } from './logic';

export interface SceneEnv {
  /** The Pain section's rect, or null when it is not mounted. */
  sectionRect(): { top: number; bottom: number } | null;
  innerHeight(): number;
  /** One engine-clock frame, once; returns the cancel function. */
  frame(cb: () => void): () => void;
  setScene(state: 'active' | 'paused'): void;
  /** The section's `data-render` attribute: undefined when not set yet. */
  getRender(): 'active' | 'deferred' | null;
  setRender(state: 'active' | 'deferred'): void;
  /** `--start-selling-intrinsic-block-size`, set from the section height before it is deferred. */
  setIntrinsic(px: number): void;
  /** Called when the section turns active (the original asks for a scheduler frame, JS 2733 `rE`). */
  onActivate(): void;
}

/**
 * The scene scheduler of the Pain section (JS 2681-2783 `dE`, called at 4736 with `deferRendering`): active at mount from the
 * section rect, then per observer entry. An active section is rendered; an inactive one is marked `deferred` two frames
 * later (unless it already is), and the stylesheet then skips its subtree. Lean `PainNotes.Render.after`.
 */
export function createScene(env: SceneEnv) {
  let active = true;
  let cancel: (() => void) | null = null;

  const setRender = (on: boolean) => {
    cancel?.();
    cancel = null;
    if (on) {
      env.setRender('active');
      return;
    }
    if (env.getRender() === 'deferred') return;
    cancel = env.frame(() => {
      cancel = env.frame(() => {
        cancel = null;
        if (active) return;
        const r = env.sectionRect();
        const h = r ? r.bottom - r.top : 0;
        if (h > 0) env.setIntrinsic(h);
        env.setRender('deferred');
      });
    });
  };

  const set = (on: boolean) => {
    env.setScene(on ? 'active' : 'paused');
    if (active === on) return;
    active = on;
    setRender(on);
    if (on) env.onActivate();
  };

  return {
    /** Mount: JS 2763-2770. */
    start() {
      const r = env.sectionRect();
      active = r ? sceneActive({ top: r.top, bottom: r.bottom, h: env.innerHeight() }) : true;
      env.setScene(active ? 'active' : 'paused');
      setRender(active);
      if (active) env.onActivate();
    },
    /** An observer entry for the section (JS 2744-2746). */
    intersect: set,
    active: () => active,
    dispose() {
      cancel?.();
      cancel = null;
    },
  };
}
