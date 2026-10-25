// Which arms job `vm` of the toolbar lane runs. Default first, then two of the five flag arms; ten jobs cover each flag arm four times
// (job v takes numbers 2(v-1) and 2(v-1)+1 mod 5, jobs 6 to 10 swap the two so every arm runs in both positions). A commit message with
// `[toolbar-plan:a+b,c,...]` replaces the plan: entry v is job v (flag arm names joined by +), and `[toolbar-top:N]` sets the job count.
import { FLAG_ARMS } from './toolbar.mjs';

export const JOBS = 10;

const ORDER = Object.freeze(['touch-first', 'open-once', 'unthrottle', 'overscroll-lock', 'threaded']);

export function overrideOf(message) {
  const m = /\[toolbar-plan:([^\]]*)\]/.exec(message ?? '');
  if (!m) return null;
  return m[1].split(',').map((e) => e.split('+').map((a) => a.trim()).filter(Boolean));
}

export function armsOf(vm, message = '') {
  const over = overrideOf(message);
  if (over) {
    const e = over[vm - 1];
    if (!e) throw new Error(`toolbar-plan has no entry for job ${vm}`);
    const bad = e.filter((a) => !FLAG_ARMS.includes(a));
    if (bad.length) throw new Error(`unknown arm ${bad.join(', ')}; one of ${FLAG_ARMS.join(', ')}`);
    return ['default', ...e];
  }
  const a = ORDER[(2 * (vm - 1)) % ORDER.length], b = ORDER[(2 * (vm - 1) + 1) % ORDER.length];
  return vm > JOBS / 2 ? ['default', b, a] : ['default', a, b];
}

/** Jobs of a message: `[toolbar-top:N]`, else the plan override's length, else JOBS. */
export function jobsOf(message = '') {
  const m = /\[toolbar-top:(\d+)\]/.exec(message);
  if (m) return Number(m[1]);
  return overrideOf(message)?.length ?? JOBS;
}

/** The arms of every job in a push, for the plan printed in the log. */
export const planOf = (message = '') => Array.from({ length: jobsOf(message) }, (_, i) => armsOf(i + 1, message));
