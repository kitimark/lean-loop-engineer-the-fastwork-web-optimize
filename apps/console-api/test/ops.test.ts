import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
const post = async (body: unknown) => {
  const store = await Store.open(mkdtempSync(join(tmpdir(), "fw-ops-")), selectCore());
  stores.push(store);
  const r = await createApp(store).request("/api/ops/path-check", { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json" } });
  return { status: r.status, body: await r.json() };
};

describe("POST /api/ops/path-check (Lean ops.pathCheck)", () => {
  it("answers with the paths outside the scope", async () => {
    const scope = ["**", "!.fw-console/", "!.claude/settings*"];
    expect(await post({ scope, paths: ["a/b.ts", ".fw-console/events.jsonl", ".claude/settings.json"] })).toEqual(
      { status: 200, body: { ok: false, violations: [".fw-console/events.jsonl", ".claude/settings.json"] } });
    expect(await post({ scope, paths: ["a/b.ts"] })).toEqual({ status: 200, body: { ok: true, violations: [] } });
  });
  it("400 on a malformed body", async () => {
    expect((await post({ paths: [] })).status).toBe(400);
  });
});
