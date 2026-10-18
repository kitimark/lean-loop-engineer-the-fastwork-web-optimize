export function tokens(cmd: string): string[];
export function fwArgv(cmd: string): string[] | null;
export function cmdHash(argv: string[]): string;
export type Identity =
  | { who: "lead"; role: null; actor: "lead" }
  | { who: "agent"; role: string; actor: "reviewer" | "owner" }
  | { who: "unknown"; role: null; actor: null }
  | { error: string };
export type CapDecision =
  | { decision: "mint"; actor: "lead" | "reviewer" | "owner"; argv: string[] }
  | { decision: "noMint"; reason: "notFwPrefix" | "trailingPipe" | "unknownActor"; error?: string };
export function decideCap(agentId: unknown, agentType: unknown, toks: string[]): CapDecision;
export function isRedirStub(s: string): boolean;
export function mentionsFw(cmd: string): boolean;
export const reasonText: Record<"notFwPrefix" | "trailingPipe" | "unknownActor", string>;
export function identity(agentId: unknown, agentType: unknown): Identity;
