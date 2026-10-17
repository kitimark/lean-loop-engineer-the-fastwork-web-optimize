import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text; media.test.ts checks the two agree once breakpoints.gen.json is filled. `mq.rm-reduce` is also read in JS
 * (N2:4156). `(max-width: 600px)` (N2:4157) only drives the splash (hero.orbit), not the exit, so it is not read here.
 * Note `mq.w-le-600` (<=600) and `mq.w-gt-600` (>600) leave no gap, but `(width>=601px)` would: use these two only.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-600', 'mq.w-gt-600'] as const;

/** matchMedia list for a condition id, or null while the placeholder breakpoints file has no entry (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
