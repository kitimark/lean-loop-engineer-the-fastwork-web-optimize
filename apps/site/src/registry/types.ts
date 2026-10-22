export type Impl = 'mui' | 'plain';

export interface VariantDef {
  kind: 'faithful' | 'optimized' | 'ablation' | 'proposal';
  tier?: string;
  /** A probe arm that answers a question and never ships; it is `ablation` and never enters a preset. */
  diagnostic?: boolean;
  /** Look class while the part moves (PLAN 4.7); `L` is a look change, never in `v2-proved`. */
  visClass?: 'E' | 'E-s' | 'Q' | 'L';
  layerBudget?: number;
  /** Source files of the part folder this variant runs (no tests); files several variants list are shared. */
  files?: string[];
  provenance?: Record<string, string>;
}

/**
 * One box of a part that can be its own compositing layer. `id` is `part_box`, only `BuildsOpen.okChar` characters,
 * unique in the part; the box carries `data-fw-layer="<id>"`. `text` is true when the box holds text.
 */
export interface LayerDef {
  id: string;
  label: string;
  text: boolean;
}

/** Static `part.json`, the single source of truth for one part (PLAN 6.2). */
export interface PartDef {
  id: string;
  slot: string;
  anchors: string[];
  experiment: boolean;
  impls: Impl[];
  /** ownerState values the AOT census must render (S2). */
  muiStates: string[];
  variants: Record<string, VariantDef>;
  /** Layer boxes in page order; absent for a part with none declared. */
  layers?: LayerDef[];
  /** "part:variant" -> list of "part:variant" that must also be selected. */
  requires: Record<string, string[]>;
  /** "part:variant" -> list of "part:variant" that must not be selected together with it (Lean Rule.conflicts). */
  conflicts: Record<string, string[]>;
}

export interface PresetDef {
  name: string;
  extends?: string;
  /** part id -> variant, optionally "variant@impl". */
  fw: Record<string, string>;
}

export interface FwConfig {
  /** every registered part id -> chosen variant */
  variants: Record<string, string>;
  /** every registered part id -> chosen implementation */
  impl: Record<string, Impl>;
}

export type ResolveResult =
  | { ok: true; config: FwConfig; configHash: string; source: 'url-fw' | 'url-preset' | 'default' }
  | { ok: false; errors: string[] };
