import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). CSS: reduced motion (the
 * stick animation off) and `(width<=860px)` (stage hidden, narrow note style); JS: the same two for the tick guard and
 * `mq.c860` for the drag gate. The CSS module restates the CSS ones; media.test.ts checks the text.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-860', 'mq.c860'] as const;
export type MediaId = (typeof MEDIA_IDS)[number];

/** matchMedia list for a condition id, or null when the browser rejects the text (then: not matching). */
export function matchList(id: MediaId): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
