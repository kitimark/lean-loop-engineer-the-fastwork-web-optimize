/** Text of the section (the English strings of the original's messages, restated) and the pictures bundled from the snapshot. */
export const TEXT = {
  titleBase: 'Other platforms keep taking fee.',
  titleAccent: 'We let you keep more.',
  yourClient: 'Your client',
  yourClientQuestion: 'Bring your own clients,',
  forever: 'you keep 100%!',
  directBody:
    'Invite them through your profile link and use us to get the job done — 0% referral fee, forever! (aka 0% commission). Payment fee may apply.',
  why: 'Why bring client to Fastwork?',
  foundDesktop: 'A client from us?',
  foundCompact: 'A client from us?',
  referralOnly: 'A small referral fee, then 0%.',
  referralBody:
    'When we introduce you to a client, we take an 18% referral fee on what they pay you, up to $100. Once you hit the cap, you keep 100% of every transaction. Payment fee may apply.',
} as const;

/**
 * Pictures of the section, bundled from the unmodified snapshot (snapshot/site/selling/commission/): the three client faces
 * (nodes/2.DyWL8TcE.js 3052-3054) and the two arrows, the compact one below the `mq.c1000` condition (3302-3305).
 */
import face1 from '../../../../../snapshot/site/selling/commission/client-avatar-1.png';
import face2 from '../../../../../snapshot/site/selling/commission/client-avatar-2.png';
import face3 from '../../../../../snapshot/site/selling/commission/client-avatar-3.png';
import arrow from '../../../../../snapshot/site/selling/commission/direct-client-arrow.svg';
import arrowCompact from '../../../../../snapshot/site/selling/commission/compact-your-client-arrow.svg';

export const FACES: readonly string[] = [face1, face2, face3];
export const ARROW = arrow;
export const ARROW_COMPACT = arrowCompact;

/** Own hand-drawn style underline paths, one per boil frame (viewBox 0 0 199.201 19.8599). */
export const UNDERLINE_PATHS = [
  'M2 13.5C32 5.5 128 -0.5 133 2.5C138 5.5 71 11.5 73.5 17.5C76 23.5 162 2.5 197.5 8',
  'M1.5 13.8C32.3 5.3 128 -0.3 133.8 2C138.3 5.4 71.5 11.4 73.3 16.8C75.5 22.7 162.3 2.6 197.3 8.5',
  'M1.8 13.2C31.5 5.8 128.9 -0.7 133.3 2.7C138.8 4.8 71 10.8 73.7 17.5C76.1 23.7 161.9 2 197.9 7.7',
] as const;

/** Own hand-drawn style zero (a loop and a slash) per boil frame (viewBox 0 0 107.498 98.0007). */
export const ZERO_PATHS = [
  ['M54 12C30 6 8 30 8 56C8 82 28 94 50 92C76 90 96 70 94 44C92 22 74 10 54 12Z', 'M20 86L90 18'],
  ['M54.4 12.3C30.3 6.2 8.4 30.2 8.3 56.1C8.2 82.2 28.4 94.3 50.2 92.2C76.3 90.1 96.2 70.3 94.4 44.1C92.1 22.2 74.2 10.2 54.1 12.4Z', 'M20.4 86.3L90.3 18.2'],
  ['M53.6 11.8C29.8 5.8 7.8 29.8 7.7 55.8C7.6 81.8 27.7 93.8 49.8 91.8C75.8 89.8 95.8 69.8 93.7 43.8C91.8 21.8 73.8 9.8 53.7 11.9Z', 'M19.7 85.8L89.8 17.8'],
] as const;
