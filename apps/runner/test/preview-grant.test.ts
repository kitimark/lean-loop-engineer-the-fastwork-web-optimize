import { describe, expect, it } from "vitest";
import { previewCli, type Fetch } from "../src/preview.ts";

const reply = (status: number, body: unknown): Fetch => async () => ({ status, json: async () => body });

describe("fw preview grant", () => {
  it("prints the link and nothing else", async () => {
    const lines: string[] = []; let sent = "";
    const f: Fetch = async (_u, init) => { sent = init.body; return { status: 200, json: async () => ({ ok: true, url: "http://127.0.0.1:1/__grant?t=abc", expiresInSec: 600 }) }; };
    expect(await previewCli(["grant", "p1", "--arm", "o"], "http://127.0.0.1:2", f, (l) => lines.push(l))).toBe(0);
    expect(lines).toEqual(["http://127.0.0.1:1/__grant?t=abc"]);
    expect(JSON.parse(sent)).toEqual({ id: "p1", arm: "o" });
  });
  it("a refusal prints no link and exits 2", async () => {
    const lines: string[] = [];
    expect(await previewCli(["grant"], "http://x", reply(403, { ok: false, reason: "loopback only" }), (l) => lines.push(l))).toBe(2);
    expect(lines).toEqual([]);
  });
  it("bad usage", async () => {
    await expect(previewCli(["nope"], "http://x")).rejects.toThrow(/usage/);
    await expect(previewCli(["grant", "--arm", "z"], "http://x")).rejects.toThrow(/usage/);
    await expect(previewCli(["grant", "--arm", "o"], "http://x")).rejects.toThrow(/usage/);
    await expect(previewCli(["grant", "a", "b"], "http://x")).rejects.toThrow(/usage/);
  });
});
