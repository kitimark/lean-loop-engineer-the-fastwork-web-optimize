/**
 * Variant `draw-one` of hero.accent (Lean: lean/Fw/Parts/HeroAccentOpt.lean section 7, `animates`, `strokeAnimated`,
 * `drawOne_visSame`; golden: packages/contracts/golden/parts/hero.accent.drawone.jsonl). While a word is drawn out or
 * in, copies 1 and 2 are opacity 0 (accent.module.css, `:is(.drawingIn, .drawingOut) .idleFrame` then `.frame0`), so
 * only copy 0 runs the stroke-dashoffset animation. The selector itself lives in the CSS (`:not(.frame0)`); this module
 * holds the decision the golden rows check and the one attribute the component writes.
 */

export type DrawVariant = 'faithful' | 'draw-one';
export type DrawPhase = 'idle' | 'drawing';

/** Opacity of copy `j` in the draw window (Lean `drawAlpha`). */
export function drawAlpha(i: { j: number }): number {
  return i.j === 0 ? 1 : 0;
}

/** Does copy `j` run the stroke animation in the draw window (Lean `animates`). */
export function animates(i: { variant: DrawVariant; j: number }): boolean {
  return i.variant === 'faithful' ? true : drawAlpha({ j: i.j }) !== 0;
}

/** Does copy `j` run it in `phase` (Lean `strokeAnimated`). */
export function strokeAnimated(i: { variant: DrawVariant; phase: DrawPhase; j: number }): boolean {
  return i.phase === 'idle' ? false : animates({ variant: i.variant, j: i.j });
}

/** How many of the three copies run it (Lean `animatedCount`). */
export function animatedCount(i: { variant: DrawVariant; phase: DrawPhase }): number {
  return [0, 1, 2].filter((j) => strokeAnimated({ ...i, j })).length;
}

/** The `data-fw-draw` attribute the component writes: `one` for `draw-one`, none otherwise. */
export function drawAttr(variant: string): 'one' | undefined {
  return variant === 'draw-one' ? 'one' : undefined;
}
