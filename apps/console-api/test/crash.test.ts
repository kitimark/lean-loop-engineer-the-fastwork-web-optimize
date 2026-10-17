import { afterEach, describe, expect, it } from "vitest";
import { emptyState } from "@fw/contracts";
import { selectCore } from "../src/core/index.ts";
import { leanBinary, type Incident } from "../src/core/lean.ts";

const open = { type: "card.open", key: "k1", actor: "owner", card: "A", owner: "o", needsDevice: false, ts: 1 } as const;
let core: ReturnType<typeof selectCore> | null = null;
afterEach(() => core?.close());

describe("fwcore failure handling", () => {
  it("missing binary: clear message with the build command", () => {
    expect(() => leanBinary("/nonexistent-root", {})).toThrow(/cd lean && lake build/);
  });
  it("a crash fails the in-flight call, is logged, and the next call restarts the process", async () => {
    const incidents: Incident[] = [];
    core = selectCore(process.env, undefined, (i) => incidents.push(i));
    expect((await core.apply(emptyState(), open)).outcome).toEqual({ accepted: true, duplicate: false });
    core.stopForTest(); // frozen child: it cannot answer before it is killed, so the call is truly in flight
    const inflight = core.apply(emptyState(), { ...open, key: "k2" });
    const exited = core.killForTest();
    const settled = inflight.then(() => "ok", (e: Error) => e);
    await exited; // explicit: the process is known dead and the crash is accounted
    expect(await settled).toMatchObject({ message: expect.stringMatching(/fwcore crashed/) });
    expect(incidents.some((i) => i.kind === "exit")).toBe(true);
    expect(core.restarts).toBe(1);
    expect((await core.apply(emptyState(), open)).outcome).toEqual({ accepted: true, duplicate: false });
  });
});
