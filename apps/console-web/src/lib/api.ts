import { useEffect, useState } from "react";
import { apiFetch } from "./auth";
import { LiveBoard, Command, CommandReply } from "@fw/contracts";

/** Live board over SSE. The board is a projection; the browser never holds or sets status. */
export function useBoard(): { board: LiveBoard | null; offset: number; live: boolean } {
  const [board, setBoard] = useState<LiveBoard | null>(null);
  const [offset, setOffset] = useState(0);
  const [live, setLive] = useState(false);
  useEffect(() => {
    // fetch, not EventSource: an EventSource cannot send the Authorization header that carries the owner token
    const ac = new AbortController();
    const onBlock = (block: string) => {
      let ev = "message"; const data: string[] = [];
      for (const line of block.split("\n")) {
        if (line.startsWith("event:")) ev = line.slice(6).trim();
        else if (line.startsWith("data:")) data.push(line.slice(5).replace(/^ /, ""));
      }
      if (ev !== "board" || data.length === 0) return;
      const b = LiveBoard.parse(JSON.parse(data.join("\n")));
      setBoard(b);
      setOffset(b.now - Date.now()); // server clock minus local clock
    };
    void (async () => {
      while (!ac.signal.aborted) {
        try {
          const r = await apiFetch("/api/stream", { signal: ac.signal, headers: { accept: "text/event-stream" } });
          if (r.status === 401) { setLive(false); window.location.assign("/owner/login"); return; }
          if (!r.ok || !r.body) throw new Error(`stream ${r.status}`);
          setLive(true);
          const reader = r.body.getReader(); const dec = new TextDecoder(); let buf = "";
          for (;;) {
            const { done, value } = await reader.read();
            if (done) break;
            buf += dec.decode(value, { stream: true });
            for (let i = buf.indexOf("\n\n"); i >= 0; i = buf.indexOf("\n\n")) { onBlock(buf.slice(0, i)); buf = buf.slice(i + 2); }
          }
        } catch { /* aborted or dropped: retry below */ }
        if (ac.signal.aborted) return;
        setLive(false);
        await new Promise((res) => setTimeout(res, 3000));
      }
    })();
    return () => ac.abort();
  }, []);
  return { board, offset, live };
}

/** A fresh key per click, so a retried request is idempotent but two clicks are two commands. */
export async function sendAsUser(partial: Record<string, unknown>): Promise<CommandReply> {
  const cmd = Command.parse({ ...partial, actor: "user", key: `web:${crypto.randomUUID()}` });
  const r = await apiFetch("/api/commands", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(cmd) });
  return CommandReply.parse(await r.json());
}

export function useNow(offset: number): number {
  const [t, setT] = useState(() => Date.now() + offset);
  useEffect(() => {
    const id = setInterval(() => setT(Date.now() + offset), 1000);
    return () => clearInterval(id);
  }, [offset]);
  return t;
}

export const age = (ms: number): string => {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  return `${(s / 3600).toFixed(1)}h`;
};
