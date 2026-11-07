// Checks for supabase/migrations/20261107130000_admin_report_media.sql.
// Isolated in-memory PGlite database shaped like production (account blocking,
// visibility, appeals, Sprint 3 chat + media + deletion, the production restriction
// function copied verbatim, reports + admin report management), then the Lift
// Restriction, Appeal Cooldown and Report Media migrations in deployment order.
// Storage is the test stub (storage.objects with RLS): reading a row as a user is what
// Supabase checks before it signs a URL for that user. Never touches Supabase.
// Run: cd tests/database && npm install && node admin_report_media_test.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const base = fileURLToPath(new URL('../../', import.meta.url));
const read = f => readFileSync(base + f, 'utf8').replace(/^\\.*$/gm, '');
const MEDIA = 'supabase/migrations/20261107130000_admin_report_media.sql';
const MEDIA_ROLLBACK = 'supabase/rollbacks/20261107130000_admin_report_media_rollback.sql';
const MEDIA_VERIFY = 'supabase/checks/20261107130000_admin_report_media_verify.sql';

const exported = read('tests/database/production_compat/05_production_definitions.sql');
const productionFn = name => exported.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\nend; \\$\\$;`))[0];

const db = new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql'));
await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;', ''));
for (const f of ['20261018_matching.sql', '20261018_condition_reviews.sql', '20261021090000_chat_reads_remove_booking.sql'])
  await db.exec(read('supabase/migrations/' + f));
await db.exec(exported.slice(exported.indexOf('begin;') + 6, exported.indexOf('CREATE OR REPLACE FUNCTION')));
for (const f of ['20261021_account_blocking.sql', '20261022_account_moderation_visibility.sql', '20261023_account_appeals.sql',
  '20261024_cancel_with_blocked_participant.sql', '20261105000000_chat_end_reactions.sql', '20261105010000_chat_reopen.sql',
  '20261105020000_chat_media_ai_consent.sql', '20261105030000_message_deletion_video.sql'])
  await db.exec(read('supabase/migrations/' + f));
await db.exec(productionFn('admin_restrict_conversation'));
await db.exec(`revoke all on function public.admin_restrict_conversation(uuid,text) from public,anon;
  grant execute on function public.admin_restrict_conversation(uuid,text) to authenticated;`);
await db.exec(read('supabase/migrations/20261105_message_reports.sql'));
await db.exec(read('supabase/migrations/20261106100000_admin_report_management.sql'));
await db.exec(read('supabase/migrations/20261107030000_appeal_and_block_fixes.sql'));

let k = 0; const uid = () => `80000000-0000-4000-8000-${String(++k).padStart(12, '0')}`;
const users = {};
async function user(name, role = 'help_seeker') {
  const id = uid(); users[name] = id;
  await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',
    [id, `${name}@t`, JSON.stringify({full_name: name, role: role === 'volunteer' ? 'volunteer' : 'help_seeker'})]);
  if (role === 'volunteer')
    await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'D','English','x','approved')", [id]);
  if (role === 'admin') await db.query("update profiles set role='admin' where id=$1", [id]);
}
async function as(name) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [users[name] ?? '']);
  if (name === 'anon') await db.exec('set role anon'); else if (name) await db.exec('set role authenticated');
}
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
let n = 0; async function check(label, f) { await f(); n++; console.log('PASS', label); }

for (const [name, role] of [['seeker', 's'], ['vol', 'volunteer'], ['seeker2', 's'], ['vol2', 'volunteer'], ['seeker3', 's'],
  ['vol3', 'volunteer'], ['seeker4', 's'], ['vol4', 'volunteer'], ['outsider', 's'], ['admin', 'admin'], ['admin2', 'admin']])
  await user(name, role);

async function conversation(s, v) {
  await as(''); return (await one("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id", [users[s], users[v]])).id;
}
const order = [];  // [message id] in the intended conversation order
async function text(req, who, body) {
  await as(who);
  const id = (await one('insert into messages(request_id,sender_id,body) values($1,$2,$3) returning id', [req, users[who], body])).id;
  order.push(id); return id;
}
const KINDS = {image: ['image/png', 'png', 128, null, 'Photo'], voice: ['audio/wav', 'wav', 32044, 1000, 'Voice message'],
  video: ['video/mp4', 'mp4', 128, null, 'Video']};
async function media(req, who, kind) {
  const [mime, ext, size, duration, body] = KINDS[kind];
  await as(who);
  const id = (await one('select gen_random_uuid() id')).id;
  const path = `${req}/${users[who]}/${id}.${ext}`;
  await db.query("insert into storage.objects(bucket_id,name,metadata) values('chat-media',$1,$2)", [path, JSON.stringify({size, mimetype: mime})]);
  await db.query(`insert into messages(id,request_id,sender_id,body,message_type,attachment_path,attachment_mime,attachment_bytes,duration_ms)
    values($1,$2,$3,$4,$5,$6,$7,$8,$9)`, [id, req, users[who], body, kind, path, mime, size, duration]);
  order.push(id); return {id, path};
}
async function fixOrder() {  // deterministic created_at in insertion order
  await as('');
  for (const [i, id] of order.entries())
    await db.query("update messages set created_at = timestamptz '2026-11-01 10:00' + $2 * interval '1 minute' where id=$1", [id, i]);
}
const report = async (who, messageId, reason = 'harassment') => {
  await as(who); await db.query('select report_maak_message($1,$2,null)', [messageId, reason]);
  await as(''); return (await one('select id from reports where message_id=$1 and reporter_id=$2', [messageId, users[who]])).id;
};
const visible = async who => { await as(who); return (await db.query("select name from storage.objects where bucket_id='chat-media' order by name")).rows.map(r => r.name); };
const canRead = async (who, path) => (await visible(who)).includes(path);
const reportMedia = async (who, id) => { await as(who); return (await one('select admin_report_media($1) m', [id])).m; };
const allTrue = async file => { await as(''); for (const [kk, v] of Object.entries(await one(read(file)))) assert.equal(v, true, `${file}: ${kk}`); };

// Conversation A: 13 messages, the reported photo is #7. #2 (-5) and #12 (+5) are inside
// the context window, #1 (-6) and #13 (+6) are outside it.
const A = await conversation('seeker', 'vol');
const farBefore = await media(A, 'vol', 'image');
const voiceIn = await media(A, 'seeker', 'voice');
for (let i = 0; i < 4; i++) await text(A, i % 2 ? 'vol' : 'seeker', `before ${i}`);
const reported = await media(A, 'vol', 'image');
for (let i = 0; i < 4; i++) await text(A, i % 2 ? 'vol' : 'seeker', `after ${i}`);
const videoIn = await media(A, 'vol', 'video');
const farAfter = await media(A, 'seeker', 'image');
// Conversation B: media but no report.
const B = await conversation('seeker2', 'vol2');
const unreported = await media(B, 'vol2', 'image');
// Conversation C: reported video later deleted for everyone; a context photo too; a text report.
const C = await conversation('seeker3', 'vol3');
const ctxC = await media(C, 'vol3', 'image');
const reportedC = await media(C, 'vol3', 'video');
const textC = await text(C, 'seeker3', 'plain text');
// Conversation D: reported voice message; the reporter's account is deleted later.
const D = await conversation('seeker4', 'vol4');
const reportedD = await media(D, 'vol4', 'voice');
await fixOrder();

const reportA = await report('seeker', reported.id);
const reportC = await report('seeker3', reportedC.id, 'spam');
const reportText = await report('vol3', textC, 'spam');
const reportD = await report('seeker4', reportedD.id);
await as('vol3');
await db.query('select delete_maak_message($1,true)', [reportedC.id]);
await db.query('select delete_maak_message($1,true)', [ctxC.id]);

const PARTICIPANTS = ['seeker', 'vol', 'seeker2', 'vol2', 'seeker3', 'vol3', 'seeker4', 'vol4', 'outsider'];
const before = {};
for (const who of [...PARTICIPANTS, 'admin']) before[who] = await visible(who);

await check('MEDIA-01 applies after Lift and Cooldown, twice; all three verify scripts true', async () => {
  assert.deepEqual(before.admin, [], 'admins had no chat-media access before');
  await as('');
  for (const f of ['20261107110000_admin_lift_restriction.sql', '20261107120000_appeal_cooldown.sql'])
    await db.exec(read('supabase/migrations/' + f));
  await db.exec(read(MEDIA)); await db.exec(read(MEDIA));
  await allTrue(MEDIA_VERIFY);
  await allTrue('supabase/checks/20261107110000_admin_lift_restriction_verify.sql');
  await allTrue('supabase/checks/20261107120000_appeal_cooldown_verify.sql');
});

await check('MEDIA-02 participant Storage access is exactly as before (every account)', async () => {
  for (const who of PARTICIPANTS) assert.deepEqual(await visible(who), before[who], who);
  assert.ok(before.seeker.includes(farBefore.path) && before.vol.includes(reported.path), 'participants still see their media');
  assert.ok(!before.seeker3.includes(reportedC.path) && !before.vol3.includes(reportedC.path), 'deleted-for-everyone stays revoked');
  assert.deepEqual(before.outsider, []);
});

await check('MEDIA-03 Admin reads the reported photo and only the ±5 context media of the open report', async () => {
  const seen = await visible('admin');
  for (const p of [reported, voiceIn, videoIn]) assert.ok(seen.includes(p.path), 'allowed');
  for (const p of [farBefore, farAfter, unreported, ctxC]) assert.ok(!seen.includes(p.path), 'denied');
});

await check('MEDIA-04 admin_report_media returns the reported item and the in-window context only', async () => {
  const m = await reportMedia('admin', reportA);
  assert.equal(m.context_media_allowed, true); assert.equal(m.conversation_exists, true);
  assert.equal(m.reported.available, true); assert.equal(m.reported.path, reported.path);
  assert.equal(m.reported.mime, 'image/png'); assert.equal(m.reported.deleted_for_everyone, false);
  assert.deepEqual(m.context.map(c => c.message_id), [voiceIn.id, videoIn.id]);
  assert.deepEqual(m.context.map(c => [c.message_type, c.mime, c.duration_ms, c.available]),
    [['voice', 'audio/wav', 1000, true], ['video', 'video/mp4', null, true]]);
  const json = JSON.stringify(m);
  for (const p of [farBefore, farAfter]) assert.ok(!json.includes(p.path), 'out-of-window path never returned');
  assert.equal((await reportMedia('admin', reportText)).reported, null, 'text report has no media');
});

await check('MEDIA-05 no Admin access to conversations without a report', async () => {
  await as('admin');
  assert.equal((await one('select can_admin_view_report_media($1) ok', [unreported.path])).ok, false);
  assert.equal(await canRead('admin', unreported.path), false);
});

await check('MEDIA-06 members, the reporter, outsiders and anonymous callers cannot use the Admin access', async () => {
  for (const who of ['seeker', 'vol', 'outsider']) {
    await as(who);
    await assert.rejects(() => db.query('select admin_report_media($1)', [reportA]), /not_allowed/);
    assert.equal((await one('select can_admin_view_report_media($1) ok', [reportedC.path])).ok, false);
  }
  assert.equal(await canRead('outsider', reported.path), false);
  await as('anon');
  await assert.rejects(() => db.query('select admin_report_media($1)', [reportA]), /permission denied/);
  await assert.rejects(() => db.query('select can_admin_view_report_media($1)', [reported.path]), /permission denied/);
  await as('admin');
  await assert.rejects(() => db.query('select maak_report_media_item($1,$2,null,true)', ['image', reported.path]), /permission denied/);
});

await check('MEDIA-07 Admin access is read-only: no upload, overwrite, delete or snapshot change', async () => {
  await as('admin');
  await assert.rejects(() => db.query("insert into storage.objects(bucket_id,name,metadata) values('chat-media',$1,'{}')",
    [`${A}/${users.admin}/${uid()}.png`]), /row-level security/);
  await assert.rejects(() => db.query("insert into storage.objects(bucket_id,name,metadata) values('chat-media',$1,'{}')",
    [reported.path]), /row-level security/);
  await db.query('delete from storage.objects where name=$1', [reported.path]);
  await assert.rejects(() => db.query("update reports set attachment_path=$1 where id=$2", [unreported.path, reportA]), /permission denied/);
  await as(''); assert.equal((await one('select count(*)::int c from storage.objects where name=$1', [reported.path])).c, 1, 'not deleted');
});

await check('MEDIA-08 forged or malformed paths are refused', async () => {
  await as('admin');
  const forged = [reported.path.toUpperCase(), reported.path.replace('.png', '.mp4'), `${A}/${users.vol}/../${reported.id}.png`,
    `${A}/${users.seeker}/${reported.id}.png`, `${B}/${users.vol}/${reported.id}.png`, reported.path + '/x', 'chat-media/' + reported.path, '', null];
  for (const p of forged) assert.equal((await one('select can_admin_view_report_media($1) ok', [p])).ok, false, String(p));
});

await check('MEDIA-09 an account that is no longer an Admin loses access immediately', async () => {
  // Admin accounts cannot be blocked (guard_account_block_target); removal of the role is the real case.
  assert.ok((await visible('admin2')).includes(reported.path), 'second admin had access');
  await as(''); await db.query("update profiles set role='help_seeker' where id=$1", [users.admin2]);
  assert.deepEqual(await visible('admin2'), []);
  await as('admin2'); await assert.rejects(() => db.query('select admin_report_media($1)', [reportA]), /not_allowed/);
});

await check('MEDIA-10 reported media deleted for everyone: Admin still sees it, participants do not, context photo hidden', async () => {
  assert.equal(await canRead('admin', reportedC.path), true);
  for (const who of ['seeker3', 'vol3']) assert.equal(await canRead(who, reportedC.path), false, who);
  assert.equal(await canRead('admin', ctxC.path), false, 'deleted context media stays hidden');
  const m = await reportMedia('admin', reportC);
  assert.equal(m.reported.available, true); assert.equal(m.reported.deleted_for_everyone, true);
  assert.equal(m.reported.message_type, 'video'); assert.equal(m.reported.mime, 'video/mp4');
  assert.deepEqual(m.context, [], 'deleted context media is not listed');
});

await check('MEDIA-11 decided report: reported media kept for audit, context media denied', async () => {
  await as('admin'); await db.query("select admin_dismiss_report($1,'Reviewed, no action needed')", [reportA]);
  assert.equal(await canRead('admin', reported.path), true);
  for (const p of [voiceIn, videoIn]) assert.equal(await canRead('admin', p.path), false);
  const m = await reportMedia('admin', reportA);
  assert.equal(m.context_media_allowed, false); assert.deepEqual(m.context, []);
  assert.equal(m.reported.available, true);
  for (const who of ['seeker', 'vol']) assert.deepEqual(await visible(who), before[who], 'participants unchanged');
});

await check('MEDIA-12 conversation deleted with an account: backend denies the orphaned file', async () => {
  assert.equal(await canRead('admin', reportedD.path), true, 'allowed while the conversation exists');
  await as(''); await db.query('delete from auth.users where id=$1', [users.seeker4]);
  assert.equal((await one('select count(*)::int c from storage.objects where name=$1', [reportedD.path])).c, 1, 'orphan remains');
  assert.equal((await one('select count(*)::int c from reports where id=$1', [reportD])).c, 1, 'report remains');
  assert.equal(await canRead('admin', reportedD.path), false);
  const m = await reportMedia('admin', reportD);
  assert.equal(m.conversation_exists, false); assert.equal(m.reported.available, false);
  assert.equal(m.reported.path, null); assert.equal(m.reported.unavailable_reason, 'conversation_deleted');
  assert.deepEqual(m.context, []);
});

await check('MEDIA-13 missing file and unsupported type are reported, never a path', async () => {
  await as(''); await db.query('delete from storage.objects where name=$1', [reportedC.path]);
  const m = await reportMedia('admin', reportC);
  assert.equal(m.reported.available, false); assert.equal(m.reported.unavailable_reason, 'file_missing'); assert.equal(m.reported.path, null);
  await as('');
  const gif = (await one("select maak_report_media_item('image',$1,null,true) i", [`${C}/${users.vol3}/${uid()}.gif`])).i;
  assert.equal(gif.unavailable_reason, 'unsupported'); assert.equal(gif.path, null);
  const wrongKind = (await one("select maak_report_media_item('voice',$1,null,true) i", [reported.path])).i;
  assert.equal(wrongKind.unavailable_reason, 'unsupported');
});

await check('MEDIA-14 rollback removes only the Admin access; re-apply restores it', async () => {
  await as(''); await db.exec(read(MEDIA_ROLLBACK)); await db.exec(read(MEDIA_ROLLBACK));
  assert.deepEqual(await visible('admin'), []);
  for (const who of ['seeker', 'vol', 'seeker2', 'vol2', 'outsider']) assert.deepEqual(await visible(who), before[who], who);
  await as('admin'); await assert.rejects(() => db.query('select admin_report_media($1)', [reportA]), /does not exist/);
  await as(''); await db.exec(read(MEDIA));
  await allTrue(MEDIA_VERIFY);
  assert.equal(await canRead('admin', reported.path), true);
});

console.log(`${n} report-media checks passed.`);
await db.close();
