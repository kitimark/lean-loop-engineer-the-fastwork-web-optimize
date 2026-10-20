import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// Canonical git mode of every file a package.json "bin" names, and of the runner entry.
// pnpm chmods bin targets to 755 on install, so a bin entry on a 100644 file flips the mode
// in whichever worktree commits with -a. The runner is run as `node apps/runner/src/fw.ts`, so it has no bin.
const CANONICAL = "100644";
const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const git = (...a: string[]) => execFileSync("git", a, { cwd: root, encoding: "utf8" });

const manifests = git("ls-files", "--", "package.json", "**/package.json").split("\n").filter(Boolean);

function binTargets(manifest: string): string[] {
  const bin = (JSON.parse(readFileSync(join(root, manifest), "utf8")) as { bin?: string | Record<string, string> }).bin;
  const rel = bin === undefined ? [] : typeof bin === "string" ? [bin] : Object.values(bin);
  return rel.map((r) => join(dirname(manifest), r));
}

const indexMode = (path: string): string | undefined => git("ls-files", "-s", "--", path).split(" ")[0] || undefined;

describe("bin target modes", () => {
  const targets = [...new Set([...manifests.flatMap(binTargets), "apps/runner/src/fw.ts"])];
  it.each(targets)("%s index mode is canonical", (t) => {
    expect(indexMode(t)).toBe(CANONICAL);
  });
});
