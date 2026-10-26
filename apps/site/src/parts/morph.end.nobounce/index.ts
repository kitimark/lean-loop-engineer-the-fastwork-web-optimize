export const NOBOUNCE_ID = 'morph.end.nobounce';
export const NOBOUNCE_ON = 'on';
/** Lean `Fw.Parts.MorphEndNobounce.attr`: the page root carries it when the flag is on; the rule that reads it is in styles/reset.css. */
export const NOBOUNCE_ATTR = 'data-fw-nobounce';
/** Lean `Fw.Parts.MorphEndNobounce.css`: the one rule, in the stylesheet from first paint and never toggled. */
export const NOBOUNCE_CSS = 'html:has([data-fw-nobounce]){overscroll-behavior-y:none}';

/** Props for the page-root element: the server renders the attribute, so the rubber band is gone before the first scroll. */
export function nobounceProps(variant: string): Record<string, string> {
  return variant === NOBOUNCE_ON ? { [NOBOUNCE_ATTR]: '' } : {};
}
