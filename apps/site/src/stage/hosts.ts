/**
 * Which page piece hosts a part. A sub-part lives inside its section (hero.accent in the hero h1), so staging it mounts
 * the section; the other parts of the section run their own variants (`?fw=`). A stage target is a part, the host is
 * what React must render for it.
 */
export type Host = 'hero' | 'people' | 'pain' | 'commission' | 'platform' | 'columns' | 'nav' | 'panel' | 'drawer' | 'signup';

/** Section hosts in page order; each is replaced by a fixed-size stub when nothing staged lives in it. */
export const SECTIONS = ['hero', 'people', 'pain', 'commission', 'platform', 'columns'] as const;

/**
 * Stub heights as multiples of the stage `vh` (fixed numbers, set once). Approximate by design: they keep the stage's
 * page geometry in the right order of magnitude (people from the PEOPLE_H slope, pain from PAIN_H.totalVh, commission
 * from COMMISSION_H.minVh in shells/model.ts); the exact per-width boxes are gen-shells' and are not read here.
 */
export const STUB_VH: Readonly<Record<(typeof SECTIONS)[number], number>> = {
  hero: 1,
  people: 3.15,
  pain: 3,
  commission: 1.06,
  platform: 2,
  columns: 1,
};

/** `data-fw` anchor of each section host (the section part's `anchors[0]`). */
export const SECTION_ANCHOR: Readonly<Record<(typeof SECTIONS)[number], string>> = {
  hero: 'hero',
  people: 'people',
  pain: 'pain',
  commission: 'commission',
  platform: 'platform',
  columns: 'morph-columns',
};

export function hostOf(id: string): Host | null {
  if (id === 'hero' || id.startsWith('hero.')) return 'hero';
  if (id === 'people' || id.startsWith('people.')) return 'people';
  if (id === 'pain' || id.startsWith('pain.')) return 'pain';
  if (id === 'commission' || id.startsWith('commission.')) return 'commission';
  if (id === 'platform' || id.startsWith('platform.') || id === 'engine.scene') return 'platform';
  if (id === 'morph.columns') return 'columns';
  if (id === 'nav' || id.startsWith('nav.')) return 'nav';
  if (id === 'morph.mount' || id === 'morph.panel' || id === 'morph.countdown') return 'panel';
  if (id === 'overlays.drawer') return 'drawer';
  if (id === 'overlays.signup') return 'signup';
  return null;
}

/** The distinct hosts a stage renders, in a stable order. */
export function hostsOf(members: readonly string[]): Host[] {
  const hs = new Set<Host>();
  for (const m of members) {
    const h = hostOf(m);
    if (h) hs.add(h);
  }
  return [...hs].sort();
}

export const stubHeight = (section: (typeof SECTIONS)[number], vh: number): number => Math.round(STUB_VH[section] * vh);
