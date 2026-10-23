export type DrawVariant = 'faithful' | 'draw-one';
export type DrawPhase = 'idle' | 'drawing';

export function drawAlpha(i: { j: number }): number {
  return i.j === 0 ? 1 : 0;
}

export function animates(i: { variant: DrawVariant; j: number }): boolean {
  return i.variant === 'faithful' ? true : drawAlpha({ j: i.j }) !== 0;
}

export function strokeAnimated(i: { variant: DrawVariant; phase: DrawPhase; j: number }): boolean {
  return i.phase === 'idle' ? false : animates({ variant: i.variant, j: i.j });
}

export function animatedCount(i: { variant: DrawVariant; phase: DrawPhase }): number {
  return [0, 1, 2].filter((j) => strokeAnimated({ ...i, j })).length;
}

export function drawAttr(variant: string): 'one' | 'nolayout' | undefined {
  return variant === 'draw-one' ? 'one' : variant === 'draw-nolayout' ? 'nolayout' : undefined;
}
