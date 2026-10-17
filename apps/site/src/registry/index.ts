import heroCountdown from '../parts/hero.countdown/part.json';
import heroExit from '../parts/hero.exit/part.json';
import engineScroll from '../parts/engine.scroll/part.json';
import navHitTest from '../parts/nav.hitTest/part.json';
import original from './presets/original.json';
import stripDemo from './presets/strip-demo.json';
import { resolve } from './resolve';
import type { PartDef, PresetDef, ResolveResult } from './types';

export const parts: PartDef[] = [heroCountdown as PartDef, heroExit as PartDef, engineScroll as PartDef, navHitTest as PartDef];
export const presets: Record<string, PresetDef> = {
  original: original as PresetDef,
  'strip-demo': stripDemo as PresetDef,
};

export function resolveSearch(search: string): ResolveResult {
  return resolve(search, parts, presets);
}
export * from './types';
export { hashConfig, canonicalConfig } from './resolve';
