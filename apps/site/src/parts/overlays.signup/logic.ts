/**
 * Pure logic of overlays.signup (no DOM): the waitlist sign-up dialog of the original.
 * Original: _app/immutable/chunks/D313Dngs.js:1927-1933 (direction), 1985-2038 (open, close, Escape, backdrop, cancel);
 * nodes/2.DyWL8TcE.js:3910-3912 (form validity), 7201-7270 (close guard), 13265-13400 (submit flow);
 * assets/DialogHeader.Qcgwm6ST.css:698-714 (enter animation).
 * Lean: lean/Fw/Parts/OverlaySignup.lean (+ Bezier.lean). Golden vectors: packages/contracts/golden/parts/overlays.signup.jsonl.
 */

/** Enter animation length, ms (`--duration-medium-max`). */
export const ENTER_MS = 400;
/** Start scale of the enter animation. */
export const SCALE0 = 0.95;
/** Length of the direction vector, px. */
export const DIR_LENGTH = 16;

/** The design system's `--ease-standard` as control points. */
export const EASE_STANDARD = { x1: 0.24, y1: 1, x2: 0.4, y2: 1 } as const;
const STEPS = 40;
const coord = (a: number, b: number, s: number): number => 3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s;

/** Lean `Bezier.ease` for `--ease-standard`: 40 bisection steps on x(s) = t, then y(s). */
export function ease(t: number): number {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  const c = EASE_STANDARD;
  let lo = 0;
  let hi = 1;
  for (let i = 0; i < STEPS; i++) {
    const m = (lo + hi) / 2;
    if (coord(c.x1, c.x2, m) < t) lo = m;
    else hi = m;
  }
  return coord(c.y1, c.y2, (lo + hi) / 2);
}

/** Lean `leSqrt`: c * sqrt(d) <= 32 * x, decided on squares. */
function leSqrt(c: number, x: number, d: number): boolean {
  if (c <= 0) return 0 <= x ? true : c * c * d >= 1024 * x * x;
  return x < 0 ? false : c * c * d <= 1024 * x * x;
}

/** Lean `comp`: round(16 x / sqrt(d)) as the largest k in [-16, 16] with (2k - 1) sqrt(d) <= 32 x. */
function comp(x: number, d: number): number {
  let acc = -16;
  for (let i = 0; i < 33; i++) {
    const k = i - 16;
    if (leSqrt(2 * k - 1, x, d)) acc = k;
  }
  return acc;
}

/** Lean `dir`: the unit direction from the viewport centre to the trigger centre (offsets x, y), times 16, rounded. */
export function dir(x: number, y: number): [number, number] {
  const d = x * x + y * y;
  return d === 0 ? [0, 0] : [comp(x, d), comp(y, d)];
}

/** Lean `openDir`: from the trigger when something other than the body has focus, else (0, 16). */
export function openDir(trigger: { x: number; y: number } | null): [number, number] {
  return trigger ? dir(trigger.x, trigger.y) : [0, DIR_LENGTH];
}

/** Offsets of an element's centre from the viewport centre (D313Dngs 1927-1931), the input of `dir`. */
export function triggerOffset(rect: { left: number; top: number; width: number; height: number }, vw: number, vh: number) {
  return { x: rect.left + rect.width / 2 - vw / 2, y: rect.top + rect.height / 2 - vh / 2 };
}

export interface Frame {
  opacity: number;
  tx: number;
  ty: number;
  scale: number;
}

/** Animation progress: reduced motion has no animation. */
export function progress(elapsed: number, reduced: boolean): number {
  return reduced ? 1 : ease(elapsed / ENTER_MS);
}

/** The animated values `elapsed` ms after the dialog opens (keyframes 0% and `to`). */
export function frame(dx: number, dy: number, elapsed: number, reduced: boolean): Frame {
  const p = progress(elapsed, reduced);
  return { opacity: p, tx: (1 - p) * dx, ty: (1 - p) * dy, scale: SCALE0 + (1 - SCALE0) * p };
}

export type Source = 'escape' | 'backdrop' | 'cancel';
export type Purpose = 'info' | 'form' | 'required';
export interface Reaction {
  prevent: boolean;
  close: boolean;
}

/** Lean `react`: what a close source does (preventDefault and/or a close request). */
export function react(source: Source, purpose: Purpose, self: boolean, composing: boolean, layered: boolean): Reaction {
  switch (source) {
    case 'escape':
      return composing || layered ? { prevent: false, close: false } : { prevent: true, close: purpose !== 'required' };
    case 'backdrop':
      return { prevent: false, close: self && purpose === 'info' };
    case 'cancel':
      return self ? { prevent: true, close: !layered && purpose !== 'required' } : { prevent: false, close: false };
  }
}

/** `onBeforeClose` is `!submitting` (JS 13307). */
export function closeAllowed(submitting: boolean): boolean {
  return !submitting;
}

export type Sync = 'showModal' | 'close' | 'none';

/** Lean `sync`: the element operation that makes the dialog agree with the prop. */
export function sync(isOpen: boolean, domOpen: boolean): Sync {
  return isOpen ? (domOpen ? 'none' : 'showModal') : domOpen ? 'close' : 'none';
}

/** JavaScript whitespace (`\s`, `trim()`). */
export function isSpace(c: string): boolean {
  const n = c.codePointAt(0)!;
  return (n >= 9 && n <= 13) || n === 32 || n === 160 || n === 5760 || (n >= 8192 && n <= 8202) || n === 8232 || n === 8233 || n === 8239 || n === 8287 || n === 12288 || n === 65279;
}

const chars = (s: string): string[] => Array.from(s);

/** Lean `trim` on code points. */
export function trim(s: string[]): string[] {
  let a = 0;
  let b = s.length;
  while (a < b && isSpace(s[a]!)) a++;
  while (b > a && isSpace(s[b - 1]!)) b--;
  return s.slice(a, b);
}

const plain = (c: string): boolean => !isSpace(c) && c !== '@';

function domainOk(t: string[]): boolean {
  if (!t.every((c) => plain(c) || c === '.')) return false;
  for (let i = 1; i + 1 < t.length; i++) if (t[i] === '.') return true;
  return false;
}

/** Lean `emailOk`: `^[^\s@]+@[^\s@]+\.[^\s@]+$` on a trimmed string. */
export function emailOk(s: string[]): boolean {
  const parts = s.join('').split('@');
  if (parts.length !== 2) return false;
  const a = chars(parts[0]!);
  return a.length > 0 && a.every(plain) && domainOk(chars(parts[1]!));
}

/** Lean `valid` (`iD`): non-blank name and a plausible email. */
export function valid(name: string, email: string): boolean {
  return trim(chars(name)).length > 0 && emailOk(trim(chars(email)));
}

export interface Form {
  submitting: boolean;
  done: boolean;
  error: boolean;
}
export const FORM_INIT: Form = { submitting: false, done: false, error: false };

/** Lean `submit`: the new flags and whether a request is sent. */
export function submit(f: Form, v: boolean, hasHandler: boolean): { form: Form; send: boolean } {
  if (!v || f.submitting) return { form: f, send: false };
  if (!hasHandler) return { form: { ...f, error: true }, send: false };
  return { form: { ...f, submitting: true, error: false }, send: true };
}

/** Lean `settle`: a finished request sets `done` or `error`, and clears `submitting`. */
export function settle(f: Form, ok: boolean): Form {
  return ok ? { ...f, done: true, submitting: false } : { ...f, error: true, submitting: false };
}
