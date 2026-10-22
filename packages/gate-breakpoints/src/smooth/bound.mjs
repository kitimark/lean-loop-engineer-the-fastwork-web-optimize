import { END_PUSH } from './schedule.mjs';

export const BOUND_CSS = '[data-fw="nav-earn"], [data-fw="nav-earn"]::before, [data-fw="nav-earn"]::after { transition: none !important; }';

export const BOUND_JS = `(() => {
  if (!document.getElementById('fw-bound')) {
    const s = document.createElement('style');
    s.id = 'fw-bound';
    s.textContent = ${JSON.stringify(BOUND_CSS)};
    document.head.appendChild(s);
  }
  const b = document.querySelector('[data-fw="nav-earn"]');
  return b ? getComputedStyle(b).transitionDuration : null;
})()`;

export const KNOWN_ARMS = ['orig', 'base', 'aa', 'look', 'v2', 'bound'];

export function parseArms(spec) {
  if (spec === undefined || spec === null || spec === '') return undefined;
  const ids = String(spec).split(',').map((s) => s.trim()).filter(Boolean);
  if (!ids.length) return undefined;
  for (const id of ids) if (!KNOWN_ARMS.includes(id)) throw new Error(`unknown arm "${id}" (known: ${KNOWN_ARMS.join(', ')})`);
  if (new Set(ids).size !== ids.length) throw new Error('an arm id is listed twice');
  return ids;
}

export const endPushFor = (holdMs) => (holdMs ? { ...END_PUSH, holdMs: Number(holdMs) } : END_PUSH);
