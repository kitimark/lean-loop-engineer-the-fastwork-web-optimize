import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { Nav } from './index';

const header = (variant: string): { cls: string; box: string | null } => {
  const html = renderToStaticMarkup(createElement(Nav, { variant }));
  const tag = /<header[^>]*>/.exec(html)![0];
  return { cls: /class="([^"]*)"/.exec(tag)![1]!, box: /data-fw-box="([^"]*)"/.exec(tag)?.[1] ?? null };
};

describe('nav variants set cumulative classes', () => {
  it('faithful and earn-no-transition keep the original classes and no box attribute', () => {
    for (const v of ['faithful', 'earn-no-transition']) {
      const h = header(v);
      expect(h.box).toBeNull();
      expect(h.cls.split(' ').length).toBe(2);
      expect(h.cls).toMatch(/is-hero-pill$/);
    }
  });
  it('clip-box adds one class, bar-fixed two, logo-3d three', () => {
    const n = (v: string) => header(v).cls.split(' ').length;
    expect([n('clip-box'), n('bar-fixed'), n('logo-3d')]).toEqual([3, 4, 5]);
    for (const v of ['clip-box', 'bar-fixed', 'logo-3d']) expect(header(v).box).toBe('union');
  });
});
