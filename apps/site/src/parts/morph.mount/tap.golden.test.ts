import { goldenConformance } from '../../engine/golden.testutil';
import * as logic from './logic';

type Ev = [ms: number, near: boolean, push: boolean, input: boolean, scroll: boolean, check: boolean, active: boolean];

function replay(events: Ev[], tap: boolean) {
  let mounted = false;
  let last = 0;
  let calls = 0;
  const out = [{ mounted, calls }];
  for (const [ms, near, push, input, scroll, check, active] of events) {
    const hears = scroll && !(tap && mounted);
    if (hears) calls++;
    const warm = check && !mounted && logic.warmStill(active, ms - last);
    const stamp = push || input || hears;
    mounted = logic.mountNextWarm(mounted, near, push, warm);
    if (stamp) last = ms;
    out.push({ mounted, calls });
  }
  return out;
}

goldenConformance('morph-mount-tap', {
  warmStill: (i) => logic.warmStill(i.active as boolean, i.quiet as number),
  tapRun: (i) => {
    const events = i.events as Ev[];
    const shift = replay(events, false);
    const tap = replay(events, true);
    return shift.map((s, t) => ({ m: s.mounted, mt: tap[t]!.mounted, c: s.calls, ct: tap[t]!.calls }));
  },
});
