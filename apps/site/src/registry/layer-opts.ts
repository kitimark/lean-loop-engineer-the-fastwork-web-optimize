import { layerOptsTable } from './layer-opts.gen';
import type { LayerOptEntry } from './types';

export function layerStyle(entries: readonly LayerOptEntry[]): string {
  return entries
    .map((e) => layerOptsTable[e.layer]?.[e.opts] ?? '')
    .filter((s) => s !== '')
    .join('\n');
}

export function installLayerStyle(doc: Document, entries: readonly LayerOptEntry[]): HTMLStyleElement | null {
  const text = layerStyle(entries);
  if (text === '') return null;
  const el = doc.createElement('style');
  el.id = 'fw-layer-opts';
  el.textContent = text;
  doc.head.appendChild(el);
  return el;
}
