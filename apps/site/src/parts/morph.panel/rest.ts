/**
 * Variant `rest` of the platform panel's blur (ledger n=11; Lean: lean/Fw/Parts/MorphPanelOpt.lean `fade`, `radius`,
 * `filterO`, `filterV`, `rest_visSame_E`). The original keeps `filter: blur(0px)` at rest, which in both engines still
 * builds a filter effect / indirect layer. The variant writes `filter: none` when the radius is 0 and the same blur
 * otherwise. E at rest under the premise RG10 (no fixed or absolute descendant uses the panel as containing block and
 * the stacking order is unchanged); the premise is a hypothesis of the Lean proof, not checked here.
 * NOT WIRED: the filter is declared on `.start-selling-platform` (parts/platform) and `--morph-fade` is written by
 * parts/morph.tween; neither is in this task's writes (see the handoff).
 */

/** `QM(e) = 1 - min(1, e / 0.55)`: the fade the script writes into `--morph-fade` from the section progress `r`. */
export function fade(r: number): number {
  return 1 - Math.min(1, r * (20 / 11));
}

/** The blur radius in px of `blur(calc((1 - phi) * 12px))`; `calc()` clamps a negative length to 0. */
export function radius(phi: number): number {
  return Math.max(0, (1 - phi) * 12);
}

export interface FilterOp {
  name: 'blur';
  args: [number];
}

/** The original's filter list: always one blur, `blur(0)` included. */
export function filterO(phi: number): FilterOp[] {
  return [{ name: 'blur', args: [radius(phi)] }];
}

/** The variant's filter list: none when the radius is 0, else the original's. */
export function filterV(phi: number): FilterOp[] {
  return radius(phi) === 0 ? [] : filterO(phi);
}

/** The CSS `filter` value of the variant: `none` at rest, else the original's blur text. */
export function filterCss(phi: number): string {
  const f = filterV(phi);
  return f.length === 0 ? 'none' : `blur(${f[0]!.args[0]}px)`;
}
