import { useEffect } from 'react';
import { configureScroll } from '../../engine/scroll';
import type { ScrollVariant } from './logic';

/**
 * Mounts the scroll engine's variant. Renders nothing (no DOM, no MUI), so `impl: plain` is the same code path: the
 * twin exists for the N3 comparison and must measure equal. Place it once, near the root, and pass the resolved
 * `config.variants['engine.scroll']`.
 */
export function EngineScroll({ variant }: { variant: string; impl?: 'mui' | 'plain' }) {
  useEffect(() => {
    configureScroll(variant === 'batched' ? ('batched' satisfies ScrollVariant) : 'faithful');
  }, [variant]);
  return null;
}
