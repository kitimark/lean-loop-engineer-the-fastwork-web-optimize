/**
 * Conditions this part reads (ids as in research/kickoff/11-breakpoints/breakpoints.json). The part's own CSS module reads
 * none; the clock inside is the hero.countdown component, whose CSS module restates `mq.w-le-400` and `mq.c1000-nodw`
 * and whose driver reads `mq.rm-reduce` in JS. The inventory lists the same three for morph.countdown, so the ids are
 * kept in step with hero.countdown by media.test.ts. The gate scope (Fw.Gate.Scope) reads this list.
 */
export const MEDIA_IDS = ['mq.rm-reduce', 'mq.w-le-400', 'mq.c1000-nodw'] as const;
