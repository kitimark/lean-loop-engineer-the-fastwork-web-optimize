// TS stand-in of Fw.Measure.SimBound (lean/Fw/Measure/SimBound.lean): what the session does when the Simulator's inspector
// is dead. Checked against the Lean goldens (packages/contracts/golden/measure/measure.inspector.jsonl and
// measure.simBounds.jsonl, test/fwcore.test.mjs). Glue only: the limits, the rule and the exit code are Lean's.

/** The time constants of the dead-inspector path in ms (Lean: `measure.simBounds`). */
export const BOUNDS = Object.freeze({
  tickMs: 30000, probeMs: 25000, failLimit: 2, detectMs: 85000, terminateMs: 20000, launchMs: 90000, socketMs: 60000,
  proxyMs: 40000, tabMs: 60000, askMs: 20000, connectMs: 30000, stopMs: 2000, lsofMs: 5000, proxyStartMs: 35000, repairMs: 42000,
  relaunchMs: 320000, exitMs: 40000, stallMs: 720000, deadEndMs: 614000, deadExit: 4, setupMin: 8, tailMin: 10,
  targetWaitMs: 480000, targetAfterMs: 90000, targetEndMs: 930000, targetLostExit: 5,
});
/** Exit code of a run that gave up on a dead inspector (Lean: `deadExit`; the stall watchdog uses 3). */
export const DEAD_EXIT = BOUNDS.deadExit;

/** Lean: `Probe.ok`. A probe is `{socket, proxy, page}`. */
export const probeOk = (p) => p.socket && p.proxy && p.page;
/** Lean: `nextFails`. */
export const nextFails = (fails, p) => (probeOk(p) ? 0 : fails + 1);
/** Lean: `dead`. */
export const inspectorDead = (socket, fails) => !socket || fails >= BOUNDS.failLimit;
/** Lean: `act`. @returns {'proceed'|'relaunch'|'giveUp'} */
export const inspectorAction = (relaunched, socket, fails) =>
  (inspectorDead(socket, fails) ? (relaunched ? 'giveUp' : 'relaunch') : 'proceed');
/** Lean: `afterRelaunch`. A failed relaunch gives up, a working one goes on. @returns {'proceed'|'giveUp'} */
export const inspectorAfterRelaunch = (ok) => (ok ? 'proceed' : 'giveUp');
/** The `measure.inspector` reply; `afterRelaunch` is there when the request names `relaunchOk`. */
export const inspectorReply = ({ relaunched, fails, socket, proxy, page, relaunchOk }) => {
  const n = nextFails(fails, { socket, proxy, page });
  return {
    ok: probeOk({ socket, proxy, page }), fails: n, dead: inspectorDead(socket, n), action: inspectorAction(relaunched, socket, n), exitCode: DEAD_EXIT,
    ...(typeof relaunchOk === 'boolean' ? { afterRelaunch: inspectorAfterRelaunch(relaunchOk) } : {}),
  };
};

/** The inspector is dead and Safari was relaunched once already (or the relaunch failed): the run ends with exit code 4. */
export class InspectorDeadError extends Error {
  constructor(message) { super(message); this.name = 'InspectorDeadError'; this.exitCode = DEAD_EXIT; }
}

/** Exit code of a session that lost its page target for good (Lean: `targetLostExit`). */
export const TARGET_LOST_EXIT = BOUNDS.targetLostExit;
/** Lean: `targetLimit`. The wait bound of a stretch: before the relaunch 480 s, after it 90 s. */
export const targetLimit = (relaunched) => (relaunched ? BOUNDS.targetAfterMs : BOUNDS.targetWaitMs);
/** What is left of a bound `limitMs` at `elapsedMs` (Lean: `targetCapMs` for the bounds of `targetLimit`). */
export const remainingMs = (limitMs, elapsedMs) => Math.max(0, limitMs - elapsedMs);
/** Lean: `targetCapMs`. The longest a poll may take. */
export const targetCapMs = (relaunched, elapsedMs) => remainingMs(targetLimit(relaunched), elapsedMs);
/** Lean: `targetAction`. @returns {'connect'|'wait'|'relaunch'|'failSession'} */
export const targetAction = (relaunched, elapsedMs, found) => {
  if (found) return 'connect';
  if (elapsedMs < targetLimit(relaunched)) return 'wait';
  return relaunched ? 'failSession' : 'relaunch';
};
/** Lean: `targetAfterRelaunch`. @returns {'wait'|'failSession'} */
export const targetAfterRelaunch = (ok) => (ok ? 'wait' : 'failSession');
/** The `measure.targetLost` reply; `afterRelaunch` is there when the request names `relaunchOk`. */
export const targetReply = ({ relaunched, elapsedMs, found, relaunchOk }) => ({
  action: targetAction(relaunched, elapsedMs, found), limitMs: targetLimit(relaunched), capMs: targetCapMs(relaunched, elapsedMs), exitCode: TARGET_LOST_EXIT,
  ...(typeof relaunchOk === 'boolean' ? { afterRelaunch: targetAfterRelaunch(relaunchOk) } : {}),
});

/** The page target stayed lost through the bound and the one relaunch (or the relaunch failed): the session ends with exit code 5. */
export class TargetLostError extends Error {
  constructor(message) { super(message); this.name = 'TargetLostError'; this.exitCode = TARGET_LOST_EXIT; }
}
