import { describe, expect, it } from 'vitest';
import { avatarOf, coverOf, fileOf, postOf, reviewerAvatar, RING_ORDER, thumbOf } from './assets';
import { PROFILES } from './data';
import { PANELS } from './panels.data';

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
  it('every review photo, reviewer avatar and about logo that the data names resolves, or has no logo (monogram)', () => {
    const missing: string[] = [];
    for (const p of PROFILES) {
      const d = PANELS[p.id]!;
      for (const r of d.reviews.items) {
        if (!reviewerAvatar(r.author.avatar)) missing.push(r.author.avatar);
        for (const img of r.images) if (!fileOf(p, img)) missing.push(`${p.id}/${img}`);
      }
      for (const e of [...d.about.experience, ...d.about.education, ...d.about.certificates]) if (e.logo && !fileOf(p, e.logo)) missing.push(`${p.id}/${e.logo}`);
    }
    expect(missing).toEqual(['graphic-designer/logo-fastwork.png']);
  });
});
