"""Pieces of every pass attempt and every gate decision in the green job logs (step clock from the step start).
usage: pieces.py <logdir> <jobs.json> <out.json>"""
import json, os, re, sys
from datetime import datetime

logdir, jobsf, outf = sys.argv[1:4]
meta = {str(r['job']): r for r in json.load(open(jobsf))}
TS = re.compile(r'\t(\d{4}-\d\d-\d\dT[\d:.]+)Z\s?(.*)$')


def ts(s):
    return datetime.strptime(s[:26], '%Y-%m-%dT%H:%M:%S.%f').timestamp()


jobs = []
for fn in sorted(os.listdir(logdir)):
    if not fn.endswith('.log'):
        continue
    jid = fn[:-4]
    evs = []
    for ln in open(os.path.join(logdir, fn), errors='replace'):
        m = TS.search(ln.rstrip('\n'))
        if m:
            evs.append((ts(m.group(1)), m.group(2).strip()))
    iserv = next((i for i, (_, x) in enumerate(evs) if x.startswith('serving the ')), None)
    if iserv is None:
        jobs.append(dict(job=jid, run=meta.get(jid, {}).get('run'), skip='no serving line'))
        continue
    igrp = max(i for i in range(iserv) if evs[i][1].startswith('##[group]Run'))
    t0 = evs[igrp][0]
    sess = next((int(x.split(':')[1]) for _, x in evs[igrp:iserv] if re.match(r'SESSIONS: \d+$', x)), 1)
    maxTries = next((int(x.split(':')[1]) for _, x in evs[igrp:iserv] if re.match(r'FW_WK_ATTEMPTS: \d+$', x)), 2)
    att, dec, cur = [], [], None
    for t, x in evs[iserv:]:
        el = round(t - t0)
        if re.match(r'pass \d/2$', x) or x.startswith('pass attempt') and 'failed (' in x or 'past the ceiling; repeating' in x:
            if cur and cur.get('phase') == 'tail':
                cur['tailS'] = round(t - cur['scrollEnd'])
            if cur and cur.get('phase') == 'head' and 'headS' not in cur:
                cur['headS'] = round(t - cur['start'])
                cur['headFailed'] = True
            if x.startswith('pass attempt') or 'past the ceiling' in x:
                n = re.match(r'pass attempt (\d+)', x)
                dec.append(dict(kind='pass', at=el, tries=int(n.group(1)) if n else None))
            cur = dict(start=t, startEl=el, phase='head', retry=not re.match(r'pass \d/2$', x), tries=[])
            att.append(cur)
            if re.match(r'pass \d/2$', x) and x != 'pass 1/2':
                dec.append(dict(kind='tab', at=el))
        elif cur is None:
            continue
        elif x.startswith('census y='):
            cur['censusEnd'] = t
        elif x.startswith('scroll attempt') and 'failed (' in x:
            s0 = cur['tries'][-1]['end'] if cur['tries'] else cur.get('censusEnd', cur['start'])
            if 'headS' not in cur:
                cur['headS'] = round(cur.get('censusEnd', cur['start']) - cur['start'])
            cur['tries'].append(dict(s=round(t - s0), end=t, ok=False, recon=bool(len(cur['tries']))))
            dec.append(dict(kind='scroll', at=el, tries=int(re.match(r'scroll attempt (\d+)', x).group(1))))
        elif x.startswith('scroll: '):
            s0 = cur['tries'][-1]['end'] if cur['tries'] else cur.get('censusEnd', cur['start'])
            if 'headS' not in cur:
                cur['headS'] = round(cur.get('censusEnd', cur['start']) - cur['start'])
            cur['tries'].append(dict(s=round(t - s0), end=t, ok=True, recon=bool(len(cur['tries']))))
            cur['scrollEnd'] = t
            cur['phase'] = 'tail'
            dec.append(dict(kind='tab', at=el))
        elif re.match(r'seek n=\d+:', x) and not x.startswith('seek n=100:'):
            dec.append(dict(kind='tab', at=el))
        elif x.startswith('host load1 ') or re.match(r'pass \d/2 written', x) and cur.get('phase') == 'tail':
            if cur.get('phase') == 'tail':
                cur['tailS'] = round(t - cur['scrollEnd'])
            cur['endEl'] = el
            cur['phase'] = 'done'
    for a in att:
        a['tries'] = [dict(s=r['s'], ok=r['ok'], recon=r['recon']) for r in a['tries']]
        for k in ('start', 'censusEnd', 'scrollEnd', 'phase'):
            a.pop(k, None)
    jobs.append(dict(job=jid, run=meta.get(jid, {}).get('run'), sessions=sess, maxTries=maxTries, servingOffS=round(evs[iserv][0] - t0), attempts=att, decisions=dec))
json.dump(jobs, open(outf, 'w'), indent=0)
ok = [j for j in jobs if 'skip' not in j]
print('jobs', len(jobs), 'parsed', len(ok), 'skipped', [j['job'] for j in jobs if 'skip' in j])
print('sessions', sorted({j['sessions'] for j in ok}), 'maxTries', sorted({j['maxTries'] for j in ok}))


def top(vals, n=3):
    return sorted(vals, reverse=True)[:n]


heads = [(a.get('headS'), a['retry'], j['job']) for j in ok for a in j['attempts'] if a.get('headS') is not None]
print('head first', top([(h, jb) for h, r, jb in heads if not r]), 'retry', top([(h, jb) for h, r, jb in heads if r]))
tr = [(t['s'], t['recon'], j['job']) for j in ok for a in j['attempts'] for t in a['tries']]
print('scroll try first', top([(s, jb) for s, r, jb in tr if not r]), 'retry', top([(s, jb) for s, r, jb in tr if r]))
print('tail', top([(a['tailS'], j['job']) for j in ok for a in j['attempts'] if a.get('tailS') is not None]))
print('decisions', {k: sum(1 for j in ok for d in j['decisions'] if d['kind'] == k) for k in ('scroll', 'pass', 'tab')})
