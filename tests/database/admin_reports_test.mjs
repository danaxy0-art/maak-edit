// Checks for supabase/migrations/20261106100000_admin_report_management.sql (Admin US1-US5).
// Isolated in-memory PGlite database built from the repository files, shaped like
// production: account blocking/visibility/appeals, the Sprint 3 chat migrations, the
// production conversation restriction functions copied verbatim from the production
// export, Razan's reports migration, then this migration. Never touches Supabase.
// Run: cd tests/database && npm install && node admin_reports_test.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const base = fileURLToPath(new URL('../../', import.meta.url));
const read = f => readFileSync(base + f, 'utf8');
const noMeta = sql => sql.replace(/^\\.*$/gm, '');
const MIGRATION = 'supabase/migrations/20261106100000_admin_report_management.sql';
const ROLLBACK = 'supabase/rollbacks/20261106100000_admin_report_management_rollback.sql';
const VERIFY = 'supabase/checks/20261106100000_admin_report_management_verify.sql';

// Production export: restriction columns/constraints and two functions, verbatim.
const exported = read('tests/database/production_compat/05_production_definitions.sql');
const restrictionColumns = exported.slice(exported.indexOf('begin;') + 6, exported.indexOf('CREATE OR REPLACE FUNCTION'));
const productionFn = name => {
  const m = exported.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\nend; \\$\\$;`));
  if (!m) throw new Error(`export is missing ${name}`);
  return m[0];
};

async function build({verbatimRestriction = true} = {}) {
  const db = new PGlite();
  await db.exec(noMeta(read('tests/database/account_blocking/00_supabase_stub.sql')));
  await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
  await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;', ''));
  for (const f of ['20261018_matching.sql', '20261018_condition_reviews.sql', '20261021090000_chat_reads_remove_booking.sql'])
    await db.exec(read('supabase/migrations/' + f));
  await db.exec(restrictionColumns);
  for (const f of ['20261021_account_blocking.sql', '20261022_account_moderation_visibility.sql', '20261023_account_appeals.sql',
    '20261024_cancel_with_blocked_participant.sql', '20261105000000_chat_end_reactions.sql', '20261105010000_chat_reopen.sql',
    '20261105020000_chat_media_ai_consent.sql', '20261105030000_message_deletion_video.sql'])
    await db.exec(read('supabase/migrations/' + f));
  if (verbatimRestriction) {
    await db.exec(productionFn('admin_restrict_conversation') + '\n' + productionFn('admin_support_requests'));
  } else {
    // The older test approximation (different body): the migration must refuse it.
    const approx = read('tests/database/account_blocking/05_live_only_approximation.sql');
    await db.exec(approx.match(/create or replace function public\.admin_restrict_conversation[\s\S]*?end; \$\$;/)[0]);
  }
  await db.exec(`revoke all on function public.admin_restrict_conversation(uuid,text) from public,anon;
    grant execute on function public.admin_restrict_conversation(uuid,text) to authenticated;`);
  await db.exec(read('supabase/migrations/20261105_message_reports.sql'));
  return db;
}

let n = 0;
async function check(label, f) { await f(); n++; console.log('PASS', label); }

// ---------------------------------------------------------------- migration guards
await check('ADM-00 migration refuses an unverified admin_restrict_conversation', async () => {
  const other = await build({verbatimRestriction: false});
  await assert.rejects(() => other.exec(read(MIGRATION)), /unexpected definition/);
  await other.close();
});

const db = await build();
const ids = {
  seeker: '20000000-0000-0000-0000-000000000001', vol: '20000000-0000-0000-0000-000000000002',
  seeker2: '20000000-0000-0000-0000-000000000003', vol2: '20000000-0000-0000-0000-000000000004',
  admin: '20000000-0000-0000-0000-000000000005', admin2: '20000000-0000-0000-0000-000000000006',
  outsider: '20000000-0000-0000-0000-000000000007',
};
const names = {seeker: 'Sara Seeker', vol: 'Vera Volunteer', seeker2: 'Sami Seeker', vol2: 'Victor Volunteer',
  admin: 'Amal Admin', admin2: 'Basma Admin', outsider: 'Olga Outsider'};
for (const [k, id] of Object.entries(ids))
  await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',
    [id, `${k}@example.com`, JSON.stringify({full_name: names[k], role: k.startsWith('vol') ? 'volunteer' : 'help_seeker'})]);
await db.query("update profiles set role='admin' where id in ($1,$2)", [ids.admin, ids.admin2]);
for (const v of ['vol', 'vol2'])
  await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Experience','approved')", [ids[v]]);

async function as(name) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [ids[name] ?? '']);
  if (name === 'anon') await db.exec('set role anon');
  else if (name) await db.exec('set role authenticated');
}
const one = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const rpc = async (fn, args = []) => {
  const ph = args.map((_, i) => `$${i + 1}`).join(',');
  return Object.values(await one(`select ${fn}(${ph}) as r`, args))[0];
};
const list = async status => (await db.query('select admin_list_reports($1) as r', [status ?? null])).rows.map(r => r.r);
const conversation = async (s, v) => { await as(''); return (await one("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id", [ids[s], ids[v]])).id; };
const send = async (req, who, body) => { await as(''); return (await one('insert into messages(request_id,sender_id,body) values($1,$2,$3) returning id', [req, ids[who], body])).id; };
const report = async (who, msg, reason = 'harassment', desc = null) => {
  await as(who); await db.query('select report_maak_message($1,$2,$3)', [msg, reason, desc]);
  await as(''); return (await one('select id from reports where message_id=$1 and reporter_id=$2', [msg, ids[who]])).id;
};

// A report filed with Razan's RPC BEFORE this migration exists (existing data).
await as('');
const P = (await one("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id", [ids.outsider, ids.vol2])).id;
const pMsg = (await one('insert into messages(request_id,sender_id,body) values($1,$2,$3) returning id', [P, ids.vol2, 'filed before the admin migration'])).id;
await as('outsider'); await db.query('select report_maak_message($1,$2,$3)', [pMsg, 'spam', 'pre-existing']);
await as('');
const snapshot = async () => JSON.stringify((await db.query('select * from reports order by id')).rows);
const before = await snapshot();
const columnsBefore = JSON.stringify((await db.query("select column_name,data_type,is_nullable from information_schema.columns where table_name='reports' order by column_name")).rows);
const grantsBefore = JSON.stringify((await db.query("select grantee,privilege_type from information_schema.role_table_grants where table_name='reports' order by 1,2")).rows);
const policiesBefore = JSON.stringify((await db.query("select policyname,cmd,qual from pg_policies where tablename='reports' order by 1")).rows);

// Migration applies after Razan's, twice (idempotent), rolls back and re-applies cleanly.
await check('ADM-01 migration keeps existing reports, Razan\'s columns, grants and policies; rollback restores her schema', async () => {
  await as('');
  await db.exec(read(MIGRATION)); await db.exec(read(MIGRATION));
  assert.equal(await snapshot(), before, 'existing report rows unchanged');
  assert.equal(JSON.stringify((await db.query("select column_name,data_type,is_nullable from information_schema.columns where table_name='reports' order by column_name")).rows), columnsBefore, 'no column added or changed');
  assert.equal(JSON.stringify((await db.query("select grantee,privilege_type from information_schema.role_table_grants where table_name='reports' order by 1,2")).rows), grantsBefore, 'grants unchanged');
  assert.equal(JSON.stringify((await db.query("select policyname,cmd,qual from pg_policies where tablename='reports' order by 1")).rows), policiesBefore, 'policies unchanged');
  await db.exec(read(ROLLBACK));
  assert.equal(await snapshot(), before, 'rollback keeps report rows');
  const def = await one("select pg_get_constraintdef(oid) d from pg_constraint where conname='reports_status_check'");
  assert.ok(!def.d.includes('conversation_ended') && def.d.includes('dismissed'));
  assert.equal((await one("select to_regclass('public.report_decisions') r")).r, null);
  assert.equal(await one("select to_regprocedure('public.admin_list_reports(text)') r").then(r => r.r), null);
  // Remove the fixture row so later checks count only their own reports.
  await db.query('delete from reports where message_id=$1', [pMsg]);
  await db.exec(read(MIGRATION));
});

await check('ADM-02 verify script reports every column true', async () => {
  await as('');
  const row = await one(read(VERIFY));
  for (const [k, v] of Object.entries(row)) assert.equal(v, true, k);
});

// Seed: conversation A (seeker+vol) with 14 messages; B (seeker2+vol2); C (seeker+vol2).
const A = await conversation('seeker', 'vol');
const aMsgs = [];
for (let i = 1; i <= 14; i++) aMsgs.push(await send(A, i % 2 ? 'vol' : 'seeker', `A message ${i}`));
const B = await conversation('seeker2', 'vol2');
const bMsg = await send(B, 'vol2', 'B private message');
const C = await conversation('seeker', 'vol2');
const cMsg = await send(C, 'vol2', 'C message');
const reported = aMsgs[6]; // "A message 7", from vol
const r1 = await report('seeker', reported, 'harassment', 'He was rude to me');
const r2 = await report('vol', aMsgs[7], 'spam');            // seeker's message 8, reported by vol
const rB = await report('seeker2', bMsg, 'unwanted_medical_advice');
const rC = await report('seeker', cMsg, 'other', 'Not sure');

// ---------------------------------------------------------------- authorization
await check('ADM-03 members and anonymous callers cannot use any admin report RPC', async () => {
  for (const who of ['seeker', 'vol', 'outsider']) {
    await as(who);
    await assert.rejects(() => list(null), /not_allowed/);
    await assert.rejects(() => rpc('admin_report_details', [r1]), /not_allowed/);
    await assert.rejects(() => rpc('admin_dismiss_report', [r1, 'x']), /not_allowed/);
    await assert.rejects(() => rpc('admin_end_reported_conversation', [r1, 'x']), /not_allowed/);
  }
  await as('anon');
  await assert.rejects(() => list(null), /permission denied/);
  await assert.rejects(() => rpc('admin_report_details', [r1]), /permission denied/);
  await as('seeker');
  await assert.rejects(() => db.query("update reports set status='dismissed' where id=$1", [r1]), /permission denied/);
  await assert.rejects(() => db.query('select maak_report_member($1)', [ids.vol]), /permission denied/);
});

await check('ADM-04 a blocked admin loses access (is_maak_admin)', async () => {
  await as('');
  // Admins cannot be blocked through the app; simulate a direct block to prove the server check.
  await db.exec('alter table account_blocks disable trigger maak_account_block_target; alter table account_blocks disable trigger maak_account_block_event_guard;');
  const ev = (await one("insert into account_moderation_events(user_id,action,reason,actor_id) values($1,'blocked','t',$2) returning id", [ids.admin2, ids.admin])).id;
  await db.query("insert into account_blocks(user_id,reason,blocked_by,block_event_id) values($1,'t',$2,$3)", [ids.admin2, ids.admin, ev]);
  await as('admin2');
  await assert.rejects(() => list(null), /not_allowed/);
  await as('');
  await db.query('delete from account_blocks where user_id=$1', [ids.admin2]);
  await db.exec('alter table account_blocks enable trigger maak_account_block_target; alter table account_blocks enable trigger maak_account_block_event_guard;');
});

// ---------------------------------------------------------------- US1 list + filter
await check('ADM-05 admin lists every report, newest first, with member cards and no emails', async () => {
  await as('admin');
  const rows = await list(null);
  assert.equal(rows.length, 4);
  assert.deepEqual(rows.map(r => r.report_id), [rC, rB, r2, r1]);
  const a = rows.find(r => r.report_id === r1);
  assert.equal(a.status, 'open'); assert.equal(a.reason, 'harassment'); assert.equal(a.description, 'He was rude to me');
  assert.equal(a.reporter.name, 'Sara Seeker'); assert.equal(a.reporter.role, 'help_seeker');
  assert.equal(a.reported.name, 'Vera Volunteer'); assert.equal(a.reported.role, 'volunteer');
  assert.equal(a.reported.is_blocked, false); assert.equal(a.message_preview, 'A message 7');
  assert.equal(a.conversation_open_reports, 2); assert.equal(a.conversation_restricted, false);
  assert.equal(a.decided_at, null);
  assert.ok(!JSON.stringify(rows).includes('@example.com'), 'no emails');
  assert.ok(!JSON.stringify(rows).includes('attachment_path'), 'no attachment paths');
});

await check('ADM-06 status filter returns only that status; unknown status is refused', async () => {
  await as('admin');
  assert.equal((await list('open')).length, 4);
  assert.equal((await list('dismissed')).length, 0);
  assert.equal((await list('conversation_ended')).length, 0);
  await assert.rejects(() => list('closed'), /invalid_report_status/);
});

// ---------------------------------------------------------------- US2 details
await check('ADM-07 details: stored evidence, both participants, and other reports in the conversation', async () => {
  await as('admin');
  const d = await rpc('admin_report_details', [r1]);
  assert.equal(d.message_body, 'A message 7'); assert.equal(d.message_type, 'text');
  assert.equal(d.attachment_present, false); assert.equal(d.message_now.exists, true); assert.equal(d.message_now.deleted, false);
  assert.equal(d.conversation.help_seeker.name, 'Sara Seeker'); assert.equal(d.conversation.volunteer.name, 'Vera Volunteer');
  assert.equal(d.conversation.status, 'accepted'); assert.equal(d.conversation.restricted_at, null);
  assert.equal(d.other_reports.length, 1); assert.equal(d.other_reports[0].report_id, r2);
  assert.equal(d.other_reports[0].reporter_name, 'Vera Volunteer');
});

await check('ADM-08 context is narrow: at most 5 messages either side, this conversation only', async () => {
  await as('admin');
  const d = await rpc('admin_report_details', [r1]);
  assert.deepEqual(d.context.map(m => m.body), ['A message 2', 'A message 3', 'A message 4', 'A message 5', 'A message 6',
    'A message 7', 'A message 8', 'A message 9', 'A message 10', 'A message 11', 'A message 12']);
  assert.equal(d.context.filter(m => m.is_reported).length, 1);
  assert.equal(d.context.find(m => m.is_reported).sender, 'reported');
  assert.equal(d.context.find(m => m.body === 'A message 8').sender, 'reporter');
  const text = JSON.stringify(d);
  assert.ok(!text.includes('B private message') && !text.includes('C message'), 'no other conversations');
  assert.ok(!text.includes('A message 1"') && !text.includes('A message 13') && !text.includes('A message 14'));
  assert.ok(!text.includes('attachment_path') && !text.includes('@example.com'));
  const edge = await rpc('admin_report_details', [rC]);
  assert.deepEqual(edge.context.map(m => m.body), ['C message']);
});

await check('ADM-09 a deleted message keeps its evidence; context shows only the placeholder', async () => {
  await as('vol'); await db.query('select delete_maak_message($1,true)', [reported]);
  await as('admin');
  const d = await rpc('admin_report_details', [r1]);
  assert.equal(d.message_body, 'A message 7'); assert.equal(d.message_now.deleted, true);
  assert.equal(d.context.find(m => m.is_reported).body, 'This message was deleted.');
  assert.equal(d.context.find(m => m.is_reported).deleted, true);
});

await check('ADM-10 unknown report is reported as report_not_found', async () => {
  await as('admin');
  await assert.rejects(() => rpc('admin_report_details', ['20000000-0000-0000-0000-0000000000ff']), /report_not_found/);
  await assert.rejects(() => rpc('admin_dismiss_report', ['20000000-0000-0000-0000-0000000000ff', 'x']), /report_not_found/);
  await assert.rejects(() => rpc('admin_end_reported_conversation', ['20000000-0000-0000-0000-0000000000ff', 'x']), /report_not_found/);
});

// ---------------------------------------------------------------- US3 dismiss + US5 tracking
await check('ADM-11 dismiss requires a reason of 1-500 characters', async () => {
  await as('admin');
  for (const bad of [null, '', '   ', 'x'.repeat(501)])
    await assert.rejects(() => rpc('admin_dismiss_report', [rC, bad]), /invalid_report_decision_note/);
  assert.equal((await list('open')).length, 4);
});

await check('ADM-12 dismissing records who, when and why, and leaves the conversation open', async () => {
  await as('admin');
  const out = await rpc('admin_dismiss_report', [rC, '  Not a rule violation  ']);
  assert.equal(out.status, 'dismissed'); assert.ok(out.decided_at);
  const row = (await list('dismissed'))[0];
  assert.equal(row.report_id, rC); assert.equal(row.decision_note, 'Not a rule violation');
  assert.equal(row.decided_by_name, 'Amal Admin'); assert.equal(row.decided_by_is_me, true);
  assert.ok(!JSON.stringify(row).includes(ids.admin), 'the deciding admin UUID is not returned');
  await as('admin2');
  const seen = (await list('dismissed'))[0];
  assert.equal(seen.decided_by_name, 'Amal Admin'); assert.equal(seen.decided_by_is_me, false);
  await as('vol2'); await db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3)', [C, ids.vol2, 'still open']);
  await as(''); assert.equal((await one('select restricted_at from support_requests where id=$1', [C])).restricted_at, null);
});

await check('ADM-13 a decided report cannot be decided again (stale second admin)', async () => {
  await as('admin2');
  await assert.rejects(() => rpc('admin_dismiss_report', [rC, 'again']), /report_already_decided/);
  await assert.rejects(() => rpc('admin_end_reported_conversation', [rC, 'again']), /report_already_decided/);
  await as('');
  const r = await one('select decided_by, note, outcome from report_decisions where report_id=$1', [rC]);
  assert.equal(r.decided_by, ids.admin); assert.equal(r.note, 'Not a rule violation'); assert.equal(r.outcome, 'dismissed');
  assert.equal((await one('select count(*)::int c from report_decisions where report_id=$1', [rC])).c, 1);
});

await check('ADM-13b reporters see their report status, but never the deciding admin or the note', async () => {
  await as('seeker');
  const own = (await db.query('select * from reports where id=$1', [rC])).rows[0];
  assert.equal(own.status, 'dismissed', 'select * still works for reporters');
  assert.ok(!JSON.stringify(own).includes(ids.admin) && !JSON.stringify(own).includes('Not a rule violation'));
  await assert.rejects(() => db.query('select * from report_decisions'), /permission denied/);
  await as('admin');
  await assert.rejects(() => db.query('select * from report_decisions'), /permission denied/, 'admins read decisions only through RPCs');
});

await check('ADM-14 evidence and decisions are immutable, even for direct SQL', async () => {
  await as('');
  await assert.rejects(() => db.query("update reports set message_body='edited' where id=$1", [r1]), /report_evidence_immutable/);
  await assert.rejects(() => db.query("update reports set reason='spam' where id=$1", [r1]), /report_evidence_immutable/);
  await assert.rejects(() => db.query("update reports set status='open' where id=$1", [rC]), /report_already_decided/);
  await assert.rejects(() => db.query('delete from reports where id=$1', [rB]), /report_history_immutable/);
  await assert.rejects(() => db.query('truncate reports'), /report_history_immutable/);
  // A status change needs a recorded decision with the same outcome.
  await assert.rejects(() => db.query("update reports set status='dismissed' where id=$1", [rB]), /report_decision_missing/);
  await assert.rejects(() => db.query("update reports set status='reviewed' where id=$1", [rB]), /report_decision_missing/);
  // Decisions: insert once for an open report; never changed or removed.
  await assert.rejects(() => db.query("update report_decisions set note='changed' where report_id=$1", [rC]), /report_history_immutable/);
  await assert.rejects(() => db.query('delete from report_decisions where report_id=$1', [rC]), /report_history_immutable/);
  await assert.rejects(() => db.query('truncate report_decisions'), /report_history_immutable/);
  await assert.rejects(() => db.query("insert into report_decisions(report_id,outcome,note,decided_by) values($1,'dismissed','x',$2)", [rC, ids.admin]), /report_already_decided|duplicate key/);
  await assert.rejects(() => db.query("insert into report_decisions(report_id,outcome,note,decided_by) values($1,'dismissed','x',$2)", ['20000000-0000-0000-0000-0000000000fe', ids.admin]), /report_not_found/);
  await assert.rejects(() => db.query("insert into report_decisions(report_id,outcome,note,decided_by) values($1,'dismissed','',$2)", [rB, ids.admin]), /report_decisions_note_check/);
  // Unrelated non-status updates of an open report are still evidence changes and refused.
  await assert.rejects(() => db.query("update reports set description='x' where id=$1", [rB]), /report_evidence_immutable/);
  assert.equal((await one('select status from reports where id=$1', [rB])).status, 'open');
});

// ---------------------------------------------------------------- US4 end conversation
// Conversation D: the volunteer ended it and asked to reopen; the seeker has not answered.
const D = await conversation('seeker2', 'vol');
const dMsg = await send(D, 'vol', 'D message from vol');
await as('vol'); await db.query('select end_maak_chat($1)', [D]); await db.query('select request_maak_chat_reopen($1)', [D]);
const rD = await report('seeker2', dMsg, 'harassment');

await check('ADM-15 ending requires a reason and only works on an open report', async () => {
  await as('admin');
  await assert.rejects(() => rpc('admin_end_reported_conversation', [r1, '  ']), /invalid_report_decision_note/);
  await as(''); assert.equal((await one('select restricted_at from support_requests where id=$1', [A])).restricted_at, null);
});

let messagesBefore;
await check('ADM-16 ending restricts the conversation and resolves all its open reports with one decision', async () => {
  await as(''); messagesBefore = (await one('select count(*)::int c from messages where request_id=$1', [A])).c;
  await as('admin');
  const out = await rpc('admin_end_reported_conversation', [r1, 'Harassment of a help seeker']);
  assert.equal(out.status, 'conversation_ended'); assert.equal(out.resolved_reports, 2); assert.equal(out.request_id, A);
  const ended = await list('conversation_ended');
  assert.deepEqual(ended.map(r => r.report_id).sort(), [r1, r2].sort());
  assert.ok(ended.every(r => r.decision_note === 'Harassment of a help seeker' && r.decided_by_is_me && r.conversation_restricted));
  assert.deepEqual((await list('open')).map(r => r.report_id).sort(), [rB, rD].sort(), 'other conversations untouched');
  const d = await rpc('admin_report_details', [r2]);
  assert.ok(d.conversation.restricted_at); assert.equal(d.conversation.restriction_reason, 'Harassment of a help seeker');
  assert.equal(d.conversation.restricted_by_name, 'Amal Admin'); assert.equal(d.conversation.restricted_by_is_me, true);
});

await check('ADM-17 after ending: messages kept, both notified, no account blocked', async () => {
  await as('');
  assert.equal((await one('select count(*)::int c from messages where request_id=$1', [A])).c, messagesBefore);
  const notes = (await db.query("select user_id,body from notifications where kind='restricted' and reference_id=$1", [A])).rows;
  assert.deepEqual(notes.map(x => x.user_id).sort(), [ids.seeker, ids.vol].sort());
  assert.ok(notes.every(x => x.body.includes('Harassment of a help seeker')));
  assert.equal((await one('select count(*)::int c from account_blocks')).c, 0);
  assert.equal((await one("select status from support_requests where id=$1", [A])).status, 'accepted');
});

await check('ADM-18 participants can no longer send, upload, react or reopen', async () => {
  for (const who of ['seeker', 'vol']) {
    await as(who);
    await assert.rejects(() => db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3)', [A, ids[who], 'after']), /row-level security|chat_closed/);
    assert.equal((await one('select can_send_maak_message($1) c', [A])).c, false);
    assert.equal((await one("select can_access_maak_media($1,true) c", [`${A}/${ids[who]}/x.png`])).c, false);
    await assert.rejects(() => db.query("select toggle_maak_reaction($1,$2,'👍')", [A, aMsgs[0]]), /chat_unavailable/);
  }
  // A participant ending and then asking to reopen is refused while restricted.
  await as('seeker'); await db.query('select end_maak_chat($1)', [A]);
  await assert.rejects(() => db.query('select request_maak_chat_reopen($1)', [A]), /chat_unavailable/);
  await as(''); assert.ok((await one('select restricted_at from support_requests where id=$1', [A])).restricted_at, 'end_maak_chat does not lift it');
  await as('seeker'); assert.equal((await db.query('select my_maak_chat_messages($1)', [A])).rows.length, messagesBefore, 'history still readable');
});

await check('ADM-19 a pending reopen request cannot be accepted after an admin ends the chat', async () => {
  await as('admin');
  await rpc('admin_end_reported_conversation', [rD, 'Threatening language']);
  await as('seeker2');
  await assert.rejects(() => db.query('select decide_maak_chat_reopen($1,true)', [D]), /chat_unavailable/);
  await as('');
  const s = await one('select ended_at, restricted_at from support_requests where id=$1', [D]);
  assert.ok(s.ended_at && s.restricted_at, 'stays ended and restricted');
});

await check('ADM-20 a second end on the same conversation is refused; a later report can be dismissed', async () => {
  await as('admin2');
  await assert.rejects(() => rpc('admin_end_reported_conversation', [r2, 'Again']), /report_already_decided/);
  // Members may still report messages in a restricted conversation (Razan's RPC).
  const late = await report('vol', aMsgs[9], 'spam');
  await as('admin2');
  await assert.rejects(() => rpc('admin_end_reported_conversation', [late, 'Again']), /conversation_already_restricted/);
  await rpc('admin_dismiss_report', [late, 'Conversation already ended']);
  await as(''); assert.equal((await one('select status from reports where id=$1', [late])).status, 'dismissed');
});

await check('ADM-21 a failed end leaves nothing half-done', async () => {
  await as('');
  await as('admin');
  await assert.rejects(() => rpc('admin_end_reported_conversation', [rB, 'x'.repeat(501)]), /invalid_report_decision_note/);
  await as('');
  assert.equal((await one('select status from reports where id=$1', [rB])).status, 'open');
  assert.equal((await one('select restricted_at from support_requests where id=$1', [B])).restricted_at, null);
  assert.equal((await one("select count(*)::int c from notifications where kind='restricted' and reference_id=$1", [B])).c, 0);
});

// ---------------------------------------------------------------- regression + account deletion
await check('ADM-22 Razan\'s member reporting still works and new reports start open', async () => {
  const m = await send(B, 'vol2', 'B second');
  const id = await report('seeker2', m, 'other', '  details  ');
  await as('');
  const r = await one('select status,description,message_body,message_type,reason from reports where id=$1', [id]);
  assert.deepEqual(r, {status: 'open', description: 'details', message_body: 'B second', message_type: 'text', reason: 'other'});
  assert.equal((await one('select count(*)::int c from report_decisions where report_id=$1', [id])).c, 0);
  await as('seeker2');
  await assert.rejects(() => db.query('select report_maak_message($1,$2,$3)', [m, 'spam', null]), /already_reported/);
  assert.ok((await db.query('select * from reports')).rows.every(x => x.reporter_id === ids.seeker2), 'reporters still see only their own');
});

await check('ADM-23 deleted accounts: evidence stays readable, conversation is unavailable', async () => {
  await as(''); await db.query('delete from auth.users where id=$1', [ids.vol2]);
  await as('admin');
  const d = await rpc('admin_report_details', [rB]);
  assert.equal(d.reported.account_exists, false); assert.equal(d.reported.name, null);
  assert.equal(d.conversation.exists, false); assert.deepEqual(d.context, []); assert.equal(d.message_now.exists, false);
  assert.equal(d.message_body, 'B private message');
  await assert.rejects(() => rpc('admin_end_reported_conversation', [rB, 'Too late']), /conversation_unavailable/);
  await rpc('admin_dismiss_report', [rB, 'Account no longer exists']);
});

await check('ADM-24 rollback refuses once decisions exist', async () => {
  await as('');
  await assert.rejects(() => db.exec(read(ROLLBACK)), /moderation decisions/);
  await db.exec('rollback'); // the refused script leaves its transaction aborted
  assert.ok(await one("select to_regprocedure('public.admin_list_reports(text)') r").then(r => r.r));
});

await check('ADM-25 re-running Razan\'s migration after this one keeps both working', async () => {
  await as('');
  const decisions = JSON.stringify((await db.query('select * from report_decisions order by report_id')).rows);
  const rows = await snapshot();
  await db.exec(read('supabase/migrations/20261105_message_reports.sql'));
  assert.equal(await snapshot(), rows); assert.equal(JSON.stringify((await db.query('select * from report_decisions order by report_id')).rows), decisions);
  const def = await one("select pg_get_constraintdef(oid) d from pg_constraint where conname='reports_status_check'");
  assert.ok(def.d.includes('conversation_ended'), 'status extension survives');
  const row = await one(read(VERIFY));
  for (const [k, v] of Object.entries(row)) assert.equal(v, true, k);
  const C2 = await conversation('outsider', 'vol');
  const m = await send(C2, 'vol', 'after re-run');
  const id = await report('outsider', m, 'spam');
  await as('admin'); await rpc('admin_dismiss_report', [id, 'Checked after re-run']);
});

console.log(`${n} admin report checks passed`);
await db.close();
