import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('platform', {
  raw: (i) => L.raw({ bottom: i.bottom as number, vh: i.vh as number }),
  shrinking: (i) => L.shrinking({ bottom: i.bottom as number, vh: i.vh as number }),
  shrink: (i) => L.shrink({ reduced: i.reduced as boolean, bottom: i.bottom as number, vh: i.vh as number }),
  scale: (i) => L.scale({ s: i.s as number }),
  stageHeight: (i) => L.stageHeight({ w: i.w as number }),
  artboardScale: (i) => L.artboardScale({ w: i.w as number }),
  const: () => ({
    bgBlur: L.STAGE.bgBlur,
    bgOpacity: L.STAGE.bgOpacity,
    bgOpacityQuote: L.STAGE.bgOpacityQuote,
    grainOpacity: L.STAGE.grainOpacity,
    grainOpacitySecure: L.STAGE.grainOpacitySecure,
    grainTile: L.STAGE.grainTile,
  }),
});

describe('platform logic', () => {
  it('the card is unshrunk at 0.85 vh and fully shrunk at 0.35 vh', () => {
    expect(L.shrink({ reduced: false, bottom: 850, vh: 1000 })).toBe(0);
    expect(L.shrink({ reduced: false, bottom: 350, vh: 1000 })).toBe(1);
    expect(L.shrink({ reduced: true, bottom: 600, vh: 1000 })).toBe(1);
  });
  it('the artboard fills the stage', () => {
    expect(512 * L.artboardScale({ w: 361 })).toBeCloseTo(L.stageHeight({ w: 361 }), 12);
  });
});
