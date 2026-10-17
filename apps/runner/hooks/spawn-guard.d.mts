export const ROLES: { name: string; runsAs: string; edits: boolean }[];
export const CAPS: { unnamedReadOnly: boolean };
export function request(p: Record<string, unknown>, now?: number): Record<string, unknown>;
export function fwcorePath(dir: string | null): string | null;
export function ask(bin: string | null, req: Record<string, unknown>): { decision: string; reason: string | null; [k: string]: unknown } | null;
export function record(p: Record<string, unknown>, reply: { decision: string; reason: string | null } | null, now?: number): Record<string, unknown>;
