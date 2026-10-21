/**
 * Pure logic of `platform` and `platform.stageBg` (no DOM): the shrink of the section card on scroll and the stage
 * geometry. Restated from the original (nodes/2.DyWL8TcE.js:12434-12448; assets/2.gBuqKVzi.css:5530, 6330-6405).
 * Spec and proofs: lean/Fw/Parts/PlatformSection.lean. Golden vectors: packages/contracts/golden/parts/platform.jsonl
 * (logic.test.ts).
 */

export const clamp01 = (x: number): number => Math.min(1, Math.max(0, x));

/** Smoothstep (JS `p`): `c^2 (3 - 2c)` of the clamped input. */
export function smooth(x: number): number {
  const c = clamp01(x);
  return c * c * (3 - 2 * c);
}

/** Raw progress `a` from the card bottom (px from the viewport top) and the viewport height. */
export function raw({ bottom, vh }: { bottom: number; vh: number }): number {
  const r = (17 * vh) / 20;
  const i = (7 * vh) / 20;
  return bottom >= r ? 0 : bottom <= i ? 1 : (r - bottom) / (vh / 2);
}

/** `--platform-shrink`: smoothstep of `a`, or the fixed step `a >= 0.5` under reduced motion. */
export function shrink({ reduced, bottom, vh }: { reduced: boolean; bottom: number; vh: number }): number {
  const a = raw({ bottom, vh });
  return reduced ? (a >= 0.5 ? 1 : 0) : smooth(a);
}

/** The `is-platform-shrinking` class: `a > 0.04`. */
export function shrinking({ bottom, vh }: { bottom: number; vh: number }): boolean {
  return raw({ bottom, vh }) > 1 / 25;
}

/**
 * The `mq` write decision (Lean `PlatformShrinkOpt.writeNow` / `lastAfter`): no write while the gate (`mq.c860`) matches,
 * else a write exactly when the value differs from the last written one. `last` stays put while a write is skipped.
 */
export function planShrink({ gated, s, last }: { gated: boolean; s: number; last: number }): { write: boolean; last: number } {
  const write = !gated && s !== last;
  return { write, last: write ? s : last };
}

/**
 * The card's look at inline `--platform-shrink` value `v` (Lean `PlatformShrinkOpt.look`): scale and radius in px, given
 * whether `mq.c860` and `mq.w-le-720` match. Restates platform.module.css:8, 31, 32 with the overrides at 286-290, 303-315.
 */
export function cardLook({ c860, le720, v }: { c860: boolean; le720: boolean; v: number }): { scale: number; radius: number } {
  if (c860) return { scale: 1, radius: 0 };
  return { scale: 1 - 0.083333 * v, radius: (le720 ? 24 : 32) * v };
}

/** Card scale `1 - 0.083333 s`. */
export function scale({ s }: { s: number }): number {
  return 1 - 0.083333 * s;
}

/** Stage height for a stage of width `w` (`aspect-ratio: 640/512`). */
export function stageHeight({ w }: { w: number }): number {
  return (w * 512) / 640;
}

/** Artboard scale `100cqw / 640px`. */
export function artboardScale({ w }: { w: number }): number {
  return w / 640;
}

/** Constants the CSS Modules restate (platform.stageBg). */
export const STAGE = {
  bgBlur: 16,
  bgOpacity: 0.5,
  bgOpacityQuote: 0.15,
  grainOpacity: 0.55,
  grainOpacitySecure: 0.42,
  grainTile: 128,
} as const;
