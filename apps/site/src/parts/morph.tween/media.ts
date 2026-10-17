import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). Only reduced motion, in JS
 * (N2:12976, read at each push: the value jumps instead of tweening). There is no width gate and the part ships no CSS
 * (the `(max-width: 600px)` list beside it in the original drives the ring splash, not the tween).
 */
export const MEDIA_IDS = ['mq.rm-reduce'] as const;

/** matchMedia list for a condition id, or null while the breakpoints file has no entry (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
