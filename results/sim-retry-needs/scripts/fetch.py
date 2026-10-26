import json, os, subprocess, sys

jobs, out = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(out, 'logs'), exist_ok=True)
green = [str(r['job']) for r in json.load(open(jobs)) if r['concl'] == 'success']
n = 0
for j in green:
    p = os.path.join(out, 'logs', j + '.log')
    if os.path.exists(p) and os.path.getsize(p) > 0:
        n += 1
        continue
    r = subprocess.run(['gh', 'run', 'view', '--job', j, '--log'], capture_output=True, text=True)
    if r.returncode != 0:
        print('fail', j, r.stderr[:200])
        if '403' in r.stderr or 'rate limit' in r.stderr:
            sys.exit(3)
        continue
    open(p, 'w').write(r.stdout)
    n += 1
print('done', n, 'of', len(green))
