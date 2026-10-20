// TS stand-in of Fw.Measure.SimBound (lean/Fw/Measure/SimBound.lean): what the session does when the Simulator's inspector
// is dead. Checked against the Lean goldens (packages/contracts/golden/measure/measure.inspector.jsonl and
// measure.simBounds.jsonl, test/fwcore.test.mjs). Glue only: the limits, the rule and the exit code are Lean's.

/** The time constants of the dead-inspector path in ms (Lean: `measure.simBounds`). */
export const BOUNDS = Object.freeze({
  tickMs: 30000, probeMs: 25000, failLimit: 2, detectMs: 85000, terminateMs: 20000, launchMs: 90000, socketMs: 60000,
  proxyMs: 40000, tabMs: 60000, askMs: 20000, connectMs: 30000, relaunchMs: 320000, exitMs: 40000, stallMs: 360000,
  deadEndMs: 765000, deadExit: 4, setupMin: 6, tailMin: 10,
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
/** The `measure.inspector` reply. */
export const inspectorReply = ({ relaunched, fails, socket, proxy, page }) => {
  const n = nextFails(fails, { socket, proxy, page });
  return { ok: probeOk({ socket, proxy, page }), fails: n, dead: inspectorDead(socket, n), action: inspectorAction(relaunched, socket, n), exitCode: DEAD_EXIT };
};

/** The inspector is dead and Safari was relaunched once already (or the relaunch failed): the run ends with exit code 4. */
export class InspectorDeadError extends Error {
  constructor(message) { super(message); this.name = 'InspectorDeadError'; this.exitCode = DEAD_EXIT; }
}
