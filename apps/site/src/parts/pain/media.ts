import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). All CSS: the sticky pin only
 * without a motion preference to reduce, and the narrow layout at `(width<=860px)`. The CSS module restates the text;
 * media.test.ts checks it against the generated conditions.
 */
export const MEDIA_IDS = ['mq.rm-nopref', 'mq.w-le-860'] as const;

/** The conditions as CSS text, from the generated file. */
export const mediaTexts = (): string[] => MEDIA_IDS.map((id) => mediaCondition(id));
