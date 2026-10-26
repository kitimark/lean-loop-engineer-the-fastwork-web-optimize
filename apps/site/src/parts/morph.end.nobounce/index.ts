export const NOBOUNCE_ID = 'morph.end.nobounce';
export const NOBOUNCE_ON = 'on';
export const NOBOUNCE_ATTR = 'data-fw-nobounce';
export const NOBOUNCE_CSS = 'html:has([data-fw-nobounce]){overscroll-behavior-y:none}';

export function nobounceProps(variant: string): Record<string, string> {
  return variant === NOBOUNCE_ON ? { [NOBOUNCE_ATTR]: '' } : {};
}
