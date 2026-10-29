import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { LEDGER_FILE, ledgerNoteKeyCheck } from "../src/land.ts";
import { noteKeyDups, noteKeyRefusal, onePerKey, type NoteKey } from "../src/land-verdict.ts";

// scripts/merge-ledger.mjs (git merge driver) against Lean's Fw.Ops.LedgerMerge: the golden vectors
// (packages/contracts/golden/ops/ledger-merge.jsonl, written by `lake test -- --write-ledger-merge-golden`), the real
// ledgers' formatting, and the 2026-10-18 land conflict (two branches append different incidents) in a scratch repo.
const repo = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const script = join(repo, "scripts", "merge-ledger.mjs");

type Entry = Record<string, unknown>;
type Row = { keep: Entry } | { drop: string } | { clash: string; base: Entry | null; ours: Entry | null; theirs: Entry | null };
type Driver = {
  rows: (b: Entry[], o: Entry[], t: Entry[]) => Row[];
  merge: (b: Entry[], o: Entry[], t: Entry[]) => Entry[] | null;
  mergeTexts: (b: string, o: string, t: string) => { text: string; conflicts: number };
};
const scriptUrl: string = new URL(`file://${script}`).href;
const driver = (await import(scriptUrl)) as Driver;

type Golden = { name: string; base: Entry[]; ours: Entry[]; theirs: Entry[]; rows: Row[]; merged: Entry[] | null };
const golden: Golden[] = readFileSync(join(repo, "packages", "contracts", "golden", "ops", "ledger-merge.jsonl"), "utf8")
  .split("\n").filter((l) => l !== "").map((l) => JSON.parse(l) as Golden);

describe("merge-ledger.mjs reproduces the Lean golden (Fw.Ops.LedgerMerge)", () => {
  it("has the cases", () => expect(golden.length).toBeGreaterThanOrEqual(16));
  for (const g of golden) {
    it(g.name, () => {
      expect(driver.rows(g.base, g.ours, g.theirs)).toEqual(g.rows);
      expect(driver.merge(g.base, g.ours, g.theirs)).toEqual(g.merged);
    });
  }
});

type NoteKeyGolden = { name: string; notes: { entry: string; task: string; field: string }[]; dups: NoteKey[]; onePerKey: boolean };
const noteKeyGolden: NoteKeyGolden[] = readFileSync(join(repo, "packages", "contracts", "golden", "ops", "ledger-note-key.jsonl"), "utf8")
  .split("\n").filter((l) => l !== "").map((l) => JSON.parse(l) as NoteKeyGolden);

describe("one note per (entry, task) reproduces the Lean golden (onePerKey, dupKeys; inc-ledger-note-key-dup)", () => {
  it("has both refused incident cases and a passing case", () => {
    expect(noteKeyGolden.filter((g) => g.name.startsWith("refused: combo-scroll-fight") || g.name.startsWith("refused: commission-band-mech")).map((g) => g.onePerKey)).toEqual([false, false]);
    expect(noteKeyGolden.some((g) => g.onePerKey && g.notes.length > 0)).toBe(true);
  });
  for (const g of noteKeyGolden) {
    it(g.name, () => {
      expect(noteKeyDups(g.notes)).toEqual(g.dups);
      expect(onePerKey(g.notes)).toBe(g.onePerKey);
      const r = noteKeyRefusal(LEDGER_FILE, g.notes);
      if (g.onePerKey) expect(r).toBeNull();
      else for (const d of g.dups) expect(r).toContain(`note:${JSON.stringify([d.entry, d.task])}: `);
    });
  }
  it("the real findings ledger passes the dry land's check", () => expect(ledgerNoteKeyCheck(repo)).toBeNull());
});

const ledgers = ["docs/team/incidents/ledger.json", "research/findings/ledger.json", "research/mistakes/ledger.json"];

describe("the real ledgers keep their formatting", () => {
  for (const p of ledgers) {
    it(`${p}: merge(x, x, x) is x byte for byte`, () => {
      const t = readFileSync(join(repo, p), "utf8");
      expect(driver.mergeTexts(t, t, t)).toEqual({ text: t, conflicts: 0 });
    });
  }
});

describe("findings notes keyed by (entry, task) (inc-findings-shared-entry; Lean distinct_notes_merge)", () => {
  type Finding = Entry & { candidate: string; part: string; mechanism: string };
  type Note = { entry: string; task: string; field: string; text: string };
  const p = "research/findings/ledger.json";
  const text = readFileSync(join(repo, p), "utf8");
  const doc = JSON.parse(text) as { findings: Finding[]; notes: Note[] };
  const render = (d: unknown) => JSON.stringify(d, null, 1);

  it("every note names a finding by its candidate, carries task, field and text, and the keys are distinct", () => {
    const candidates = new Set(doc.findings.map((f) => f.candidate));
    const fields = new Set(Object.keys(doc.findings[0]!));
    const keys = new Set<string>();
    for (const n of doc.notes) {
      expect(Object.keys(n).sort()).toEqual(["entry", "field", "task", "text"]);
      expect(candidates.has(n.entry), n.entry).toBe(true);
      expect(fields.has(n.field), n.field).toBe(true);
      expect(n.text.length).toBeGreaterThan(0);
      keys.add(JSON.stringify([n.entry, n.task]));
    }
    expect(keys.size).toBe(doc.notes.length);
  });

  const hero = doc.findings.find((f) => f.part === "hero.exit")!;
  const note = (task: string): Note => ({ entry: hero.candidate, task, field: "mechanism", text: `${task} adds a fact` });

  it("two tasks each append a note to hero.exit: merged cleanly, both notes kept", () => {
    const a = render({ ...doc, notes: [...doc.notes, note("task-a")] });
    const b = render({ ...doc, notes: [...doc.notes, note("task-b")] });
    const r = driver.mergeTexts(text, a, b);
    expect(r.conflicts).toBe(0);
    expect(JSON.parse(r.text)).toEqual({ ...doc, notes: [...doc.notes, note("task-a"), note("task-b")] });
  });

  it("two tasks each rewrite hero.exit's shared mechanism: one conflict (the incident)", () => {
    const edit = (s: string) => render({ ...doc, findings: doc.findings.map((f) => (f === hero ? { ...f, mechanism: `${f.mechanism} ${s}` } : f)) });
    expect(driver.mergeTexts(text, edit("a"), edit("b")).conflicts).toBe(1);
  });
});

describe("the 2026-10-18 land conflict in a scratch repo", () => {
  const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith("GIT_")));
  // gc.auto=0 and maintenance.auto=false: git starts no detached background writer in a scratch repo.
  const gitIn = (dir: string, ...a: string[]) =>
    spawnSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false",
      "-c", "gc.auto=0", "-c", "maintenance.auto=false", ...a], { cwd: dir, encoding: "utf8", env });
  const okIn = (dir: string, ...a: string[]) => { const r = gitIn(dir, ...a); expect(r.status, r.stderr).toBe(0); return r.stdout; };
  const path = "docs/team/incidents/ledger.json";
  const real = JSON.parse(readFileSync(join(repo, path), "utf8")) as { incidents: Entry[] };
  const n = real.incidents.length;
  const doc = (incidents: Entry[]) => JSON.stringify({ ...real, incidents }, null, 1) + "\n";
  const base = real.incidents.slice(0, n - 2);
  const [x, y] = [real.incidents[n - 2]!, real.incidents[n - 1]!];

  /** Fresh history in `dir`: main = base ledger; branch a appends x, branch b appends y (or edits, via the callbacks). */
  const populate = (dir: string, a: Entry[], b: Entry[], driverOn: boolean) => {
    const ok = (...c: string[]) => okIn(dir, ...c);
    const file = join(dir, path);
    ok("init", "-q", "-b", "main");
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(join(dir, ".gitattributes"), `${path} merge=ledger\n`);
    writeFileSync(file, doc(base));
    ok("add", "-A"); ok("commit", "-qm", "base");
    ok("checkout", "-qb", "a"); writeFileSync(file, doc(a)); ok("commit", "-qam", "a");
    ok("checkout", "-q", "main"); ok("checkout", "-qb", "b"); writeFileSync(file, doc(b)); ok("commit", "-qam", "b");
    ok("checkout", "-q", "a");
    if (driverOn) ok("config", "merge.ledger.driver", `node ${script} %O %A %B`);
  };

  // The pre-fix setup, kept for the regression test: one shared dir, reset by removing .git (the remove is injectable).
  const oldSetup = (dir: string, remove: (p: string) => void, a: Entry[], b: Entry[], driverOn: boolean) => {
    remove(join(dir, ".git"));
    populate(dir, a, b, driverOn);
  };

  const made: string[] = [];
  let dir = "";
  const file = () => join(dir, path);
  const git = (...a: string[]) => gitIn(dir, ...a);
  const ok = (...a: string[]) => okIn(dir, ...a);
  /** Every setup gets its own mkdtemp directory, so no state of an earlier test can exist in it. */
  const setup = (a: Entry[], b: Entry[], driverOn: boolean) => {
    dir = mkdtempSync(join(tmpdir(), "ledger-merge-"));
    made.push(dir);
    populate(dir, a, b, driverOn);
  };
  afterEach(() => { for (const d of made.splice(0)) rmSync(d, { recursive: true, force: true }); });

  it("regression: when the reset leaves the old repo behind, the old setup fails with 'a branch named a already exists', the fresh one passes", () => {
    const shared = mkdtempSync(join(tmpdir(), "ledger-merge-old-"));
    made.push(shared);
    oldSetup(shared, (p) => rmSync(p, { recursive: true, force: true }), [...base, x], [...base, y], false);
    expect(() => oldSetup(shared, () => {}, [...base, x], [...base, y], false)).toThrow(/a branch named 'a' already exists/);
    setup([...base, x], [...base, y], false);
    expect(git("branch", "--list", "a").stdout).toContain("a");
    expect(shared).not.toBe(dir);
  });

  it("without the driver, two appends conflict (the land refusal)", () => {
    setup([...base, x], [...base, y], false);
    expect(git("merge", "-q", "--no-edit", "b").status).not.toBe(0);
    expect(readFileSync(file(), "utf8")).toContain("<<<<<<<");
  });

  it("with the driver, two appends merge cleanly to base, ours', theirs'", () => {
    setup([...base, x], [...base, y], true);
    const r = git("merge", "-q", "--no-edit", "b");
    expect(r.status, r.stderr).toBe(0);
    expect(readFileSync(file(), "utf8")).toBe(doc([...base, x, y]));
  });

  it("with the driver, one side's backfill and the other's append both survive", () => {
    const filled = base.map((e) => ({ ...e, backfilled: true }));
    setup(filled, [...base, y], true);
    expect(git("merge", "-q", "--no-edit", "b").status).toBe(0);
    expect(readFileSync(file(), "utf8")).toBe(doc([...filled, y]));
  });

  it("with the driver, the same incident edited differently is a conflict with markers", () => {
    const first = base[0]!;
    setup([{ ...first, title: "ours" }, ...base.slice(1)], [{ ...first, title: "theirs" }, ...base.slice(1)], true);
    expect(git("merge", "-q", "--no-edit", "b").status).not.toBe(0);
    const t = readFileSync(file(), "utf8");
    expect(t).toContain('<<<<<<< ours\n  {\n   "id": ' + JSON.stringify(first.id));
    expect(t).toContain('"title": "theirs"');
    expect(ok("diff", "--name-only", "--diff-filter=U").trim()).toBe(path);
  });
});
