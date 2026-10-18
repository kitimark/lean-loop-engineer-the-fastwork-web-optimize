import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text (media.test.ts checks the two agree). `mq.rm-reduce` is also read in JS at the start of each run (JS 2481).
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.c1000'] as const;

/** matchMedia list for a condition id, or null when matchMedia is missing (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
