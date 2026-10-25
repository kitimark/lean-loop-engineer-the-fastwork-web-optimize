const HARNESS = new Set(['usbReset', 'staleTab']);
const USB_TEXTS = ['proxy closed', 'not on USB', 're-enumerat', 'listed no tabs'];

export const isHarness = (fault) => HARNESS.has(fault);

export function faultOf(msg) {
  if (USB_TEXTS.some((t) => msg.includes(t))) return 'usbReset';
  if (msg.includes('stale own tab')) return 'staleTab';
  return 'other';
}

export const mayAttempt = (faults) => faults.length < 2 || (faults.length < 3 && faults.every(isHarness));

export const recordFault = (faults, f) => [...faults, f];

export const handReset = (faults) => faults;

export const appendOnly = (old, next) => old.length <= next.length && old.every((f, i) => next[i] === f);

export const ownTab = (host, u) => u === host || u.startsWith(host + ':') || u.startsWith(host + '/');

export function tabPlan(host, urls) {
  const blank = urls.filter((u) => u === 'about:blank').length;
  const own = urls.filter((u) => ownTab(host, u)).length;
  if (blank === 1) return { plan: 'drive', i: urls.indexOf('about:blank') };
  if (blank === 0 && own === 1) return { plan: 'reset', i: urls.findIndex((u) => ownTab(host, u)) };
  return { plan: 'refuse' };
}
