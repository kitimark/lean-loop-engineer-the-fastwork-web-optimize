import { ENTER_HI, ENTER_LO, EXIT_HI, EXIT_LO } from './logic';

export const SETTLE_EVENTS = 29;

export interface Bands {
  enterFrom: number;
  enterTo: number;
  exitFrom: number;
  exitTo: number;
}

export const bands = (cardTop: number, bottom: number, vh: number): Bands => ({
  enterFrom: cardTop - ENTER_HI * vh,
  enterTo: cardTop - ENTER_LO * vh,
  exitFrom: bottom - EXIT_HI * vh,
  exitTo: bottom - EXIT_LO * vh,
});

export const inBand = (b: Bands, y: number): boolean => (b.enterFrom < y && y < b.enterTo) || (b.exitFrom < y && y < b.exitTo);
