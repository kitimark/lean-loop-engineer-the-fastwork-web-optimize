import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { PANEL } from './content';
import { MorphPanel } from './index';

const file = fileURLToPath(new URL('../../../../../snapshot/site/_app/immutable/nodes/2.DyWL8TcE.js', import.meta.url));
const js = readFileSync(file, 'utf8');

const start = js.indexOf('<div class="start-selling-morph-panel">');
const template = js.slice(start, js.indexOf('`', start));
const anchors = [...template.matchAll(/<a\b([^>]*)>/g)].map((m) => m[1]!);
const attr = (a: string, n: string) => new RegExp(`${n}="([^"]*)"`).exec(a)?.[1];

const html = (impl: 'mui' | 'plain') => renderToStaticMarkup(createElement(MorphPanel, { variant: 'faithful', impl }));
const hrefs = (h: string) => [...h.matchAll(/<a\b[^>]*href="([^"]*)"/g)].map((m) => m[1]);

describe('morph.panel text and links equal the snapshot', () => {
  it('the snapshot template was found with its two links', () => {
    expect(start).toBeGreaterThan(0);
    expect(anchors).toHaveLength(2);
  });
  for (const impl of ['mui', 'plain'] as const) {
    it(`hrefs, target, rel and selenium ids (${impl})`, () => {
      const h = html(impl);
      expect(hrefs(h)).toEqual(anchors.map((a) => attr(a, 'href')));
      expect(h).toContain(`data-selenium="${attr(anchors[0]!, 'data-selenium')}"`);
      expect(h).toContain('target="_blank" rel="noopener"');
      expect(anchors[0]).toContain('target="_blank" rel="noopener"');
    });
    it(`visible strings are the snapshot's English literals (${impl})`, () => {
      const h = html(impl);
      const text = h.replace(/<svg.*?<\/svg>/g, '').replace(/<[^>]+>/g, '|');
      for (const s of [PANEL.title, PANEL.cta, PANEL.rsvp, PANEL.operated, PANEL.copyright, PANEL.privacy]) {
        expect(js.includes('`' + s + '`'), s).toBe(true);
        expect(text, s).toContain(s);
      }
      expect(h).not.toMatch(/Placeholder|#morph-panel/);
    });
  }
  it('the RSVP en entry and the privacy link are in the snapshot', () => {
    expect(/\ben:\s*`/.test(js) && js.includes('`' + PANEL.rsvp + '`')).toBe(true);
    expect(new RegExp('en:\\s*`' + PANEL.rsvp + '`').test(js)).toBe(true);
    expect(template.includes('href="' + PANEL.privacyHref + '"')).toBe(true);
  });
});
