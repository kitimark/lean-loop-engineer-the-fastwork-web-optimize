import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { MorphColumns } from '../morph.columns';
import { MorphCountdown } from './index';

const strip = (s: string) => s.replace(/data-fw-variant="[^"]*"/g, '');

describe('hidden-pause server markup equals the faithful markup (the pause is client-only)', () => {
  it('morph.columns', () => {
    const a = renderToString(createElement(MorphColumns, { variant: 'faithful' }));
    const b = renderToString(createElement(MorphColumns, { variant: 'hidden-pause' }));
    expect(strip(b)).toBe(strip(a));
    expect(b).not.toContain('data-fw-hidden');
  });
  it('morph.countdown', () => {
    const a = renderToString(createElement(MorphCountdown, { variant: 'faithful', impl: 'plain' }));
    const b = renderToString(createElement(MorphCountdown, { variant: 'hidden-pause', impl: 'plain' }));
    expect(strip(b)).toBe(strip(a));
  });
});
