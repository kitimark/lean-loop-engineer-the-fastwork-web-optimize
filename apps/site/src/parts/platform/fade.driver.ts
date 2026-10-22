import { DURATION_MS, fade } from '../morph.tween/logic';
import { EASING_CSS, keyframes } from './fade.logic';

export interface FadeAnim {
  startTime: number | null;
  cancel(): void;
}
export interface FadeEl {
  animate(kfs: { offset: number; opacity: number; filter: string }[], opts: { duration: number; easing: string; fill: 'both' }): FadeAnim;
  style: { setProperty(name: string, value: string): void };
}

/** The sink morph.tween's driver feeds instead of writing `--morph-fade` every frame. */
export interface FadeSink {
  /** A push from `from` to `to` whose tween started at `start` (ms, the origin of `document.timeline`). */
  push(from: number, to: number, start: number): void;
  /** The tween settled at `m` or jumped there (reduced motion): write its fade inline and drop the effect. */
  settle(m: number): void;
  dispose(): void;
}

/**
 * Variant `fade-threaded` (Lean `PlatformFade.stepF`): one opacity and blur effect per push on the section, keyframed
 * in eased progress (`keyframes`), eased by the morph's curve and started at the tween's start, so every frame shows the
 * original's `--morph-fade` (Lean `threaded_eq`, `frame_blur_eq`). The inline `--morph-fade` changes only at a settle.
 */
export function createThreadedFade(el: () => FadeEl | null): FadeSink {
  let anim: FadeAnim | null = null;
  const drop = () => {
    anim?.cancel();
    anim = null;
  };
  return {
    push(from, to, start) {
      drop();
      const p = el();
      if (!p) return;
      const kfs = keyframes(from, to).map((k) => ({ offset: k.off, opacity: k.fade, filter: `blur(${k.blur}px)` }));
      anim = p.animate(kfs, { duration: DURATION_MS, easing: EASING_CSS, fill: 'both' });
      anim.startTime = start;
    },
    settle(m) {
      el()?.style.setProperty('--morph-fade', String(fade({ m })));
      drop();
    },
    dispose: drop,
  };
}
