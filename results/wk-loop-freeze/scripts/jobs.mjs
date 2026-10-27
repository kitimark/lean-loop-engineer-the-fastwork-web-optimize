let s = '';
process.stdin.on('data', (d) => { s += d; });
process.stdin.on('end', () => {
  for (const j of JSON.parse(s).jobs) {
    if (!j.name.startsWith('sim')) continue;
    const bad = (j.steps ?? []).filter((x) => x.conclusion === 'failure').map((x) => x.name).join('; ');
    console.log(j.name.slice(-3, -1), j.status, j.conclusion, j.startedAt.slice(11, 19), j.completedAt.slice(11, 19), j.databaseId, bad);
  }
});
