/**
 * Pure logic of nav.langMenu (no DOM): the three-phase machine of the language switch menu. Restated from the original
 * (nodes/2.DyWL8TcE.js): state 12750-12756, close 12757-12763, open 12764-12767, select 12768-12776, document listeners
 * 12777-12790, classes 12834-12850. Spec and proofs: lean/Fw/Parts/NavLangMenu.lean. Golden vectors:
 * packages/contracts/golden/parts/nav.langMenu.jsonl (logic.test.ts).
 */

export type Phase = 'closed' | 'open' | 'closing';
export type Ev = 'toggle' | 'select' | 'outside' | 'timer';
export type TimerAction = 'keep' | 'clear' | 'rearm';

/** Close timer, ms (N2:12763). */
export const CLOSE_MS = 140;

/** One step of the machine (N2:12757-12776). */
export function step({ phase, ev }: { phase: Phase; ev: Ev }): { phase: Phase; timer: TimerAction } {
  const open = phase === 'open';
  switch (ev) {
    case 'toggle':
      return open ? { phase: 'closing', timer: 'rearm' } : { phase: 'open', timer: 'clear' };
    case 'select':
    case 'outside':
      return open ? { phase: 'closing', timer: 'rearm' } : { phase, timer: 'keep' };
    case 'timer':
      return phase === 'closing' ? { phase: 'closed', timer: 'keep' } : { phase, timer: 'keep' };
  }
}

/** Derived flags (N2:12754-12755, 12777, 12834, 12771). */
export function flags({ phase }: { phase: Phase }) {
  return {
    isOpen: phase === 'open',
    mounted: phase !== 'closed',
    isClosing: phase === 'closing',
    listening: phase === 'open',
    navLocaleOpen: phase !== 'closed',
  };
}
