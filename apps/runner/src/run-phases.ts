import type { Span } from "./timing.ts";
import type { Gh, WaitFn } from "./run.ts";

type Begin = (tool: string, step: string) => (exit?: number | null, extra?: Partial<Span>) => void;
type Phase = "dispatch" | "wait" | "file" | "dry";

export function runPhases(begin: Begin, dry: boolean) {
  let open: { phase: Phase; end: ReturnType<Begin> } | null = null;
  const enter = (phase: Phase) => {
    open?.end(0);
    open = { phase, end: begin("fw", `run ${phase}`) };
  };
  enter(dry ? "dry" : "dispatch");
  const isDispatch = (a: string[]) => a[0] === "workflow" && a[1] === "run";
  return {
    gh: (gh: Gh): Gh => async (a, o) => {
      if (open?.phase === "file" && isDispatch(a)) enter("dispatch");
      const r = await gh(a, o);
      if (open?.phase === "dispatch" && isDispatch(a)) enter("wait");
      return r;
    },
    wait: (wait: WaitFn): WaitFn => async (t, s) => {
      if (open?.phase === "dispatch") enter("wait");
      const w = await wait(t, s);
      if (w.code !== 3 && open?.phase === "wait") {
        const id = /^run (\d+) /.exec(w.lines[0] ?? "")?.[1];
        open.end(w.code, id ? { runId: Number(id) } : {});
        open = { phase: "file", end: begin("fw", "run file") };
      }
      return w;
    },
    finish: (exit: number) => { open?.end(exit); open = null; },
  };
}
