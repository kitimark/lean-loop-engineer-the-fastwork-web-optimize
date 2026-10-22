// The nodes and properties the trajectory probe compares (task trajectory-probe). Data only: no decision is made here.
// Identity, not inference: every node is a (part, role) pair of anchors.json, the registry the breakpoint gate already uses, so
// both arms' selectors come from one place. A node is read as ALL elements its selector matches, compared by index.
// The kind of a property (discrete, geometry, unit, colour) picks its tolerance in Lean (Fw.Gate.Trajectory.tol).
import { loadAnchors } from '../spec.mjs';

/**
 * One property of a node. `r` names the in-page reader (kit.mjs); the other fields are its parameters. `lean` marks the properties
 * read in every frame of a wheel push when the lean read set is asked for (`--reads lean`): the discrete ones (classes, attributes,
 * focus, visibility) and the logo's rectangle in the nav; the rest is read at rest and in the holds.
 */
const P = (id, kind, r, extra = {}) => ({ id, kind, r, lean: kind === 'discrete', ...extra });

const cls = (name) => P(`cls.${name}`, 'discrete', 'cls', { name });
const attr = (name, extra = {}) => P(`attr.${name}`, 'discrete', 'attr', { name, ...extra });

/** What a hero-path node is compared on: everything that moves a card or the copy while the page scrolls. */
export const MOTION_PROPS = [
  P('opacity', 'unit', 'num', { css: 'opacity' }),
  P('filter.fn', 'discrete', 'fnmask', { css: 'filter' }),
  P('filter.num', 'unit', 'fnnum', { css: 'filter' }),
  P('transform.lin', 'unit', 'tlin'),
  P('transform.shift', 'geometry', 'tshift'),
  P('translate', 'geometry', 'translate'),
  P('rotate', 'geometry', 'rotate'),
  P('scale', 'unit', 'scale'),
  P('rect', 'geometry', 'rect'),
];

/** Nodes of the hero path, each a (part, role) of anchors.json. */
export const HERO_NODES = [
  { id: 'hero.track', part: 'hero.exit', role: 'track' },
  { id: 'hero.stage', part: 'hero.exit', role: 'hero' },
  { id: 'hero.copy', part: 'hero', role: 'copy' },
  { id: 'hero.cta', part: 'hero', role: 'ctaStack' },
  { id: 'hero.countdown.unit', part: 'hero.countdown', role: 'unit' },
  { id: 'hero.cue', part: 'hero.cue', role: 'cue' },
  { id: 'hero.orbit', part: 'hero.orbit', role: 'orbit' },
  { id: 'hero.orbit.stage', part: 'hero.orbit', role: 'stage' },
  { id: 'hero.orbit.card', part: 'hero.orbit', role: 'card' },
  { id: 'hero.deck', part: 'hero.deck', role: 'deck' },
  { id: 'hero.deck.card', part: 'hero.deck', role: 'card' },
].map((n) => ({ ...n, props: MOTION_PROPS }));

const NAV_CLASSES = ['is-hero-pill', 'is-hero-chrome-ready', 'is-morphing', 'is-expanded', 'is-on-dark', 'is-scroll-hidden'];
/** Whether the element takes keyboard focus: its effective tabIndex, since one arm writes tabindex=0 where the other relies on a link. */
const FOCUS = P('tabindex', 'discrete', 'attr', { name: 'tabindex', prop: 'tabIndex' });
const LINEAR = [P('transform.lin', 'unit', 'tlin'), P('transform.shift', 'geometry', 'tshift')];

/** Nodes of the end-of-page path (the nav, its logo and the morph panel), per the nav-bug note's table. */
export const MORPH_NODES = [
  { id: 'nav', part: 'nav', role: 'nav', props: [
    ...NAV_CLASSES.map(cls), P('visibility', 'discrete', 'css', { css: 'visibility' }), P('rect', 'geometry', 'rect'),
    P('border-radius', 'geometry', 'lens', { css: 'border-top-left-radius' }),
    P('background-color', 'colour', 'colour', { css: 'background-color' }), P('opacity', 'unit', 'num', { css: 'opacity' }),
    P('backdrop-filter.fn', 'discrete', 'fnmask', { css: ['backdrop-filter', '-webkit-backdrop-filter'] }),
    P('backdrop-filter.num', 'unit', 'fnnum', { css: ['backdrop-filter', '-webkit-backdrop-filter'] }), ...LINEAR] },
  { id: 'logo', part: 'nav', role: 'logo', props: [
    P('position', 'discrete', 'css', { css: 'position' }), P('transform-origin', 'geometry', 'lens', { css: 'transform-origin' }),
    P('rect-in-nav', 'geometry', 'relrect', { to: 'nav', lean: true }), P('color', 'colour', 'colour', { css: 'color' }),
    P('translate', 'geometry', 'translate'), P('scale', 'unit', 'scale'), ...LINEAR] },
  { id: 'actions', part: 'nav', role: 'actions', props: [
    P('gap', 'geometry', 'lens', { css: 'column-gap' }), P('opacity', 'unit', 'num', { css: 'opacity' })] },
  { id: 'earn', part: 'nav', role: 'earn', props: [
    FOCUS, attr('aria-hidden'), P('opacity', 'unit', 'num', { css: 'opacity' }),
    P('filter.fn', 'discrete', 'fnmask', { css: 'filter' }), P('filter.num', 'unit', 'fnnum', { css: 'filter' }),
    P('max-width', 'geometry', 'lens', { css: 'max-width' }), ...LINEAR] },
  { id: 'panel', part: 'morph.panel', role: 'panel', props: [
    attr('data-start-selling-scene'), attr('aria-hidden'),
    // the original keeps the panel's expanded state as a nav class, the rewrite as an attribute of the panel
    { ...P('expanded', 'discrete', 'flag', { name: 'data-expanded' }), orig: { r: 'cls', name: 'is-expanded', on: 'nav' } },
    P('opacity', 'unit', 'num', { css: 'opacity' }),
    P('filter.fn', 'discrete', 'fnmask', { css: 'filter' }), P('filter.num', 'unit', 'fnnum', { css: 'filter' }), ...LINEAR] },
  { id: 'panel.cta', part: 'morph.panel', role: 'cta', props: [FOCUS] },
  // Not compared: the platform section (its fade, blur and pointer-events). The rewrite's morph.mount target is a hidden,
  // zero-sized sentinel (anchors.json), so there is nothing there to read.
];

export const GPU_NODES = [
  { id: 'nav', part: 'nav', role: 'nav', props: [
    P('rect', 'geometry', 'rect'), P('border-radius', 'geometry', 'lens', { css: 'border-top-left-radius' }),
    P('clip-path', 'geometry', 'css', { css: 'clip-path' })] },
  { id: 'panel', part: 'morph.panel', role: 'panel', props: [
    P('opacity', 'unit', 'num', { css: 'opacity' }), P('filter.num', 'unit', 'fnnum', { css: 'filter' }), P('transform.lin', 'unit', 'tlin')] },
];

export const GPU_CELLS = {
  pain: { section: { part: 'pain', role: 'section' }, trigger: { part: 'people.card', role: 'section' }, cls: 'is-pain-dark', maxWidth: 860, stepPx: 4 },
  carousel: { scene: { part: 'people.card', role: 'section' }, container: { part: 'people.carousel', role: 'avatars' }, sampleMs: 4200 },
};

export const PAGE_PROPS = [P('scroll-height', 'geometry', 'scrollHeight')];

export const HERO_STEPS = [
  { id: 's0', at: 0 }, { id: 's25', at: 0.25 }, { id: 's50', at: 0.5 }, { id: 's90', at: 0.9 }, { id: 's200', at: 2 },
  { id: 'mid', at: 'mid' }, { id: 'hold', at: 'mid', dwellMs: 1200 }, { id: 'b50', at: 0.5 }, { id: 'b25', at: 0.25 }, { id: 'b0', at: 0 },
];

export const WIDTHS = [390, 640, 641, 1280];
const TOUCH = { height: 844, dpr: 2, hover: 'none', pointer: 'coarse', reducedMotion: 'no-preference', colorScheme: 'light' };
const DESK = { height: 900, dpr: 1, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
export const envFor = (width) => ({ ...(width <= 640 ? TOUCH : DESK), width, deviceWidth: width, deviceHeight: width <= 640 ? 844 : 900 });

export function resolveNodes(nodes, anchors = loadAnchors()) {
  return nodes.map((n) => {
    const role = anchors.parts[n.part]?.roles?.find((r) => r.role === n.role);
    if (!role) throw new Error(`trajectory registry: no role ${n.part}:${n.role} in anchors.json`);
    return { ...n, orig: role.orig, rewrite: role.rewrite };
  });
}
