// fwcore's `samples` op returns one request/reply per op; the console ones must satisfy the zod contracts.
import { afterAll, describe, expect, it } from "vitest";
import { ApplyRequest, ApplyResponse, Board, State } from "@fw/contracts";
import { selectCore } from "../src/core/index.ts";

const core = selectCore();
afterAll(() => core.close());

type Sample = { name: string; request: Record<string, unknown>; response: Record<string, unknown> };
const samples = ((await core.raw("samples")).samples as Sample[]);
const named = (n: string) => samples.find((s) => s.name === n)!;

describe("fwcore samples vs zod", () => {
  it("lists one sample per op", () => {
    expect(samples.map((s) => s.name)).toEqual(expect.arrayContaining(["console.apply", "console.board", "verdict", "lease.step"]));
  });
  it("console.apply request and reply parse", () => {
    const s = named("console.apply");
    expect(ApplyRequest.safeParse(s.request).success).toBe(true);
    expect(ApplyResponse.safeParse(s.response).success).toBe(true);
  });
  it("console.board request state and reply board parse", () => {
    const s = named("console.board");
    expect(State.safeParse(s.request.state).success).toBe(true);
    expect(Number.isInteger(s.request.now)).toBe(true);
    expect(Number.isInteger(s.request.seq)).toBe(true);
    expect(Board.safeParse(s.response.board).success).toBe(true);
  });
  it("replaying the apply sample through fwcore reproduces its reply", async () => {
    const s = named("console.apply");
    const req = ApplyRequest.parse(s.request);
    expect(JSON.parse(JSON.stringify(await core.applyPure(req.state, req.event)))).toEqual(s.response);
  });
});
