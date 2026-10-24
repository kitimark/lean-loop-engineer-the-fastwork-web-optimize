export const COST_MODES = ['off', 'on', 'only'];

export function parseCost(value) {
  if (!COST_MODES.includes(value)) throw new Error(`--cost must be one of ${COST_MODES.join('|')}, got ${JSON.stringify(value)}`);
  return { cost: value !== 'off', costOnly: value === 'only' };
}

export const ACCENT_FLAGS = Object.freeze({ nolayout: '?fw=hero.accent:draw-nolayout', full: '?fw=hero.accent:draw-nolayout-full' });

export function accentSetup({ accent, cost, site }) {
  if (!(accent && cost && site)) return { accent: null, arms: null };
  const arms = { faithful: { id: 'faithful', search: '' }, nolayout: { id: 'nolayout', search: ACCENT_FLAGS.nolayout }, full: { id: 'full', search: ACCENT_FLAGS.full } };
  return {
    accent: { arms, home: arms.faithful },
    arms: Object.fromEntries(Object.entries(arms).map(([k, a]) => [k, { dir: site, search: a.search }])),
  };
}

export function swapSetup({ swap, cost, site, search }) {
  if (!(swap && cost && site && search)) return { swap: null, arms: null };
  return {
    swap: { arms: { crop: { id: 'crop', search }, faithful: { id: 'faithful', search: '' } }, home: { id: 'crop', search } },
    arms: { crop: { dir: site, search }, faithful: { dir: site, search: '' } },
  };
}
