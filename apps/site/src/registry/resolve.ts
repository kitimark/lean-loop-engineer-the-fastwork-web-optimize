import { fnv1a64 } from './hash';
import type { FwConfig, Impl, PartDef, PresetDef, ResolveResult } from './types';

export const DEFAULT_IMPL: Impl = 'mui';

/** Canonical text of a config: sorted "part:variant@impl" lines. */
export function canonicalConfig(config: FwConfig): string {
  return Object.keys(config.variants)
    .sort()
    .map((id) => `${id}:${config.variants[id]}@${config.impl[id]}`)
    .join('\n');
}

export function hashConfig(config: FwConfig): string {
  return fnv1a64(canonicalConfig(config));
}

function splitEntry(entry: string): { id: string; variant: string; impl?: string } | null {
  // "part.id:variant" or "part.id:variant@impl"
  const m = /^([^:@]+):([^:@]+)(?:@([^:@]+))?$/.exec(entry.trim());
  return m ? { id: m[1]!, variant: m[2]!, impl: m[3] } : null;
}

function presetEntries(
  name: string,
  presets: Record<string, PresetDef>,
  errors: string[],
  seen: string[] = [],
): Record<string, string> {
  const p = presets[name];
  if (!p) {
    errors.push(`unknown preset "${name}"`);
    return {};
  }
  if (seen.includes(name)) {
    errors.push(`preset cycle: ${[...seen, name].join(' -> ')}`);
    return {};
  }
  const base = p.extends ? presetEntries(p.extends, presets, errors, [...seen, name]) : {};
  return { ...base, ...p.fw };
}

/**
 * Resolution order (PLAN 6.3): URL `?fw=` over `?preset=` over the registry default `faithful`.
 * Mirrors Lean `Fw.Flags.resolve` (defaults = head variant, overrides applied in order, last wins, then
 * `Config.ok`). The `?preset=`, `@impl` and URL syntax are TS-only extras with no Lean spec yet.
 * Unknown ids, unknown variants and violated `requires`/`conflicts` are errors, never fallbacks.
 */
export function resolve(
  search: string,
  parts: PartDef[],
  presets: Record<string, PresetDef>,
): ResolveResult {
  const errors: string[] = [];
  const params = new URLSearchParams(search);
  const byId = new Map(parts.map((p) => [p.id, p]));

  const variants: Record<string, string> = {};
  const impl: Record<string, Impl> = {};
  for (const p of parts) {
    // Lean `defaults`: the head of the registered variants (first key of part.json `variants`).
    variants[p.id] = Object.keys(p.variants)[0] ?? 'faithful';
    impl[p.id] = DEFAULT_IMPL;
  }

  const apply = (id: string, variant: string, implName: string | undefined, from: string) => {
    const part = byId.get(id);
    if (!part) return void errors.push(`${from}: unknown part "${id}"`);
    if (!(variant in part.variants))
      return void errors.push(`${from}: part "${id}" has no variant "${variant}"`);
    variants[id] = variant;
    if (implName !== undefined) {
      if (!(part.impls as string[]).includes(implName))
        return void errors.push(`${from}: part "${id}" has no impl "${implName}"`);
      impl[id] = implName as Impl;
    }
  };

  const presetNames = params.getAll('preset');
  if (presetNames.length > 1) errors.push('only one ?preset= is allowed');
  const presetName = presetNames[0];
  if (presetName !== undefined) {
    for (const [id, v] of Object.entries(presetEntries(presetName, presets, errors))) {
      const [variant, implName] = v.split('@');
      apply(id, variant!, implName, `preset "${presetName}"`);
    }
  }

  const fwEntries = params
    .getAll('fw')
    .flatMap((v) => v.split(','))
    .filter((s) => s.trim() !== '');
  for (const entry of fwEntries) {
    const e = splitEntry(entry);
    if (!e) errors.push(`?fw=: cannot parse "${entry}" (expected part:variant)`);
    else apply(e.id, e.variant, e.impl, '?fw=');
  }

  if (errors.length === 0) {
    const selected = new Set(Object.entries(variants).map(([id, v]) => `${id}:${v}`));
    for (const part of parts) {
      const key = `${part.id}:${variants[part.id]}`;
      for (const need of part.requires[key] ?? [])
        if (!selected.has(need)) errors.push(`${key} requires ${need}`);
      for (const bad of part.conflicts[key] ?? [])
        if (selected.has(bad)) errors.push(`${key} conflicts with ${bad}`);
    }
  }

  if (errors.length > 0) return { ok: false, errors };
  const config: FwConfig = { variants, impl };
  const source = fwEntries.length > 0 ? 'url-fw' : presetName !== undefined ? 'url-preset' : 'default';
  return { ok: true, config, configHash: hashConfig(config), source };
}
