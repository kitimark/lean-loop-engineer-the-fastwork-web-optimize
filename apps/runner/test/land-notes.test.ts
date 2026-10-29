import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { checksWithReads, FWCORE_USERS, LEDGER_FILE, LEDGER_NOTES_ID, ledgerNoteKeyCheck, LOCAL_TESTS, selectChecks } from "../src/land.ts";
import { noteShapeProblems } from "../src/land-notes.ts";

// Task ledger-note-check (mistake class c-late-check; builds hero-exit-gate-clear and cols-probe, 2026-10-29): a findings-ledger note
// whose entry is free text or whose field is no findings field is refused before the land's remote suite. Fixtures only: the real ledger is read, never edited.
const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const finding = { n: 1, candidate: "cand-a", part: "hero", mechanism: "m", missingWhy: "", next: "" };
const note = { entry: "cand-a", task: "t1", field: "mechanism", text: "a fact" };
const ledger = (notes: unknown[]) => JSON.stringify({ findings: [finding], notes }, null, 1) + "\n";

describe("noteShapeProblems on fixtures", () => {
  it("a note naming a candidate and a findings field passes; no notes pass", () => {
    expect(noteShapeProblems(ledger([note]))).toEqual([]);
    expect(noteShapeProblems(JSON.stringify({ findings: [finding] }))).toEqual([]);
  });
  it("an entry that is free text, not a candidate, is refused (cols-probe)", () => {
    const p = noteShapeProblems(ledger([{ ...note, entry: "the columns probe, in prose" }]));
    expect(p).toHaveLength(1);
    expect(p[0]).toContain("is not the candidate of a finding");
  });
  it("a field that is not a findings field is refused (hero-exit-gate-clear: 'gate')", () => {
    const p = noteShapeProblems(ledger([{ ...note, field: "gate" }]));
    expect(p).toHaveLength(1);
    expect(p[0]).toContain('field "gate" is not a findings field');
  });
  it("a missing key, an extra key, an empty text and a repeated (entry, task) are refused", () => {
    const { task: _t, ...noTask } = note;
    expect(noteShapeProblems(ledger([noTask])).join("\n")).toContain("keys are");
    expect(noteShapeProblems(ledger([{ ...note, extra: 1 }])).join("\n")).toContain("keys are");
    expect(noteShapeProblems(ledger([{ ...note, text: "" }])).join("\n")).toContain("text is empty");
    expect(noteShapeProblems(ledger([note, { ...note, field: "next" }])).join("\n")).toContain("repeats");
  });
  it("not JSON, notes that are no array, and a note that is no object are refused", () => {
    expect(noteShapeProblems("{")).toEqual(["not valid JSON"]);
    expect(noteShapeProblems(JSON.stringify({ findings: [finding], notes: {} }))).toEqual(["notes is not an array"]);
    expect(noteShapeProblems(ledger(["free text"]))).toEqual(["note 0: not an object"]);
  });
  it("the real findings ledger passes the rule", () => {
    expect(noteShapeProblems(readFileSync(join(root, LEDGER_FILE), "utf8"))).toEqual([]);
  });
});

describe("the dry land refuses a bad note (ledgerNoteKeyCheck, a checkout fixture)", () => {
  const dir = mkdtempSync(join(tmpdir(), "land-notes-"));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));
  const put = (notes: unknown[]) => { mkdirSync(join(dir, "research/findings"), { recursive: true }); writeFileSync(join(dir, LEDGER_FILE), ledger(notes)); };
  it("a good note passes", () => { put([note]); expect(ledgerNoteKeyCheck(dir)).toBeNull(); });
  it("a free-text entry and a non-field field are refused naming the line", () => {
    put([{ ...note, entry: "prose" }]);
    expect(ledgerNoteKeyCheck(dir)).toContain("ledger-note-shape");
    expect(ledgerNoteKeyCheck(dir)).toContain("note 0: entry");
    put([{ ...note, field: "gate" }]);
    expect(ledgerNoteKeyCheck(dir)).toContain("is not a findings field");
  });
});

describe("a change to the findings ledger selects the ledger tests (Lean LandTier.ledger_selects_notes)", () => {
  it("the local gate is declared from the Lean golden, runs the ledger-merge and note tests, and needs no fwcore build", () => {
    const t = LOCAL_TESTS.find((x) => x.id === LEDGER_NOTES_ID)!;
    expect(t.argv).toEqual(["pnpm", "--filter", "./apps/runner", "exec", "vitest", "run", "test/ledger-merge.test.ts", "test/land-notes.test.ts"]);
    expect(FWCORE_USERS).not.toContain(LEDGER_NOTES_ID);
    for (const f of t.argv.filter((a) => a.startsWith("test/"))) expect(readFileSync(join(root, "apps/runner", f), "utf8").length).toBeGreaterThan(0);
  });
  it("the findings ledger, alone or among others, selects it; unrelated files do not", () => {
    expect(selectChecks(LOCAL_TESTS, [LEDGER_FILE])).toContain(LEDGER_NOTES_ID);
    expect(selectChecks(LOCAL_TESTS, ["docs/x.md", LEDGER_FILE, "apps/site/src/x.ts"])).toContain(LEDGER_NOTES_ID);
    expect(checksWithReads(root, [LEDGER_FILE]).map((c) => c.id)).toContain(LEDGER_NOTES_ID);
    expect(selectChecks(LOCAL_TESTS, ["docs/team/tools/land.md"])).not.toContain(LEDGER_NOTES_ID);
  });
});

describe("the commit check is planned and blocks (scripts/checkmap.mjs, Lean Fw.Ops.CheckMap ledgerNotes)", () => {
  const bin = join(root, "lean/.lake/build/bin/fwcore");
  const ask = (paths: string[]) => {
    const r = spawnSync(bin, [], { input: JSON.stringify({ id: 1, op: "ops.checkMap", paths }) + "\n", encoding: "utf8" });
    return JSON.parse(r.stdout.split("\n")[0] ?? "{}") as { cmds?: { check: string; argv: string[] }[] };
  };
  it("a staged findings ledger plans the ledger-notes command over it", () => {
    const m = ask([LEDGER_FILE]);
    expect(m.cmds?.map((c) => c.check)).toContain("ledgerNotes");
    expect(m.cmds?.find((c) => c.check === "ledgerNotes")?.argv).toEqual(["node", "scripts/checkmap.mjs", "file", "ledger", LEDGER_FILE]);
    expect(ask(["research/mistakes/ledger.json"]).cmds?.map((c) => c.check)).not.toContain("ledgerNotes");
  });
  it("`checkmap file ledger` exits 1 on a bad note and 0 on a good one (working tree of a fixture checkout)", () => {
    const dir = mkdtempSync(join(tmpdir(), "land-notes-cm-"));
    try {
      spawnSync("git", ["init", "-q"], { cwd: dir });
      mkdirSync(join(dir, "research/findings"), { recursive: true });
      const run = (notes: unknown[]) => {
        writeFileSync(join(dir, LEDGER_FILE), ledger(notes));
        return spawnSync("node", [join(root, "scripts/checkmap.mjs"), "file", "ledger", LEDGER_FILE], { cwd: dir, encoding: "utf8" });
      };
      expect(run([note]).status).toBe(0);
      const bad = run([{ ...note, field: "gate" }]);
      expect(bad.status).toBe(1);
      expect(bad.stderr).toContain("is not a findings field");
      expect(run([{ ...note, entry: "prose" }]).status).toBe(1);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});
