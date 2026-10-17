import json, glob, sys, bisect, statistics
from datetime import datetime
M=sys.argv[1]
P=lambda s: datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
writes = {}  # agent -> sorted times of status writes on rows they own or wrote
for f in glob.glob(M+'/status/*.json'):
    d=json.load(open(f))
    for e in d.get('history') or []:
        writes.setdefault(e.get('by'),[]).append(P(e['at']))
for k in writes: writes[k].sort()
ev=[]
for f in glob.glob(M+'/console/C-*.json'):
    d=json.load(open(f)); owner=d.get('by')
    for e in d.get('history') or []:
        if e.get('who')=='user' and e.get('action') in ('answer','skip') and owner!='lead':
            ev.append(('step', owner, P(e['at']))); 
            if e.get('action')!='done': pass
for f in glob.glob(M+'/console/proposals/PR-*.json'):
    d=json.load(open(f)); owner=d.get('by') or d.get('author')
    for e in d.get('history') or []:
        if e.get('action')=='decided': ev.append(('proposal', owner, P(e['at'])))
lags=[]; none=0; byk={'step':[], 'proposal':[]}
for k,o,t in ev:
    w=writes.get(o,[]); i=bisect.bisect_left(w,t)
    if i==len(w): none+=1; continue
    L=(w[i]-t)/60; lags.append(L); byk[k].append(L)
lags.sort()
q=lambda a,p: a[min(len(a)-1,int(p*len(a)))]
print('events',len(ev),'with a later owner write',len(lags),'never written after',none)
print('median %.1f p75 %.1f p90 %.1f min; >10min %d; >60min %d'%(statistics.median(lags),q(lags,.75),q(lags,.9),sum(1 for x in lags if x>10),sum(1 for x in lags if x>60)))
for k,a in byk.items():
    if a: a.sort(); print(k,len(a),'median %.1f p90 %.1f'%(statistics.median(a),q(a,.9)))
