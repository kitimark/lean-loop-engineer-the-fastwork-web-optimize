import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * same text; media.test.ts checks the two agree. Both are CSS only (the reduced-motion rule drops the enter animation;
 * the <=600 rule adds the safe-area bottom padding).
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-600'] as const;

/** The conditions as CSS text, from the generated file. */
export const mediaTexts = (): string[] => MEDIA_IDS.map((id) => mediaCondition(id));
