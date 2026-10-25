const HARNESS = new Set(['usbReset', 'staleTab', 'foreignProxy']);
const USB_TEXTS = ['proxy closed', 'not on USB', 're-enumerat', 'listed no tabs'];

export const isHarness = (fault) => HARNESS.has(fault);

export function faultOf(msg) {
  if (USB_TEXTS.some((t) => msg.includes(t))) return 'usbReset';
  if (msg.includes('stale own tab')) return 'staleTab';
  if (msg.includes('another ios_webkit_debug_proxy')) return 'foreignProxy';
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

export const keepOk = (next, v) => {
  const n = next.find((x) => x.index === v.index);
  return n ? appendOnly(v.faults, n.faults) : v.faults.length === 0;
};

export const writeOk = (old, next) => old.every((v) => keepOk(next, v));

export function resetPlan(recs, idx, reason, nVisits) {
  if (!/^[0-9]+$/.test(idx) || nVisits <= Number(idx)) return { plan: 'badIndex' };
  if (/^[ \t\r\n]*$/.test(reason)) return { plan: 'noReason' };
  const index = Number(idx);
  return recs.some((r) => r.index === index) ? { plan: 'note', index, reason } : { plan: 'noVisit' };
}

export const USB_WAIT_S = 180;
export const GUARDED_PORTS = [9221, 9222];

export const usbVerdict = ({ listed, onBus, evidence }) => (evidence || (!listed && onBus) ? 'reset' : listed ? 'ok' : 'absent');

export const usbLine = (line) => line.includes('usbpowerd') && (line.includes('terminated') || line.includes('discovered'));

export function classify(msg, usb) {
  const f = faultOf(msg);
  return f === 'other' && usb === 'reset' ? 'usbReset' : f;
}

export const usbWait = (listed, waitedS) => (listed ? 'resume' : USB_WAIT_S <= waitedS ? 'giveUp' : 'keep');

const regexy = (id) => [...id].some((c) => '.*+?[](){}|^$\\'.includes(c));

export const specAttaches = (udid, spec) =>
  spec.replace(/\n/g, ',').split(',').some((e) => {
    const p = e.split(':');
    return p.length === 2 && p[0] !== 'null' && p[1] !== '-1' && (p[0] === '' || p[0] === udid || regexy(p[0]));
  });

export function proxyVerdict(ports, spec, udid) {
  if (ports.some((p) => GUARDED_PORTS.includes(p))) return 'holdsPorts';
  if (spec === null) return 'attached';
  return specAttaches(udid, spec) ? 'attached' : 'clear';
}

export const proxiesClear = (ps, udid) => ps.every((p) => proxyVerdict(p.ports, p.spec, udid) === 'clear');
