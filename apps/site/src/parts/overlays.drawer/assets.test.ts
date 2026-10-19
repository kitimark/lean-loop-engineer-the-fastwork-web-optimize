import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import { OverlayDrawer } from './index';

// The drawer mounts through an effect (client-only); the static render starts from the mounted state instead.
vi.mock('react', async (orig) => {
  const actual = await orig<typeof import('react')>();
  return { ...actual, useState: (init: unknown) => [{ ...(init as object), mounted: true, shown: true }, () => {}] };
});

const manifest = JSON.parse(readFileSync(resolve(__dirname, '../../../assets.manifest.json'), 'utf8')) as { files: Array<{ url: string }> };
const urls = new Set(manifest.files.map((f) => f.url));
const imgSrcs = (html: string) => [...html.matchAll(/<img[^>]*?\ssrc="([^"]*)"/g)].map((m) => m[1]!);

describe('overlays.drawer assets', () => {
  const html = renderToStaticMarkup(createElement(OverlayDrawer, { variant: 'faithful' }));
  const srcs = imgSrcs(html);
  const base = '/selling/commission/why-bring/';
  it('renders the three icons in order and the divider twice', () => {
    expect(srcs.filter((s) => !s.endsWith('divider.svg'))).toEqual(['reputation.svg', 'payment.svg', 'folder.svg'].map((f) => base + f));
    expect(srcs.filter((s) => s === `${base}divider.svg`)).toHaveLength(2);
  });
  it('has no inline gif placeholder', () => {
    expect(html).not.toContain('data:image/gif');
  });
  it('every src is a manifest url', () => {
    expect(srcs.length).toBeGreaterThan(0);
    for (const s of srcs) expect(urls.has(s), s).toBe(true);
  });
});
