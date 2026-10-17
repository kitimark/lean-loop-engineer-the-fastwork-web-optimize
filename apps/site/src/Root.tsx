import { CacheProvider } from '@emotion/react';
import type { EmotionCache } from '@emotion/cache';
import { ThemeProvider } from '@mui/material/styles';
import type { ReactNode } from 'react';
import { theme } from './theme';

// Runtime-supported ThemeProvider prop (system createCssVarsProvider) that MUI's ThemeProvider typings omit.
const styleSheetProps = { disableStyleSheetGeneration: __FW_ENGINE__ === 'aot' } as object;

/**
 * Shared by server, client and census: one own cache through CacheProvider (never StyledEngineProvider), one
 * module-scope theme. In the `aot` engine the CSS variable sheet is static CSS, so the provider does not emit
 * its `<Global>` (S8, S9). The `runtime` engine keeps MUI's default, the plain-Emotion negative control.
 */
export function Root({ cache, children }: { cache: EmotionCache; children: ReactNode }) {
  return (
    <CacheProvider value={cache}>
      <ThemeProvider theme={theme} defaultMode="light" {...styleSheetProps}>
        {children}
      </ThemeProvider>
    </CacheProvider>
  );
}
