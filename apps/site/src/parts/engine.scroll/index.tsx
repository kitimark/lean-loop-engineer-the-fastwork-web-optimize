import { useEffect } from 'react';
import { configureScroll } from '../../engine/scroll';
import type { ScrollVariant } from './logic';
import { installThrottleLift } from './throttle';
import { installUnthrottle } from './unthrottle';

/**
 * Mounts the scroll engine's variant. Renders nothing (no DOM, no MUI), so `impl: plain` is the same code path: the
 * twin exists for the N3 comparison and must measure equal. Place it once, near the root, and pass the resolved
 * `config.variants['engine.scroll']`.
 */
export function EngineScroll({ variant }: { variant: string; impl?: 'mui' | 'plain' }) {
  useEffect(() => {
    configureScroll(variant === 'batched' ? ('batched' satisfies ScrollVariant) : 'faithful');
  }, [variant]);
  // Diagnostic arm only (never in a preset): one non-compositable scroll-driven animation, see throttle.ts.
  useEffect(() => (variant === 'throttle-lift' ? installThrottleLift(document) : undefined), [variant]);
  // Shippable arm: the same lift, style Lean-generated and guarded by @supports (unthrottle.ts).
  useEffect(() => (variant === 'unthrottle' ? installUnthrottle(document) : undefined), [variant]);
  // Anchor for the breakpoint parity gate: marks the scroll container (the document element) once mounted. One attribute
  // write at mount, never per frame; absent in the prerendered HTML.
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.fw = 'engine-scroll';
    return () => {
      if (root.dataset.fw === 'engine-scroll') delete root.dataset.fw;
    };
  }, []);
  return null;
}
