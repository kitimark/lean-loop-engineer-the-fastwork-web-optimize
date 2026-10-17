import heroCountdown from '../parts/hero.countdown/part.json';
import original from './presets/original.json';
import stripDemo from './presets/strip-demo.json';
import { resolve } from './resolve';
import type { PartDef, PresetDef, ResolveResult } from './types';

export const parts: PartDef[] = [heroCountdown as PartDef];
export const presets: Record<string, PresetDef> = {
  original: original as PresetDef,
  'strip-demo': stripDemo as PresetDef,
};

export function resolveSearch(search: string): ResolveResult {
  return resolve(search, parts, presets);
}
export * from './types';
export { hashConfig, canonicalConfig } from './resolve';
