import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text (media.test.ts byte-compares). `mq.rm-reduce` is also read in JS at mount (N2:3680): under reduced motion the
 * chain never starts. The original's `(width<=600px)` rule for the accent targets classes the Svelte hero does not use
 * (`.start-selling-script-accent`), so it has no counterpart here.
 */
export const MEDIA_IDS = ['mq.rm-reduce'] as const;

/** matchMedia list for a condition id, or null when the id is unknown (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
