// Which pages a session visits (device-lag-recorder). I/O glue: reads the site's preset and part files, resolves each rewrite arm's
// URL search (`root` = {presets, parts} directories, the site's by default) to the flags it loads (`?preset=` then `?fw=`, last wins, defaults removed, as apps/site/src/registry/resolve.ts does),
// and hands the flag lists to Lean's dedup (device-session.mjs `dedupArms`, golden-checked). An arm that loads the same page as an
// earlier one is dropped from the plan, so the person never spends a pass on a duplicate. The resolver here is a TS stand-in: the
// site's own resolve has no Lean spec for presets yet (its header says so).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dedupArms, planFor, sameFlags } from './device-session.mjs';

const SITE = { presets: fileURLToPath(new URL('../../../apps/site/src/registry/presets/', import.meta.url)), parts: fileURLToPath(new URL('../../../apps/site/src/parts/', import.meta.url)) };
const DEFAULT_IMPL = 'mui';
const readJson = (dir, rel) => JSON.parse(readFileSync(`${dir}${rel}`, 'utf8'));

/** The `part:variant[@impl]` entries (sorted) a URL search loads on top of the faithful defaults; throws on an unknown preset, part or variant. */
export function resolveFlags(search, root = SITE) {
  const params = new URLSearchParams(search);
  const chosen = new Map();
  const put = (entry, from) => {
    const m = /^([^:@]+):([^:@]+)(?:@([^:@]+))?$/.exec(entry.trim());
    if (!m) throw new Error(`${from}: cannot parse "${entry}" (expected part:variant)`);
    chosen.set(m[1], { variant: m[2], impl: m[3] });
  };
  const chain = (name, seen = []) => {
    if (seen.includes(name)) throw new Error(`preset cycle: ${[...seen, name].join(' -> ')}`);
    let p;
    try { p = readJson(root.presets, `${name}.json`); } catch { throw new Error(`unknown preset "${name}"`); }
    return { ...(p.extends ? chain(p.extends, [...seen, name]) : {}), ...p.fw };
  };
  const presets = params.getAll('preset');
  if (presets.length > 1) throw new Error('only one ?preset= is allowed');
  if (presets.length === 1) for (const [id, v] of Object.entries(chain(presets[0]))) put(`${id}:${v}`, `preset "${presets[0]}"`);
  for (const e of params.getAll('fw').flatMap((v) => v.split(',')).filter((x) => x.trim() !== '')) put(e, '?fw=');
  const out = [];
  for (const [id, { variant, impl }] of chosen) {
    let part;
    try { part = readJson(root.parts, `${id}/part.json`); } catch { throw new Error(`unknown part "${id}"`); }
    if (!(variant in part.variants)) throw new Error(`part "${id}" has no variant "${variant}"`);
    if (impl !== undefined && !part.impls.includes(impl)) throw new Error(`part "${id}" has no impl "${impl}"`);
    const isDefault = variant === Object.keys(part.variants)[0] && (impl === undefined || impl === DEFAULT_IMPL);
    if (!isDefault) out.push(impl === undefined ? `${id}:${variant}` : `${id}:${variant}@${impl}`);
  }
  return out.sort();
}

/** The search each rewrite arm loads; `look` is the lead's `?fw=` choice. */
export const armSearch = (arm, lookSearch) => ({ rewrite: '', v2: '?preset=v2-proved', look: lookSearch })[arm];

/**
 * The plan of this session: Lean's dedup over the three rewrite arms' resolved flags, then Lean's plan text for the arms that stay.
 * `dropped` names each dropped arm and the kept arm it duplicates, for the step list the lead relays.
 */
export function sessionPlan(lookSearch, root = SITE) {
  if (!lookSearch) throw new Error('the look-change arm needs --search ?fw=part:variant,... (chosen by the lead)');
  const xs = ['rewrite', 'v2', 'look'].map((a) => [a, resolveFlags(armSearch(a, lookSearch), root)]);
  const kept = dedupArms(xs);
  const dropped = xs.filter(([a]) => !kept.includes(a)).map(([a, f]) => ({ arm: a, sameAs: kept.find((k) => sameFlags(xs.find(([x]) => x === k)[1], f)), flags: f }));
  return { kept, dropped, flags: Object.fromEntries(xs), plan: planFor(kept) };
}
