import json, glob, collections, sys, re
M = sys.argv[1]
C = collections.Counter()
for f in glob.glob(M+'/incidents/I-*.json'):
    d = json.load(open(f))
    for e in d.get('history') or []:
        if e.get('action') == 'update': C[tuple(sorted((e.get('changes') or {}).keys()))] += 1
print('incident update key sets', C.most_common(12))
R = collections.Counter(); RC=collections.Counter()
for f in glob.glob(M+'/incidents/I-*.json'):
    d = json.load(open(f)); R[d.get('resolution')] += 1; RC[d.get('status')]+=1
print('incident resolutions', R.most_common(), RC.most_common())
# proposals
P = collections.Counter(); PB=collections.Counter()
for f in glob.glob(M+'/console/proposals/PR-*.json'):
    d = json.load(open(f))
    for e in d.get('history') or []:
        P[e.get('action')] += 1; PB['user' if e.get('by')=='user' else 'lead' if e.get('by')=='lead' else 'agent'] += 1
print('proposal history', sum(P.values()), P.most_common(), dict(PB))
# threads
T = collections.Counter(); first = collections.Counter(); catch = 0; users=0
pat = re.compile(r'\b(status|progress|catch ?up|what.?s (going on|happening)|update me|stale|out of date|not updated|still (wait|pending)|where are we|current state|which agent|who is)\b', re.I)
stale = re.compile(r'\b(stale|out of date|outdated|not updated|wrong status|still (shows|says)|already (decided|answered|done|landed))\b', re.I)
st=0
for f in glob.glob(M+'/console/threads/T-*.json'):
    d = json.load(open(f))
    for m in d.get('messages') or []:
        b = m.get('by'); T['user' if b=='user' else 'lead' if b=='lead' else 'agent'] += 1
        if b == 'user':
            users += 1
            if pat.search(m.get('text') or ''): catch += 1
            if stale.search(m.get('text') or ''): st += 1
print('thread messages', dict(T), 'user msgs', users, 'status/catch-up regex', catch, 'stale regex', st)
