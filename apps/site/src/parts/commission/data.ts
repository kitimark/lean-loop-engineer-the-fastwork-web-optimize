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
