import { hp, wp, type Layout, type Vp } from './tracks';

export const FLIP_CLASS = 'is-flip';
export const QUIET_CLASS = 'is-flip-quiet';
export const LEAVE_OPS = ['suppress', 'removeFlip', 'flush', 'restore'] as const;
export const MOVE_OPS = ['save', 'reparent', 'restore'] as const;
const TAGS: [string, string][] = [
  ['bar', ':scope > div'],
  ['logo', 'a[aria-label="Fastwork home"]'],
  ['actions', '[data-fw="nav-actions"]'],
  ['lang', '[data-fw="nav-actions"] > :first-child'],
  ['earn', '[data-fw="nav-earn"]'],
  ['panel', '[data-fw="morph-panel"]'],
  ['backdropClip', '[data-fw-role="backdrop"]'],
  ['centre', '[data-fw-role="center"]'],
  ['footer', '[data-fw-role="footer"]'],
  ['footerGrad', '[data-fw-role="grad"]'],
  ['footerEnd', '[data-fw-role="footer-end"]'],
];

const el = (tag = 'div', mg = ''): HTMLElement => {
  const e = document.createElement(tag);
  if (mg) e.dataset.mg = mg;
  return e;
};

export interface Built {
  vp: Vp;
  layout: Layout;
}

function wrapEarn(nav: HTMLElement): void {
  const earn = nav.querySelector<HTMLElement>('[data-mg="earn"]');
  if (!earn || earn.querySelector(':scope > [data-mg="earnClip"]')) return;
  const clip = el('span', 'earnClip');
  const label = el('span', 'earnLabel');
  label.append(...earn.childNodes);
  clip.append(label);
  earn.append(clip);
}

function wrapBackdrop(nav: HTMLElement): void {
  const b = nav.querySelector<HTMLElement>('[data-mg="backdropClip"]');
  if (!b || b.querySelector(':scope > [data-mg="Kb"]')) return;
  const kb = el('div', 'Kb');
  const ub = el('div', 'Ub');
  ub.append(...b.childNodes);
  kb.append(ub);
  b.append(kb);
}

function unwrap(nav: HTMLElement): void {
  for (const [outer, inner] of [['earnClip', 'earnLabel'], ['Kb', 'Ub']] as const) {
    const o = nav.querySelector<HTMLElement>(`[data-mg="${outer}"]`);
    const i = nav.querySelector<HTMLElement>(`[data-mg="${inner}"]`);
    if (o && i) o.parentElement?.append(...i.childNodes);
    o?.remove();
  }
}

type Saved = [Element, string | null, string, number][];

export function saveAnims(root: HTMLElement): Saved {
  if (typeof root.getAnimations !== 'function' || typeof CSSAnimation === 'undefined') return [];
  const out: Saved = [];
  for (const a of root.getAnimations({ subtree: true })) {
    const e = a.effect;
    if (a instanceof CSSAnimation && e instanceof KeyframeEffect && e.target && a.currentTime !== null) {
      out.push([e.target, e.pseudoElement, a.animationName, Number(a.currentTime)]);
    }
  }
  return out;
}

export function restoreAnims(root: HTMLElement, saved: Saved): void {
  if (saved.length === 0) return;
  for (const a of root.getAnimations({ subtree: true })) {
    const e = a.effect;
    if (!(a instanceof CSSAnimation) || !(e instanceof KeyframeEffect)) continue;
    const s = saved.find((x) => x[0] === e.target && x[1] === e.pseudoElement && x[2] === a.animationName);
    if (s) a.currentTime = s[3];
  }
}

export function enter(nav: HTMLElement, eng: Layout['eng']): Built {
  const root = document.documentElement;
  const vp = { w: window.innerWidth, h: window.innerHeight };
  const saved = saveAnims(nav);
  nav.dataset.mg = 'nav';
  root.classList.add(FLIP_CLASS);
  for (const [name, sel] of TAGS) nav.querySelector<HTMLElement>(sel)?.setAttribute('data-mg', name);
  document.querySelector('[data-fw="platform"]')?.setAttribute('data-mg', 'platform');
  const imgs: [number, number][][] = [];
  document.querySelectorAll<HTMLElement>('[data-fw="morph-columns"] > div').forEach((col, i) => {
    col.dataset.mg = 'column';
    col.dataset.i = String(i);
    let y = 0;
    const rows: [number, number][] = [];
    col.querySelectorAll<HTMLElement>('img').forEach((img, j) => {
      img.dataset.mg = 'image';
      img.dataset.i = String(i);
      img.dataset.j = String(j);
      const h = Number.parseFloat(img.style.height) || img.offsetHeight;
      rows.push([y, h]);
      y += h + 12;
    });
    imgs.push(rows);
  });
  nav.style.setProperty('--mg-w', `${wp(vp)}px`);
  nav.style.setProperty('--mg-h', `${hp(vp)}px`);
  const [k0, k1, k2, k3, u, g, d] = ['K0', 'K1', 'K2', 'K3', 'U', 'G', 'D'].map((n) => el('div', n));
  if (vp.w > 640) g.setAttribute('data-mg-up', '');
  const kids = [...nav.childNodes];
  nav.append(k0);
  k0.append(k1);
  k1.append(k2);
  k2.append(k3);
  k3.append(u);
  u.append(g, d, ...kids);
  const ph = vp.w <= 640;
  wrapEarn(nav);
  wrapBackdrop(nav);
  const rem = Number.parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
  const w0 = (ph ? 9.5 : 11) * rem;
  nav.style.setProperty('--mg-w0', `${w0}px`);
  const lw = nav.querySelector<HTMLElement>('[data-mg="lang"]')?.offsetWidth ?? (ph ? 120 : 144);
  const logoW = nav.querySelector<HTMLElement>('[data-mg="logo"]')?.offsetWidth ?? (ph ? 120 : 160);
  nav.style.setProperty('--mg-logo-w', `${logoW}px`);
  restoreAnims(nav, saved);
  return {
    vp,
    layout: { eng, a: 0, b: 1, inset: ph ? 16 : 24, logoW, lw, w0, gL: 0, imgs },
  };
}

export function leave(nav: HTMLElement): void {
  const saved = saveAnims(nav);
  unwrap(nav);
  const k0 = nav.querySelector<HTMLElement>(':scope > [data-mg="K0"]');
  const u = nav.querySelector<HTMLElement>('[data-mg="U"]');
  if (k0 && u) {
    const kids = [...u.childNodes].filter((n) => !(n instanceof HTMLElement && (n.dataset.mg === 'G' || n.dataset.mg === 'D')));
    k0.remove();
    nav.append(...kids);
  }
  nav.style.removeProperty('--mg-w');
  nav.style.removeProperty('--mg-h');
  nav.style.removeProperty('--mg-logo-w');
  nav.style.removeProperty('--mg-w0');
  nav.classList.add(QUIET_CLASS);
  document.documentElement.classList.remove(FLIP_CLASS);
  void nav.getBoundingClientRect();
  restoreAnims(nav, saved);
  nav.classList.remove(QUIET_CLASS);
}

export function find(a: { el: string; i: number; j: number }): HTMLElement | null {
  const b = `[data-mg="${a.el}"]`;
  const s = a.el === 'column' ? `${b}[data-i="${a.i}"]` : a.el === 'image' ? `${b}[data-i="${a.i}"][data-j="${a.j}"]` : b;
  return document.querySelector<HTMLElement>(s);
}
