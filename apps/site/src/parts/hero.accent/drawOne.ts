/** Variant `draw-one` (Lean `Fw.Parts.HeroAccentOpt` section 7; golden `golden/parts/hero.accent.drawone.jsonl`). */

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
