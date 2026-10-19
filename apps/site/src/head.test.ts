// The document head, the html attributes, the locale links and the countdown label equal the snapshot's on every entry
// head.gen.json declares (read at test time). Declared differences: the content-security policy, analytics.js, the tag
// manager, the Cloudflare beacon, the modulepreload hints, and the stylesheets and inline styles (owned by the CSS lanes).
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
// @ts-expect-error plain ESM helper without types
import { htmlAttrs, normEntry, parseHead, parseHtmlAttrs, renderHead, renderLocaleLinks } from '../scripts/head.mjs';
import gen from './head.gen.json';

const at = (p: string) => fileURLToPath(new URL(p, import.meta.url));
const snapshot = readFileSync(at('../../../snapshot/site/index.html'), 'utf8');
const key = (e: unknown) => JSON.stringify(e);
const declared = (gen.entries as { tag: string; attrs: string[][]; text: string }[]).map((e) => normEntry(e));
type Entry = ReturnType<typeof normEntry>;

type Raw = { tag: string; attrs: string[][] };
const attr = (e: Raw, k: string) => e.attrs.find(([n]) => n === k)?.[1];
const EXCLUDED = (e: Raw) =>
  attr(e, 'http-equiv')?.toLowerCase() === 'content-security-policy' || ['modulepreload', 'stylesheet'].includes(attr(e, 'rel') ?? '');
const kept = (html: string) => (parseHead(html) as Entry[]).filter((e) => !EXCLUDED(e));

const page = `<!doctype html><html ${htmlAttrs(gen)}><head>${renderHead(gen)}</head><body></body></html>`;

describe('document head', () => {
  it('the snapshot head, minus the excluded entries, is the declared list in order', () => {
    expect(kept(snapshot).map(key)).toEqual(declared.map(key));
  });

  it('the rendered head holds exactly the declared entries', () => {
    expect((parseHead(page) as Entry[]).map(key)).toEqual(declared.map(key));
  });

  const built = at('../dist/aot/index.html');
  const hasBuild = existsSync(built);
  it.skipIf(!hasBuild)('the built dist/aot head equals the declared entries', () => {
    const html = readFileSync(built, 'utf8');
    expect(kept(html).map(key)).toEqual(declared.map(key));
    expect(parseHtmlAttrs(html)).toEqual(gen.html);
  });

  it.skipIf(!hasBuild)('the built dist/aot has the language links last in body, after #root', () => {
    const html = readFileSync(built, 'utf8');
    const nav = renderLocaleLinks(gen);
    const rootAt = html.indexOf('<div id="root"');
    const navAt = html.indexOf('<nav class="site-locale-links"');
    expect(rootAt).toBeGreaterThan(-1);
    expect(html.split('site-locale-links').length - 1).toBe(1);
    expect(html).toContain(nav);
    expect(navAt).toBeGreaterThan(rootAt);
    expect(html.slice(navAt + nav.length)).toMatch(/^\s*(<script\b[^>]*>[\s\S]*?<\/script>\s*)*<\/body>\s*<\/html>\s*$/);
  });

  it('html attributes equal the snapshot', () => {
    expect(parseHtmlAttrs(snapshot)).toEqual(gen.html);
    expect(gen.html).toEqual({ lang: 'en', dir: 'ltr', 'data-theme': 'light' });
  });

  it('locale links equal the snapshot nav', () => {
    const nav = /<nav class="site-locale-links"[^>]*>([\s\S]*?)<\/nav>/.exec(snapshot)?.[1] ?? '';
    const links = [...nav.matchAll(/<a href="([^"]*)" hreflang="([^"]*)" lang="([^"]*)">([^<]*)<\/a>/g)].map((m) => ({
      code: m[2],
      href: m[1],
      label: m[4],
    }));
    expect(links.length).toBe(3);
    expect(gen.locales.map((l) => ({ code: l.code, href: l.href, label: l.label }))).toEqual(links);
  });

  it.skipIf(!hasBuild)('the built nav declarations equal the snapshot .site-locale-links rule', () => {
    const html = readFileSync(built, 'utf8');
    const rule = /\.site-locale-links\{([^}]*)\}/.exec(snapshot)?.[1];
    expect(rule).toBeTruthy();
    expect(/<nav class="site-locale-links"[^>]*style="([^"]*)"/.exec(html)?.[1]).toBe(rule);
  });

  it.skipIf(!hasBuild)('the built countdown carries the snapshot label', () => {
    const html = readFileSync(built, 'utf8');
    expect(html).toContain(`role="timer" aria-live="off" aria-label="${gen.countdownAriaLabel}"`);
  });

  it('the countdown label equals the snapshot and the part', () => {
    expect(snapshot).toContain(`role="timer" aria-label="${gen.countdownAriaLabel}"`);
    const src = readFileSync(at('./parts/hero.countdown/index.tsx'), 'utf8');
    expect(src).toContain(`'aria-label': '${gen.countdownAriaLabel}'`);
  });

  it('every icon and manifest href is a listed asset', () => {
    const files = new Set((JSON.parse(readFileSync(at('../assets.manifest.json'), 'utf8')).files as { url: string }[]).map((f) => f.url));
    for (const e of gen.entries) {
      const href = e.attrs.find(([k]) => k === 'href')?.[1] ?? '';
      const rel = e.attrs.find(([k]) => k === 'rel')?.[1] ?? '';
      if (e.tag === 'link' && /icon|manifest/.test(rel)) expect(files.has(href), href).toBe(true);
    }
  });
});
