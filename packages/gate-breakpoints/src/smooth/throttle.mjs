// The CPU throttle of the cadence lane (task smoothness-cpu-throttle). A cheap Linux PROXY of the lag felt on WebKit (iPhone), never WebKit
// evidence: CDP Emulation.setCPUThrottlingRate slows the page's main thread by a factor while the scripted scroll runs. Two values only:
// 1 is the control (no throttle), 6 is the factor the user named. TS stand-in (no Lean rule): the allowlist is the whole decision.
export const THROTTLES = [1, 6];

/** The throttle of a flag or input string: empty means 1; anything but an allowed value is refused (null). */
export function parseThrottle(s) {
  const t = String(s ?? '').trim();
  if (t === '') return 1;
  return /^\d+$/.test(t) && THROTTLES.includes(Number(t)) ? Number(t) : null;
}
