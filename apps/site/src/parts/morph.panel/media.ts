import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text, in the original's source order (1000, 720, reduced motion, 640). `mq.w-le-600` and `mq.c860` are listed
 * for morph.panel in the inventory but only set the host's (nav's) `--panel-w/h` and the nav's own state: the panel
 * root fills the host with `inset: 0`, so this part restates neither.
 */
export const MEDIA_IDS = ['mq.w-le-1000', 'mq.w-le-720', 'mq.rm-reduce', 'mq.w-le-640'] as const;

export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
