export function tokens(cmd: string): string[];
export function fwArgv(cmd: string): string[] | null;
export function cmdHash(argv: string[]): string;
export type Identity =
  | { who: "lead"; role: null; actor: "lead" }
  | { who: "agent"; role: string; actor: "reviewer" | "owner" }
  | { who: "unknown"; role: null; actor: null }
  | { error: string };
export function identity(agentId: unknown, agentType: unknown): Identity;
