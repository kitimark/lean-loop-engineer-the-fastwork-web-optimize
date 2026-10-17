#!/usr/bin/env python3
"""Profile the sub-agents of one Claude Code session from their transcripts (read-only, stdlib only).

Usage: python3 -I docs/team/tools/agent-profile.py <session-dir> [--out <dir>] [--json] [--top N]

<session-dir> is ~/.claude/projects/<project>/<session-id>/ (the folder holding subagents/). It reads
subagents/agent-*.jsonl (+ .meta.json) and subagents/workflows/*/agent-*.jsonl (+ journal.jsonl labels).

Per agent: wall time split into model time (api-request -> last streamed block of that request), tool
time (tool_use block -> its tool_result, minus model overlap), client overhead (short gaps) and idle
(gaps > --idle-gap seconds: waiting for messages, machine sleep) and api-wait (requests that
never got a response: retried, failed or aborted calls, counted until the next transcript line). Per tool call: name, normalised command,
duration, is_error. Aggregates per normalised command (count, total, p50, p95, max, error rate) per agent
and across all agents; retries after errors; repeated identical commands (polling / flaky loops);
permission denials; Read re-reads and big Reads; tokens (input, cache read, cache write 5m / 1h,
output), context per turn, cache writes after a gap longer than the cache TTL (expired-cache re-writes),
relative cost units (input-token equivalents: input 1, write 5m 1.25, write 1h 2, read 0.1, output 5;
per-model base prices are not applied). Home paths are replaced by ~, the bare OS username by <user>, e-mail-like strings by <email> in every output
(including the command text in calls.jsonl).
--out writes profile.json (everything) and calls.jsonl (one line per tool call) into <dir>.
--cutoff <ISO ts> ignores transcript lines stamped after it, so two runs can be compared.

Timing: results of a message with several tool_use blocks arrive only after the whole message streamed, so a call
is timed from the timestamp of the LAST tool_use block of its message.id to its tool_result; the streaming of the
sibling blocks stays model time. A result stamped before that block (tool ran during the stream) counts 0 s. permission_wait (call duration minus the tool's own durationMs) is recorded only
when the tool result carries a durationMs field; the current transcripts do not, so it is normally absent.
Commands: a chained Bash call is split into its parts (&& || ; | newlines, heredoc bodies dropped) and keyed by
its most expensive part (heavy verbs: lake, pnpm, node, docker, xcrun, ... outrank python3/sed/grep).
build_test_measure aggregates calls with a part in: lake build/exe/test, pnpm test*/determinism/census,
node host.mjs, check.sh.
Permission source: calls per permissionDecision.reasonType (rule / mode / classifier / subcommandResults / other),
and the classifier share of Bash calls. Cache TTL: per agent the 5m vs 1h cache-write token mix. The lead's main
transcript (<session-dir>.jsonl) is profiled as "lead" (kept out of the agent totals; shown under res["lead"]).
Parent: the agent whose transcript holds the tool_use that spawned it (.meta.json toolUseId); the "parent" field is
null when that tool_use is not in any profiled transcript, and deeper nesting is then not attributable.
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
USER = os.path.basename(HOME)
IDLE_GAP = 60.0  # s; gaps longer than this with no request or tool running count as idle
TRIVIAL = {"cd", "export", "set", "source", ".", "echo", "printf", "cat", "ls", "head", "tail", "wc", "grep",
           "rg", "sed", "awk", "sort", "uniq", "tr", "cut", "true", "false", "test", "[", "pwd", "which",
           "command", "xargs", "tee", "date", "basename", "dirname", "jq", "column", "nl", "diff", "file",
           "stat", "mkdir", "rm", "cp", "mv", "touch", "find", "env", "type", "shasum", "realpath", "readlink"}
MULTI = {"pnpm", "npm", "yarn", "bun", "npx", "git", "lake", "docker", "xcrun", "gh", "brew", "elan", "cargo",
         "pnpx", "serena", "uv", "uvx", "pip", "pip3", "launchctl", "defaults", "simctl", "lean", "corepack"}
ARGFLAGS = {"-C", "--dir", "--filter", "-F", "--prefix", "-w", "--workspace", "-c", "--cwd", "-R"}
RUNNERS = {"node", "python", "python3", "bash", "sh", "zsh", "tsx", "ts-node", "deno", "osascript", "perl", "ruby"}
DENY_RE = re.compile(r"Permission to use .{0,80} has been denied|has been denied|permission denied|not allowed|"
                     r"denied by|was blocked|requires approval|user (?:rejected|declined)|rejected by", re.I)
HEAVY = {"lake", "pnpm", "npm", "yarn", "bun", "node", "docker", "xcrun", "cargo", "brew", "gh", "elan", "lean",
         "uv", "uvx", "npx", "pnpx", "tsx", "deno", "git"}
BTS_RE = re.compile(r"^(lake (build|exe|test)|pnpm (test|determinism|census)|node host\.mjs|(\S+ )?(\S*/)?check\.sh)")
POLL_RE = re.compile(r"(^|[;&|\s(])(sleep|until|while|wait)\b")


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def scrub(s):
    if not isinstance(s, str):
        return s
    s = re.sub(r"[\w.+-]+@[\w-]+\.[\w.]+", "<email>", s)
    s = s.replace(HOME, "~")
    s = re.sub(r"/Users/[^/\s'\"]+", "~other", s)
    s = s.replace("/Users/", "<users>/")
    if len(USER) >= 3:
        s = re.sub(r"(?<![\w])" + re.escape(USER) + r"(?![\w])", "<user>", s)
    s = re.sub(r"(?:/private)?/tmp/claude-\d+/[^/\s'\"]+/[0-9a-f-]{36}/scratchpad", "<scratch>", s)
    s = re.sub(r"(?:/private)?/tmp/claude-\d+/[^\s'\"]*", "<tmp>", s)
    s = re.sub(r"~/\.claude/projects/[^/\s'\"]+", "<projects>", s)
    s = re.sub(r"~/source/[^/\s'\"]+/\.claude/worktrees/[^/\s'\"]+", "<wt>", s)
    s = re.sub(r"~/source/[^/\s'\"]+", "<repo>", s)
    return re.sub(r"[\w.+-]+@[\w-]+\.[\w.]+", "<email>", s)


def pct(xs, p):
    if not xs:
        return 0.0
    xs = sorted(xs)
    k = (len(xs) - 1) * p / 100.0
    lo = int(k)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def split_segments(cmd):
    """Split a shell command on && || ; | and newlines, outside quotes (heredoc bodies are dropped)."""
    out, cur, q, i = [], [], None, 0
    lines = cmd.split("\n")
    # drop heredoc bodies: after a line containing <<'EOF' / <<EOF skip until the terminator
    keep, term = [], None
    for ln in lines:
        if term is not None:
            if ln.strip() == term:
                term = None
            continue
        keep.append(ln)
        m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", ln)
        if m:
            term = m.group(1)
    cmd = "\n".join(keep)
    while i < len(cmd):
        c = cmd[i]
        if q:
            cur.append(c)
            if c == q:
                q = None
            elif c == "\\" and q == '"' and i + 1 < len(cmd):
                cur.append(cmd[i + 1]); i += 1
        elif c in "'\"":
            q = c; cur.append(c)
        elif c in ";\n|&":
            if c == "&" and not (i + 1 < len(cmd) and cmd[i + 1] == "&"):
                if i > 0 and cmd[i - 1] in "<>" or (i + 1 < len(cmd) and cmd[i + 1] == ">"):
                    cur.append(c); i += 1; continue
            out.append("".join(cur)); cur = []
            if i + 1 < len(cmd) and cmd[i + 1] == c:
                i += 1
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return [s.strip() for s in out if s.strip()]


def toks(seg):
    t = re.findall(r"'[^']*'|\"(?:\\.|[^\"])*\"|\S+", seg)
    t = [x.strip("'\"") for x in t]
    while t and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t[0]) or t[0] in ("time", "exec", "nice", "command",
                                                                      "(", "{", "!", "then", "do", "else")):
        t = t[1:]
    while t and t[0] in ("timeout", "gtimeout"):
        t = t[1:]
        while t and (t[0].startswith("-") or re.match(r"^\d+[smh]?$", t[0])):
            t = t[1:]
    return t


def seg_key(t):
    if not t:
        return ""
    b = os.path.basename(t[0])
    if b in MULTI:
        rest, i = [], 1
        while i < len(t):
            x = t[i]
            if x in ARGFLAGS:
                i += 2; continue
            if x.startswith("-"):
                i += 1; continue
            rest.append(x); i += 1
            if b in ("pnpm", "npm", "yarn", "bun") and rest == ["run"]:
                rest = []; continue
            if b == "lake" and rest == ["env"]:
                continue
            if b == "xcrun" and rest == ["simctl"]:
                continue
            if b in ("npx", "pnpx", "uvx") and len(rest) == 1:
                break
            if b in ("pnpm", "npm") and rest == ["exec"]:
                rest = []; continue
            break
        sub = " ".join(os.path.basename(r) for r in rest)
        return (b + " " + sub).strip()
    if b in RUNNERS:
        for x in t[1:]:
            if x.startswith("-"):
                if x in ("-c", "-e"):
                    return b + " " + x
                if x == "-":
                    return b + " <stdin>"
                continue
            if x.startswith("<"):
                return b + " <stdin>"
            return b + " " + os.path.basename(x)
        return b
    return b


def normalise(cmd):
    """Key of the first non-trivial segment; loops (for/while/until) are keyed by their body or condition."""
    keys, loop = [], False
    for sg in split_segments(cmd or ""):
        t = toks(sg)
        if t and t[0] in ("for", "select", "case"):
            loop = True; continue
        if t and t[0] in ("while", "until", "if", "elif"):
            loop = loop or t[0] in ("while", "until")
            t = t[1:]
        while t and t[0] in ("do", "then", "else", "done", "fi", "esac", "}", ")"):
            t = t[1:]
        k = seg_key(t)
        if k:
            keys.append(k)
    def rank(k):
        v = k.split(" ")[0]
        if BTS_RE.search(k):
            return 3
        if v in HEAVY:
            return 2
        return 0 if v in TRIVIAL else 1
    main = max(keys, key=rank) if keys else ""   # first among equals
    if rank(main) == 0:
        main = next((k for k in keys if k != "cd"), main)
        main = main.split(" ")[0]
    return ("loop: " if loop else "") + main, keys


def result_text(block):
    c = block.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return ""


def merge(iv):
    iv = sorted((a, b) for a, b in iv if b > a)
    out = []
    for a, b in iv:
        if out and a <= out[-1][1]:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def total(iv):
    return sum(b - a for a, b in iv)


def subtract(a_iv, b_iv):
    """a minus b, both merged."""
    out, j = [], 0
    for a, b in a_iv:
        cur = a
        for c, d in b_iv:
            if d <= cur or c >= b:
                continue
            if c > cur:
                out.append([cur, c])
            cur = max(cur, d)
        if cur < b:
            out.append([cur, b])
    return out


def load_names(sub):
    labels = {}
    for j in glob.glob(os.path.join(sub, "workflows", "*", "journal.jsonl")):
        wf = os.path.basename(os.path.dirname(j))
        for line in open(j):
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("type") == "started" and o.get("agentId"):
                labels[o["agentId"]] = (wf, o.get("label"), o.get("phase"))
    return labels


def profile_agent(path, labels, lead=False, cutoff=None):
    aid = "lead" if lead else os.path.basename(path)[6:-6]
    meta = {}
    mp = path[:-6] + ".meta.json"
    if not lead and os.path.exists(mp):
        try:
            meta = json.load(open(mp))
        except Exception:
            pass
    wf = labels.get(aid)
    name = "lead" if lead else meta.get("name") or (("wf:" + (wf[1] or aid)) if wf else None) or meta.get("description") or aid
    phase = meta.get("workflowPhase") or (wf[2] if wf else None) or "team"
    A = {"id": aid, "name": name, "agentType": meta.get("agentType"), "phase": phase,
         "workflow": wf[0] if wf else None, "description": scrub(meta.get("description")),
         "spawn_tool_use": meta.get("toolUseId"), "spawn_depth": meta.get("spawnDepth"),
         "parent": meta.get("parentAgentId")}

    reqs = {}          # requestRef -> {start, end, usage, model, qs}
    req_order = []
    calls = {}         # tool_use_id -> call
    call_order = []
    stamps = []
    received = 0
    perm_rejects = 0
    api_errors = 0
    first_user = None
    for line in open(path):
        try:
            o = json.loads(line)
        except Exception:
            continue
        t = o.get("type")
        s = o.get("timestamp")
        if cutoff is not None and s and ts(s) > cutoff:
            continue
        if s and t in ("user", "assistant", "attachment", "api-request"):
            stamps.append(ts(s))
        if t == "api-request":
            r = reqs.setdefault(o["id"], {"start": None, "end": None, "usage": {}, "model": None})
            r["start"] = ts(s)
            r["qs"] = o.get("querySource")
            if isinstance(o.get("params"), dict):
                r["model"] = o["params"].get("model")
            req_order.append(o["id"])
        elif t == "assistant":
            m = o.get("message") or {}
            if o.get("isApiErrorMessage") or m.get("model") == "<synthetic>":
                api_errors += 1
            ref = o.get("requestRef") or m.get("id")
            r = reqs.setdefault(ref, {"start": None, "end": None, "usage": {}, "model": None})
            if ref not in req_order:
                req_order.append(ref)
            r["end"] = max(r["end"] or 0, ts(s))
            r["model"] = r["model"] or m.get("model")
            if o.get("thinkingDurationMs"):
                r["thinking_ms"] = max(r.get("thinking_ms", 0), o["thinkingDurationMs"])
            u = m.get("usage") or {}
            cc = u.get("cache_creation") or {}
            for k, v in (("input", u.get("input_tokens")), ("read", u.get("cache_read_input_tokens")),
                         ("write", u.get("cache_creation_input_tokens")),
                         ("w5m", cc.get("ephemeral_5m_input_tokens")), ("w1h", cc.get("ephemeral_1h_input_tokens")),
                         ("output", u.get("output_tokens"))):
                if isinstance(v, int):
                    r["usage"][k] = max(r["usage"].get(k, 0), v)
            for b in m.get("content") or []:
                if b.get("type") == "tool_use":
                    inp = (o.get("wireToolInputs") or {}).get(b["id"]) or b.get("input") or {}
                    if not isinstance(inp, dict):
                        inp = {}
                    c = {"id": b["id"], "tool": b.get("name"), "start": ts(s), "end": None, "is_error": False,
                         "denied": False, "agent": name, "msg": m.get("id") or ref}
                    if b.get("name") in ("Bash", "bash"):
                        cmd = inp.get("command") or ""
                        c["cmd"] = scrub(cmd)[:400]
                        c["norm"], c["segs"] = normalise(cmd)
                        c["norm"] = scrub(c["norm"])
                        c["background"] = bool(inp.get("run_in_background"))
                        c["poll"] = bool(POLL_RE.search(cmd))
                        c["key"] = "Bash: " + (c["norm"] or "?")
                        c["bts"] = any(BTS_RE.search(k) for k in c["segs"])
                    elif b.get("name") == "Read":
                        c["path"] = scrub(inp.get("file_path"))
                        c["key"] = "Read"
                    else:
                        c["key"] = b.get("name")
                        if b.get("name") in ("Edit", "Write"):
                            c["path"] = scrub(inp.get("file_path"))
                    calls[b["id"]] = c
                    call_order.append(b["id"])
        elif t == "user":
            m = o.get("message") or {}
            content = m.get("content")
            pdn = o.get("permissionDecision") or {}
            if isinstance(content, str) or (isinstance(content, list) and not any(
                    isinstance(b, dict) and b.get("type") == "tool_result" for b in content)):
                if first_user is None:
                    first_user = ts(s)
                else:
                    received += 1
            if isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict) or b.get("type") != "tool_result":
                        continue
                    c = calls.get(b.get("tool_use_id"))
                    if not c:
                        continue
                    c["end"] = ts(s)
                    c["is_error"] = bool(b.get("is_error"))
                    c["perm"] = (pdn.get("decision", "") + ":" + str(pdn.get("source", "")) + ":" +
                                 str(pdn.get("reasonType", ""))) if pdn else None
                    c["reason"] = pdn.get("reasonType") if pdn else None
                    txt = result_text(b)
                    if pdn.get("decision") == "reject":
                        perm_rejects += 1
                        c["denied"] = True
                    elif c["is_error"] and DENY_RE.search(txt[:600]):
                        c["denied"] = True
                    if c["is_error"]:
                        c["err"] = scrub(txt[:200])
                    tur = o.get("toolUseResult")
                    if c["tool"] == "Read" and isinstance(tur, dict) and isinstance(tur.get("file"), dict):
                        f = tur["file"]
                        c["lines"] = f.get("numLines")
                        c["bytes"] = len(f.get("content") or "")
                        c["totalLines"] = f.get("totalLines")
                    if isinstance(tur, dict):
                        tm = tur.get("durationMs", tur.get("duration_ms"))
                        if isinstance(tm, (int, float)):
                            c["tool_ms"] = tm
                    if isinstance(tur, dict) and tur.get("backgroundTaskId"):
                        c["background"] = True
                    if isinstance(tur, dict) and tur.get("timedOutAfterMs"):
                        c["timed_out_ms"] = tur["timedOutAfterMs"]
        elif t == "attachment":
            a = o.get("attachment") or {}
            if a.get("type") == "queued_command":
                received += 1

    # results arrive after the whole message streamed: time each call from the last tool_use block of its message
    last_blk = {}
    for c in calls.values():
        last_blk[c["msg"]] = max(last_blk.get(c["msg"], 0), c["start"])
    for c in calls.values():
        c["stream_s"] = last_blk[c["msg"]] - c["start"]
        c["start"] = last_blk[c["msg"]]

    # ---- timeline
    stamps.sort()
    wall0, wall1 = (stamps[0], stamps[-1]) if stamps else (0, 0)
    model_iv = merge([(r["start"], r["end"]) for r in reqs.values() if r["start"] and r["end"]])
    tool_iv = merge([(c["start"], c["end"]) for c in calls.values() if c["end"]])
    # api requests that never got a response (retried / failed / aborted): wait until the next transcript line
    lost = []
    for r in reqs.values():
        if r["start"] and not r["end"]:
            nxt = next((x for x in stamps if x > r["start"] + 0.01), r["start"])
            lost.append((r["start"], nxt))
    lost_iv = subtract(merge(lost), merge(model_iv + tool_iv))
    busy = merge(model_iv + tool_iv + lost_iv)
    gaps = [(busy[i][1], busy[i + 1][0]) for i in range(len(busy) - 1)]
    if busy:
        gaps = [(wall0, busy[0][0])] + gaps + [(busy[-1][1], wall1)]
    idle = sum(b - a for a, b in gaps if b - a > IDLE_GAP)
    overhead = sum(b - a for a, b in gaps if 0 < b - a <= IDLE_GAP)
    long_gaps = sorted(((b - a, a) for a, b in gaps if b - a > IDLE_GAP), reverse=True)[:5]
    A.update({
        "start": datetime.fromtimestamp(wall0, timezone.utc).isoformat() if stamps else None,
        "wall_s": wall1 - wall0, "model_s": total(model_iv),
        "tool_s": total(subtract(tool_iv, model_iv)), "overhead_s": overhead, "idle_s": idle,
        "api_unanswered": len(lost), "api_wait_s": total(lost_iv),
        "idle_gaps_min": [round(g / 60, 1) for g, _ in long_gaps],
        "messages_received": received, "api_errors": api_errors, "perm_rejects": perm_rejects,
    })

    # ---- requests / tokens
    turns = []
    prev_end = None
    tok = Counter()
    by_model = defaultdict(Counter)
    expired = []
    lat = []
    for ref in req_order:
        r = reqs[ref]
        u = r["usage"]
        if not u:
            continue
        ctx = u.get("input", 0) + u.get("read", 0) + u.get("write", 0)
        for k in ("input", "read", "write", "w5m", "w1h", "output"):
            tok[k] += u.get(k, 0)
            by_model[r.get("model") or "?"][k] += u.get(k, 0)
        st = r["start"] or r["end"]
        gap = (st - prev_end) if prev_end and st else 0
        if r["start"] and r["end"]:
            lat.append(r["end"] - r["start"])
        ttl = 3600 if u.get("w1h", 0) > u.get("w5m", 0) else 300
        if gap > ttl and u.get("write", 0) > 0.5 * ctx and ctx > 10000:
            expired.append({"gap_min": round(gap / 60, 1), "rewrite_tokens": u.get("write", 0), "ctx": ctx,
                            "ttl": "1h" if ttl == 3600 else "5m"})
        turns.append({"ctx": ctx, "gap_s": round(gap, 1), "write": u.get("write", 0), "read": u.get("read", 0)})
        prev_end = r["end"] or prev_end
    units = (tok["input"] + 1.25 * tok["w5m"] + 2 * tok["w1h"] + 1.25 * max(0, tok["write"] - tok["w5m"] - tok["w1h"])
             + 0.1 * tok["read"] + 5 * tok["output"])
    A.update({
        "requests": len(turns), "tokens": dict(tok), "tokens_by_model": {k: dict(v) for k, v in by_model.items()},
        "cost_units": units,
        "ctx_max": max((t["ctx"] for t in turns), default=0), "ctx_final": turns[-1]["ctx"] if turns else 0,
        "model_latency_p50": pct(lat, 50), "model_latency_p95": pct(lat, 95),
        "expired_cache_rewrites": expired,
        "expired_rewrite_tokens": sum(e["rewrite_tokens"] for e in expired),
        "query_sources": dict(Counter(r.get("qs") for r in reqs.values() if r.get("qs"))),
    })

    # ---- calls
    cl = [calls[i] for i in call_order]
    for c in cl:
        c["dur"] = (c["end"] - c["start"]) if c["end"] else None
        if c["dur"] is not None and c["dur"] < 0:
            c["dur"] = 0.0   # result came back while the message was still streaming (tool ran during the stream)
            c["early"] = True
        if c["dur"] is not None and c.get("tool_ms") is not None:
            c["permission_wait"] = max(0.0, c["dur"] - c["tool_ms"] / 1000.0)
    rs = Counter(c["reason"] or "none" for c in cl if c.get("perm"))
    bash = [c for c in cl if c["tool"] in ("Bash", "bash") and c.get("perm")]
    A["reason_types"] = dict(rs)
    A["bash_with_perm"] = len(bash)
    A["bash_classifier"] = sum(c["reason"] == "classifier" for c in bash)
    A["bts_s"] = sum(c["dur"] or 0 for c in cl if c.get("bts"))
    A["bts_calls"] = sum(1 for c in cl if c.get("bts"))
    A["permission_wait_s"] = (sum(c.get("permission_wait", 0) for c in cl)
                              if any("permission_wait" in c for c in cl) else None)
    w5, w1 = tok["w5m"], tok["w1h"]
    A["cache_ttl_mix"] = {"w5m": w5, "w1h": w1, "share_1h": (w1 / (w5 + w1)) if (w5 + w1) else None}
    A["tool_calls"] = len(cl)
    A["early_results"] = sum(1 for c in cl if c.get("early"))
    A["errors"] = sum(c["is_error"] for c in cl)
    A["denials"] = [{"tool": c["tool"], "cmd": c.get("cmd", "")[:160], "err": c.get("err", "")[:160]}
                    for c in cl if c["denied"]]
    # retries: same key re-run within the next 6 calls after an error
    retries = Counter()
    for i, c in enumerate(cl):
        if c["is_error"]:
            for d in cl[i + 1:i + 7]:
                if d["key"] == c["key"]:
                    retries[c["key"]] += 1
                    break
    A["retries"] = dict(retries)
    exact = Counter(c["cmd"] for c in cl if c.get("cmd"))
    A["repeated_cmds"] = [{"cmd": k[:160], "n": v} for k, v in exact.most_common() if v >= 3][:10]
    A["error_keys_3plus"] = {k: v for k, v in Counter(c["key"] for c in cl if c["is_error"]).items() if v >= 3}
    reads = Counter(c["path"] for c in cl if c["tool"] == "Read" and c.get("path"))
    A["rereads"] = [{"path": p, "n": n} for p, n in reads.most_common() if n >= 2]
    A["reread_calls"] = sum(n - 1 for n in reads.values() if n >= 2)
    A["big_reads"] = sorted([{"path": c["path"], "lines": c.get("lines"), "bytes": c.get("bytes")}
                             for c in cl if c["tool"] == "Read" and (c.get("bytes") or 0) > 40000],
                            key=lambda x: -x["bytes"])[:5]
    A["read_bytes"] = sum(c.get("bytes") or 0 for c in cl if c["tool"] == "Read")
    polls = [c for c in cl if c.get("poll")]
    A["poll_calls"] = len(polls)
    A["poll_s"] = sum(c["dur"] or 0 for c in polls)
    A["background_calls"] = sum(bool(c.get("background")) for c in cl)
    A["timeouts"] = sum(1 for c in cl if c.get("timed_out_ms"))
    return A, cl


def agg(calls):
    g = defaultdict(list)
    for c in calls:
        if c["dur"] is not None:
            g[c["key"]].append(c)
    rows = []
    for k, cs in g.items():
        d = [c["dur"] for c in cs]
        rows.append({"key": k, "count": len(cs), "total_s": sum(d), "p50_s": pct(d, 50), "p95_s": pct(d, 95),
                     "max_s": max(d), "error_rate": sum(c["is_error"] for c in cs) / len(cs),
                     "agents": [a for a, _ in Counter(c["agent"] for c in cs).most_common(4)]})
    rows.sort(key=lambda r: -r["total_s"])
    return rows


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print(__doc__); sys.exit(2)
    sess = args[0].rstrip("/")
    out = args[args.index("--out") + 1] if "--out" in args else None
    top = int(args[args.index("--top") + 1]) if "--top" in args else 15
    cutoff = ts(args[args.index("--cutoff") + 1]) if "--cutoff" in args else None
    global IDLE_GAP
    if "--idle-gap" in args:
        IDLE_GAP = float(args[args.index("--idle-gap") + 1])
    sub = os.path.join(sess, "subagents") if os.path.isdir(os.path.join(sess, "subagents")) else sess
    labels = load_names(sub)
    files = sorted(glob.glob(os.path.join(sub, "agent-*.jsonl")) +
                   glob.glob(os.path.join(sub, "workflows", "*", "agent-*.jsonl")))
    agents, allcalls = [], []
    for f in files:
        a, cl = profile_agent(f, labels, cutoff=cutoff)
        if not a["requests"] and not cl:
            continue  # empty transcript (e.g. a resumed workflow agent's placeholder)
        agents.append(a)
        allcalls.extend(cl)
    lead, owner = None, {}
    lj = (sess if sess.endswith(".jsonl") else sess) + ".jsonl"
    if os.path.isfile(lj):
        lead, lcl = profile_agent(lj, {}, lead=True, cutoff=cutoff)
        for c in lcl:
            owner[c["id"]] = "lead"
    for a, cl in ((a, [c for c in allcalls if c["agent"] == a["name"]]) for a in agents):
        for c in cl:
            owner.setdefault(c["id"], a["name"])
    for a in agents:
        a["parent"] = a["parent"] or owner.get(a["spawn_tool_use"])
        a["by_command"] = agg([c for c in allcalls if c["agent"] == a["name"]])[:12]
    overall = agg(allcalls)
    bts = [c for c in allcalls if c.get("bts")]
    bts_rows = {"calls": len(bts), "total_s": sum(c["dur"] or 0 for c in bts),
                "by_agent": dict(Counter({a["name"]: a["bts_s"] for a in agents if a["bts_s"]}).most_common(10))}
    reasons = Counter()
    for a in agents:
        reasons.update(a["reason_types"])
    bp = sum(a["bash_with_perm"] for a in agents)
    bc = sum(a["bash_classifier"] for a in agents)
    phases = defaultdict(lambda: Counter())
    for a in agents:
        p = phases[a["agentType"] or "?"]
        p["cost_units"] += a["cost_units"]; p["agents"] += 1; p["model_s"] += a["model_s"]; p["tool_s"] += a["tool_s"]
        p["api_wait_s"] += a["api_wait_s"]; p["idle_s"] += a["idle_s"]
    w5 = sum(a["cache_ttl_mix"]["w5m"] for a in agents)
    w1 = sum(a["cache_ttl_mix"]["w1h"] for a in agents)
    res = {"agents": agents, "lead": lead, "overall_by_command": overall, "build_test_measure": bts_rows,
           "permission_reasons": dict(reasons),
           "bash_classifier_share": (bc / bp) if bp else None,
           "cache_ttl_mix_subagents": {"w5m": w5, "w1h": w1, "share_1h": (w1 / (w5 + w1)) if (w5 + w1) else None},
           "by_agent_type": {k: dict(v) for k, v in phases.items()},
           "totals": {k: sum(a[k] for a in agents) for k in ("wall_s", "model_s", "tool_s", "overhead_s", "idle_s",
                                                              "tool_calls", "errors", "requests", "cost_units", "api_wait_s", "api_unanswered",
                                                              "expired_rewrite_tokens", "reread_calls", "poll_s")}}
    res = json.loads(scrub(json.dumps(res)))
    if out:
        os.makedirs(out, exist_ok=True)
        json.dump(res, open(os.path.join(out, "profile.json"), "w"), indent=1)
        with open(os.path.join(out, "calls.jsonl"), "w") as fh:
            for c in allcalls:
                fh.write(scrub(json.dumps({k: c.get(k) for k in ("agent", "tool", "key", "cmd", "path", "start", "dur", "is_error",
                                                                    "denied", "perm", "reason", "bts", "stream_s",
                                                                    "permission_wait", "background", "poll")})) + "\n")
    if "--json" in args:
        json.dump(res, sys.stdout, indent=1); return
    T = res["totals"]
    P = print
    P(f"agents {len(agents)}  calls {T['tool_calls']}  errors {T['errors']}  requests {T['requests']}")
    P(f"agent-hours: wall {T['wall_s']/3600:.1f}  model {T['model_s']/3600:.1f}  tool {T['tool_s']/3600:.1f}"
      f"  api-wait {T['api_wait_s']/3600:.1f} ({T['api_unanswered']} unanswered requests)"
      f"  overhead {T['overhead_s']/3600:.1f}  idle {T['idle_s']/3600:.1f}")
    P(f"build_test_measure: {bts_rows['calls']} calls, {bts_rows['total_s']/60:.1f} min")
    sh = res["bash_classifier_share"]
    P(f"permission reasons {res['permission_reasons']}  classifier share of Bash {'n/a' if sh is None else f'{sh*100:.1f}%'}")
    m = res["cache_ttl_mix_subagents"]
    P(f"cache-write 1h share: sub-agents {0 if m['share_1h'] is None else m['share_1h']*100:.1f}% ({m['w1h']:,} / {m['w5m']+m['w1h']:,})", end="")
    if res["lead"]:
        l = res["lead"]["cache_ttl_mix"]
        P(f"   lead {0 if l['share_1h'] is None else l['share_1h']*100:.1f}% ({l['w1h']:,} / {l['w5m']+l['w1h']:,})")
    else:
        P("   lead n/a")
    P(f"\nTop {top} time sinks (all agents)\n{'key':44} {'n':>5} {'min':>7} {'p50s':>6} {'p95s':>7} {'maxs':>7} {'err':>5}  agents")
    for r in overall[:top]:
        P(scrub(f"{r['key'][:44]:44} {r['count']:5} {r['total_s']/60:7.1f} {r['p50_s']:6.1f} {r['p95_s']:7.1f} "
                f"{r['max_s']:7.1f} {r['error_rate']*100:4.0f}%  {', '.join(r['agents'])}"))
    P(f"\n{'agent':26} {'wall m':>7} {'model':>6} {'tool':>6} {'apiW':>5} {'idle':>6} {'calls':>5} {'err':>4} "
      f"{'ctxMax':>7} {'units M':>7} {'expRW':>6}")
    for a in sorted(agents, key=lambda a: -a["wall_s"])[:top]:
        P(scrub(f"{a['name'][:26]:26} {a['wall_s']/60:7.1f} {a['model_s']/60:6.1f} {a['tool_s']/60:6.1f} "
                f"{a['api_wait_s']/60:5.1f} {a['idle_s']/60:6.1f} {a['tool_calls']:5} {a['errors']:4} {a['ctx_max']:7} "
                f"{a['cost_units']/1e6:7.2f} {len(a['expired_cache_rewrites']):6}"))


if __name__ == "__main__":
    main()
