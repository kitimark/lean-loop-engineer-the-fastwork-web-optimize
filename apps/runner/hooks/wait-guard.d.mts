export function request(p: Record<string, unknown>): { op: string; cmd: string } | null;
export function modeOf(dir: string | null, env?: Record<string, string | undefined>): "enforce" | "shadow" | "off";
export function message(reply: { reason: string | null; shape?: string | null }): string;
export function verdict(mode: string, reply: { decision: string; reason: string | null; shape?: string | null } | null): { hookSpecificOutput: { hookEventName: string; permissionDecision: string; permissionDecisionReason: string } } | null;
export function record(p: Record<string, unknown>, reply: { decision: string; reason: string | null; shape?: string | null } | null, now?: number): Record<string, unknown>;
