// The preview server finds a prerendered flag page whatever order the typed ?fw= list has
// (canonical key: lean/Fw/Wire/FlagKey.lean, packages/contracts/src/flag-key.mjs).
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { handler } from "../src/preview/serve-child.ts";

const servers: Server[] = [];
afterEach(() => { for (const s of servers.splice(0)) s.close(); });

describe("preview lookup of a flag page", () => {
  it("finds the page of a requires-chain in both orders", async () => {
    const root = mkdtempSync(join(tmpdir(), "fw-flagorder-"));
    mkdirSync(join(root, "c"), { recursive: true });
    writeFileSync(join(root, "index.html"), "<h1>default</h1>");
    writeFileSync(join(root, "c/h.html"), "<h1>chain</h1>");
    const key = "?fw=hero.countdown:strip,morph.countdown:strip";
    writeFileSync(join(root, "configs.json"), JSON.stringify({ bySearch: { "": "d", [key]: "h" }, byHash: { d: "index.html", h: "c/h.html" } }));
    const srv = createServer(handler({ root, prerendered: true }));
    servers.push(srv);
    const port = await new Promise<number>((r) => srv.listen(0, "127.0.0.1", () => r((srv.address() as AddressInfo).port)));
    for (const typed of [key, "?fw=morph.countdown:strip,hero.countdown:strip", "?fw=morph.countdown:strip&fw=hero.countdown:strip"]) {
      expect(await (await fetch(`http://127.0.0.1:${port}/${typed}`)).text(), typed).toBe("<h1>chain</h1>");
    }
    expect(await (await fetch(`http://127.0.0.1:${port}/?fw=morph.countdown:strip`)).text()).toBe("<h1>default</h1>");
    rmSync(root, { recursive: true, force: true });
  });
});
