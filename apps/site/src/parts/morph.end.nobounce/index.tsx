export const NOBOUNCE_ID = 'morph.end.nobounce';
export const NOBOUNCE_ON = 'on';
/** Lean `Fw.Parts.MorphEndNobounce.css`: the one rule, set at first paint and never toggled. */
export const NOBOUNCE_CSS = 'html{overscroll-behavior-y:none}';

/** Renders the rule in the page (server and client alike), so the rubber band is gone before the first scroll. */
export function EndNobounce({ variant }: { variant: string }) {
  return variant === NOBOUNCE_ON ? <style data-fw="morph-end-nobounce">{NOBOUNCE_CSS}</style> : null;
}
