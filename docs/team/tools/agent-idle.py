#!/usr/bin/env python3
"""Idle time, cache TTL and context size of every subagent/teammate in a Claude Code session.

Usage: python3 -I docs/team/tools/agent-idle.py <session-transcript-dir>/subagents [--now ISO8601]
Prints one row per agent: idle minutes since its last transcript line, the cache TTL its writes used
(5m or 1h), and its last-turn context in tokens. Verdict "respawn" when idle > TTL and context > 30k.
"""
import json, sys, glob, os
from datetime import datetime, timezone

def parse(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))

def main():
    d = sys.argv[1]
    now = datetime.now(timezone.utc)
    if "--now" in sys.argv:
        now = parse(sys.argv[sys.argv.index("--now") + 1])
    rows = []
    for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
        name, last, ctx, w5, w1 = os.path.basename(f)[6:-6], None, 0, 0, 0
        meta = f[:-6] + ".meta.json"
        if os.path.exists(meta):
            try:
                name = json.load(open(meta)).get("name") or name
            except Exception:
                pass
        for line in open(f):
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("timestamp"):
                last = o["timestamp"]
            m = o.get("message")
            u = m.get("usage") if isinstance(m, dict) else None
            if u:
                cc = u.get("cache_creation") or {}
                w5 += cc.get("ephemeral_5m_input_tokens", 0)
                w1 += cc.get("ephemeral_1h_input_tokens", 0)
                ctx = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                       + u.get("cache_creation_input_tokens", 0))
        if not last:
            continue
        ttl = 60 if w1 > w5 else 5
        idle = (now - parse(last)).total_seconds() / 60
        verdict = "respawn" if idle > ttl and ctx > 30_000 else ("resume-ok" if idle <= ttl else "resume-cheap")
        rows.append((name, idle, ttl, ctx, verdict))
    print(f"{'agent':40} {'idle_min':>8} {'ttl':>4} {'ctx_tok':>8}  verdict")
    for n, i, t, c, v in sorted(rows, key=lambda r: r[1]):
        print(f"{n[:40]:40} {i:8.1f} {t:4} {c:8}  {v}")

if __name__ == "__main__":
    main()
