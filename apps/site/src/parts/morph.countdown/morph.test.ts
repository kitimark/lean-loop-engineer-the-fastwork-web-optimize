import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { MorphCountdown } from './index';
import part from './part.json';

const css = readFileSync(resolve(__dirname, 'morph.module.css'), 'utf8');

describe('morph.countdown', () => {
  it('the wrapper restates the original rule and reads no media condition', () => {
    expect(css).not.toMatch(/@media/);
    for (const d of ['justify-content: center', 'width: 100%', 'margin-top: 32px', 'display: flex']) expect(css).toContain(d);
  });
  it('restates the paused-scene rule (css 11754-11758)', () => {
    expect(css).toContain("[data-start-selling-scene='paused']");
    expect(css).toMatch(/will-change: auto !important/);
    expect(css).toMatch(/animation-play-state: paused !important/);
  });
  it('renders the inverse clock under its own anchor, not the hero one', () => {
    const html = renderToString(createElement(MorphCountdown, { variant: 'faithful', impl: 'plain' }));
    expect(html).toContain('data-fw="morph-countdown"');
    expect(html).toContain('data-fw="morph-countdown-clock"');
    expect(html).not.toContain('data-fw="hero-countdown"');
    expect(html).toMatch(/class="[^"]*inverse/);
  });
  it('strip requires hero.countdown:strip', () => {
    expect(part.requires).toEqual({ 'morph.countdown:strip': ['hero.countdown:strip'] });
    expect(part.variants.faithful.kind).toBe('faithful');
  });
});
