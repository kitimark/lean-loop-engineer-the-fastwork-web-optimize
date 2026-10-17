export type Impl = 'mui' | 'plain';

export interface VariantDef {
  kind: 'faithful' | 'optimized' | 'ablation' | 'proposal';
  tier?: string;
  layerBudget?: number;
  provenance?: Record<string, string>;
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
