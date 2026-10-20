// TS stand-in of Fw.Measure.SimBound (lean/Fw/Measure/SimBound.lean): what the session does when the Simulator's inspector
// is dead. Checked against the Lean goldens (packages/contracts/golden/measure/measure.inspector.jsonl, test/fwcore.test.mjs).
// Glue only: the limit, the rule and the exit code are Lean's; nothing is decided here.

/** Refused proxy connections in a row that count as a dead inspector (Lean: `refusalLimit`). */
export const REFUSAL_LIMIT = 2;
/** Exit code of a run that gave up on a dead inspector (Lean: `deadExit`; the stall watchdog uses 3). */
export const DEAD_EXIT = 4;

/** Lean: `dead`. */
export const inspectorDead = (socket, refusals) => !socket || refusals >= REFUSAL_LIMIT;
/** Lean: `act`. @returns {'proceed'|'relaunch'|'giveUp'} */
export const inspectorAction = (relaunched, socket, refusals) =>
  (inspectorDead(socket, refusals) ? (relaunched ? 'giveUp' : 'relaunch') : 'proceed');
/** The `measure.inspector` reply. */
export const inspectorReply = ({ relaunched, socket, refusals }) => ({
  dead: inspectorDead(socket, refusals), action: inspectorAction(relaunched, socket, refusals), exitCode: DEAD_EXIT,
});

/** The inspector is dead and Safari was relaunched once already (or the relaunch failed): the run ends with exit code 4. */
export class InspectorDeadError extends Error {
  constructor(message) { super(message); this.name = 'InspectorDeadError'; this.exitCode = DEAD_EXIT; }
}
