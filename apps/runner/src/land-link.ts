import { execFileSync } from "node:child_process";
import { askCore } from "../hooks/land-guard.mjs";

export type AddedLink = { path: string; target: string };
export type LinkRefusal = AddedLink & { reason: "empty" | "absolute" | "escapes" };

const gitOut = (cwd: string, args: string[]): string =>
  execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 256 * 1024 * 1024 });

export function addedLinks(cwd: string, main: string, tip: string): AddedLink[] {
  const base = gitOut(cwd, ["merge-base", main, tip]).trim();
  const raw = gitOut(cwd, ["diff", "--raw", "-z", "--no-renames", "--no-ext-diff", "--diff-filter=AMT", base, tip]).split("\0");
  const out: AddedLink[] = [];
  for (let i = 0; i + 1 < raw.length; i += 2) {
    const m = /^:(\d+) (\d+) \S+ (\S+) [A-Z]$/.exec(raw[i]!);
    if (m && m[2] === "120000") out.push({ path: raw[i + 1]!, target: gitOut(cwd, ["cat-file", "blob", m[3]!]) });
  }
  return out;
}

export function refusedLinks(links: AddedLink[]): { refused: LinkRefusal[] } | { error: string } {
  if (links.length === 0) return { refused: [] };
  const r = askCore("ops.landLink", { links });
  if (!r || !Array.isArray(r.refused)) return { error: "fwcore is not available to decide (build lean/.lake)" };
  return { refused: r.refused as LinkRefusal[] };
}

export function linkRefusal(cwd: string, main: string, tip: string, branch: string): string | null {
  let links: AddedLink[];
  try { links = addedLinks(cwd, main, tip); } catch (e) { return `land-link: git could not list the links of ${branch}: ${String((e as { stderr?: string }).stderr ?? e).trim().slice(0, 200)}`; }
  const r = refusedLinks(links);
  if ("error" in r) return `land-link: ${r.error}`;
  if (r.refused.length === 0) return null;
  return `land-link: ${main}..${branch} adds symlinks whose target leaves the worktree (incident inc-scratch-symlink-wait):${r.refused.map((l) => `\n  ${l.path} -> ${l.target} (${l.reason})`).join("")}\nremove the link (git rm), and keep scratch files in scratchpad/<agent-name>/ copied, not linked`;
}
