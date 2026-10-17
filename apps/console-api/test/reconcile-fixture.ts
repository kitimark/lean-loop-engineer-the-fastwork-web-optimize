// Throwaway git repo for reconciler / land tests: main checkout + one worktree per card branch.
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const run = (cwd: string, ...args: string[]) =>
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", ...args], { cwd, encoding: "utf8" }).trim();

export type Fixture = {
  root: string;            // main checkout (branch main)
  consoleDir: string;
  worktree(branch: string): string;
  commit(dir: string, file: string, text?: string): string;
  git(cwd: string, ...args: string[]): string;
};

export function makeRepo(): Fixture {
  const base = realpathSync(mkdtempSync(join(tmpdir(), "fw-land-")));
  const root = join(base, "main");
  mkdirSync(root);
  run(root, "init", "-q", "-b", "main");
  writeFileSync(join(root, "README"), "x\n");
  run(root, "add", "--", "README");
  run(root, "commit", "-q", "-m", "init");
  let n = 0;
  return {
    root, consoleDir: join(base, "console"),
    worktree(branch) {
      const dir = join(base, `wt-${branch.replace(/\//g, "-")}`);
      run(root, "worktree", "add", "-q", "-b", branch, dir, "main");
      return dir;
    },
    commit(dir, file, text) {
      mkdirSync(dirname(join(dir, file)), { recursive: true });
      writeFileSync(join(dir, file),text ?? `${++n}\n`);
      run(dir, "add", "--", file);
      run(dir, "commit", "-q", "-m", `change ${file} ${n}`);
      return run(dir, "rev-parse", "HEAD");
    },
    git: run,
  };
}
