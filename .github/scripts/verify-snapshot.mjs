// Verifies the checked-out Fastwork snapshot against snapshot.lock.json before any measurement job uses it.
//   node .github/scripts/verify-snapshot.mjs [--root <repo root>] [--print]
// Checks, per tree (site, site-pretty): the file count and the git tree id (v1Pin.trees; computed here in pure
// Node, no git needed, same algorithm as git write-tree over the files: blob/tree objects, sorted entries).
// Also: the lock's own contentHash = sha256("site <tree>\nsite-pretty <tree>\n") and the id suffix.
// Glue only: it holds no measurement decision. Exit 0 = all equal, 1 = mismatch, 2 = missing file.
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, lstatSync, readlinkSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const args = process.argv.slice(2);
const root = resolve(args.includes('--root') ? args[args.indexOf('--root') + 1] : '.');
const print = args.includes('--print');
const sha1 = (...bufs) => { const h = createHash('sha1'); for (const b of bufs) h.update(b); return h.digest(); };
let files = 0;
let treeRoot = '';
// Local-only files that v1 never tracked (its .gitignore: .mirror/missing-local.txt, .mirror/chrome-profile/).
const IGNORED = new Set(['.mirror/missing-local.txt', '.mirror/chrome-profile']);

function objectId(type, body) { return sha1(Buffer.from(`${type} ${body.length}\0`), body); }
const EMPTY_TREE = objectId('tree', Buffer.alloc(0));

/** git tree id (raw 20 bytes) of directory `dir`; counts files. Directories sort as `name/`. */
function treeId(dir) {
  const ents = readdirSync(dir).filter((name) => !IGNORED.has(join(dir, name).slice(treeRoot.length + 1))).map((name) => {
    const p = join(dir, name);
    const st = lstatSync(p);
    if (st.isDirectory()) return { name, key: `${name}/`, mode: '40000', id: treeId(p) };
    files++;
    if (st.isSymbolicLink()) return { name, key: name, mode: '120000', id: objectId('blob', Buffer.from(readlinkSync(p))) };
    return { name, key: name, mode: st.mode & 0o111 ? '100755' : '100644', id: objectId('blob', readFileSync(p)) };
  }).filter((e) => !(e.mode === '40000' && e.id.equals(EMPTY_TREE))); // git stores no empty trees
  ents.sort((a, b) => Buffer.compare(Buffer.from(a.key), Buffer.from(b.key)));
  return objectId('tree', Buffer.concat(ents.map((e) => Buffer.concat([Buffer.from(`${e.mode} ${e.name}\0`), e.id]))));
}

const lockPath = join(root, 'snapshot.lock.json');
if (!existsSync(lockPath)) { console.error(`missing ${lockPath}`); process.exit(2); }
const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
let bad = 0;
const got = {};
for (const t of ['site', 'site-pretty']) {
  const dir = join(root, 'snapshot', t);
  if (!existsSync(dir)) { console.error(`missing ${dir}`); process.exit(2); }
  files = 0;
  treeRoot = dir;
  const id = treeId(dir).toString('hex');
  got[t] = id;
  const wantId = lock.v1Pin.trees[t];
  const wantFiles = lock.trees[t].files;
  const ok = id === wantId;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${t}: tree ${id} (lock ${wantId}), files ${files}`);
  // The tree id is the check. trees.<t>.files in the lock disagrees with the pinned git tree (269 files, MEASURED
  // with git ls-tree in the v1 repo), so a count difference is only a warning.
  if (files !== wantFiles) console.log(`warn ${t}: ${files} files, lock says ${wantFiles}`);
}
const contentHash = createHash('sha256').update(`site ${got.site}\nsite-pretty ${got['site-pretty']}\n`).digest('hex');
const idOk = contentHash === lock.v1Pin.contentHash && lock.snapshot === `b${lock.build}-${contentHash.slice(0, 8)}`;
if (!idOk) bad++;
console.log(`${idOk ? 'ok  ' : 'FAIL'} contentHash ${contentHash} snapshot id ${lock.snapshot}`);
if (print) console.log(JSON.stringify({ trees: got, contentHash }));
if (bad) { console.error(`snapshot does not match snapshot.lock.json (${bad} mismatch)`); process.exit(1); }
console.log(`snapshot verified: ${lock.snapshot}`);
