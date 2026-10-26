# Writes the `jobs` block of lean/Fw/Measure/SimHostGolden.lean from pieces.json.
# usage: python3 -I lean_data.py <pieces.json> <SimHostGolden.lean> [--check]
import json
import sys

src, out = sys.argv[1], sys.argv[2]
jobs = json.load(open(src))
head = 'def jobs : List Job := [\n'
rows = []
for j in jobs:
    ds = ', '.join(f"⟨.{d['kind']}, {d['at']}, {d.get('tries', 1)}⟩" for d in j['decisions'])
    rows.append(f"  ⟨{j['job']}, {j['run']}, {j['sessions']}, {j['maxTries']}, [{ds}]⟩")
block = head + ',\n'.join(rows) + '\n]\n'
text = open(out).read()
start = text.index(head)
stop = text.index('\n]\n', start) + 3
new = text[:start] + block + text[stop:]
if '--check' in sys.argv[3:]:
    if new != text:
        sys.exit(f'sim-retry data: the jobs block of {out} differs from {src}')
    print(f'sim-retry data: the jobs block of {out} is up to date ({len(jobs)} jobs)')
else:
    open(out, 'w').write(new)
