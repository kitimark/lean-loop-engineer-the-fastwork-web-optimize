import { createTheme } from '@mui/material/styles';

/** S8/S6: one theme at module scope, CSS variables, one colour scheme, ripples off. S13: system font stack placeholder. */
export const theme = createTheme({
  cssVariables: true,
  colorSchemes: { light: true },
  typography: {
    fontFamily: 'system-ui, -apple-system, "Segoe UI", sans-serif',
  },
  components: {
    // No MUI breakpoint media: Toolbar `regular`/gutters and Dialog `maxWidth` emit @media from MUI's default
    // xs..xl. Sites conditions come only from src/breakpoints.ts (Lean-generated), so these defaults avoid them.
    MuiToolbar: { defaultProps: { disableGutters: true, variant: 'dense' } },
    MuiDialog: { defaultProps: { maxWidth: false } },
    MuiMenuItem: { defaultProps: { dense: true } },
    MuiTabs: { defaultProps: { allowScrollButtonsMobile: true } },
    MuiButtonBase: {
      defaultProps: { disableRipple: true, disableTouchRipple: true },
    },
  },
});

type Sheet = Record<string, Record<string, unknown> | unknown>;

/** The theme's CSS variable sheet as plain CSS text (what ThemeProvider would otherwise inject via Emotion `<Global>`). */
export function themeVariablesCss(): string {
  const sheets = (theme as unknown as { generateStyleSheets: () => Sheet[] }).generateStyleSheets();
  let out = '';
  const emit = (selector: string, body: Record<string, unknown>) => {
    const decls: string[] = [];
    const nested: [string, Record<string, unknown>][] = [];
    for (const [k, v] of Object.entries(body)) {
      if (v !== null && typeof v === 'object') nested.push([k, v as Record<string, unknown>]);
      else decls.push(`${k}:${v}`);
    }
    if (decls.length) out += `${selector}{${decls.join(';')}}`;
    for (const [k, v] of nested) {
      if (k.startsWith('@')) {
        out += `${k}{`;
        emit(selector, v);
        out += '}';
      } else emit(k.includes('&') ? k.replace(/&/g, selector) : k, v);
    }
  };
  for (const sheet of sheets) {
    for (const [selector, body] of Object.entries(sheet)) {
      if (body !== null && typeof body === 'object') emit(selector, body as Record<string, unknown>);
    }
  }
  return out;
}
