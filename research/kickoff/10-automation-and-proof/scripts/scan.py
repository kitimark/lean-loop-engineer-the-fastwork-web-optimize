# Scan v1 transcripts for console-maintenance tool calls. Usage: python3 -I scan.py <projdir> <agents.json> <out.jsonl>
import json, sys, os, re, glob
proj, agentsf, outf = sys.argv[1:4]
names = {}
for a in json.load(open(agentsf)):
    names[a['file']] = (a.get('name') or ('lead' if a['kind']=='session' else '?'), a['kind'])
def role(name, kind):
    if kind == 'session': return 'lead'
    n = name.lower()
    for p, r in [('mgmt-ops','mgmt-ops'),('mgmt','mgmt-other'),('fix-','fix-owner'),('ts-','toolsmith'),('review','reviewer'),
                 ('rev-','reviewer'),('de-','design-eng'),('arch','architect'),('iphone','phone-runner'),('phone','phone-runner'),
                 ('research','research'),('rs-','research'),('bench','bench'),('desk','desk')]:
        if n.startswith(p): return r
    return 'other'
CATS = [
 ('status_write', re.compile(r'status\.mjs\s+(set|priority|seed|sync)\b')),
 ('status_read', re.compile(r'status\.mjs\s+(list|show|mine|stale|check|agent|agents|phone-next)\b|status\.mjs\s*($|[|;&>])')),
 ('progress_write', re.compile(r'console\.mjs\s+progress\s+(set|best)\b')),
 ('progress_read', re.compile(r'console\.mjs\s+progress(?!\s+(set|best))')),
 ('console_status_read', re.compile(r'console\.mjs\s+status\b')),
 ('step_runner', re.compile(r'console\.mjs\s+(post|ack|redo|reopen|cancel|answer)\b')),
 ('step_wait', re.compile(r'console\.mjs\s+wait\b')),
 ('step_read', re.compile(r'console\.mjs\s+(list|show)\b')),
 ('thread_write', re.compile(r'console\.mjs\s+thread\s+(reply|new|close|reopen|merge|unmerge|relate|assign|escalate|desk\s+set|steward\s+set|topic\s+set)\b')),
 ('thread_wait', re.compile(r'console\.mjs\s+thread\s+wait\b')),
 ('thread_read', re.compile(r'console\.mjs\s+thread\s+(list|show|lint)\b')),
 ('proposal_write', re.compile(r'console\.mjs\s+proposal\s+(post|revise|live|phone|publish|withdraw|decide|hold|unhold|revising)\b')),
 ('proposal_read', re.compile(r'console\.mjs\s+proposal\s+(list|show|wait|overdue|talk)\b')),
 ('finding_write', re.compile(r'finding\.mjs\s+(post|ack|claim|resolve)\b')),
 ('finding_read', re.compile(r'finding\.mjs\s+(list|show|wait|digest)\b')),
 ('incident_write', re.compile(r'incident\.mjs\s+(open|update|resolve)\b')),
 ('incident_read', re.compile(r'incident\.mjs\s+(list|show|wait|announce)\b')),
 ('lock_status', re.compile(r'lock\.mjs\s+status\b')),
 ('lock_repair', re.compile(r'lock\.mjs\s+repair\b')),
 ('usage', re.compile(r'usage\.mjs\b')),
 ('idle', re.compile(r'idle\.mjs\b')),
]
LEDGER = re.compile(r'(fixes/PROGRESS\.json|ops-handover\.md|PREDICTIONS\.md|fixes/FINDINGS\.md|fixes/INCIDENTS\.md|fixes/LEAD\.md|fixes/AGENT_ROLES\.md|fixes/[^/]+/README\.md|/memory/|CLAUDE\.md)')
def ledger_name(p):
    m = LEDGER.search(p)
    if not m: return None
    s = m.group(1)
    if s.startswith('fixes/') and s.endswith('/README.md') and s.count('/')==2: return 'fixes/<topic>/README.md'
    return s.strip('/')
out = open(outf, 'w')
files = glob.glob(os.path.join(proj, '*.jsonl')) + glob.glob(os.path.join(proj, '*', 'subagents', '*.jsonl'))
for fp in files:
    rel = os.path.relpath(fp, proj)
    nm, kind = names.get(rel, ('?', 'agent' if 'subagents' in rel else 'session'))
    r = role(nm, kind)
    msgs = {}  # id -> {out, cr, cw, inp, calls:[...]} ; take max usage
    results = {}
    try:
        fh = open(fp, errors='replace')
    except Exception: continue
    for line in fh:
        if '"tool_use"' not in line and '"tool_result"' not in line and '"usage"' not in line: continue
        try: d = json.loads(line)
        except Exception: continue
        t = d.get('type')
        if t == 'assistant':
            m = d.get('message', {}); mid = m.get('id') or d.get('uuid')
            u = m.get('usage') or {}
            e = msgs.setdefault(mid, {'out':0,'cr':0,'cw':0,'inp':0,'ts':d.get('timestamp'),'calls':[]})
            e['out'] = max(e['out'], u.get('output_tokens') or 0); e['cr'] = max(e['cr'], u.get('cache_read_input_tokens') or 0)
            e['cw'] = max(e['cw'], u.get('cache_creation_input_tokens') or 0); e['inp'] = max(e['inp'], u.get('input_tokens') or 0)
            for c in m.get('content') or []:
                if c.get('type') != 'tool_use': continue
                tool = c.get('name'); inp = c.get('input') or {}
                cats = []
                if tool == 'Bash':
                    cmd = inp.get('command') or ''
                    cats = [k for k, rx in CATS if rx.search(cmd)]
                    for lm in LEDGER.finditer(cmd):
                        # shell writes to ledgers (redirects, sed -i, node scripts editing) are rare; mark mention only
                        pass
                elif tool in ('Edit', 'Write', 'MultiEdit', 'NotebookEdit'):
                    ln = ledger_name(inp.get('file_path') or '')
                    if ln: cats = ['ledger_edit:' + ln]
                e['calls'].append({'id': c.get('id'), 'tool': tool, 'cats': cats})
        elif t == 'user':
            c = (d.get('message') or {}).get('content')
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get('type') == 'tool_result':
                        cc = b.get('content'); n = len(cc) if isinstance(cc, str) else sum(len(x.get('text','')) for x in cc if isinstance(x, dict)) if isinstance(cc, list) else 0
                        results[b.get('tool_use_id')] = n
    for mid, e in msgs.items():
        if not e['calls']: continue
        out.write(json.dumps({'f': rel, 'name': nm, 'role': r, 'mid': mid, 'ts': e['ts'], 'out': e['out'], 'cr': e['cr'], 'cw': e['cw'],
            'calls': [{'tool': x['tool'], 'cats': x['cats'], 'res': results.get(x['id'], 0)} for x in e['calls']]}) + '\n')
out.close()
