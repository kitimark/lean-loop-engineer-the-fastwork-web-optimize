import type { Piece } from './logic';

/**
 * The ten ring cards: geometry restated from the original's piece list (nodes/2.DyWL8TcE.js:3322-3463; px on the 1512 x 779
 * design canvas) and the Lean spec `HeroOrbit.pieces`. Names, roles and pictures are in `CARDS` (same order).
 */
export const PIECES: readonly Piece[] = [
  { id: 'p1', left: -27, top: 71.6, width: 195, height: 243, rotate: 3.05, unit: 1, float: false },
  { id: 'p2', left: 1155.1, top: -66, width: 193, height: 240, rotate: 4, unit: 0, float: false },
  { id: 'p3', left: 128.1, top: -54, width: 193, height: 240, rotate: 4, unit: 0, float: false },
  { id: 'p4', left: 197.2, top: 211.7, width: 203, height: 252, rotate: -2, unit: 2, float: false },
  { id: 'p5', left: -10.9, top: 346.6, width: 238, height: 297, rotate: 4, unit: 3, float: true },
  { id: 'p6', left: 80.7, top: 525.6, width: 258, height: 322, rotate: 3.05, unit: 4, float: false },
  { id: 'p7', left: 1154.4, top: 606.2, width: 214, height: 266, rotate: 3.81, unit: 4, float: false },
  { id: 'p8', left: 1305.1, top: 50, width: 193, height: 240, rotate: 4, unit: 1, float: false },
  { id: 'p9', left: 1346.9, top: 507.5, width: 190, height: 235, rotate: -4, unit: 3, float: false },
  { id: 'p10', left: 1273, top: 265, width: 230, height: 287, rotate: -5.18, unit: 2, float: true },
];

export interface CardInfo {
  readonly name: string;
  readonly role: string;
  readonly cover: string;
  readonly avatar: string;
}

const hero = (id: string) => ({ cover: `/selling/hero/${id}-cover.jpg`, avatar: `/selling/hero/${id}-avatar.jpg` });

/** Card content in `PIECES` order, restated from the original's prerendered ring (names, roles, pictures served from /selling/). */
export const CARDS: readonly CardInfo[] = [
  { name: 'Chapavich Temnitikul', role: 'Sound Composer · Bangkok', ...hero('chapavich') },
  { name: 'buttercup', role: 'Packaging Designer · Bangkok', ...hero('buttercup') },
  { name: 'LEOBEER', role: 'AI Video Editor · Bangkok', cover: '/selling/hero/leobeer-cover.jpg', avatar: '/selling/sellers/ai-video-editor/avatar.jpg' },
  { name: 'Slayalldeep', role: 'Artist · Jakarta', ...hero('slayalldeep') },
  { name: 'Bold Sarunyoo', role: 'Web Designer · Bangkok', cover: '/selling/hero/bold-cover.jpg', avatar: '/selling/sellers/ux-ui-designer/avatar.jpg' },
  { name: 'Weng Kitsana', role: 'Photographer · San Francisco', ...hero('weng') },
  { name: 'Pakincht', role: '', ...hero('pakincht') },
  { name: 'Peter Sato', role: 'Interior Designer · Osaka', ...hero('peter') },
  { name: 'MOD SUPACHA', role: 'Graphic Designer · Bangkok', ...hero('mod') },
  { name: 'Nguyen Van Nam', role: 'Wedding Photographer · Ho Chi Minh', ...hero('nam') },
];

export const ONLINE_ICON = '/selling/profile/online.svg';

/** The phone deck: slot class, piece index it repeats, rest rotation (N2:3464-3468). */
export const DECK: readonly { slot: 'a' | 'b' | 'd' | 'e'; piece: number; rotate: number }[] = [
  { slot: 'a', piece: 2, rotate: -2 },
  { slot: 'b', piece: 4, rotate: 4 },
  { slot: 'd', piece: 5, rotate: 2 },
  { slot: 'e', piece: 8, rotate: -4 },
];

/** 1x1 transparent GIF; keeps the `<img>` boxes without any picture. */
export const BLANK_GIF = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';
