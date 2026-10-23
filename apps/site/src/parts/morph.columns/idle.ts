export interface IdleState {
  clock: number;
  present: boolean;
}

/** Lean `MorphIdleNone.scenePaused` read from the panel's scene attribute: the tracks carry no animation while it is `paused`. */
export const idleRemoved = (sceneAttr: string | null): boolean => sceneAttr === 'paused';

/** Lean `MorphIdleNone.varStep`, with the scene rule given as morph in thousandths. */
export function idleStep(s: IdleState, dt: number, mm: number): IdleState {
  return mm > 1 ? { clock: s.clock + dt, present: true } : { clock: s.clock, present: false };
}

const targetOf = (a: Animation): Element | null => (a.effect as KeyframeEffect | null)?.target ?? null;

/** The time each track animation is seeked to when its animation returns. */
export class IdleHold {
  private held = new Map<Element, number>();

  /** Keep the current time of every animation about to be removed. */
  keep(anims: readonly Animation[]): void {
    for (const a of anims) {
      const target = targetOf(a);
      if (target && a.currentTime !== null) this.held.set(target, Number(a.currentTime));
    }
  }

  /** Seek the returned animations to their kept times, then forget them. */
  restore(anims: readonly Animation[]): void {
    for (const a of anims) {
      const target = targetOf(a);
      const t = target ? this.held.get(target) : undefined;
      if (t !== undefined) a.currentTime = t;
    }
    this.held.clear();
  }
}
