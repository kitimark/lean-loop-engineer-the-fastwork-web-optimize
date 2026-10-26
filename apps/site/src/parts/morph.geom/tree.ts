/**
 * DOM side of morph.geom:on: tags the existing elements with `data-mg`, builds the K0..U wrappers and the G and D fills
 * around the nav's children, and takes them down again. Glue only: no decision lives here (the tracks come from
 * tracks.ts, the contract is `data-mg=<el>` plus `data-i`/`data-j` on columns and images from Lean `selector`).
 */
import { hp, wp, type Layout, type Vp } from './tracks';

export const FLIP_CLASS = 'is-flip';
const TAGS: [string, string][] = [
  ['bar', ':scope > div'],
  ['logo', 'a[aria-label="Fastwork home"]'],
  ['actions', '[data-fw="nav-actions"]'],
  ['lang', '[data-fw="nav-actions"] > :first-child'],
  ['earn', '[data-fw="nav-earn"]'],
  ['panel', '[data-fw="morph-panel"]'],
  ['veil', '[data-fw-role="veil"]'],
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

/** Tag, wrap and measure. Returns the viewport and the measured layout the tracks are built for. */
export function enter(nav: HTMLElement, eng: Layout['eng']): Built {
  const root = document.documentElement;
  const vp = { w: window.innerWidth, h: window.innerHeight };
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
  const logoW = nav.querySelector<HTMLElement>('[data-mg="logo"]')?.offsetWidth ?? (ph ? 120 : 160);
  nav.style.setProperty('--mg-logo-w', `${logoW}px`);
  return {
    vp,
    layout: { eng, a: 0, b: 1, inset: ph ? 16 : 24, logoW, lw: ph ? 120 : 144, w0: ph ? 152 : 176, gL: 0, imgs },
  };
}

/** Unwrap: the nav's children go back in order; the flip class leaves. */
export function leave(nav: HTMLElement): void {
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
  document.documentElement.classList.remove(FLIP_CLASS);
}

export function find(a: { el: string; i: number; j: number }): HTMLElement | null {
  const b = `[data-mg="${a.el}"]`;
  const s = a.el === 'column' ? `${b}[data-i="${a.i}"]` : a.el === 'image' ? `${b}[data-i="${a.i}"][data-j="${a.j}"]` : b;
  return document.querySelector<HTMLElement>(s);
}
