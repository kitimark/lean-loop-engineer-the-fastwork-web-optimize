import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

export const SLOT_MAIN_REL = join("apps", "runner", "src", "slot-main.ts");

/** The main checkout's directory: the parent of the shared git dir, or null outside a repo. */
export function mainCheckout(cwd: string): string | null {
  try {
    const out = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    return out === "" ? null : dirname(out);
  } catch { return null; }
}

/** The slot-main.ts a caller runs: the main checkout's, else the caller's own file. */
export function resolveSlotMain(local: string, main: string | null, exists: (p: string) => boolean = existsSync): string {
  if (main === null) return local;
  const shared = join(main, SLOT_MAIN_REL);
  return exists(shared) ? shared : local;
}

export function slotMainPath(local: string, cwd: string): string {
  return resolveSlotMain(local, mainCheckout(cwd));
}
