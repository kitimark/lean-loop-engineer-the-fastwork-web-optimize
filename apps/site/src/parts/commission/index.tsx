import Typography from '@mui/material/Typography';
import css from './box.module.css';

/**
 * Static shell (PLAN Q36) of the original's `commission` section. The outer box height per viewport comes from the generated
 * `box.module.css` (scripts/gen-shells.mjs); the content is placeholder text. No driver, no per-frame work.
 * A port replaces this folder as a whole.
 */
export function Commission({ variant }: { variant: string }) {
  return (
    <section className={css.box} data-fw="commission" data-fw-variant={variant}>
      <Typography variant="h2">Commission</Typography>
      <Typography variant="body1">Placeholder section (static shell).</Typography>
    </section>
  );
}
