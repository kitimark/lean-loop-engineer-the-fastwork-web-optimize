export type Impl = 'mui' | 'plain';

export interface VariantDef {
  kind: 'faithful' | 'optimized' | 'ablation' | 'proposal' | 'probe';
  tier?: string;
  diagnostic?: boolean;
  visClass?: 'E' | 'E-s' | 'Q' | 'L';
  layerBudget?: number;
  files?: string[];
  provenance?: Record<string, string>;
}

export interface LayerDef {
  id: string;
  label: string;
  text: boolean;
}

export interface PartDef {
  id: string;
  slot: string;
  anchors: string[];
  experiment: boolean;
  impls: Impl[];
  muiStates: string[];
  variants: Record<string, VariantDef>;
  layers?: LayerDef[];
  requires: Record<string, string[]>;
  conflicts: Record<string, string[]>;
}

export interface PresetDef {
  name: string;
  extends?: string;
  fw: Record<string, string>;
}

export interface FwConfig {
  variants: Record<string, string>;
  impl: Record<string, Impl>;
}

export interface LayerOptEntry {
  layer: string;
  opts: string;
}

export type ResolveResult =
  | {
      ok: true;
      config: FwConfig;
      configHash: string;
      source: 'url-fw' | 'url-preset' | 'default';
      layerOpts: LayerOptEntry[];
    }
  | { ok: false; errors: string[] };
