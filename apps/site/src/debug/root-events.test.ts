import { describe, expect, it } from 'vitest';
import { installRootEventsDebug, rootEventsDebugOn, type RootEventsLog } from './root-events';

function fakeTarget() {
  const calls: string[] = [];
  const proto = {
    addEventListener(type: string) {
      calls.push(type);
    },
  };
  return { proto, calls };
}

describe('root-events debug recorder', () => {
  it('is on only for fw-debug=root-events', () => {
    expect(rootEventsDebugOn('?fw-debug=root-events')).toBe(true);
    expect(rootEventsDebugOn('?fw-debug=nav-transition,root-events')).toBe(true);
    expect(rootEventsDebugOn('?fw-debug=nav-transition')).toBe(false);
    expect(rootEventsDebugOn('')).toBe(false);
  });

  it('counts watched registrations by target and phase and passes every call through', () => {
    const { proto, calls } = fakeTarget();
    const win = { addEventListener: (type: string) => calls.push(`win:${type}`), removeEventListener: () => {} };
    const store: Record<string, unknown> = {};
    const off = installRootEventsDebug({ proto: proto as unknown as EventTarget, win: win as unknown as EventTarget, store });
    const root = { id: 'root' };
    const add = proto.addEventListener as unknown as (this: unknown, ...args: unknown[]) => void;
    add.call(root, 'transitionend', () => {}, true);
    add.call(root, 'transitionend', () => {}, false);
    add.call({}, 'animationstart', () => {}, { capture: true });
    add.call(root, 'click', () => {}, true);
    const log = (store.__fwDebug as { rootEvents: RootEventsLog }).rootEvents;
    expect(log.registered).toEqual({ 'root:transitionend:c': 1, 'root:transitionend:b': 1, 'other:animationstart:c': 1 });
    expect(calls).toContain('click');
    off();
  });
});
