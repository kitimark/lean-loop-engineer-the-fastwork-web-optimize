import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text; media.test.ts checks the two agree. `mq.rm-reduce` is also read in JS (the unmount delay is 0 under it,
 * original JS 2917); `mq.w-le-860` and `mq.w-le-640` are CSS only.
 */
export const MEDIA_IDS = ['mq.w-le-860', 'mq.w-le-640', 'mq.rm-reduce'] as const;

/** matchMedia list for a condition id, or null when unavailable (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
