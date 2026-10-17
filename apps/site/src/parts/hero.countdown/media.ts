import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates
 * the same text; media.test.ts checks the two agree once breakpoints.gen.json is filled.
 * `mq.w-le-400` and `mq.c1000-nodw` are CSS-only; `mq.rm-reduce` is read in JS (N2:3817).
 * Never use the pure-width `<=1000` or the C1000 variant with the device-width arm here: this part is C1000-nodw.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-400', 'mq.c1000-nodw'] as const;

/** matchMedia list for a condition id, or null while the placeholder breakpoints file has no entry (then: not matching). */
export function matchList(id: (typeof MEDIA_IDS)[number]): MediaQueryList | null {
  try {
    return window.matchMedia(mediaCondition(id));
  } catch {
    return null;
  }
}
