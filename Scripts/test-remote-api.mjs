import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

// Run only against an isolated smoke-test profile, never a production server.
const base = process.env.CONTROLLARR_TEST_URL ?? 'http://127.0.0.1:18791';
let cookie = '';
async function request(path, options = {}) {
  const response = await fetch(base + path, { ...options, redirect: 'error', headers: { Cookie: cookie, ...options.headers } });
  return response;
}
async function form(path, fields) {
  return request(path, { method: 'POST', body: new URLSearchParams(fields) });
}
const unauthenticated = await request('/api/controllarr/remote');
assert.ok([401, 403].includes(unauthenticated.status));
const login = await form('/api/v2/auth/login', { username: 'admin', password: 'adminadmin' });
assert.equal(login.status, 200);
cookie = login.headers.get('set-cookie')?.split(';')[0] ?? '';
assert.ok(cookie.startsWith('SID='));
const caps = await (await request('/api/controllarr/remote')).json();
assert.equal(caps.protocol, 1);
const windows = caps.platform === 'Windows';
const key = (mac, win) => windows ? win : mac;
const settings = await (await request('/api/controllarr/settings')).json();
const name = 'RemoteSmoke-' + Date.now();
const root = settings[key('defaultSavePath', 'default_save_path')];
const category = { name, [key('savePath', 'save_path')]: root,
  [key('extractArchives', 'extract_archives')]: false,
  [key('blockedExtensions', 'blocked_extensions')]: [],
  [key('createTorrentSubfolder', 'create_torrent_subfolder')]: true };
const post = value => ({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(value) });
assert.equal((await request('/api/controllarr/categories', post(category))).status, 200);
let hash;
try {
  const torrentName = name + '.bin';
  const info = Buffer.concat([Buffer.from(`d6:lengthi16384e4:name${torrentName.length}:${torrentName}12:piece lengthi16384e6:pieces20:`), Buffer.alloc(20), Buffer.from('e')]);
  hash = createHash('sha1').update(info).digest('hex');
  const upload = new FormData();
  upload.append('torrents', new Blob([Buffer.concat([Buffer.from('d4:info'), info, Buffer.from('e')])]), 'fixture.torrent');
  upload.append('category', name);
  upload.append('contentLayout', 'Subfolder');
  upload.append('paused', 'true');
  assert.equal((await request('/api/v2/torrents/add', { method: 'POST', body: upload })).status, 200);
  let page;
  for (let i = 0; i < 30; i++) {
    page = await (await request('/api/controllarr/remote/torrents?category=' + encodeURIComponent(name))).json();
    if (page.items.length) break;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  assert.equal(page.items.length, 1);
  assert.equal(page.items[0].hash.toLowerCase(), hash);
  assert.notEqual(page.items[0].save_path, page.items[0].content_path);
  assert.equal((await form(`/api/controllarr/torrents/${hash}/repairLayout`, {})).status, 400);
  assert.equal((await form('/api/v2/torrents/reannounce', { hashes: hash })).status, 200);
  assert.equal((await form('/api/v2/torrents/pause', { hashes: hash })).status, 200);
  const events = await (await request('/api/controllarr/remote/events')).json();
  assert.equal(events.reset, true);
  const next = await (await request(`/api/controllarr/remote/events?epoch=${events.epoch}&cursor=${events.cursor}`)).json();
  assert.equal(next.reset, false);
  assert.ok(Array.isArray(next.events));
  const invalid = { ...settings, [key('webUIPort', 'web_ui_port')]: 99999 };
  assert.equal((await request('/api/controllarr/settings', post(invalid))).status, 400);
  console.log(`PASS: ${caps.platform} authenticated Remote Protocol 1, scoped intake/content paths, pagination, events, actions, repair confirmation and port validation`);
} finally {
  if (hash) await form('/api/v2/torrents/delete', { hashes: hash, deleteFiles: 'true' });
  await request('/api/controllarr/categories/' + encodeURIComponent(name), { method: 'DELETE' });
}
