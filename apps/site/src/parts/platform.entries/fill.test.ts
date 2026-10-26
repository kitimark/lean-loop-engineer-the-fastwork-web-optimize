import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';

const css = readFileSync(resolve(__dirname, '../platform/visuals.module.css'), 'utf8');
const tsx = readFileSync(resolve(__dirname, '../platform/Visuals.tsx'), 'utf8');
const part = JSON.parse(readFileSync(resolve(__dirname, 'part.json'), 'utf8')) as {
  id: string;
  variants: Record<string, { kind: string }>;
};

type Decl = [string, string];
interface Rule { sel: string; decls: Decl[]; ctx: string[] }

function parse(src: string): Rule[] {
  const text = src.replace(/\/\*[\s\S]*?\*\//g, '');
  const out: Rule[] = [];
  let i = 0;
  const block = (ctx: string[]): void => {
    let buf = '';
    while (i < text.length) {
      const ch = text[i++]!;
      if (ch === '{') {
        const pre = buf.trim().replace(/\s+/g, ' ');
        buf = '';
        if (pre.startsWith('@')) { block([...ctx, pre]); continue; }
        const start = i;
        let depth = 1;
        while (depth > 0) { const c = text[i++]; if (c === '{') depth++; else if (c === '}') depth--; }
        const decls = text.slice(start, i - 1).split(';').map((d) => d.trim()).filter(Boolean)
          .map((d): Decl => { const k = d.indexOf(':'); return [d.slice(0, k).trim(), d.slice(k + 1).trim().replace(/\s+/g, ' ')]; });
        out.push({ sel: pre, decls, ctx });
      } else if (ch === '}') return;
      else if (ch === ';') buf = '';
      else buf += ch;
    }
  };
  block([]);
  return out;
}

const rules = parse(css);
const selectors = (r: Rule) => r.sel.split(',').map((s) => s.trim());
const isKeyframes = (r: Rule) => r.ctx.some((c) => c.startsWith('@keyframes'));
const isReduce = (r: Rule) => r.ctx.some((c) => /prefers-reduced-motion:\s*reduce/.test(c));
const isVariant = (r: Rule) => r.sel.includes('.fillRelease');
const variantRules = rules.filter((r) => !isKeyframes(r) && isVariant(r));

function classCount(sel: string): number {
  const s = sel.replace(/:where\([^)]*\)/g, '').replace(/::[\w-]+/g, '').replace(/:not\(([^)]*)\)/g, ' $1');
  return (s.match(/\.[\w-]+|\[[^\]]*\]|:[\w-]+/g) ?? []).length;
}

function tokens(value: string): string[] {
  let v = value;
  for (let prev = ''; prev !== v;) { prev = v; v = v.replace(/[\w-]+\([^()]*\)/g, ' '); }
  return v.split(/\s+/).filter(Boolean);
}

function keyframesTo(name: string): Decl[] {
  const r = rules.find((x) => x.sel === 'to' && x.ctx.at(-1) === `@keyframes ${name}`);
  if (!r) throw new Error(`no to block for ${name}`);
  return r.decls;
}

const keyframeNames = new Set(rules.flatMap((r) => r.ctx).filter((c) => c.startsWith('@keyframes ')).map((c) => c.slice(11)));
const animated = new Set(['opacity', 'transform', 'filter']);

function row(faithful: string, els: string[]) {
  const base = rules.find((r) => !isKeyframes(r) && r.ctx.length === 1 && selectors(r).includes(faithful));
  if (!base) throw new Error(`no faithful rule ${faithful}`);
  const shorthand = base.decls.find(([p]) => p === 'animation')?.[1] ?? '';
  const toks = tokens(shorthand);
  const kf = toks.find((t) => keyframeNames.has(t)) ?? '';
  const time = toks.find((t) => /^\d*\.?\d+m?s$/.test(t)) ?? '';
  const durMs = time.endsWith('ms') ? Number(time.slice(0, -2)) : Number(time.slice(0, -1)) * 1000;
  const vr = variantRules.filter((r) => selectors(r).some((s) => s.replace('.fillRelease', '') === faithful));
  if (vr.length !== 1) throw new Error(`${vr.length} variant rules for ${faithful}`);
  const v = vr[0]!;
  const elRe = new RegExp(`\\.(${els.join('|')})(?![\\w-])`);
  const rivals = rules
    .filter((r) => !isKeyframes(r) && !isReduce(r) && !isVariant(r))
    .filter((r) => r.decls.some(([p]) => animated.has(p) || p.startsWith('animation')))
    .flatMap(selectors)
    .filter((s) => elRe.test(s.split(/[\s>+~]+/).at(-1) ?? ''));
  return {
    variant: v.sel,
    kf,
    fill: toks.includes('both') ? 'both' : toks.includes('backwards') ? 'backwards' : toks.includes('forwards') ? 'forwards' : 'none',
    durMs,
    to: keyframesTo(kf),
    decls: v.decls,
    spec: classCount(v.sel),
    rival: Math.max(0, ...rivals.map(classCount)),
  };
}

function constOut() {
  const opt = Object.entries(part.variants).filter(([, x]) => x.kind === 'optimized').map(([k]) => k);
  const media = [...new Set(variantRules.map((r) => r.ctx.at(-1)))];
  return {
    flag: `${part.id}:${opt[0]}`,
    variant: opt[0],
    cls: 'fillRelease',
    media: media.length === 1 ? media[0]!.replace(/^@media /, '') : media.join(' | '),
    roots: [...new Set(variantRules.map((r) => r.sel.match(/^\.([\w-]+)\.fillRelease/)?.[1] ?? ''))],
    rows: variantRules.length,
  };
}

goldenConformance('platform-entries-fill', {
  const: () => constOut(),
  row: (i) => row(i.faithful as string, i.els as string[]),
});

describe('platform.entries:fill-release wiring', () => {
  it('every variant rule sits in @layer parts and the no-preference block only', () => {
    for (const r of variantRules) expect(r.ctx).toEqual(['@layer parts', '@media (prefers-reduced-motion: no-preference)']);
  });
  it('each stage root carries fillRelease from subs.entriesFill', () => {
    for (const root of constOut().roots) expect(tsx).toMatch(new RegExp(`cx\\(v\\.${root}, subs\\.entriesFill && v\\.fillRelease`));
  });
});
