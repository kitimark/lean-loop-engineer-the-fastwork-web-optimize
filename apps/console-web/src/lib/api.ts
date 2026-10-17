import { useEffect, useState } from "react";
import { LiveBoard, Command, CommandReply } from "@fw/contracts";

/** Live board over SSE. The board is a projection; the browser never holds or sets status. */
export function useBoard(): { board: LiveBoard | null; offset: number; live: boolean } {
  const [board, setBoard] = useState<LiveBoard | null>(null);
  const [offset, setOffset] = useState(0);
  const [live, setLive] = useState(false);
  useEffect(() => {
    const es = new EventSource("/api/stream");
    es.onopen = () => setLive(true);
    es.onerror = () => setLive(false); // EventSource reconnects by itself
    es.addEventListener("board", (m) => {
      const b = LiveBoard.parse(JSON.parse((m as MessageEvent<string>).data));
      setBoard(b);
      setOffset(b.now - Date.now()); // server clock minus local clock
    });
    return () => es.close();
  }, []);
  return { board, offset, live };
}

/** A fresh key per click, so a retried request is idempotent but two clicks are two commands. */
export async function sendAsUser(partial: Record<string, unknown>): Promise<CommandReply> {
  const cmd = Command.parse({ ...partial, actor: "user", key: `web:${crypto.randomUUID()}` });
  const r = await fetch("/api/commands", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(cmd) });
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
