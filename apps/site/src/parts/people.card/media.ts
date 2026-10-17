import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the same
 * text (media.test.ts checks the two agree); the driver reads reduced motion and the 860 px edge with matchMedia
 * (N2:11262-11263, `(max-width: 860px)`).
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-640', 'mq.w-le-860', 'mq.c860'] as const;

/** The conditions as CSS text, from the generated file. */
export const mediaTexts = (): string[] => MEDIA_IDS.map((id) => mediaCondition(id));

/** matchMedia list for a condition id, or null when it cannot be built (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
