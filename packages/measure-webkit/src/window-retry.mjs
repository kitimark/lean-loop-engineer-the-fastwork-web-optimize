import { refusal } from './touchlock.mjs';
import { blockMs } from './walk-budget.mjs';

export const VERDICTS = Object.freeze(['kept', 'notRedoable', 'already', 'noDriver', 'noTime', 'redo']);

export const OUTCOMES = Object.freeze(['recovered', 'noOpen', 'tooShort', 'lockMoved', 'failed']);

export const REDOABLE = Object.freeze(['noOpen', 'tooShort']);

export const rowRefusal = (row) => (row.status === 'ok' ? refusal(row) : null);

export const eligible = (status, why) => status === 'ok' && REDOABLE.includes(why);

export const redoFits = (dl, now, reserve, left) => now + blockMs(left + 1) + reserve <= dl;

export function verdict(a) {
  if (a.status === 'ok' && a.refusal === null) return 'kept';
  if (!eligible(a.status, a.refusal)) return 'notRedoable';
  if (a.redone) return 'already';
  if (!a.driverOn) return 'noDriver';
  if (!redoFits(a.dl, a.now, a.reserve, a.left)) return 'noTime';
  return 'redo';
}

export function outcomeOf(status, why) {
  if (status !== 'ok') return 'failed';
  return why ?? 'recovered';
}

export const finalClass = (first, outcome) => (outcome === 'recovered' ? 'ok' : first);

export async function withRedo(first, { ask, run, now = Date.now, log = () => {} }) {
  const why = rowRefusal(first);
  const v = verdict({ status: first.status, refusal: why, redone: false, ...ask() });
  if (v === 'kept' || v === 'notRedoable') return first;
  if (v !== 'redo') return { ...first, redo: { from: why, outcome: v } };
  const t0 = now();
  let second = null;
  try { second = await run(); } catch (e) { log(`  touch-lock redo of ${first.arm} rep ${first.rep} failed (${e.message})`); }
  const status = second?.status ?? 'error';
  const outcome = outcomeOf(status, second ? rowRefusal(second) : null);
  const redo = { from: why, outcome, status, ms: now() - t0 };
  log(`touch-lock ${first.arm} rep ${first.rep}: redo of ${why} -> ${outcome} (${Math.round(redo.ms / 1000)} s)`);
  return outcome === 'recovered' ? { ...second, redo } : { ...first, redo };
}

export function redoTally(rows) {
  const out = {};
  for (const r of rows) if (r.redo) out[r.redo.outcome] = (out[r.redo.outcome] ?? 0) + 1;
  return out;
}
