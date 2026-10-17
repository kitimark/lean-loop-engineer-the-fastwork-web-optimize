import type { FwConfig } from './registry/types';
import type { FwBuildId, FwGlobal } from './globals';

export function installFw(init: {
  config: FwConfig;
  configHash: string;
  mode: FwGlobal['mode'];
}): FwGlobal {
  const fw: FwGlobal = {
    ...init,
    buildId: __FW_BUILD__,
    hydrated: false,
    hydrationErrors: [],
    measureStartedAt: null,
    styleMisses: [],
    markMeasureStart() {
      // Call after `hydrated` (and after the rest window, PLAN 6.7). Idempotent.
      if (fw.measureStartedAt !== null) return;
      fw.measureStartedAt = performance.now();
      performance.mark('fw:measure-start');
      window.dispatchEvent(new Event('fw:measure-start'));
    },
  };
  window.__fw = fw;
  return fw;
}

export function setHydrated(): void {
  if (typeof window !== 'undefined' && window.__fw) {
    window.__fw.hydrated = true;
    performance.mark('fw:hydrated');
  }
}

export type { FwBuildId };
