import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { resolveSearch } from '../registry';
import { parseOnly } from '../registry/only';
import { HOST_FRAME } from './hosts';
import { PartStage } from './PartStage';

// Task overflow-430: the stage page of group g2 (?only=g2&stage=vw:430,vh:932) scrolled 13 px sideways (scrollWidth 443 at 430). The
// morph panel's backdrop is `inset: 0 -3%` (3 % of 430 = 12.9 px each side); the page seats the panel in the nav (position: fixed,
// overflow: hidden), the stage seated it in a plain div. The measure gate (scrollWidth beyond the client width refuses the run) is the live guard.

const stageHtml = (search: string): string => {
  const only = parseOnly(search);
  if (only.kind !== 'ok') throw new Error('not a stage search: ' + search);
  const resolved = resolveSearch(search);
  if (!resolved.ok) throw new Error('config refused: ' + search);
  const pinned = { mismatch: false, restore: () => {} };
  return renderToStaticMarkup(createElement(PartStage, { stage: only.stage, config: resolved.config, pinned }));
};

describe('stage host frames', () => {
  it('only the panel host is framed, as the page frames it: fixed and clipping', () => {
    expect(Object.keys(HOST_FRAME)).toEqual(['panel']);
    expect(HOST_FRAME.panel).toMatchObject({ position: 'fixed', overflow: 'hidden' });
  });
  it('the panel host of a rendered stage carries the frame; the section hosts do not', () => {
    const html = stageHtml('?only=g2&stage=vw:430,vh:932');
    const hosts = [...html.matchAll(/<div data-fw-stage-host="([a-z]+)"([^>]*)>/g)].map((m) => ({ host: m[1]!, attrs: m[2]! }));
    const panel = hosts.find((h) => h.host === 'panel');
    expect(panel, 'g2 mounts the panel host').toBeDefined();
    expect(panel!.attrs).toContain('position:fixed');
    expect(panel!.attrs).toContain('overflow:hidden');
    for (const h of hosts.filter((x) => x.host !== 'panel')) expect(h.attrs, h.host).not.toContain('overflow');
  });
});
