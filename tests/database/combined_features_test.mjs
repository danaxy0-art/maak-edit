// Both feature sets installed together, in migration order: message reports +
// admin report management (Sprint 3) and push notifications, profile pictures,
// appeals and blocking fixes. Checks the places where they meet.
// Run: cd tests/database && npm install && node combined_features_test.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');const mig=f=>read('supabase/migrations/'+f);
const exported=read('tests/database/production_compat/05_production_definitions.sql');
const restrictionColumns=exported.slice(exported.indexOf('begin;')+6,exported.indexOf('CREATE OR REPLACE FUNCTION'));
const productionFn=name=>exported.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\nend; \\$\\$;`))[0];
const db=new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;',''));
for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql']) await db.exec(mig(f));
await db.exec(restrictionColumns);
for(const f of ['20261021_account_blocking.sql','20261022_account_moderation_visibility.sql','20261023_account_appeals.sql',
 '20261024_cancel_with_blocked_participant.sql','20261105000000_chat_end_reactions.sql','20261105010000_chat_reopen.sql',
 '20261105020000_chat_media_ai_consent.sql','20261105030000_message_deletion_video.sql','20261021_matching_connections.sql',
 '20261105040000_ai_matching_toggle.sql']) await db.exec(mig(f));
await db.exec(productionFn('admin_restrict_conversation')+'\n'+productionFn('admin_support_requests'));
await db.exec(`revoke all on function public.admin_restrict_conversation(uuid,text) from public,anon;
 grant execute on function public.admin_restrict_conversation(uuid,text) to authenticated;`);
await db.exec(`create schema vault; create schema net;
create table vault.decrypted_secrets(name text primary key, decrypted_secret text);
insert into vault.decrypted_secrets values('maak_project_url','https://ref.supabase.co'),('maak_push_secret','s');
create table net.calls(id serial, body jsonb);
create function net.http_post(url text, body jsonb, params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
 returns bigint language sql as $$ insert into net.calls(body) values(body) returning id::bigint $$;`);
// Every migration from both versions, in filename order.
for(const f of ['20261105_message_reports.sql','20261106000000_push_notifications.sql','20261106010000_appeal_and_match_notifications.sql',
 '20261106020000_detailed_chat_request_notifications.sql','20261106100000_admin_report_management.sql','20261107000000_profile_pictures.sql',
 '20261107010000_shared_profile_pictures.sql','20261107020000_single_restriction_push.sql','20261107030000_appeal_and_block_fixes.sql'])
 await db.exec(mig(f).replace('create extension if not exists pg_net with schema extensions;',''));

const id={admin:'a0000000-0000-4000-8000-000000000001',seeker:'b0000000-0000-4000-8000-000000000001',vol:'c0000000-0000-4000-8000-000000000001'};
for(const [n,u] of Object.entries(id)) await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)`,[u,`${n}@x.com`,JSON.stringify({full_name:n,role:n==='vol'?'volunteer':'help_seeker'})]);
await db.query(`update profiles set role='admin' where id=$1`,[id.admin]);
await db.query(`insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English')`,[id.seeker]);
await db.query(`insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Story','approved')`,[id.vol]);
for(const n of ['seeker','vol']){await db.query(`insert into ai_matching_agreements(user_id,version,enabled) values($1,'2026-11-05',true)`,[id[n]]);await db.query('insert into device_tokens(token,user_id) values($1,$2)',[`tok-${n}`.padEnd(30,'x'),id[n]]);}
async function as(n){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[n?id[n]:'']);await db.exec(n?'set role authenticated':'reset role');}
async function calls(){await db.exec('reset role');const r=(await db.query('select body from net.calls order by id')).rows.map(x=>x.body);await db.exec('delete from net.calls');return r;}
let checks=0;async function ok(label,fn){await fn();checks++;console.log('PASS',label);}

let request,message,report;
await as('seeker');await db.query('select request_peer_support($1)',[id.vol]);
await db.exec('reset role');request=(await db.query('select id from support_requests')).rows[0].id;
await as('vol');await db.query('select decide_support_request($1,true)',[request]);
await as('vol');message=(await db.query(`insert into messages(request_id,sender_id,body) values($1,auth.uid(),'Rude message') returning id`,[request])).rows[0].id;
await ok('chat push still names the sender and shows the text',async()=>{
 const c=await calls();const m=c.find(b=>b.kind==='message');assert.equal(m.title,'vol');assert.equal(m.body,'Rude message');
});
await ok('a member can report a message (reports + notifications triggers coexist)',async()=>{
 await as('seeker');await db.query(`select report_maak_message($1,'harassment','Please check')`,[message]);
 await db.exec('reset role');assert.equal((await db.query('select count(*)::int c from reports')).rows[0].c,1);
});
await ok('admin ending the reported conversation pushes "restricted" to both members',async()=>{
 await calls();await as('admin');
 await db.exec('reset role');const rid=(await db.query('select id from reports limit 1')).rows[0].id;
 await as('admin');await db.query(`select admin_end_reported_conversation($1,'Breaks community rules')`,[rid]);
 const c=await calls();const restricted=c.filter(b=>b.kind==='restricted').map(b=>b.user_id).sort();
 assert.deepEqual(restricted,[id.seeker,id.vol].sort());
});
await ok('a restricted account still cannot file a report (guard unchanged for reports)',async()=>{
 await as('vol');const m2=(await db.query(`select id from messages where request_id=$1 limit 1`,[request])).rows[0].id;
 await as('admin');await db.query(`select admin_block_account($1,'Spam')`,[id.seeker]);
 await as('seeker');await assert.rejects(db.query(`select report_maak_message($1,'spam',null)`,[m2]),/account_blocked|not_allowed/);
});
await ok('the restricted account can still appeal, and gets only the restriction push',async()=>{
 await as('seeker');await db.query(`select submit_my_appeal('Please review')`);
 const c=await calls();assert.deepEqual(c.filter(b=>b.user_id===id.seeker).map(b=>b.kind),['account_blocked']);
});
console.log(`${checks} combined feature checks passed`);
