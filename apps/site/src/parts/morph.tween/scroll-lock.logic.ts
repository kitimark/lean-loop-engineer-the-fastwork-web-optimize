/** Lean `overlayOf`: the root's scrollbar takes no layout width. */
export const overlayOf = (innerWidth: number, clientWidth: number): boolean => innerWidth - clientWidth <= 0;

/** Lean `lockOn`: the root is held at `overflow: hidden` while the morph runs on overlay scrollbars. */
export const lockOn = (overlay: boolean, active: boolean): boolean => overlay && active;

/** Lean `lockWrite`: the root style write after a step, `null` when the lock already matches. */
export const lockWrite = (overlay: boolean, locked: boolean, active: boolean): boolean | null =>
  lockOn(overlay, active) === locked ? null : lockOn(overlay, active);
