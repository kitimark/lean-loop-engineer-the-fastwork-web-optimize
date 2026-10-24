import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { badNs, candidateNs } from "../../console-api/src/ledger-unique.ts";
import { allocLedger, allocN, LEDGER_FILE } from "../src/land.ts";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
type G = { name: string; main: number[]; rows: (number | null)[]; out: number[]; ok: boolean };
const golden: G[] = readFileSync(join(repo, "packages/contracts/golden/console/ledger-alloc.jsonl"), "utf8")
  .split("\n").filter((l) => l !== "").map((l) => JSON.parse(l) as G);

describe("ledger numbers are assigned at the land (Lean Fw.Console.LedgerAlloc golden)", () => {
  it("has the cases", () => expect(golden.length).toBeGreaterThanOrEqual(10));
  for (const g of golden) {
    it(`golden ${g.name}`, () => {
      expect(allocN(g.main, g.rows)).toEqual(g.out);
      expect(badNs(allocN(g.main, g.rows)).length === 0).toBe(g.ok);
    });
  }
});

describe("the ledger-unique check accepts rows without a number", () => {
  it("skips n-less candidate rows and still refuses a duplicate explicit n", () => {
    const row = (n: number | null | undefined) => ({ id: "x", candidate: "c", ...(n === undefined ? {} : { n }) });
    expect(badNs(candidateNs({ findings: [row(30), row(null), row(undefined), row(31)] as never }))).toEqual([]);
    expect(badNs(candidateNs({ findings: [row(30), row(null), row(30)] as never }))).toEqual([30]);
  });
});

describe("allocLedger on a merged tree", () => {
  const dir = mkdtempSync(join(tmpdir(), "lna-"));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));
  const git = (...a: string[]) => execFileSync("git", a, { cwd: dir, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  const text = (rows: Record<string, unknown>[]) => JSON.stringify({ about: "x", findings: rows }, null, 1) + "\n";
  it("numbers new rows above main, in row order, and keeps the rest of the file", () => {
    mkdirSync(join(dir, dirname(LEDGER_FILE)), { recursive: true });
    git("init", "-q");
    git("config", "user.email", "t@example.invalid");
    git("config", "user.name", "t");
    writeFileSync(join(dir, LEDGER_FILE), text([{ n: 70, id: "a", candidate: "a" }, { n: 72, id: "b", candidate: "b" }]));
    git("add", "--", LEDGER_FILE);
    git("commit", "-q", "-m", "main");
    const main = git("rev-parse", "HEAD").trim();
    writeFileSync(join(dir, LEDGER_FILE), text([{ n: 70, id: "a", candidate: "a" }, { id: "c", candidate: "c" }, { n: null, id: "d", candidate: "d" }, { n: 72, id: "b", candidate: "b" }]));
    expect(allocLedger(dir, main)).toBe("written");
    const rows = (JSON.parse(readFileSync(join(dir, LEDGER_FILE), "utf8")) as { findings: { n: number; id: string }[] }).findings;
    expect(rows.map((r) => [r.id, r.n])).toEqual([["a", 70], ["c", 73], ["d", 74], ["b", 72]]);
    expect(Object.keys(rows[1]!)).toEqual(["n", "id", "candidate"]);
    expect(git("diff", "--cached", "--name-only").trim()).toBe(LEDGER_FILE);
    expect(allocLedger(dir, main)).toBe("none");
  });
});
