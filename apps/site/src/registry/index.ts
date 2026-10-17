import heroCountdown from '../parts/hero.countdown/part.json';
import heroExit from '../parts/hero.exit/part.json';
import morphCountdown from '../parts/morph.countdown/part.json';
import engineScroll from '../parts/engine.scroll/part.json';
import navHitTest from '../parts/nav.hitTest/part.json';
import morphMount from '../parts/morph.mount/part.json';
import morphColumns from '../parts/morph.columns/part.json';
import morphTween from '../parts/morph.tween/part.json';
import people from '../parts/people/part.json';
import pain from '../parts/pain/part.json';
import commission from '../parts/commission/part.json';
import platform from '../parts/platform/part.json';
import platformSweep from '../parts/platform.sweep/part.json';
import platformGlint from '../parts/platform.glint/part.json';
import platformEntries from '../parts/platform.entries/part.json';
import platformStageBg from '../parts/platform.stageBg/part.json';
import platformMarquee from '../parts/platform.marquee/part.json';
import original from './presets/original.json';
import stripDemo from './presets/strip-demo.json';
import { resolve } from './resolve';
import type { PartDef, PresetDef, ResolveResult } from './types';

export const parts: PartDef[] = [heroCountdown as PartDef, heroExit as PartDef, engineScroll as PartDef, navHitTest as PartDef, morphMount as PartDef, morphCountdown as PartDef, morphColumns as PartDef, morphTween as PartDef, people as PartDef, pain as PartDef, commission as PartDef, platform as PartDef, platformSweep as PartDef, platformGlint as PartDef, platformEntries as PartDef, platformStageBg as PartDef, platformMarquee as PartDef];
export const presets: Record<string, PresetDef> = {
  original: original as PresetDef,
  'strip-demo': stripDemo as PresetDef,
};

export function resolveSearch(search: string): ResolveResult {
  return resolve(search, parts, presets);
}
export * from './types';
export { hashConfig, canonicalConfig } from './resolve';
