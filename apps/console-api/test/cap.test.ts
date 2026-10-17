import { appendFileSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { actorFor, capMac, sha256 } from "../src/cap/cap.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
// the hook's formula must equal the verifier's
import { capMac as hookMac } from "../../runner/hooks/lib.mjs";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
const NOW = Date.now();
const fresh = async () => {
  const dir = mkdtempSync(join(tmpdir(), "fw-cap-"));
  const store = await Store.open(dir, selectCore(), () => NOW);
  stores.push(store);
  const app = createApp(store);
  return { dir, store, app, secret: readFileSync(join(dir, "secret"), "utf8").trim() };
};
const grant = (dir: string, secret: string, o: { agent_type?: string; id: string; argv: string[]; ts?: number; mac?: string; agent_id?: string | null }) => {
  const agent_type = o.agent_type ?? "main", hash = sha256(o.argv.join(" "));
  appendFileSync(join(dir, "caps.jsonl"), JSON.stringify({ agent_id: o.agent_id ?? null, agent_type, tool_use_id: o.id, cmd_hash: hash,
    mac: o.mac ?? capMac(secret, agent_type, o.id, hash), ts: o.ts ?? NOW }) + "\n");
};
const post = (app: ReturnType<typeof createApp>, argv: string[], command: unknown) =>
  app.request("/api/agent/commands", { method: "POST", body: JSON.stringify({ argv, command }), headers: { "content-type": "application/json" } });
const open = { type: "card.open", key: "k1", actor: "user", card: "A", owner: "o", needsDevice: false };
const argv = ["send", "x"];

describe("capability door", () => {
  it("hook and verifier compute the same MAC", () => {
    expect(hookMac("s3cret", "t", "id", "h")).toBe(capMac("s3cret", "t", "id", "h"));
  });
  it("no capability: 403 and nothing reaches the log", async () => {
    const { dir, app } = await fresh();
    expect((await post(app, argv, open)).status).toBe(403);
    expect(readFileSync(join(dir, "events.jsonl"), "utf8")).toBe("");
  });
  it("valid capability: actor is stamped from the holder, the client's actor is ignored", async () => {
    const { dir, secret, app } = await fresh();
    grant(dir, secret, { id: "t1", argv }); // main -> lead; lead may open a card
    const r = await post(app, argv, open); // client claims actor "user"
    expect(await r.json()).toEqual({ ok: true, seq: 1, duplicate: false });
    expect(JSON.parse(readFileSync(join(dir, "events.jsonl"), "utf8"))).toMatchObject({ actor: "lead" });
  });
  it("single use: the second request with the same capability is refused", async () => {
    const { dir, secret, app } = await fresh();
    grant(dir, secret, { id: "t1", argv });
    expect((await post(app, argv, open)).status).toBe(200);
    expect((await post(app, argv, { ...open, key: "k2" })).status).toBe(403);
  });
  it("bad MAC, wrong command, expired, from the future: refused", async () => {
    const { dir, secret, app } = await fresh();
    grant(dir, secret, { id: "a", argv, mac: "0".repeat(64) });
    grant(dir, secret, { id: "b", argv: ["send", "other"] });
    grant(dir, secret, { id: "c", argv, ts: NOW - 11 * 60_000 });
    grant(dir, secret, { id: "d", argv, ts: NOW + 5 * 60_000 });
    expect((await post(app, argv, open)).status).toBe(403);
  });
  it("a MAC made with another secret is refused", async () => {
    const { dir, app } = await fresh();
    grant(dir, "not-the-secret", { id: "t1", argv });
    expect((await post(app, argv, open)).status).toBe(403);
  });
  it("the reducer still decides: owner may not approve (Lean authority table)", async () => {
    const { dir, secret, app } = await fresh();
    grant(dir, secret, { id: "t1", agent_type: "builder", argv });
    const r = await post(app, argv, { type: "card.approve", key: "k", actor: "lead", card: "A" });
    expect(r.status).toBe(422);
    expect((await r.json() as { reason: string }).reason).toBe("actor owner may not cause card.approve");
  });
  it("signedBy comes from the capability, not the body", async () => {
    const { dir, secret, app, store } = await fresh();
    await store.submit({ type: "card.open", key: "o", actor: "lead", card: "A", owner: "o", needsDevice: false });
    await store.submit({ type: "card.approve", key: "ap", actor: "lead", card: "A" });
    await store.submit({ type: "card.build", key: "b", actor: "git", card: "A", sha: "s1", agent: "bld" });
    grant(dir, secret, { id: "t2", agent_type: "code-reviewer", agent_id: "rev9", argv });
    const r = await post(app, argv, { type: "card.review", key: "r", actor: "owner", card: "A", sha: "s1", signedBy: "fake", accept: true });
    expect(await r.clone().json()).toEqual({ ok: true, seq: 4, duplicate: false });
    const last = readFileSync(join(dir, "events.jsonl"), "utf8").trim().split("\n").pop()!;
    expect(JSON.parse(last)).toMatchObject({ actor: "reviewer", signedBy: "rev9" });
  });
  it("the socket never yields user, script or git", () => {
    for (const t of ["main", "owner-1", "code-reviewer", "git", "script", "user", "hook", ""]) {
      expect(["user", "script", "git", "hook"]).not.toContain(actorFor(t));
    }
  });
  it("non-JSON and malformed bodies: 400", async () => {
    const { app } = await fresh();
    expect((await app.request("/api/agent/commands", { method: "POST", body: "x" })).status).toBe(400);
    expect((await app.request("/api/agent/commands", { method: "POST", body: "{}" })).status).toBe(400);
  });
});
