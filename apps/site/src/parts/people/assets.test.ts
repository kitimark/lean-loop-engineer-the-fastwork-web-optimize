import { describe, expect, it } from 'vitest';
import { avatarOf, coverOf, postOf, RING_ORDER, thumbOf } from './assets';
import { PROFILES } from './data';

describe('people assets resolve to snapshot files', () => {
  it('every profile has an avatar and a cover', () => {
    for (const p of PROFILES) {
      expect(avatarOf(p), p.id).toBeTruthy();
      expect(coverOf(p), p.id).toBeTruthy();
    }
  });
  it('every post and service of the data has a picture', () => {
    for (const p of PROFILES) {
      for (const post of p.posts) expect(postOf(p, post), `${p.id}/${post.id}`).toBeTruthy();
      for (const s of p.services) expect(thumbOf(p, s), `${p.id}/${s.id}`).toBeTruthy();
    }
  });
  it('the ring order lists each profile once', () => {
    expect([...RING_ORDER].sort()).toEqual(PROFILES.map((p) => p.id).sort());
  });
});
