import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS modules of the part
 * restate the same text; media.test.ts checks the two agree. `mq.rm-reduce` is also read in JS (shrink, entries, glint).
 * The sweep's `mq.rm-nopref` is in sweep.module.css; the stage's `mq.c860` / `mq.w-le-640` repeat in stage.module.css.
 */
export const MEDIA_IDS = [
  'mq.rm-reduce',
  'mq.rm-nopref',
  'mq.w-ge-1001',
  'mq.w-861-1000',
  'mq.w-ge-861',
  'mq.w-le-960',
  'mq.w-le-1000',
  'mq.w-le-720',
  'mq.c860',
  'mq.w-le-640',
] as const;

/** matchMedia list for a condition id, or null when the id is unknown (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
