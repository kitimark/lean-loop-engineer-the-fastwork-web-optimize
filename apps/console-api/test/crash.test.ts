import { afterEach, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { leanBinary, type Incident } from "../src/core/lean.ts";

const open = { type: "card.open", key: "k1", actor: "owner", card: "A", owner: "o", needsDevice: false, ts: 1 } as const;
const approve = { type: "card.approve", key: "k2", actor: "lead", card: "A", ts: 2 } as const;
let core: ReturnType<typeof selectCore> | null = null;
afterEach(() => core?.close());

describe("fwcore failure handling", () => {
  it("missing binary: clear message with the build command", () => {
    expect(() => leanBinary("/nonexistent-root", {})).toThrow(/cd lean && lake build/);
  });
  it("a crash fails the in-flight call, is logged, and the next call restarts the process", async () => {
    const incidents: Incident[] = [];
    core = selectCore(process.env, undefined, (i) => incidents.push(i));
    await core.open(() => []);
    expect((await core.apply(open)).outcome).toEqual({ accepted: true, duplicate: false });
    core.stopForTest(); // frozen child: it cannot answer before it is killed, so the call is truly in flight
    const inflight = core.apply({ ...open, key: "k2" });
    const exited = core.killForTest();
    const settled = inflight.then(() => "ok", (e: Error) => e);
    await exited; // explicit: the process is known dead and the crash is accounted
    expect(await settled).toMatchObject({ message: expect.stringMatching(/fwcore crashed/) });
    expect(incidents.some((i) => i.kind === "exit")).toBe(true);
    expect(core.restarts).toBe(1);
    // the log (empty here) was replayed into the new process, so card A is new again
    expect((await core.apply(open)).outcome).toEqual({ accepted: true, duplicate: false });
  });
  it("after a crash the new process replays the log before answering: same board as before the crash", async () => {
    const log: string[] = [];
    core = selectCore(process.env, undefined, () => undefined);
    await core.open(() => log);
    for (const e of [open, approve]) {
      expect((await core.apply(e)).outcome).toEqual({ accepted: true, duplicate: false });
      log.push(JSON.stringify({ ...e, seq: log.length + 1 })); // what the store appends after an accept
    }
    const before = await core.board(10, 2);
    await core.killForTest();
    expect(core.restarts).toBe(1);
    expect(await core.board(10, 2)).toEqual(before); // first call after the crash: replay, then query
    expect(core.replays).toBe(2);
    expect((await core.apply(open)).outcome).toEqual({ accepted: true, duplicate: true }); // k1 is known again
    expect(before.cards[0]).toMatchObject({ id: "A", stage: "build" });
  });
  it("a replay that fails poisons the process: the call queued behind it fails, nothing answers from a partial state", async () => {
    const incidents: Incident[] = [];
    const log = [JSON.stringify(open), '{"key":"bad","ts":3,"type":"card.nope","actor":"owner"}'];
    core = selectCore(process.env, undefined, (i) => incidents.push(i));
    await expect(core.open(() => log)).rejects.toThrow(/unknown event type card.nope/);
    expect(incidents.some((i) => i.kind === "exit" && /replay failed/.test(i.detail))).toBe(true);
    log.pop(); // repaired log: the next call replays it into a fresh process
    expect((await core.apply(open)).outcome).toEqual({ accepted: true, duplicate: true });
  });
  it("restart() drops the process; the next call replays the log", async () => {
    const log = [JSON.stringify({ ...open, seq: 1 })];
    core = selectCore(process.env, undefined, () => undefined);
    await core.open(() => log);
    expect((await core.apply(approve)).outcome).toEqual({ accepted: true, duplicate: false }); // not logged
    core.restart();
    expect((await core.board(10, 1)).cards[0]).toMatchObject({ id: "A", stage: "question" }); // the approve is gone
  });
});
