import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text, in the original's source order (1000, 720, reduced motion, 640, then the page's inline style: 600, written in the original's legacy `max-width` text). `mq.c860` is listed for
 * morph.panel in the inventory but only sets the host's (nav's) `--panel-w/h`: the panel root fills the host with
 * `inset: 0`, so this part restates it not.
 */
export const MEDIA_IDS = ['mq.w-le-1000', 'mq.w-le-720', 'mq.rm-reduce', 'mq.w-le-640', 'mq.w-le-600'] as const;

export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
