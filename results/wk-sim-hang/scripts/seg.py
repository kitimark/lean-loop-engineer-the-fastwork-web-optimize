import json, os, re, sys
from datetime import datetime

base = os.path.dirname(os.path.abspath(__file__))
logs = os.path.join(base, 'logs')
TS = re.compile(r'(\d{4}-\d\d-\d\dT[\d:.]+)Z\s(.*)')
meta = {}
for f in ('survey2.txt', 'survey3.txt'):
    p = os.path.join(base, f)
    if os.path.exists(p):
        for l in open(p):
            try:
                r = json.loads(l)
                meta[str(r['job'])] = r
            except Exception:
                pass

def ts(s):
    return datetime.strptime(s[:26], '%Y-%m-%dT%H:%M:%S.%f').timestamp()

out = []
for fn in sorted(os.listdir(logs)):
    jid = fn[:-4]
    m = meta.get(jid)
    if not m:
        continue
    evs = []
    for ln in open(os.path.join(logs, fn)):
        mm = TS.search(ln)
        if mm:
            evs.append((ts(mm.group(1)), mm.group(2).strip()))
    for i, (t, txt) in enumerate(evs):
        kind = None
        if txt.startswith('scroll attempt') and 'failed' in txt: kind = 'scroll'
        elif txt.startswith('pass attempt') and 'failed' in txt: kind = 'pass'
        elif txt.startswith('warm-up attempt') and 'failed' in txt: kind = 'warm'
        if not kind:
            continue
        # prior event time = the start of the failed attempt is unknown; segment = this failure -> success marker
        end = None
        reconnect_end = None
        for t2, x in evs[i + 1:]:
            if kind == 'scroll' and x.startswith('scroll:'): end = t2; break
            if kind == 'pass' and re.match(r'pass \d/2 written', x): end = t2; break
            if kind == 'warm' and x.startswith('warm-up 1/1'): end = t2; break
            if re.search(r'attempt \d failed', x): break
        out.append(dict(job=jid, run=m['run'], concl=m['concl'], kind=kind, seg=round(end - t) if end else None, msg=txt[:100]))
json.dump(out, open(os.path.join(base, 'segs.json'), 'w'))
for k in ('scroll', 'pass', 'warm'):
    for c in ('success', 'failure'):
        v = sorted([(o['seg'], o['run'], o['job']) for o in out if o['kind'] == k and o['concl'] == c and o['seg'] is not None], reverse=True)
        print(k, c, 'n', len(v), 'top', v[:3])
