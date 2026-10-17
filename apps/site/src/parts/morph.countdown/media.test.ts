import { describe, expect, it } from 'vitest';
import { MEDIA_IDS as HERO_IDS } from '../hero.countdown/media';
import { MEDIA_IDS } from './media';

describe('morph.countdown media', () => {
  it('reads the same conditions as the clock it embeds', () => {
    expect([...MEDIA_IDS]).toEqual([...HERO_IDS]);
  });
});
