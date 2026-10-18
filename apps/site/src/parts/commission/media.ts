import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text (media.test.ts checks the two agree). `mq.rm-reduce` and `mq.c1000` are also read in JS (JS 3085-3090,
 * 3092). `mq.c860` is in the inventory for this part but its commission rule (css 10990) belongs to the underlay class of
 * another section, so it is not read here (see the dismissed entry in lean/Fw/Gate/Scope.lean).
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-640', 'mq.w-641-1000', 'mq.w-ge-1001-nopref', 'mq.c1000'] as const;

/** matchMedia list for a condition id, or null when matchMedia is missing (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
