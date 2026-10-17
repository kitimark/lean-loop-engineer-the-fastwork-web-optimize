import { describe, expect, it } from 'vitest';
import { COLUMNS, trackHeight } from './data';

describe('morph.columns data', () => {
  it('five columns, 21 images (original list)', () => {
    expect(COLUMNS.length).toBe(5);
    expect(COLUMNS.reduce((a, c) => a + c.heights.length, 0)).toBe(21);
  });
  it('track height = sum of heights + 12 px gaps', () => {
    expect(trackHeight(COLUMNS[0]!)).toBe(360 + 212 + 349 + 167 + 212 + 48);
    expect(trackHeight(COLUMNS[1]!)).toBe(360 + 360 + 360 + 224 + 36);
  });
});
