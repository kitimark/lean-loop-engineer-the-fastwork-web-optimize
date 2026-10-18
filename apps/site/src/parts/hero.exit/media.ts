import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text; media.test.ts checks the two agree. `mq.rm-reduce` is also read in JS (N2:4156). The copy and the cue read
 * `(width>600px)` themselves (hero.cue); this part's CSS has only the track and the stage.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-600'] as const;

/** matchMedia list for a condition id, or null while the placeholder breakpoints file has no entry (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
