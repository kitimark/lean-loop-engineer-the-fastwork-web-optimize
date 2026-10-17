import { useEffect, useRef } from 'react';
import { createWriteGate } from '../engine.scene/logic';
import { watchHidden } from '../engine.scene/observe';
import { HeroCountdown } from '../hero.countdown';
import css from './morph.module.css';

export interface MorphCountdownProps {
  variant: string;
  /** `mui` (default) or `plain`; passed to the shared clock. */
  impl?: 'mui' | 'plain';
}

const FACES = '[data-face],[data-strip]';

/**
 * Variant `hidden-pause`: the driver keeps integrating every frame; only the face `transform` writes are held while
 * the wrapper's visible fraction is at most the Lean constant, and the latest value per face is written when it
 * rises again, in the observer callback before paint (Lean `skipWrites_le`, `hsync`). Done by shadowing the `transform`
 * property on each face's `style` object, so hero.countdown's driver is unchanged. Faces the driver adds later (digit
 * count changes) are picked up by a MutationObserver.
 */
function installFaceGate(root: HTMLElement): () => void {
  const gate = createWriteGate<HTMLElement>((el, v) => el.style.setProperty('transform', v));
  const patched = new Set<HTMLElement>();
  const patch = (el: HTMLElement) => {
    if (patched.has(el)) return;
    patched.add(el);
    Object.defineProperty(el.style, 'transform', {
      configurable: true,
      get: () => el.style.getPropertyValue('transform'),
      set: (v: string) => gate.set(el, v),
    });
  };
  const patchAll = () => root.querySelectorAll<HTMLElement>(FACES).forEach(patch);
  patchAll();
  const mo = new MutationObserver(patchAll);
  mo.observe(root, { childList: true, subtree: true });
  const stop = watchHidden([root], 'fraction', (_el, hidden) => gate.setHidden(hidden));
  return () => {
    stop();
    mo.disconnect();
    gate.setHidden(false);
    for (const el of patched) delete (el.style as unknown as Record<string, unknown>).transform;
  };
}

/**
 * morph.countdown: the second countdown, inside the morph panel's centre column (original N2:12879 markup, instance at
 * N2:13160 with `inverse: true`). It is the hero.countdown clock unchanged (same logic, driver, scheduling and CSS
 * module, so the Lean goldens of hero.countdown cover it) in a centred row with a 32 px top margin. Variant `strip`
 * needs hero.countdown:strip (part.json `requires`) and reuses its one-strip-per-digit driver. The panel host
 * (morph.panel) decides when it mounts; the original mounts the panel when the platform section is within 200% of the
 * viewport (N2:13084).
 */
export function MorphCountdown({ variant, impl = 'mui' }: MorphCountdownProps) {
  const ref = useRef<HTMLDivElement>(null);
  const hiddenPause = variant === 'hidden-pause';
  useEffect(() => {
    const root = ref.current;
    if (!hiddenPause || !root) return;
    return installFaceGate(root);
  }, [hiddenPause]);
  return (
    <div ref={ref} className={css.wrap} data-fw="morph-countdown" data-fw-variant={variant}>
      <HeroCountdown variant={variant} impl={impl} inverse fwId="morph-countdown-clock" />
    </div>
  );
}
