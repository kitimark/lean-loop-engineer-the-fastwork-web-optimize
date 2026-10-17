import json,glob,sys
from datetime import datetime,timedelta
M=sys.argv[1]
def ts(s): return datetime.fromisoformat(s.replace('Z','+00:00'))
holds={}
for l in open(M+'/locks/holds.log'):
    try: h=json.loads(l)
    except: continue
    if 'acquiredAt' not in h or 'at' not in h: continue
    holds.setdefault(h.get('owner'),[]).append((ts(h['acquiredAt']),ts(h['at'])))
W=timedelta(minutes=0)
for name,pred in [('measuring',lambda c: c.get('state') in ('measuring','testing')),('researching/implementing',lambda c: c.get('state') in ('researching','implementing','designing'))]:
  for shift in [0]:
    n=hit=0
    for f in glob.glob(M+'/status/*.json'):
        r=json.load(open(f)); ids={r.get('owner'),r.get('id')}|set(r.get('aliases') or [])
        for e in r.get('history',[]):
            if not isinstance(e,dict): continue
            c=e.get('changes') or {}
            if not pred(c): continue
            t=ts(e['at'])+timedelta(hours=shift); n+=1
            if any(a-W<=t<=b+W for i in ids for (a,b) in holds.get(i,[])): hit+=1
    print(name,'shift',shift,'h:',hit,'/',n, round(100*hit/max(n,1)),'%')
