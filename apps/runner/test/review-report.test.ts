import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { UsageError } from "../src/lib.ts";
import { reportPostCli } from "../src/review.ts";

// `fw review report post --file` only reads the file and forwards it; Lean (console.report) decides. fetch is a stub here.
const file = (body: unknown) => {
  const f = join(mkdtempSync(join(tmpdir(), "fw-rp-")), "report.json");
  writeFileSync(f, JSON.stringify(body));
  return f;
};
const reply = (status: number, body: unknown) => (async () => new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;

describe("fw review report post", () => {
  it("posts the report file as it is and prints the id", async () => {
    let sent: any;
    const f = (async (url: string, init: RequestInit) => { sent = { url, body: JSON.parse(String(init.body)) }; return new Response(JSON.stringify({ ok: true, id: "r1", duplicate: false })); }) as unknown as typeof fetch;
    expect(await reportPostCli(["post", "--file", file({ id: "r1" })], "http://x", f)).toBe("report r1: posted");
    expect(sent).toEqual({ url: "http://x/api/reports", body: { report: { id: "r1" } } });
  });
  it("says duplicate for a repeated post", async () => {
    expect(await reportPostCli(["post", "--file", file({})], "http://x", reply(200, { ok: true, id: "r1", duplicate: true }))).toBe("report r1: duplicate (already posted)");
  });
  it("throws Lean's reason when the report is refused", async () => {
    await expect(reportPostCli(["post", "--file", file({})], "http://x", reply(422, { ok: false, reason: "the number has no MEASURED run id or INFERRED tag" })))
      .rejects.toThrow("refused: the number has no MEASURED run id or INFERRED tag");
  });
  it("needs the verb post, a file and valid JSON", async () => {
    await expect(reportPostCli(["list"], "http://x")).rejects.toThrow(UsageError);
    await expect(reportPostCli(["post"], "http://x")).rejects.toThrow(UsageError);
    const bad = join(mkdtempSync(join(tmpdir(), "fw-rp-")), "bad.json");
    writeFileSync(bad, "{nope");
    await expect(reportPostCli(["post", "--file", bad], "http://x")).rejects.toThrow(UsageError);
  });
});
