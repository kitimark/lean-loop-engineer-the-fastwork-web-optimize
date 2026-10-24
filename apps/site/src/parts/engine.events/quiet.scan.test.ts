import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { quietTypes } from './quiet.gen';

const SRC = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

function reachable(entry: string): string[] {
  const seen = new Set<string>();
  const queue = [entry];
  while (queue.length > 0) {
    const file = queue.pop()!;
    if (seen.has(file)) continue;
    seen.add(file);
    const text = readFileSync(file, 'utf8');
    for (const m of text.matchAll(/(?:from|import\()\s*'(\.[^']*)'/g)) {
      const base = resolve(dirname(file), m[1]!);
      const hit = [base, `${base}.ts`, `${base}.tsx`, join(base, 'index.ts'), join(base, 'index.tsx')].find((p) => /\.tsx?$/.test(p) && existsSync(p));
      if (hit) queue.push(hit);
    }
  }
  return [...seen].filter((f) => !/\.test\.tsx?$/.test(f)).sort();
}

const files = reachable(join(SRC, 'entry-client.tsx'));
const rel = (f: string) => relative(SRC, f);
const read = (f: string) => readFileSync(f, 'utf8');

const PROP = /\bon(?:Animation(?:Start|Iteration|End)|Transition(?:Run|Start|Cancel|End))(?:Capture)?\b/;
const INPUT_FAMILY = /@mui\/material(?:\/(?:InputBase|Input|FilledInput|OutlinedInput|TextField|Select|NativeSelect|Autocomplete|TablePagination)|')/;
const PORTAL = /createPortal|@mui\/material\/(?:Portal|Modal|Popover|Popper|Menu|Drawer|Dialog|Tooltip|Snackbar)\b|@mui\/base/;
const LISTEN = new RegExp(`addEventListener\\(\\s*['"\`](?:${quietTypes.join('|')})['"\`]`);

/** Files that add a quiet type to an element or window of their own, never to the React container. */
const OWN_TARGET = new Set(['parts/hero.exit/index.tsx', 'debug/nav-transition.ts']);

describe('engine.events:quiet premises, scanned over the files entry-client.tsx reaches', () => {
  it('reaches the app', () => {
    expect(files.map(rel)).toContain('App.tsx');
    expect(files.length).toBeGreaterThan(40);
  });

  it('no React handler prop for a quiet type', () => {
    expect(files.filter((f) => PROP.test(read(f))).map(rel)).toEqual([]);
  });

  it('no component that sets onAnimationStart itself (the MUI input family)', () => {
    expect(files.filter((f) => INPUT_FAMILY.test(read(f))).map(rel)).toEqual([]);
  });

  it('no portal: the root is the only container React listens on', () => {
    expect(files.filter((f) => PORTAL.test(read(f))).map(rel)).toEqual([]);
  });

  it('a quiet-type listener added by hand sits on a file that owns its target', () => {
    const adders = files.filter((f) => LISTEN.test(read(f))).map(rel);
    expect(adders.filter((f) => !OWN_TARGET.has(f))).toEqual([]);
  });

  it('the quiet list is the 7 animation and transition types React registers', () => {
    expect([...quietTypes].sort()).toEqual(['animationend', 'animationiteration', 'animationstart', 'transitioncancel', 'transitionend', 'transitionrun', 'transitionstart']);
  });
});
