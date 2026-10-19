/**
 * Port of Lean `Fw.Site.Stage` hosts (`Host`, `hostTable`, `stubX100`, `stubPx`), checked against `stage.jsonl`.
 * Which page piece hosts a part: a sub-part lives inside its section (hero.accent in the hero h1), so staging it mounts
 * the whole section and every part under it. Page-level parts have no host.
 */
export type Host = 'hero' | 'people' | 'pain' | 'commission' | 'platform' | 'columns' | 'nav' | 'panel' | 'drawer' | 'signup';

/** Render order of hosts (Lean `Host.order`). */
export const HOST_ORDER: readonly Host[] = ['hero', 'people', 'pain', 'commission', 'platform', 'columns', 'nav', 'panel', 'drawer', 'signup'];

/** Section hosts in page order; each is a fixed-height stub when nothing staged lives in it (Lean `sections`). */
export const SECTIONS = ['hero', 'people', 'pain', 'commission', 'platform', 'columns'] as const;
export type Section = (typeof SECTIONS)[number];

/** Stub heights in hundredths of the stage `vh` (Lean `stubX100`). Approximate by design; the exact boxes are gen-shells'. */
export const STUB_X100: Readonly<Record<Section, number>> = { hero: 100, people: 315, pain: 300, commission: 106, platform: 200, columns: 100 };

/** `data-fw` anchor of each section host (the section part's `anchors[0]`). */
export const SECTION_ANCHOR: Readonly<Record<Section, string>> = {
  hero: 'hero',
  people: 'people',
  pain: 'pain',
  commission: 'commission',
  platform: 'platform',
  columns: 'morph-columns',
};

/** Lean `hostTable`, by identity. */
const HOST_TABLE: Readonly<Record<string, Host>> = {
  commission: 'commission',
  'commission.typing': 'commission',
  'engine.scene': 'platform',
  hero: 'hero',
  'hero.accent': 'hero',
  'hero.countdown': 'hero',
  'hero.cue': 'hero',
  'hero.deck': 'hero',
  'hero.exit': 'hero',
  'hero.orbit': 'hero',
  'morph.columns': 'columns',
  'morph.countdown': 'panel',
  'morph.mount': 'panel',
  'morph.panel': 'panel',
  nav: 'nav',
  'nav.hitTest': 'nav',
  'nav.langMenu': 'nav',
  'overlays.drawer': 'drawer',
  'overlays.signup': 'signup',
  pain: 'pain',
  'pain.notes': 'pain',
  people: 'people',
  'people.card': 'people',
  'people.carousel': 'people',
  'people.deck': 'people',
  'people.o': 'people',
  platform: 'platform',
  'platform.entries': 'platform',
  'platform.glint': 'platform',
  'platform.marquee': 'platform',
  'platform.stageBg': 'platform',
  'platform.sweep': 'platform',
};

export function hostOf(id: string): Host | null {
  return Object.prototype.hasOwnProperty.call(HOST_TABLE, id) ? HOST_TABLE[id]! : null;
}

/** The distinct hosts of the staged members, in render order (Lean `Stage.plan` hosts). */
export function hostsOf(members: readonly string[]): Host[] {
  return HOST_ORDER.filter((h) => members.some((m) => hostOf(m) === h));
}

/** Part ids under the given hosts, in contract order (Lean `mountedOf`). */
export function mountedOf(hosts: readonly Host[], ids: readonly string[]): string[] {
  return ids.filter((i) => {
    const h = hostOf(i);
    return h !== null && hosts.includes(h);
  });
}

/** Stub height in CSS pixels, rounded half up (Lean `stubPx`), integer arithmetic. */
export const stubPx = (section: Section, vh: number): number => Math.floor((STUB_X100[section] * vh + 50) / 100);
