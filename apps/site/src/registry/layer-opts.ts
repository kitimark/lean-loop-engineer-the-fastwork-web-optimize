import { layerOptsTable } from './layer-opts.gen';
import type { LayerOptEntry } from './types';

/**
 * The CSS text of the `?fwl=` entries: each pair looked up in the Lean-generated table (`layer-opts.gen.ts`), the
 * answers joined in entry order, empty answers dropped. Mirrors Lean `Fw.Site.LayerOpts.styleOf`; the golden
 * `packages/contracts/golden/console/layer-opts.jsonl` checks it. An empty result means no style element.
 */
export function layerStyle(entries: readonly LayerOptEntry[]): string {
  return entries
    .map((e) => layerOptsTable[e.layer]?.[e.opts] ?? '')
    .filter((s) => s !== '')
    .join('\n');
}

/** Appends one unlayered `<style>` for the entries to `doc.head`; no entries or no text adds nothing. */
export function installLayerStyle(doc: Document, entries: readonly LayerOptEntry[]): HTMLStyleElement | null {
  const text = layerStyle(entries);
  if (text === '') return null;
  const el = doc.createElement('style');
  el.id = 'fw-layer-opts';
  el.textContent = text;
  doc.head.appendChild(el);
  return el;
}
