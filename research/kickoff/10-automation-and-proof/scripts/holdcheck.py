import json, glob, sys
from datetime import datetime
M=sys.argv[1]; P=lambda s: datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
holds={}
for l in open(M+'/locks/holds.log'):
    try: d=json.loads(l)
    except Exception: continue
    a=d.get('acquiredAt') or d.get('at'); b=d.get('at')
    holds.setdefault(d.get('owner'),[]).append((P(a),P(b),d.get('resource')))
tot=hit=0; wq=wqh=0
for f in glob.glob(M+'/status/*.json'):
    r=json.load(open(f)); names={r.get('owner'), r.get('id'), *(r.get('aliases') or [])}
    for e in r.get('history') or []:
        ch=e.get('changes') or {}; t=P(e['at'])
        hs=[h for n in names for h in holds.get(n,[])]
        near=any(a-1800<=t<=b+1800 for a,b,_ in hs)
        if ch.get('state') in ('measuring','testing'):
            tot+=1; hit+=near
        w=ch.get('waitingOn')
        if isinstance(w,dict) and w.get('kind') in ('chrome','phone'):
            wq+=1; wqh+= any(t-0<=a<=t+6*3600 for a,b,_ in hs)
print(f'measuring/testing writes {tot}; with an owner hold within 30 min {hit} ({100*hit/tot:.0f}%)')
print(f'chrome/phone wait writes {wq}; followed by an owner hold within 6 h {wqh} ({100*wqh/wq:.0f}%)')
