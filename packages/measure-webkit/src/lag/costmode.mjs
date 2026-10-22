export const COST_MODES = ['off', 'on', 'only'];

export function parseCost(value) {
  if (!COST_MODES.includes(value)) throw new Error(`--cost must be one of ${COST_MODES.join('|')}, got ${JSON.stringify(value)}`);
  return { cost: value !== 'off', costOnly: value === 'only' };
}
