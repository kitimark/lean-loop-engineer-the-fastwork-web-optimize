export const VERBS: Set<string>;
export function verbOf(command: unknown): string | null;
export function record(p: Record<string, unknown>, now?: number, sessionPid?: number | null): Record<string, unknown> | null;
export function claudePid(start?: number, ps?: (pid: number) => { ppid: number; comm: string } | null): number | null;
export function notification(p: Record<string, unknown>): { type: string | null; len: number | null; tool: string | null };
export function sessionPidCached(p: Record<string, unknown>, dir: string | null, find?: () => number | null): number | null;
