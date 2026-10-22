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

export interface FadeSink {
  push(from: number, to: number, start: number): void;
  settle(m: number): void;
  dispose(): void;
}

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
