// Task ci-push-render-guard: the git pre-push hook (scripts/hooks/pre-push) runs this before a `ci/*` branch leaves the machine.
// It asks the same Lean decision as `fw land` (fwcore `console.landRenderGuard`, via land.ts `renderGuard`) over
// `origin/main..<pushed sha>` and refuses a push whose range adds a media path outside snapshot/. Reads only local refs (no network).
// Pushes of any other ref (main, tags, deletions) are not decided here.
import { renderGuard } from "./land.ts";

export const CI_REF = /^refs\/heads\/ci\//;
export const BASE = "origin/main";
const ZERO = /^0+$/;

/** The REFUSED lines for a pre-push stdin (`<local ref> <local sha> <remote ref> <remote sha>` per line); empty means the push may go. */
export function ciPushRefusals(stdin: string, cwd: string, base: string = BASE): string[] {
  const out: string[] = [];
  for (const line of stdin.split("\n")) {
    const [, sha, remote] = line.trim().split(/\s+/);
    if (!sha || !remote || !CI_REF.test(remote) || ZERO.test(sha)) continue;
    const rg = renderGuard(cwd, base, sha);
    if ("error" in rg) { out.push(`REFUSED: ci push render guard: ${rg.error}`); continue; }
    if (rg.hits.length)
      out.push(`REFUSED: ci push render guard: ${base}..${remote.slice("refs/heads/".length)} (${sha.slice(0, 7)}) writes media outside snapshot/, and a later removal leaves the blob in history:${rg.hits.map((h) => `\n  ${h.path} (${h.media}) in ${h.commit}`).join("")}\nmove the other changes to a new branch from ${base} without these commits, or add the path with its reason to Fw.Land.RenderGuard.allowlist`);
  }
  return out;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const chunks: Buffer[] = [];
  for await (const c of process.stdin) chunks.push(c as Buffer);
  const refused = ciPushRefusals(Buffer.concat(chunks).toString("utf8"), process.cwd());
  for (const l of refused) console.error(l);
  process.exit(refused.length ? 1 : 0);
}
