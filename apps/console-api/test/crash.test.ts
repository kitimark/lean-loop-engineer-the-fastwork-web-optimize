import { chmodSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { leanBinary, type Incident } from "../src/core/lean.ts";

const open = { type: "card.open", key: "k1", actor: "owner", card: "A", owner: "o", needsDevice: false, ts: 1 } as const;
const approve = { type: "card.approve", key: "k2", actor: "lead", card: "A", ts: 2 } as const;
// No absolute wall-clock bound (task land-wallclock-off-gate): the deadline the fake core must miss and the generous cap
// for a call that must succeed come from env knobs the land can raise; the elapsed time is only checked from below.
const knob = (name: string, dflt: number): number => {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 ? v : dflt;
};
const DEADLINE_MS = knob("FW_TEST_DEADLINE_MS", 1500);
const CALL_MS = knob("FW_TEST_CALL_MS", 30000);
let core: ReturnType<typeof selectCore> | null = null;
afterEach(() => core?.close());

describe("fwcore failure handling", () => {
  it("missing binary: clear message with the build command", () => {
    expect(() => leanBinary("/nonexistent-root", {})).toThrow(/sh scripts\/fwcore-build.sh/);
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

  // a fake fwcore: answers every request line with `reply(id)`, or never when reply is "null"
  const fake = (reply: string) => {
    const f = join(mkdtempSync(join(tmpdir(), "fw-fake-")), "fwcore");
    writeFileSync(f, `#!/usr/bin/env node
require("readline").createInterface({ input: process.stdin }).on("line", (l) => {
  const id = JSON.parse(l).id; const r = (${reply})(id); if (r !== null) console.log(JSON.stringify(r));
});
`);
    chmodSync(f, 0o755);
    return { ...process.env, FW_CORE_BIN: f };
  };
  it("a reply whose id matches no pending call kills the child; the call fails and the next call restarts", async () => {
    const incidents: Incident[] = [];
    core = selectCore(fake("(id) => ({ id: id + 1000, outcome: null })"), undefined, (i) => incidents.push(i));
    await core.open(() => []);
    await expect(core.apply(open)).rejects.toThrow(/fwcore crashed \(reply id mismatch\)/);
    expect(core.restarts).toBe(1);
    expect(incidents.map((i) => i.kind)).toContain("bad-line");
    await expect(core.apply(open)).rejects.toThrow(/reply id mismatch/); // fresh child, same fake: dies the same way
    expect(core.restarts).toBe(2);
  });
  it("a call unanswered past the deadline kills the child and fails with a crash error", async () => {
    const incidents: Incident[] = [];
    core = selectCore(fake("() => null"), undefined, (i) => incidents.push(i), DEADLINE_MS);
    await core.open(() => []);
    const t0 = Date.now();
    await expect(core.apply(open)).rejects.toThrow(new RegExp(`timed out after ${DEADLINE_MS} ms`));
    expect(Date.now() - t0).toBeGreaterThanOrEqual(DEADLINE_MS - 50); // the deadline was waited for, not skipped
    expect(core.restarts).toBe(1);
    expect(incidents.map((i) => i.kind)).toContain("timeout");
  });
  it("a timed-out real core restarts with replay and answers the next call", async () => {
    const log = [JSON.stringify({ ...open, seq: 1 })];
    core = selectCore(process.env, undefined, () => undefined, CALL_MS);
    await core.open(() => log);
    core.stopForTest(); // frozen child never answers
    core.callTimeoutForTest(DEADLINE_MS);
    await expect(core.board(10, 1)).rejects.toThrow(/timed out/);
    core.callTimeoutForTest(CALL_MS);
    expect((await core.board(10, 1)).cards[0]).toMatchObject({ id: "A" });
    expect(core.replays).toBe(2);
  });
});
