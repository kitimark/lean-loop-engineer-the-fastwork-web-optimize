import type { FwConfig } from './registry/types';

export interface FwBuildId {
  engine: 'aot' | 'runtime';
  mui: string;
  emotionReact: string;
  emotionCache: string;
  react: string;
  vite: string;
}

export interface StyleMiss {
  id: string;
  /** first 200 chars of the serialized CSS, to find the census gap */
  styles: string;
  afterMark: boolean;
  t: number;
}

export interface FwGlobal {
  config: FwConfig;
  configHash: string;
  buildId: FwBuildId;
  /** 'hydrate' when the URL config equals the prerendered one, else 'client-render' (no mismatch possible). */
  mode: 'hydrate' | 'client-render';
  hydrated: boolean;
  hydrationErrors: string[];
  measureStartedAt: number | null;
  /** Every Emotion cache.insert call (= a miss: the id was not pre-marked / not in the SSR tags). */
  styleMisses: StyleMiss[];
  markMeasureStart: () => void;
}

declare global {
  const __FW_ENGINE__: 'aot' | 'runtime';
  const __FW_BUILD__: FwBuildId;
  interface Window {
    __fw: FwGlobal;
  }
}
