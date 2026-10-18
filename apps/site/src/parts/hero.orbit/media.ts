import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS modules (orbit and card)
 * restate the same text; media.test.ts byte-compares. `mq.rm-reduce` and `mq.w-le-600` are also read in JS at splash
 * start and restart (N2:4153, 4157, 4218): either one finishes the splash at once.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-600', 'mq.w-601-1279', 'mq.w-601-1511'] as const;

/** matchMedia list for a condition id, or null when the id is unknown (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
