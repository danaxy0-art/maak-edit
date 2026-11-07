// Checks for supabase/migrations/20261107110000_admin_lift_restriction.sql.
// Isolated in-memory PGlite database shaped like production (account blocking,
// visibility, appeals, Sprint 3 chat, the production restriction function copied
// verbatim from the production export, reports + admin report management).
// Run: cd tests/database && npm install && node restriction_lift_test.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const base = fileURLToPath(new URL('../../', import.meta.url));
const read = f => readFileSync(base + f, 'utf8').replace(/^\\.*$/gm, '');
const LIFT = 'supabase/migrations/20261107110000_admin_lift_restriction.sql';
const LIFT_ROLLBACK = 'supabase/rollbacks/20261107110000_admin_lift_restriction_rollback.sql';
const LIFT_VERIFY = 'supabase/checks/20261107110000_admin_lift_restriction_verify.sql';

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

let k = 0; const uid = () => `60000000-0000-0000-0000-${String(++k).padStart(12, '0')}`;
const ids = {admin: uid(), admin2: uid()};
const users = {};
async function user(name, role) {
  const id = uid(); users[name] = id;
  await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',
    [id, `${name}@t`, JSON.stringify({full_name: name, role: role === 'volunteer' ? 'volunteer' : 'help_seeker'})]);
  if (role === 'volunteer')
    await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'D','English','x','approved')", [id]);
  return id;
}
for (const [n, id] of Object.entries({admin: ids.admin, admin2: ids.admin2})) {
  await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)', [id, `${n}@t`, JSON.stringify({full_name: n === 'admin' ? 'Amal Admin' : 'Basma Admin', role: 'help_seeker'})]);
}
await db.query("update profiles set role='admin' where id = any($1)", [[ids.admin, ids.admin2]]);
users.admin = ids.admin; users.admin2 = ids.admin2;

async function as(name) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [users[name] ?? '']);
  if (name === 'anon') await db.exec('set role anon'); else if (name) await db.exec('set role authenticated');
}
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const rpc = async (fn, args = []) => Object.values(await one(`select ${fn}(${args.map((_, i) => `$${i + 1}`).join(',')}) as r`, args))[0];
async function conversation(s, v) {
  await as(''); return (await one("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id", [users[s], users[v]])).id;
}
const send = async (req, who, body) => { await as(who); return (await one('insert into messages(request_id,sender_id,body) values($1,$2,$3) returning id', [req, users[who], body])).id; };
const restrict = async (req, reason) => { await as('admin'); await db.query('select admin_restrict_conversation($1,$2)', [req, reason]); };
const state = async req => { await as(''); return one('select restricted_at, restricted_by, restriction_reason, ended_at, ended_by from support_requests where id=$1', [req]); };
const history = async req => { await as('admin'); return (await db.query('select admin_conversation_restriction_history($1) h', [req])).rows.map(r => r.h); };
let n = 0; async function check(label, f) { await f(); n++; console.log('PASS', label); }

for (const [name, role] of [['seeker', 's'], ['vol', 'volunteer'], ['seeker2', 's'], ['vol2', 'volunteer'], ['seeker3', 's'], ['vol3', 'volunteer'], ['outsider', 's']])
  await user(name, role);

// A conversation restricted BEFORE the migration (backfill case).
const PRE = await conversation('seeker3', 'vol3');
await send(PRE, 'vol3', 'hello'); await restrict(PRE, 'Restricted before the lift feature');

await check('LIFT-01 migration applies twice, backfills existing restrictions once, verify all true', async () => {
  await as('');
  await db.exec(read(LIFT)); await db.exec(read(LIFT));
  const ev = (await db.query("select action, reason from conversation_restriction_events where request_id=$1", [PRE])).rows;
  assert.deepEqual(ev, [{action: 'restricted', reason: 'Restricted before the lift feature'}]);
  for (const [kk, v] of Object.entries(await one(read(LIFT_VERIFY)))) assert.equal(v, true, kk);
});

// Active conversation A, restricted through the report flow (admin_end_reported_conversation).
const A = await conversation('seeker', 'vol');
await send(A, 'seeker', 'hi'); const bad = await send(A, 'vol', 'rude message');
await as('seeker'); await db.query("select report_maak_message($1,'harassment',null)", [bad]);
await as(''); const reportA = (await one('select id from reports where message_id=$1', [bad])).id;
await as('admin'); await rpc('admin_end_reported_conversation', [reportA, 'Harassment']);

await check('LIFT-02 restrictions made by the report flow are recorded with admin and reason', async () => {
  const h = await history(A);
  assert.equal(h.length, 1); assert.equal(h[0].action, 'restricted'); assert.equal(h[0].reason, 'Harassment');
  assert.equal(h[0].actor_name, 'Amal Admin'); assert.equal(h[0].actor_is_me, true);
  assert.ok(!JSON.stringify(h).includes(users.admin), 'admin UUID never returned');
});

await check('LIFT-03 members and anonymous callers cannot lift or read history', async () => {
  for (const who of ['seeker', 'vol', 'outsider']) {
    await as(who);
    await assert.rejects(() => rpc('admin_lift_conversation_restriction', [A, 'x']), /not_allowed/);
    await assert.rejects(() => db.query('select admin_conversation_restriction_history($1)', [A]), /not_allowed/);
    await assert.rejects(() => db.query('select * from conversation_restriction_events'), /permission denied/);
  }
  await as('anon');
  await assert.rejects(() => rpc('admin_lift_conversation_restriction', [A, 'x']), /permission denied/);
  assert.ok((await state(A)).restricted_at, 'still restricted');
});

await check('LIFT-04 a reason of 1-500 characters is required', async () => {
  await as('admin');
  for (const bad of [null, '', '   ', 'x'.repeat(501)])
    await assert.rejects(() => rpc('admin_lift_conversation_restriction', [A, bad]), /invalid_lift_reason/);
  assert.ok((await state(A)).restricted_at);
});

await check('LIFT-05 lifting an active chat lets both participants chat and react again', async () => {
  await as('seeker');
  await assert.rejects(() => db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3)', [A, users.seeker, 'blocked']), /row-level security|chat_closed/);
  await as('admin');
  const out = await rpc('admin_lift_conversation_restriction', [A, '  Restricted by mistake  ']);
  assert.equal(out.lifted, true); assert.equal(out.participant_ended, false);
  const s = await state(A);
  assert.equal(s.restricted_at, null); assert.equal(s.restricted_by, null); assert.equal(s.restriction_reason, null);
  assert.equal(s.ended_at, null, 'ended_at untouched');
  await send(A, 'seeker', 'thanks for lifting'); await send(A, 'vol', 'welcome back');
  await as('seeker'); await db.query("select toggle_maak_reaction($1,$2,'👍')", [A, bad]);
});

await check('LIFT-06 history keeps the restriction and the lift, with admin, reason and time', async () => {
  const h = await history(A);
  assert.deepEqual(h.map(e => e.action), ['lifted', 'restricted']);
  assert.equal(h[0].reason, 'Restricted by mistake'); assert.equal(h[0].actor_name, 'Amal Admin');
  assert.ok(new Date(h[0].created_at) >= new Date(h[1].created_at));
  await as('');
  await assert.rejects(() => db.query("update conversation_restriction_events set reason='x' where request_id=$1", [A]), /moderation_history_immutable/);
  await assert.rejects(() => db.query('delete from conversation_restriction_events where request_id=$1', [A]), /moderation_history_immutable/);
  await assert.rejects(() => db.query('truncate conversation_restriction_events'), /moderation_history_immutable/);
});

await check('LIFT-07 both participants get a generic restriction_lifted notice (no reason)', async () => {
  await as('');
  const notes = (await db.query("select user_id, title, body from notifications where kind='restriction_lifted' and reference_id=$1", [A])).rows;
  assert.deepEqual(notes.map(x => x.user_id).sort(), [users.seeker, users.vol].sort());
  assert.ok(notes.every(x => x.body === 'An administrator lifted the restriction on your conversation.'));
  assert.ok(!JSON.stringify(notes).includes('mistake'), 'admin reason not revealed');
});

await check('LIFT-08 a second lift, an unknown conversation, or a second admin are refused cleanly', async () => {
  await as('admin2');
  await assert.rejects(() => rpc('admin_lift_conversation_restriction', [A, 'again']), /conversation_not_restricted/);
  await assert.rejects(() => rpc('admin_lift_conversation_restriction', ['60000000-0000-0000-0000-0000000000ff', 'x']), /conversation_unavailable/);
  assert.equal((await history(A)).length, 2, 'no extra event');
  await as(''); assert.equal((await one("select count(*)::int n from notifications where kind='restriction_lifted' and reference_id=$1", [A])).n, 2);
});

// B: participant ended the chat, then the admin restricted it.
const B = await conversation('seeker2', 'vol2');
await send(B, 'vol2', 'hello'); await as('vol2'); await db.query('select end_maak_chat($1)', [B]);
await restrict(B, 'Safety review');

await check('LIFT-09 a participant-ended chat stays ended after the lift; the normal reopen flow works', async () => {
  await as('vol2');
  await assert.rejects(() => db.query('select request_maak_chat_reopen($1)', [B]), /chat_unavailable/, 'blocked while restricted');
  await as('admin');
  const out = await rpc('admin_lift_conversation_restriction', [B, 'Review finished']);
  assert.equal(out.participant_ended, true);
  const s = await state(B);
  assert.equal(s.restricted_at, null); assert.ok(s.ended_at, 'still ended'); assert.equal(s.ended_by, users.vol2);
  await as('seeker2');
  await assert.rejects(() => db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3)', [B, users.seeker2, 'x']), /row-level security|chat_closed/);
  await as('vol2'); await db.query('select request_maak_chat_reopen($1)', [B]);
  await as('seeker2'); await db.query('select decide_maak_chat_reopen($1,true)', [B]);
  await send(B, 'seeker2', 'reopened normally');
});

await check('LIFT-10 lifting never bypasses account blocking', async () => {
  const C = await conversation('seeker3', 'vol2');
  await send(C, 'vol2', 'hi'); await restrict(C, 'Review');
  await as('admin'); await db.query("select admin_block_account($1,'Spam')", [users.vol2]);
  await rpc('admin_lift_conversation_restriction', [C, 'Not needed']);
  await as('');
  assert.equal((await one('select count(*)::int n from account_blocks where user_id=$1', [users.vol2])).n, 1, 'block kept');
  await as('seeker3');
  assert.equal((await one('select can_send_maak_message($1) c', [C])).c, false);
  await assert.rejects(() => db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3)', [C, users.seeker3, 'x']), /participant_unavailable|row-level security/);
});

await check('LIFT-11 re-restricting after a lift records a new restriction event', async () => {
  await restrict(A, 'Happened again');
  const h = await history(A);
  assert.deepEqual(h.map(e => e.action), ['restricted', 'lifted', 'restricted']);
  assert.equal(h[0].reason, 'Happened again');
});

await check('LIFT-12 a lift done directly in SQL is still recorded', async () => {
  await as('');
  await db.query('update support_requests set restricted_at=null, restricted_by=null, restriction_reason=null where id=$1', [PRE]);
  const h = await history(PRE);
  assert.equal(h[0].action, 'lifted'); assert.equal(h[0].reason, "Lifted outside the Ma'ak app"); assert.equal(h[0].actor_name, 'Outside the app');
});

await check('LIFT-13 rollback removes the RPCs and trigger but keeps the history; re-apply works', async () => {
  await as('');
  const before = (await one('select count(*)::int n from conversation_restriction_events')).n;
  await db.exec(read(LIFT_ROLLBACK));
  assert.equal((await one("select to_regprocedure('public.admin_lift_conversation_restriction(uuid,text)') r")).r, null);
  assert.equal((await one('select count(*)::int n from conversation_restriction_events')).n, before, 'history kept');
  await db.exec(read(LIFT));
  for (const [kk, v] of Object.entries(await one(read(LIFT_VERIFY)))) assert.equal(v, true, kk);
});

console.log(`${n} restriction lift checks passed`);
await db.close();
