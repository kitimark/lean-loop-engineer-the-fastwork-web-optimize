import "./land-timeout.ts";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { binDigest, buildClean, fwcorePreflight, FWCORE_BIN, storeDigest, storedDigest } from "../src/land.ts";

const git = (dir: string, args: string[]) =>
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.invalid", ...args], { cwd: dir, encoding: "utf8" }).trim();
const sha = (s: string) => createHash("sha256").update(s).digest("hex");

let dir = "";
let head = "";
const put = (rel: string, text: string) => { mkdirSync(dirname(join(dir, rel)), { recursive: true }); writeFileSync(join(dir, rel), text); };
const store = (commit: string) => join(dir, ".git", "fw-land", "fwcore-digest", commit);

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "fwdig-"));
  git(dir, ["init", "-q", "-b", "main"]);
  put(".gitignore", ".lake/\n");
  put("lean/Fw/A.lean", "def a := 1\n");
  put("scripts/fwcore-build.sh", "#!/bin/sh\n");
  git(dir, ["add", "-A"]);
  git(dir, ["commit", "-q", "-m", "init"]);
  head = git(dir, ["rev-parse", "HEAD"]);
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe("binDigest", () => {
  it("is null when the binary is missing", () => expect(binDigest(dir)).toBeNull());
  it("is the sha256 of the binary's bytes", () => {
    put(FWCORE_BIN, "bin-1");
    expect(binDigest(dir)).toBe(sha("bin-1"));
  });
});

describe("storedDigest", () => {
  it("is null with no store and no build record", () => expect(storedDigest(dir, head)).toBeNull());
  it("is null with a garbage store entry and no build record", () => {
    put(relative(dir, store(head)), "not a digest\n");
    expect(storedDigest(dir, head)).toBeNull();
  });
  it("returns what storeDigest stored for the commit", () => {
    storeDigest(dir, head, sha("x"));
    expect(storedDigest(dir, head)).toBe(sha("x"));
    expect(storedDigest(dir, "0".repeat(40))).toBeNull();
  });
  it("falls back to the build record when it names the commit and the binary has the recorded hash", () => {
    put(FWCORE_BIN, "bin-1");
    put(`${FWCORE_BIN}.commit`, `${head} ${sha("bin-1")}\n`);
    expect(storedDigest(dir, head)).toBe(sha("bin-1"));
    put(relative(dir, store(head)), "garbage\n");
    expect(storedDigest(dir, head)).toBe(sha("bin-1"));
  });
  it("is null when the build record names another commit", () => {
    put(FWCORE_BIN, "bin-1");
    put(`${FWCORE_BIN}.commit`, `${"1".repeat(40)} ${sha("bin-1")}\n`);
    expect(storedDigest(dir, head)).toBeNull();
  });
  it("is null when the binary's hash is not the recorded one", () => {
    put(FWCORE_BIN, "bin-2");
    put(`${FWCORE_BIN}.commit`, `${head} ${sha("bin-1")}\n`);
    expect(storedDigest(dir, head)).toBeNull();
  });
  it("is null when the record's hash is garbage or the binary is missing", () => {
    put(`${FWCORE_BIN}.commit`, `${head} ${sha("bin-1")}\n`);
    expect(storedDigest(dir, head)).toBeNull();
    put(FWCORE_BIN, "bin-1");
    put(`${FWCORE_BIN}.commit`, `${head} zz\n`);
    expect(storedDigest(dir, head)).toBeNull();
    put(`${FWCORE_BIN}.commit`, `${head}\n`);
    expect(storedDigest(dir, head)).toBeNull();
  });
  it("stores under the git common dir", () => {
    storeDigest(dir, head, sha("y"));
    expect(readFileSync(store(head), "utf8")).toBe(`${sha("y")}\n`);
  });
});

describe("buildClean", () => {
  it("is true on a clean tree, with an ignored binary and an untracked file outside lean/", () => {
    put(FWCORE_BIN, "bin-1");
    put("notes.txt", "x\n");
    expect(buildClean(dir)).toBe(true);
  });
  it("is false with an untracked file under lean/", () => {
    put("lean/Fw/B.lean", "def b := 2\n");
    expect(buildClean(dir)).toBe(false);
  });
  it("is false with a changed tracked Lean file", () => {
    put("lean/Fw/A.lean", "def a := 2\n");
    expect(buildClean(dir)).toBe(false);
  });
  it("is false with a changed build script", () => {
    put("scripts/fwcore-build.sh", "#!/bin/sh\necho\n");
    expect(buildClean(dir)).toBe(false);
  });
});

describe("fwcorePreflight (task land-queue-why)", () => {
  const record = (commit: string) => { put(FWCORE_BIN, "bin"); put(`${FWCORE_BIN}.commit`, `${commit} ${sha("bin")}\n`); };
  it("refuses with the named reason when there is no build record", () => expect(fwcorePreflight(dir, "main")).toBe("fwcore-stale: run sh scripts/fwcore-build.sh"));
  it("passes when the record names main's head", () => { record(head); expect(fwcorePreflight(dir, "main")).toBeNull(); });
  it("refuses when the record's binary is not the recorded one", () => { record(head); put(FWCORE_BIN, "other"); expect(fwcorePreflight(dir, "main")).toMatch(/^fwcore-stale/); });
  it("refuses after a Lean source changed, passes after a change elsewhere", () => {
    record(head);
    put("docs/a.md", "x\n"); git(dir, ["add", "-A"]); git(dir, ["commit", "-q", "-m", "docs"]);
    expect(fwcorePreflight(dir, "main")).toBeNull();
    put("lean/Fw/A.lean", "def a := 2\n"); git(dir, ["add", "-A"]); git(dir, ["commit", "-q", "-m", "lean"]);
    expect(fwcorePreflight(dir, "main")).toMatch(/^fwcore-stale/);
  });
  it("has nothing to refuse in a tree without the build script", () => {
    git(dir, ["rm", "-q", "scripts/fwcore-build.sh"]); git(dir, ["commit", "-q", "-m", "rm"]);
    expect(fwcorePreflight(dir, "main")).toBeNull();
  });
});
