import { mediaCondition } from '../../breakpoints';

/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The CSS module restates the
 * CSS ones (media.test.ts checks the text agrees); the JS ones are read with matchMedia (N2:12996-12997): reduced motion
 * and `(max-width: 600px)` for the chrome-ready rule.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.rm-nopref', 'mq.w-le-600', 'mq.w-gt-600', 'mq.w-le-640', 'mq.w-gt-640'] as const;
export type MediaId = (typeof MEDIA_IDS)[number];
/** Read in the CSS module. */
export const CSS_IDS: readonly MediaId[] = ['mq.w-gt-640', 'mq.w-gt-600', 'mq.rm-nopref', 'mq.w-le-640', 'mq.rm-reduce'];
/** Read with matchMedia. */
export const JS_IDS: readonly MediaId[] = ['mq.rm-reduce', 'mq.w-le-600'];

/** matchMedia list for a condition id. */
export const matchList = (id: MediaId): MediaQueryList => window.matchMedia(mediaCondition(id));
