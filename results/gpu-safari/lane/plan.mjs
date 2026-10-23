
export const FAITHFUL = Object.freeze({ id: 'base', search: '', label: 'faithful' });

export const FLAG_ARMS = Object.freeze([
  { id: 'nav-clip-box', zone: 'nav', search: '?fw=nav:clip-box', label: 'nav:clip-box', task: 'nav-fixed-size' },
  { id: 'nav-bar-fixed', zone: 'nav', search: '?fw=nav:bar-fixed', label: 'nav:bar-fixed', task: 'nav-fixed-size' },
  { id: 'nav-logo-3d', zone: 'nav', search: '?fw=nav:logo-3d', label: 'nav:logo-3d', task: 'nav-fixed-size' },
  { id: 'morph-panel-threaded', zone: 'morph', search: '?fw=morph.panel:threaded', label: 'morph.panel:threaded', task: 'morph-panel-threaded' },
  { id: 'morph-panel-threaded-fade', zone: 'morph', search: '?fw=morph.panel:threaded,platform:fade-threaded', label: 'morph.panel:threaded + platform:fade-threaded (bundled)', task: 'morph-panel-threaded' },
  { id: 'pain-dark-scroll', zone: 'pain', search: '?fw=pain:dark-scroll', label: 'pain:dark-scroll', task: 'pain-dark-scroll' },
  { id: 'hero-exit-threaded', zone: 'hero', search: '?fw=hero.exit:threaded', label: 'hero.exit:threaded', task: 'hero-exit-threaded-port' },
  { id: 'people-carousel-crop', zone: 'carousel', search: '?fw=people.carousel:crop', label: 'people.carousel:crop', task: 'people-carousel-crop' },
  { id: 'people-o-preview-translate', zone: 'people', search: '?fw=people.o:preview-translate', label: 'people.o:preview-translate', task: 'people-o-preview-translate' },
].map((a) => Object.freeze(a)));

export const NAV_M = Object.freeze([0.1, 0.25, 0.5, 0.75, 0.9]);
export const NAV_EDGE_M = Object.freeze([0.1, 0.5, 0.9]);
export const NAV_GLASS_M = Object.freeze([0.25, 0.5, 0.75]);
export const MORPH_M = Object.freeze([0.25, 0.5, 0.75]);
export const HERO_EXIT_AT = Object.freeze([0.25, 0.5, 0.75]);
export const PEOPLE_FRAMES = Object.freeze([10, 20, 40]);
export const PEOPLE_DY = 3;
export const SWAP_MS = 220;
export const CAROUSEL_AT_MS = Object.freeze([55, 110, 165]);
export const PAIN_AROUND = Object.freeze([-16, -1, 0, 1, 16]);

export const MORPH_DURATION_MS = 680;
export const elapsedAt = (m) => {
  if (!(m > 0 && m < 1)) throw new Error(`morph value ${m} is outside (0, 1)`);
  return Math.round(MORPH_DURATION_MS * (1 - Math.pow(1 - m, 1 / 3)) * 1000) / 1000;
};

export function statesOf(zone, flipY = null) {
  if (zone === 'nav') return NAV_M.map((m) => ({ id: `m${m}`, kind: 'morph', m, mask: 'nav' }));
  if (zone === 'morph') return MORPH_M.map((m) => ({ id: `m${m}`, kind: 'morph', m, mask: 'frame', drive: 'push', elapsedMs: elapsedAt(m) }));
  if (zone === 'pain') {
    if (!Number.isInteger(flipY)) throw new Error('the pain zone needs the flip offset of the faithful arm');
    return PAIN_AROUND.map((d) => ({ id: `y${d >= 0 ? '+' : ''}${d}`, kind: 'scroll', y: flipY + d, mask: 'frame' }));
  }
  if (zone === 'hero') {
    if (!(Number.isFinite(flipY) && flipY > 0)) throw new Error('the hero zone needs the exit range of the faithful arm in px');
    return HERO_EXIT_AT.map((f) => ({ id: `x${f}`, kind: 'scroll', y: Math.round(flipY * f), mask: 'frame' }));
  }
  if (zone === 'people') return PEOPLE_FRAMES.map((n) => ({ id: `f${n}`, kind: 'hover-scroll', frames: n, dy: PEOPLE_DY, mask: 'frame' }));
  if (zone === 'carousel') return CAROUSEL_AT_MS.map((t) => ({ id: `t${t}`, kind: 'swap', elapsedMs: t, mask: 'box' }));
  throw new Error(`no state list for zone ${zone}`);
}

export function zoneArms(zone, loads = 3) {
  if (!(Number.isInteger(loads) && loads >= 3 && loads <= 9)) throw new Error(`loads ${loads} is outside 3..9`);
  const more = Array.from({ length: loads - 3 }, (_, i) => ({ ...FAITHFUL, id: `base${i + 4}`, label: `faithful (load ${i + 4})` }));
  return [FAITHFUL, { ...FAITHFUL, id: 'base2', label: 'faithful (A/A control)' }, ...FLAG_ARMS.filter((a) => a.zone === zone), { ...FAITHFUL, id: 'base3', label: 'faithful (order probe)' }, ...more];
}
