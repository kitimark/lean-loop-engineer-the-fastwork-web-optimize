// The body font stack is written twice: the MUI theme (theme.ts) and the reset layer (styles/reset.css). The two
// strings must stay equal. Follow-up: generate both from one source.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';
import { theme } from './theme';

const norm = (s: string) => s.replace(/\s+/g, ' ').replace(/'/g, '"').trim();

it('theme.ts and reset.css carry the same body font stack', () => {
  const css = readFileSync(fileURLToPath(new URL('./styles/reset.css', import.meta.url)), 'utf8');
  const m = /body\s*\{[^}]*?font-family:\s*([^;]+);/.exec(css);
  expect(m).not.toBeNull();
  expect(norm(m![1])).toBe(norm(theme.typography.fontFamily as string));
});
