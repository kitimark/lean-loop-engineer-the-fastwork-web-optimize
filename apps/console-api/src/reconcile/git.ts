// Thin git I/O for the reconciler. No decisions here: it only lists refs and ancestry.
import { execFileSync } from "node:child_process";

export const git = (cwd: string, args: string[]): string =>
  execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

export type Ref = { ref: string; sha: string };

/** All local branches (main checkout and every worktree share the one ref store). */
export function branches(repo: string): Ref[] {
  const out = git(repo, ["for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads"]);
  return out.split("\n").filter(Boolean).map((l) => {
    const [ref, sha] = l.split(" ");
    return { ref: ref!, sha: sha! };
  });
}

/** Commits reachable from `tip` and not from `base`, oldest first. */
export function commitsAhead(repo: string, base: string, tip: string): string[] {
  const out = git(repo, ["rev-list", "--reverse", `${base}..${tip}`]);
  return out ? out.split("\n") : [];
}

export function isAncestor(repo: string, sha: string, of: string): boolean {
  try { execFileSync("git", ["merge-base", "--is-ancestor", sha, of], { cwd: repo, stdio: "ignore" }); return true; }
  catch { return false; }
}
