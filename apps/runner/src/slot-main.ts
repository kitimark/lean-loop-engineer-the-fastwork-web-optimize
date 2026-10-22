import { SlotUsage, realDeps, slotCli } from "./slot.ts";

export async function slotMain(rest: string[], cwd: string, err: (s: string) => void = (s) => { process.stderr.write(s); }): Promise<number> {
  try {
    return await slotCli(rest, realDeps(cwd));
  } catch (e) {
    err(`${e instanceof Error ? e.message : String(e)}\n`);
    return e instanceof SlotUsage ? 64 : 1;
  }
}
