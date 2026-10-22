import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';
import { actionsX, boxActive, boxVariant, clipRect, insets, logoX, unionRect } from './box';

type Row = Record<string, number | boolean>;
const golden = (name: string): Row[] =>
  readFileSync(new URL(`../../../../../packages/contracts/golden/parts/${name}.jsonl`, import.meta.url), 'utf8')
    .split('\n')
    .filter((l) => l.trim() !== '')
    .map((l) => decodeRat(JSON.parse(l)) as Row);
const clipRows = golden('nav-clip-box');
const barRows = golden('nav-bar-fixed');
const navCss = readFileSync(new URL('./nav.module.css', import.meta.url), 'utf8');
const css = readFileSync(new URL('./box.module.css', import.meta.url), 'utf8');

function decls(sel: string, from = 0, sheet = css): Map<string, string> {
  const at = sheet.indexOf(`${sel} {`, from);
  if (at < 0) throw new Error(`no rule ${sel}`);
  const open = sheet.indexOf('{', at);
  let depth = 0;
  let end = open;
  for (; end < sheet.length; end++) {
    if (sheet[end] === '{') depth++;
    if (sheet[end] === '}' && --depth === 0) break;
  }
  const body = sheet.slice(open + 1, end);
  const out = new Map<string, string>();
  for (const m of body.matchAll(/(--[\w-]+|[a-z-]+):\s*([^;]*?);/gs)) out.set(m[1]!, m[2]!.replace(/\s+/g, ' ').trim());
  return out;
}

const navPhoneAt = navCss.indexOf('@media (width<=640px)');
const boxPhoneAt = css.indexOf('@media (width<=640px)');
const MORPH = ':global(.is-morphing):not(:global(.is-locale-open))';
const navBase = decls('.nav', 0, navCss);
const navPhone = decls('.nav', navPhoneAt, navCss);
const barBase = decls('.bar', 0, navCss);
const barPhone = decls('.bar', navPhoneAt, navCss);
const clipBase = decls(`.boxClip${MORPH}`);
const clipPhone = decls(`.boxClip${MORPH}`, boxPhoneAt);
const clipBar = decls(`.boxClip${MORPH} > :global([data-fw-box-role='bar'])`);
const clipPanel = decls(`.boxClip${MORPH} > :global([data-fw='morph-panel'])`);
const fixedBar = decls(`.boxBar${MORPH} > :global([data-fw-box-role='bar'])`);
const fixedLogo = decls(`.boxBar${MORPH} :global([data-fw-box-role='logo'])`);
const fixedActions = decls(`.boxBar${MORPH} :global([data-fw='nav-actions'])`);
const logo3d = decls(`.box3d${MORPH} :global([data-fw-box-role='logo'])`);
const logo3dPhone = decls(`.box3d${MORPH} :global([data-fw-box-role='logo'])`, boxPhoneAt);

function px(expr: string, env: Map<string, string>, vw: number, vh: number): number {
  let e = expr;
  for (let i = 0; i < 20 && /var\(/.test(e); i++) {
    e = e.replace(/var\((--[\w-]+)(?:,\s*([^()]+))?\)/g, (_, name: string, fb?: string) => `(${env.get(name) ?? fb ?? 'NaN'})`);
  }
  e = e
    .replace(/100vw/g, String(vw))
    .replace(/100vh/g, String(vh))
    .replace(/(\d+(?:\.\d+)?)px/g, '$1')
    .replace(/calc\(/g, '(')
    .replace(/min\(/g, 'Math.min(');
  return new Function(`return (${e});`)() as number;
}

function envOf(vw: number, m: number): Map<string, string> {
  const phone = vw <= 640;
  const env = new Map(navBase);
  if (phone) for (const [k, v] of navPhone) env.set(k, v);
  for (const [k, v] of barBase) if (k.startsWith('--')) env.set(k, v);
  if (phone) for (const [k, v] of barPhone) if (k.startsWith('--')) env.set(k, v);
  env.set('--morph', String(m));
  env.set('--nav-expand', '1');
  for (const [k, v] of clipBase) if (k.startsWith('--')) env.set(k, v);
  if (phone) for (const [k, v] of clipPhone) if (k.startsWith('--')) env.set(k, v);
  for (const [k, v] of fixedBar) if (k.startsWith('--')) env.set(k, v);
  return env;
}

describe('nav clip-box: box.ts restates the Lean rows', () => {
  it('has the rows', () => {
    expect(clipRows.length).toBe(100);
    expect(barRows.length).toBe(100);
  });
  it('reproduces the union box, the insets and the original rect', () => {
    for (const r of clipRows) {
      const v = { w: r.vw as number, h: r.vh as number };
      const m = r.m as number;
      const u = unionRect(v);
      expect(u.left).toBeCloseTo(r.unionL as number, 9);
      expect(u.top).toBeCloseTo(r.unionT as number, 9);
      expect(u.width).toBeCloseTo(r.unionW as number, 9);
      expect(u.height).toBeCloseTo(r.unionH as number, 9);
      const i = insets(v, m);
      expect(i.x).toBeCloseTo(r.insetX as number, 9);
      expect(i.t).toBeCloseTo(r.insetT as number, 9);
      expect(i.b).toBeCloseTo(r.insetB as number, 9);
      const c = clipRect(v, m);
      expect(c.left).toBeCloseTo(r.origL as number, 9);
      expect(c.top).toBeCloseTo(r.origT as number, 9);
      expect(c.width).toBeCloseTo(r.origW as number, 9);
      expect(c.height).toBeCloseTo(r.origH as number, 9);
      expect(boxActive(m, false)).toBe(r.active);
      expect(boxActive(m, true)).toBe(false);
    }
  });
  it('reproduces the bar rows', () => {
    for (const r of barRows) {
      const v = { w: r.vw as number, h: r.vh as number };
      const m = r.m as number;
      expect(logoX(v, m)).toBeCloseTo(r.logoX as number, 9);
      expect(actionsX(v, m)).toBeCloseTo(r.actionsX as number, 9);
      expect(r.barW).toBe(unionRect(v).width);
    }
  });
  it('names the variants cumulatively', () => {
    expect(['faithful', 'clip-box', 'bar-fixed', 'logo-3d', 'earn-no-transition'].map(boxVariant)).toEqual([null, 'clip-box', 'bar-fixed', 'logo-3d', null]);
  });
});

describe('nav clip-box: the CSS evaluates to the Lean rows', () => {
  const morphing = clipRows.filter((r) => r.active === true);
  it('applies only while the nav morphs with its locale menu closed', () => {
    expect(morphing.length).toBeGreaterThan(0);
    expect(css).not.toMatch(/^\s*\.box(Clip|Bar|3d)\s*\{/m);
    for (const sel of [`.boxClip${MORPH}`, `.boxBar${MORPH} > :global([data-fw-box-role='bar'])`, `.box3d${MORPH} :global([data-fw-box-role='logo'])`]) expect(css).toContain(`${sel} {`);
  });
  it('lays the nav out as the union box and clips the pill', () => {
    for (const r of morphing) {
      const [vw, vh, m] = [r.vw as number, r.vh as number, r.m as number];
      const env = envOf(vw, m);
      const phone = vw <= 640;
      const rule = new Map(clipBase);
      if (phone) for (const [k, v] of clipPhone) rule.set(k, v);
      const at = (e: string) => px(e, env, vw, vh);
      expect(at(rule.get('top')!)).toBeCloseTo(r.unionT as number, 9);
      expect(Math.max(at(rule.get('width')!), at(rule.get('min-width')!))).toBeCloseTo(r.unionW as number, 9);
      expect(at(rule.get('width')!)).toBeCloseTo(at('var(--pill-w)'), 9);
      expect(at(rule.get('height')!)).toBeCloseTo(r.unionH as number, 9);
      expect(rule.get('border-radius')).toBe('0');
      expect(at('var(--box-ix)')).toBeCloseTo(r.insetX as number, 9);
      expect(at('var(--box-it)')).toBeCloseTo(r.insetT as number, 9);
      expect(at('var(--box-ib)')).toBeCloseTo(r.insetB as number, 9);
      const clip = rule.get('clip-path')!;
      expect(clip).toBe('inset(var(--box-it) var(--box-ix) var(--box-ib) var(--box-ix) round calc(32px - 12px * var(--morph)))');
      expect(at('calc(32px - 12px * var(--morph))')).toBeCloseTo(r.radius as number, 9);
      expect(at(clipBar.get('top')!)).toBeCloseTo(r.insetT as number, 9);
      expect(at(clipBar.get('left')!)).toBeCloseTo(r.insetX as number, 9);
      expect(at(clipBar.get('right')!)).toBeCloseTo(r.insetX as number, 9);
      expect(clipPanel.get('inset')).toBe('var(--box-it) var(--box-ix) var(--box-ib) var(--box-ix)');
      expect((r.unionL as number) + at('var(--box-ix)')).toBeCloseTo(r.origL as number, 9);
      expect((r.unionT as number) + at('var(--box-it)')).toBeCloseTo(r.origT as number, 9);
    }
  });
  it('keeps the original transition lists: the sheet names no transition', () => {
    expect(css).not.toMatch(/transition/);
  });
  it('moves the logo and the actions by the Lean translations', () => {
    for (const r of barRows.filter((q) => (q.m as number) > 0.001)) {
      const [vw, vh, m] = [r.vw as number, r.vh as number, r.m as number];
      const env = envOf(vw, m);
      const at = (e: string) => px(e, env, vw, vh);
      expect(at('var(--logo-x)')).toBeCloseTo(r.logoX as number, 9);
      expect(at('var(--actions-x)')).toBeCloseTo(r.actionsX as number, 9);
      expect(at(fixedBar.get('translate')!.split(' ').slice(1).join(' '))).toBeCloseTo(r.barY as number, 9);
      expect(at(fixedLogo.get('left')!)).toBeCloseTo(r.inset as number, 9);
      expect(fixedLogo.get('translate')).toBe('calc(var(--logo-x) - 50% * var(--morph)) 0');
      expect(fixedActions.get('translate')).toBe('var(--actions-x) -50%');
      expect(at(fixedBar.get('left')!) + at(fixedBar.get('right')!)).toBe(0);
    }
  });
  it('writes the 3d logo as translate then scale, like the original translate property then scale property', () => {
    expect(logo3d.get('transform')).toBe('translate3d(calc(var(--logo-x) - 50% * var(--morph)), 0, 0) scale(var(--logo-s))');
    expect(logo3d.get('translate')).toBe('none');
    expect(logo3d.get('scale')).toBe('none');
    expect(logo3d.get('--logo-s')).toBe('1');
    expect(logo3dPhone.get('--logo-s')).toBe('0.75');
  });
});
