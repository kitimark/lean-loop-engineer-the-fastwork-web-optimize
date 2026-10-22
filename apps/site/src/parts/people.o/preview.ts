import { cardLeft, cardTop, CARD_HEIGHT } from './logic';

export type Regime = 'below' | 'aboveFree' | 'aboveClamped';

export interface Held {
  vw: number;
  vh: number;
  x: number;
  s: number;
  t: number;
  b: number;
  y0: number;
}

export interface Step {
  write: boolean;
  tr: number;
  top: number;
  left: number;
}

export function regime({ vh, t, b }: { vh: number; t: number; b: number }): Regime {
  if (vh - 12 < b + 12 + CARD_HEIGHT) return 12 <= t - 12 - CARD_HEIGHT ? 'aboveFree' : 'aboveClamped';
  return 'below';
}

export function keep({ d, held, input, y }: { d: number; held: Held; input: Held; y: number }): boolean {
  const delta = held.y0 - y;
  const r = regime(held);
  return (
    held.vw === input.vw &&
    held.vh === input.vh &&
    held.x === input.x &&
    held.s === input.s &&
    input.t === held.t + delta &&
    input.b === held.b + delta &&
    r === regime(input) &&
    (r === 'aboveClamped' || Number.isInteger(delta * d))
  );
}

export function step({ d, held, input, y }: { d: number; held: Held; input: Held; y: number }): Step {
  if (keep({ d, held, input, y })) {
    const tr = regime(held) === 'aboveClamped' ? 0 : held.y0 - y;
    return { write: false, tr, top: cardTop({ vh: held.vh, y: held.t, z: held.b }) + tr, left: cardLeft({ vw: held.vw, x: held.x, s: held.s }) };
  }
  return { write: true, tr: 0, top: cardTop({ vh: input.vh, y: input.t, z: input.b }), left: cardLeft({ vw: input.vw, x: input.x, s: input.s }) };
}
