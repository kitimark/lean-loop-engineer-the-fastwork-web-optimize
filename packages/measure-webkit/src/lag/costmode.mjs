export const COST_MODES = ['off', 'on', 'only'];

export function parseCost(value) {
  if (!COST_MODES.includes(value)) throw new Error(`--cost must be one of ${COST_MODES.join('|')}, got ${JSON.stringify(value)}`);
  return { cost: value !== 'off', costOnly: value === 'only' };
}

export function swapSetup({ swap, cost, site, search }) {
  if (!(swap && cost && site && search)) return { swap: null, arms: null };
  return {
    swap: { arms: { crop: { id: 'crop', search }, faithful: { id: 'faithful', search: '' } }, home: { id: 'crop', search } },
    arms: { crop: { dir: site, search }, faithful: { dir: site, search: '' } },
  };
}
