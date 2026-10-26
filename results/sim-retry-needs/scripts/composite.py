import json, sys

jobs = json.load(open(sys.argv[1]))
ok = [j for j in jobs if 'skip' not in j]
okTry, failTry, pass_, step = [], [], [], []
for j in ok:
    for a in j['attempts']:
        for t in a['tries']:
            if t['ok'] and a.get('tailS') is not None:
                okTry.append((t['s'] + a['tailS'], t['s'], a['tailS'], j['job']))
            elif not t['ok']:
                failTry.append((t['s'], j['job']))
        if a.get('endEl') is not None:
            pass_.append((a['endEl'] - a['startEl'], j['job']))
print('ok try + tail', sorted(okTry, reverse=True)[:4])
print('failed try', sorted(failTry, reverse=True)[:3])
print('pass attempt', sorted(pass_, reverse=True)[:3])
print('n ok tries', len(okTry), 'n attempts', sum(len(j['attempts']) for j in ok))
