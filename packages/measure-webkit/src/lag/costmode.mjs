// The --cost flag of lag/cli.mjs run: off (lag passes only), on (lag and cost passes), only (cost passes only).
export const COST_MODES = ['off', 'on', 'only'];

/** Parse the --cost value; anything but off|on|only throws. */
export function parseCost(value) {
  if (!COST_MODES.includes(value)) throw new Error(`--cost must be one of ${COST_MODES.join('|')}, got ${JSON.stringify(value)}`);
  return { cost: value !== 'off', costOnly: value === 'only' };
}
