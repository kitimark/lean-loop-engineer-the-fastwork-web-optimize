import { createTheme } from '@mui/material/styles';

/** S8/S6: one theme at module scope, ripples off. `cssVariables: false` (user decision 2026-10-18, Q34 = c): no `:root` custom properties, no theme `<Global>`; tokens resolve to literals in the rules. S13: system font stack placeholder. */
export const theme = createTheme({
  cssVariables: false,
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
