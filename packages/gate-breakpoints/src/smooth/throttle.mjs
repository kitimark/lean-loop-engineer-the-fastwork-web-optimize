export const THROTTLES = [1, 6];

export function parseThrottle(s) {
  const t = String(s ?? '').trim();
  if (t === '') return 1;
  return /^\d+$/.test(t) && THROTTLES.includes(Number(t)) ? Number(t) : null;
}
