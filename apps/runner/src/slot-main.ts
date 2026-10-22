import { SlotUsage, realDeps, slotCli } from "./slot.ts";

/** slot-waiter-light: `fw slot ...` without fw-main.ts. fw-main.ts pulls the contracts, land, ci and plan modules (about 120 MB
 *  resident); a queued `slot run` only needs slot.ts, so the entry (fw.ts) and slot-self.mjs call this instead.
 *  Same exit codes as the fw.ts slot branch: a usage error prints its message and exits 64. I/O glue, no decision. */
export async function slotMain(rest: string[], cwd: string, err: (s: string) => void = (s) => { process.stderr.write(s); }): Promise<number> {
  try {
    return await slotCli(rest, realDeps(cwd));
  } catch (e) {
    err(`${e instanceof Error ? e.message : String(e)}\n`);
    return e instanceof SlotUsage ? 64 : 1;
  }
}
