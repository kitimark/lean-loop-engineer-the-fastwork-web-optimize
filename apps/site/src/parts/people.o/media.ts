import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). Reduced motion and the 860 px
 * edge are read in JS (N2:6214, 6205 `(max-width: 860px)`); the CSS module restates reduced motion and the 860 px face rule.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-860'] as const;

export const mediaTexts = (): string[] => MEDIA_IDS.map((id) => mediaCondition(id));

/** matchMedia list for a condition id, or null when it cannot be built (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
