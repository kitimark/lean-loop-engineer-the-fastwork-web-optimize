// `fw preview grant [<id>] [--arm r|o]`: ask the running console (over loopback) for a one-time inspect link on the preview port.
// Glue only: the console decides (Lean `console.previewGrant`: loopback only, single use, ten minutes; the cookie it sets opens
// preview paths for at most an hour and never /api or /owner). Prints the link and nothing else; no token reaches a log.
import { UsageError } from "./lib.ts";

export type Fetch = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{ status: number; json(): Promise<unknown> }>;

export const PREVIEW_USAGE = "usage: fw preview grant [<preview-id>] [--arm r|o]";

export async function previewCli(args: string[], base: string, doFetch: Fetch = fetch as unknown as Fetch, out: (l: string) => void = console.log): Promise<number> {
  if (args[0] !== "grant") throw new UsageError(PREVIEW_USAGE);
  const rest = args.slice(1);
  let arm: "r" | "o" = "r"; let id: string | undefined;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i]!;
    if (a === "--arm") { const v = rest[++i]; if (v !== "r" && v !== "o") throw new UsageError(PREVIEW_USAGE); arm = v; }
    else if (!a.startsWith("-") && id === undefined) id = a;
    else throw new UsageError(PREVIEW_USAGE);
  }
  const r = await doFetch(`${base}/api/preview/grant`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ...(id ? { id } : {}), arm }) });
  const j = (await r.json().catch(() => ({}))) as { ok?: boolean; url?: string; reason?: string };
  if (r.status !== 200 || !j.ok || typeof j.url !== "string") { console.error(`refused: ${j.reason ?? `status ${r.status}`}`); return 2; }
  out(j.url);
  return 0;
}
