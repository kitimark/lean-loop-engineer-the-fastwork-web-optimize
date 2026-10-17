export const VERBS: Set<string>;
export function verbOf(command: unknown): string | null;
export function record(p: Record<string, unknown>, now?: number): Record<string, unknown> | null;
export function notification(p: Record<string, unknown>): { type: string | null; len: number | null; tool: string | null };
