import { CacheProvider } from '@emotion/react';
import type { EmotionCache } from '@emotion/cache';
import { ThemeProvider } from '@mui/material/styles';
import type { ReactNode } from 'react';
import { theme } from './theme';

/**
 * Shared by server, client and census: one own cache through CacheProvider (never StyledEngineProvider), one
 * module-scope theme. `cssVariables: false` (Q34 = c, S8): the provider emits no `<Global>` and no `:root` tokens in either engine.
 */
export function Root({ cache, children }: { cache: EmotionCache; children: ReactNode }) {
  return (
    <CacheProvider value={cache}>
      <ThemeProvider theme={theme}>
        {children}
      </ThemeProvider>
    </CacheProvider>
  );
}
