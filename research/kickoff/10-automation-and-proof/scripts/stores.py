import json, glob, collections, sys, os
M = sys.argv[1]
def hist(pattern, label, keyf=lambda e: e.get('action')):
    C = collections.Counter(); B = collections.Counter(); n=0
    for f in glob.glob(pattern):
        try: d = json.load(open(f))
        except Exception: continue
        n+=1
        for e in d.get('history') or []:
            C[keyf(e)] += 1
            b = e.get('by') or e.get('who') or '?'
            B['user' if b in ('user','<user>') else 'lead' if b=='lead' else 'agent'] += 1
    print(f'== {label}: {n} records, {sum(C.values())} history entries; by {dict(B)}'); print('  ', C.most_common(25))
hist(M+'/incidents/I-*.json', 'incidents')
hist(M+'/findings/F-*.json', 'findings')
hist(M+'/console/C-*.json', 'steps', lambda e: (e.get('who') if e.get('who') in ('user',) else 'agent') + ':' + str(e.get('action')) + (':'+e['state'] if e.get('state') else ''))
# threads and proposals
print(os.listdir(M+'/console/threads')[:5], len(os.listdir(M+'/console/threads')))
print(os.listdir(M+'/console/proposals')[:8], len(os.listdir(M+'/console/proposals')))
