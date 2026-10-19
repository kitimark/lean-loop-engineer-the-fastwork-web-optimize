import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { Ask, Profile } from './Visuals';

const manifest = JSON.parse(readFileSync(resolve(__dirname, '../../../assets.manifest.json'), 'utf8')) as { files: Array<{ url: string }> };
const urls = new Set(manifest.files.map((f) => f.url));
const imgSrcs = (html: string) => [...html.matchAll(/<img[^>]*?\ssrc="([^"]*)"/g)].map((m) => m[1]!);
const subs = { entries: true, glint: true, marquee: true };

describe('platform assets', () => {
  const profile = renderToStaticMarkup(createElement(Profile, { subs }));
  const ask = renderToStaticMarkup(createElement(Ask, { subs }));
  it('the profile renders the pin as an img', () => {
    expect(imgSrcs(profile)).toContain('/selling/icons/pin.svg');
  });
  it('the ask results render the lawyer png', () => {
    expect(imgSrcs(ask)).toContain('/samples/docs/lawyer/lawyer-consult-cover.png');
  });
  it('every img src is a manifest url', () => {
    const all = [...imgSrcs(profile), ...imgSrcs(ask)];
    expect(all.length).toBeGreaterThan(0);
    for (const s of all) expect(urls.has(s), s).toBe(true);
  });
  it('the is-drawn grain rule precedes the is-figma-bg override', () => {
    const css = readFileSync(resolve(__dirname, 'visuals.module.css'), 'utf8');
    const rules = [...css.matchAll(/\.ask::after\s*\{([^}]*)\}/g)].map((m) => m[1]!);
    expect(rules).toHaveLength(2);
    expect(rules[0]).toContain('feTurbulence');
    expect(rules[0]).toContain('opacity: 0.18');
    expect(rules[1]).toContain('grain.png');
    expect(rules[1]).toContain('mix-blend-mode: overlay');
    expect(rules[1]).toContain('opacity: 0.55');
  });
});
