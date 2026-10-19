import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const REMOTE = ["apps/runner", "apps/console-api", "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium", "packages/engine-check"];

describe("land-filter.txt (written by Lean, read by land.yml)", () => {
  const file = readFileSync(join(root, "lean/land-filter.txt"), "utf8");
  it("has one selector per Lean remote id, naming the package of that directory", () => {
    const names = REMOTE.map((d) => (JSON.parse(readFileSync(join(root, d, "package.json"), "utf8")) as { name: string }).name + "...");
    expect(file.trim().split(" ")).toEqual(names);
  });
  it("is what land.yml installs", () => {
    const yml = readFileSync(join(root, ".github/workflows/land.yml"), "utf8");
    expect(yml).toContain("cat lean/land-filter.txt");
    expect(yml).not.toMatch(/filter: '@fw/);
  });
});

describe(".github/scripts/land-base.sh", () => {
  const sh = join(root, ".github/scripts/land-base.sh");
  const git = (cwd: string, ...a: string[]) => execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", ...a], { cwd, encoding: "utf8" }).trim();
  const out = (cwd: string, w: string) => execFileSync("sh", [sh, w], { cwd, encoding: "utf8" }).trim();
  const repo = () => {
    const d = mkdtempSync(join(tmpdir(), "land-base-"));
    git(d, "init", "-q", "-b", "main");
    writeFileSync(join(d, "a"), "1");
    git(d, "add", "a");
    git(d, "commit", "-q", "-m", "m1");
    return d;
  };
  it("a probe commit: main and base are its parent", () => {
    const d = repo();
    const m = git(d, "rev-parse", "HEAD");
    writeFileSync(join(d, "a"), "2");
    git(d, "commit", "-qam", "probe");
    expect(out(d, "main")).toBe(m);
    expect(out(d, "base")).toBe(m);
  });
  it("a merge: both are the first parent, the local main it was made on", () => {
    const d = repo();
    git(d, "checkout", "-q", "-b", "side");
    writeFileSync(join(d, "b"), "1");
    git(d, "add", "b");
    git(d, "commit", "-qm", "side");
    git(d, "checkout", "-q", "main");
    writeFileSync(join(d, "c"), "1");
    git(d, "add", "c");
    git(d, "commit", "-qm", "main moves");
    const m = git(d, "rev-parse", "HEAD");
    git(d, "merge", "-q", "--no-ff", "-m", "land", "side");
    expect(out(d, "main")).toBe(m);
    expect(out(d, "base")).toBe(m);
  });
  it("an empty marker tip is skipped for both main and base", () => {
    const d = repo();
    const m = git(d, "rev-parse", "HEAD");
    writeFileSync(join(d, "a"), "2");
    git(d, "commit", "-qam", "work");
    const w = git(d, "rev-parse", "HEAD");
    git(d, "commit", "-q", "--allow-empty", "-m", "[ci:land]");
    git(d, "commit", "-q", "--allow-empty", "-m", "[ci:land] again");
    expect(out(d, "main")).toBe(m);
    expect(w).toBe(git(d, "rev-parse", "HEAD~2"));
    expect(out(d, "base")).toBe(m);
  });
  it("a single root commit: both are HEAD", () => {
    const d = repo();
    expect(out(d, "main")).toBe(git(d, "rev-parse", "HEAD"));
    expect(out(d, "base")).toBe(git(d, "rev-parse", "HEAD"));
  });
});
