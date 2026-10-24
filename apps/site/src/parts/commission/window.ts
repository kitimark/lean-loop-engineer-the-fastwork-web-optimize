import { ENTER_HI, ENTER_LO, EXIT_HI, EXIT_LO } from './logic';

/** Events after which a follower that left a band has settled (Lean `CommissionOptWindow.quiet_run`: 0.78^29 < 8e-4). */
export const SETTLE_EVENTS = 29;

export interface Bands {
  enterFrom: number;
  enterTo: number;
  exitFrom: number;
  exitTo: number;
}

/** The scroll positions where the card top and the section bottom cross the two bands (document px, viewport height `vh`). */
export const bands = (cardTop: number, bottom: number, vh: number): Bands => ({
  enterFrom: cardTop - ENTER_HI * vh,
  enterTo: cardTop - ENTER_LO * vh,
  exitFrom: bottom - EXIT_HI * vh,
  exitTo: bottom - EXIT_LO * vh,
});

export const inBand = (b: Bands, y: number): boolean => (b.enterFrom < y && y < b.enterTo) || (b.exitFrom < y && y < b.exitTo);
