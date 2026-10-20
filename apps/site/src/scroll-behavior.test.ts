// The original sets `html{scroll-behavior:smooth}` and, under prefers-reduced-motion: reduce, `html{scroll-behavior:auto}`
// (assets/2.gBuqKVzi.css, 227006 and 227682). The port keeps both in the reset layer; without them a scrollTo without a
// behaviour jumps where the original glides (trajectory probe, task faithful-hero-baseline).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const css = readFileSync(fileURLToPath(new URL('./styles/reset.css', import.meta.url)), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
const flat = css.replace(/\s+/g, ' ');

it('reset.css scrolls the page smoothly, and not under reduced motion', () => {
  expect(flat).toContain('html { scroll-behavior: smooth; }');
  expect(flat).toMatch(/@media \(prefers-reduced-motion: reduce\) \{ html \{ scroll-behavior: auto; \} \}/);
});
