import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the same
 * text (media.test.ts checks the two agree); the driver reads reduced motion, the touch layout (the 860 combo) and
 * `(min-width: 861px)` with matchMedia (N2:10762-10766, 10971-10972).
 */
export const MEDIA_IDS = [
  'mq.rm-reduce',
  'mq.w-le-640',
  'mq.w-ge-861',
  'mq.w-ge-861-nopref',
  'mq.w-le-1200',
  'mq.c860',
  'mq.c1030',
] as const;

export const mediaTexts = (): string[] => MEDIA_IDS.map((id) => mediaCondition(id));

/** matchMedia list for a condition id, or null when it cannot be built (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
