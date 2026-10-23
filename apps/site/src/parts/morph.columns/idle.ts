export interface IdleState {
  clock: number;
  present: boolean;
}

export const idleRemoved = (sceneAttr: string | null): boolean => sceneAttr === 'paused';

export function idleStep(s: IdleState, dt: number, mm: number): IdleState {
  return mm > 1 ? { clock: s.clock + dt, present: true } : { clock: s.clock, present: false };
}

const targetOf = (a: Animation): Element | null => (a.effect as KeyframeEffect | null)?.target ?? null;

export class IdleHold {
  private held = new Map<Element, number>();

  keep(anims: readonly Animation[]): void {
    for (const a of anims) {
      const target = targetOf(a);
      if (target && a.currentTime !== null) this.held.set(target, Number(a.currentTime));
    }
  }

  restore(anims: readonly Animation[]): void {
    for (const a of anims) {
      const target = targetOf(a);
      const t = target ? this.held.get(target) : undefined;
      if (t !== undefined) a.currentTime = t;
    }
    this.held.clear();
  }
}
