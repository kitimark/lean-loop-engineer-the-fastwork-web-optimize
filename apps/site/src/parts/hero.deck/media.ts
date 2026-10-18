import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). `deck.module.css` has the
 * `(width<=600px)` block; the reduced-motion rule that also resets the deck's cards is in the shared `card.module.css`
 * (the original's `.orbit-card` rule applies to the deck cards too). media.test.ts byte-compares both files.
 * Static markup: nothing is read in JS.
 */
export const MEDIA_IDS = ['mq.w-le-600', 'mq.rm-reduce'] as const;

/** The CSS text of a condition id. */
export const mediaText = (id: (typeof MEDIA_IDS)[number]): string => mediaCondition(id);
