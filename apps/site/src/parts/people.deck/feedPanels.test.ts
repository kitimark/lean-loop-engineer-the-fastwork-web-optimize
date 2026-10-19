import { createElement as h } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { PROFILES } from '../people/data';
import { PANELS } from '../people/panels.data';
import { AboutPanel, ReviewsPanel, ServicesPanel } from './feedPanels';

describe('feed panels render for every profession', () => {
  it('services: one card per service', () => {
    for (const p of PROFILES) {
      const html = renderToStaticMarkup(h(ServicesPanel, { p }));
      expect(html.match(/<li>/g)?.length, p.id).toBe(p.services.length);
      expect(html).toContain(p.services[0]!.title.replace(/&/g, '&amp;'));
    }
  });
  it('reviews: all reviews, one filter button per service with reviews plus all', () => {
    for (const p of PROFILES) {
      const d = PANELS[p.id]!;
      const html = renderToStaticMarkup(h(ReviewsPanel, { p, data: d }));
      expect(html.match(/<article/g)?.length, p.id).toBe(d.reviews.items.length);
      expect(html.match(/role="tab"/g)?.length, p.id).toBe(1 + p.services.filter((s) => s.reviewCount > 0).length);
      expect(html).toContain(`Summary from ${d.reviews.total} reviews`);
    }
  });
  it('about: experience and skills always, others only when listed', () => {
    for (const p of PROFILES) {
      const d = PANELS[p.id]!;
      const html = renderToStaticMarkup(h(AboutPanel, { p, data: d }));
      expect(html).toContain('Work experience');
      expect(html).toContain('Skills');
      expect(html.includes('Education'), p.id).toBe(d.about.education.length > 0);
      expect(html.includes('Certificates'), p.id).toBe(d.about.certificates.length > 0);
      expect(html.includes('Languages'), p.id).toBe(d.about.languages.length > 0);
      expect(html.includes('Licenses and awards'), p.id).toBe(d.about.awards.length > 0);
    }
  });
});
