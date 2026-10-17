import createCache, { type EmotionCache } from '@emotion/cache';

/** One own cache, key `mui`, on both sides (S11). No StyledEngineProvider. */
export const CACHE_KEY = 'mui';

const LAYER_ONLY = /^@layer\s+[^{]*$/;

/** Server cache: createEmotionServer (in the prerender) sets `compat`, so no inline tags are rendered. */
export function createServerCache(): EmotionCache {
  return createCache({ key: CACHE_KEY });
}

/**
 * Client cache. For `aot`, every census id is marked inserted before hydration, so `cache.insert` is never
 * called for a census style. Any call that still happens is a miss: it is logged on `window.__fw.styleMisses`
 * and, like MUI's own `enableCssLayer` wrapper does, put into `@layer mui` so a miss does not change the cascade.
 * For `runtime` (negative control) the cache hydrates from the inline SSR tags; the wrapper only logs.
 */
export function createClientCache(engine: 'aot' | 'runtime', ids: string[]): EmotionCache {
  const cache = createCache({ key: CACHE_KEY });
  if (engine === 'aot') for (const id of ids) cache.inserted[id] = true;

  const prev = cache.insert;
  cache.insert = (...args: Parameters<EmotionCache['insert']>) => {
    const fw = window.__fw;
    fw?.styleMisses.push({
      id: args[1].name,
      styles: args[1].styles.slice(0, 200),
      afterMark: fw.measureStartedAt !== null,
      t: performance.now(),
    });
    if (engine === 'aot' && !LAYER_ONLY.test(args[1].styles)) {
      args[1] = { ...args[1], styles: `@layer mui {${args[1].styles}}` };
    }
    return prev(...args);
  };
  return cache;
}
