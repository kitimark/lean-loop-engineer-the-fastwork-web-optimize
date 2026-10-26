import json, os, sys
base = os.path.dirname(os.path.abspath(__file__))
rows = {}
for f in ('survey1.txt', 'survey2.txt', 'survey3.txt'):
    for l in open(os.path.join(base, f)):
        try:
            r = json.loads(l)
        except Exception:
            continue
        rows[str(r['job'])] = r
rows = list(rows.values())
print('jobs', len(rows))
from collections import Counter
print(Counter(r['concl'] for r in rows))
runs = sorted({r['run'] for r in rows})
print('runs', len(runs), runs[0], runs[-1])
for c in ('success', 'failure'):
    rs = [r for r in rows if r['concl'] == c]
    mx = [max(max(a, b) for a, b in r['loads']) for r in rs if r['loads']]
    print(c, len(rs), 'with loads', len(mx), 'max load1', max(mx) if mx else None, 'median', sorted(mx)[len(mx)//2] if mx else None)
    for k in ('serving_proxy', 'warm', 'pass1', 'pass2', 'total'):
        v = sorted([(r[k], r['run'], r['job']) for r in rs if r.get(k) is not None], reverse=True)
        print('  ', k, 'n', len(v), 'max', v[:2])
    print('   with retries', sum(1 for r in rs if r['att'] > 0), 'of', len(rs))
out = [dict(run=r['run'], job=r['job'], concl=r['concl'], name=r['name'], att=r['att'], loadMax=(max(max(a, b) for a, b in r['loads']) if r['loads'] else None),
            startS=r['serving_proxy'], warmS=r['warm'], pass1S=r['pass1'], pass2S=r['pass2'], stepS=r['total']) for r in rows]
json.dump(out, open(os.path.join(base, 'jobs.json'), 'w'))
