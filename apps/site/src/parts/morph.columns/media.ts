import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text; media.test.ts checks the two agree. Both are CSS-only in the original (no matchMedia read for the columns).
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-1000', 'mq.w-le-640'] as const;

export const mediaTexts = (): string[] => MEDIA_IDS.map((id) => mediaCondition(id));
