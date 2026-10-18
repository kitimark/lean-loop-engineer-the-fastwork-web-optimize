export type Tok = string | { redir: true } | { stop: true };
export function lex(cmd: string): Tok[];
export function cmdWords(toks: Tok[]): string[];
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
  | { decision: "noMint"; reason: "notFwPrefix" | "unknownActor"; error?: string };
export function decideCap(agentId: unknown, agentType: unknown, toks: string[]): CapDecision;
export function mentionsFw(cmd: string): boolean;
export const reasonText: Record<"notFwPrefix" | "unknownActor", string>;
export function identity(agentId: unknown, agentType: unknown): Identity;
