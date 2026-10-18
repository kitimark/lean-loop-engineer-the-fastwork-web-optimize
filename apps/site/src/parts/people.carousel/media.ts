import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). Reduced motion is read in JS
 * (N2:11262, the loop never runs) and restated in the CSS module; the pill's width conditions belong to people.card.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-461', 'mq.w-le-860'] as const;

export const mediaTexts = (): string[] => MEDIA_IDS.map((id) => mediaCondition(id));

/** matchMedia list for a condition id, or null when it cannot be built (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
