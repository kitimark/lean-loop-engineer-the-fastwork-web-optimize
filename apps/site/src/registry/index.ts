import heroCountdown from '../parts/hero.countdown/part.json';
import heroExit from '../parts/hero.exit/part.json';
import morphCountdown from '../parts/morph.countdown/part.json';
import hero from '../parts/hero/part.json';
import heroOrbit from '../parts/hero.orbit/part.json';
import heroDeck from '../parts/hero.deck/part.json';
import heroAccent from '../parts/hero.accent/part.json';
import heroCue from '../parts/hero.cue/part.json';
import engineScroll from '../parts/engine.scroll/part.json';
import navHitTest from '../parts/nav.hitTest/part.json';
import morphMount from '../parts/morph.mount/part.json';
import morphColumns from '../parts/morph.columns/part.json';
import morphTween from '../parts/morph.tween/part.json';
import nav from '../parts/nav/part.json';
import navLangMenu from '../parts/nav.langMenu/part.json';
import people from '../parts/people/part.json';
import pain from '../parts/pain/part.json';
import commission from '../parts/commission/part.json';
import commissionTyping from '../parts/commission.typing/part.json';
import platform from '../parts/platform/part.json';
import morphPanel from '../parts/morph.panel/part.json';
import overlaysDrawer from '../parts/overlays.drawer/part.json';
import overlaysSignup from '../parts/overlays.signup/part.json';
import original from './presets/original.json';
import stripDemo from './presets/strip-demo.json';
import { resolve } from './resolve';
import type { PartDef, PresetDef, ResolveResult } from './types';

export const parts: PartDef[] = [heroCountdown as PartDef, heroExit as PartDef, engineScroll as PartDef, navHitTest as PartDef, morphMount as PartDef, morphCountdown as PartDef, morphColumns as PartDef, morphTween as PartDef, people as PartDef, pain as PartDef, commission as PartDef, commissionTyping as PartDef, platform as PartDef, morphPanel as PartDef, nav as PartDef, navLangMenu as PartDef, overlaysDrawer as PartDef, overlaysSignup as PartDef, hero as PartDef, heroOrbit as PartDef, heroDeck as PartDef, heroAccent as PartDef, heroCue as PartDef];
export const presets: Record<string, PresetDef> = {
  original: original as PresetDef,
  'strip-demo': stripDemo as PresetDef,
};

export function resolveSearch(search: string): ResolveResult {
  return resolve(search, parts, presets);
}
export * from './types';
export { hashConfig, canonicalConfig } from './resolve';
