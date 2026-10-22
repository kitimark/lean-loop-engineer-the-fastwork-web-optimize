import { fnv1a64 } from './hash';
import type { FwConfig, Impl, LayerOptEntry, PartDef, PresetDef, ResolveResult } from './types';

export const DEFAULT_IMPL: Impl = 'mui';

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
  const m = /^([^:@]+):([^:@]+)(?:@([^:@]+))?$/.exec(entry.trim());
  return m ? { id: m[1]!, variant: m[2]!, impl: m[3] } : null;
}

const LAYER_OPTS = ['c', 's', 'cs'];

function splitLayer(entry: string): LayerOptEntry | null {
  const f = entry.split(':');
  return f.length === 2 && f[0] !== '' && LAYER_OPTS.includes(f[1]!) ? { layer: f[0]!, opts: f[1]! } : null;
}

function layerEntries(entries: string[], parts: PartDef[], errors: string[]): LayerOptEntry[] {
  const out: LayerOptEntry[] = [];
  const known = new Set(parts.flatMap((p) => (p.layers ?? []).map((l) => l.id)));
  for (const raw of entries) {
    const e = splitLayer(raw);
    if (!e) {
      errors.push(`?fwl=: cannot parse "${raw}" (expected layer:c, layer:s or layer:cs)`);
      continue;
    }
    if (!known.has(e.layer)) errors.push(`?fwl=: unknown layer "${e.layer}"`);
    if (out.some((x) => x.layer === e.layer)) errors.push(`?fwl=: layer "${e.layer}" is listed twice`);
    out.push(e);
  }
  return out;
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

const FWL_MAX_LEN = 2000;
const FWL_CHARSET = /^[A-Za-z0-9.:,\-_@=&]*$/;
const FWL_CHARSET_REASON = 'search has a character outside A-Z a-z 0-9 . : , - _ @ = & (after one leading ?)';

export function resolve(
  search: string,
  parts: PartDef[],
  presets: Record<string, PresetDef>,
): ResolveResult {
  const errors: string[] = [];
  if (new URLSearchParams(search).has('fwl')) {
    if (search.length > FWL_MAX_LEN) return { ok: false, errors: ['search is longer than 2000 characters'] };
    if (!FWL_CHARSET.test(search.startsWith('?') ? search.slice(1) : search))
      return { ok: false, errors: [FWL_CHARSET_REASON] };
  }
  const params = new URLSearchParams(search);
  const byId = new Map(parts.map((p) => [p.id, p]));

  const variants: Record<string, string> = {};
  const impl: Record<string, Impl> = {};
  for (const p of parts) {
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

  const layerErrs: string[] = [];
  const layerOpts = layerEntries(
    params
      .getAll('fwl')
      .flatMap((v) => v.split(','))
      .filter((s) => s !== ''),
    parts,
    layerErrs,
  );

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

  errors.push(...layerErrs);
  if (errors.length > 0) return { ok: false, errors };
  const config: FwConfig = { variants, impl };
  const source = fwEntries.length > 0 ? 'url-fw' : presetName !== undefined ? 'url-preset' : 'default';
  return { ok: true, config, configHash: hashConfig(config), source, layerOpts };
}
