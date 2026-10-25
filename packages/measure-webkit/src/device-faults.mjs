// Twin of the fault, retry and tab rules in lean/Fw/Device/PhoneArms.lean (TS stand-in until they run as fwcore);
// test/device-faults.test.mjs checks every function against golden/device/phone-arms.jsonl.

const HARNESS = new Set(['usbReset', 'staleTab']);
const USB_TEXTS = ['proxy closed', 'not on USB', 're-enumerat', 'listed no tabs'];

/** Lean `Fault.harness`: a fault of the harness, not of the arm. */
export const isHarness = (fault) => HARNESS.has(fault);

/** Lean `faultOf`: the fault an attempt's error text names. */
export function faultOf(msg) {
  if (USB_TEXTS.some((t) => msg.includes(t))) return 'usbReset';
  if (msg.includes('stale own tab')) return 'staleTab';
  return 'other';
}

/** Lean `mayAttempt`: two attempts; a third only when every failed attempt was a harness fault. */
export const mayAttempt = (faults) => faults.length < 2 || (faults.length < 3 && faults.every(isHarness));

/** Lean `ownTab`: a tab on our own harness server; `origin` is `http://host:port`. */
export const ownTab = (origin, u) => u === origin || u.startsWith(origin + '/');

/** Lean `tabPlan`: drive the one blank tab; with none, return the one tab of our own server to blank first; otherwise refuse. */
export function tabPlan(origin, urls) {
  const blank = urls.filter((u) => u === 'about:blank').length;
  const own = urls.filter((u) => ownTab(origin, u)).length;
  if (blank === 1) return { plan: 'drive', i: urls.indexOf('about:blank') };
  if (blank === 0 && own === 1) return { plan: 'reset', i: urls.findIndex((u) => ownTab(origin, u)) };
  return { plan: 'refuse' };
}
