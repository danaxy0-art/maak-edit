// Appeal pushes to admins and "new matching volunteer" notifications for help
// seekers, run against the real migration chain. pg_net and Vault are stubbed;
// net.http_post records every queued push.
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');
const mig=f=>read('supabase/migrations/'+f);
const db=new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;',''));
for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql']) await db.exec(mig(f));
await db.exec('alter table public.support_requests add column restricted_at timestamptz;');
for(const f of ['20261021_account_blocking.sql','20261022_account_moderation_visibility.sql','20261023_account_appeals.sql',
 '20261105000000_chat_end_reactions.sql','20261105010000_chat_reopen.sql','20261105020000_chat_media_ai_consent.sql',
 '20261105030000_message_deletion_video.sql','20261021_matching_connections.sql','20261105040000_ai_matching_toggle.sql']) await db.exec(mig(f));
await db.exec(`create schema vault; create schema net; create schema if not exists extensions;
create table vault.decrypted_secrets(name text primary key, decrypted_secret text);
insert into vault.decrypted_secrets values('maak_project_url','https://ref.supabase.co'),('maak_push_secret','s3cret');
create table net.calls(id serial, body jsonb);
create function net.http_post(url text, body jsonb, params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
 returns bigint language sql as $$ insert into net.calls(body) values(body) returning id::bigint $$;`);
const push=mig('20261106000000_push_notifications.sql').replace('create extension if not exists pg_net with schema extensions;','');
const next=mig('20261106010000_appeal_and_match_notifications.sql');
await db.exec(push);await db.exec(next);await db.exec(next); // rerunnable

const id={admin:'a0000000-0000-4000-8000-000000000001',admin2:'a0000000-0000-4000-8000-000000000002',
 seeker:'b0000000-0000-4000-8000-000000000001',seekerNoAi:'b0000000-0000-4000-8000-000000000002',seekerOther:'b0000000-0000-4000-8000-000000000003',
 vol:'c0000000-0000-4000-8000-000000000001'};
const role=n=>n.startsWith('admin')?'admin':n.startsWith('seeker')?'help_seeker':'volunteer';
for(const [n,u] of Object.entries(id)) await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)`,[u,`${n}@x.com`,JSON.stringify({full_name:n,role:role(n)==='admin'?'help_seeker':role(n)})]);
await db.query(`update profiles set role='admin' where id in ($1,$2)`,[id.admin,id.admin2]);
const cond=async name=>(await db.query('select id from chronic_conditions where name=$1',[name])).rows[0].id;
const diabetes=await cond('Diabetes'),asthma=await cond('Asthma');
for(const [n,c] of [['seeker',diabetes],['seekerNoAi',diabetes],['seekerOther',asthma]]){
 await db.query(`insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'x','English')`,[id[n]]);
 await db.query('insert into user_conditions values($1,$2)',[id[n],c]);
}
for(const n of ['seeker','seekerOther','vol','admin','admin2']) await db.query('insert into device_tokens(token,user_id) values($1,$2)',[`tok-${n}`.padEnd(30,'x'),id[n]]);
for(const n of ['seeker','seekerOther']) await db.query(`insert into ai_matching_agreements(user_id,version,enabled) values($1,'2026-11-05',true)`,[id[n]]);

async function as(n){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[n?id[n]:'']);await db.exec(n?'set role authenticated':'reset role');}
async function calls(){await db.exec('reset role');const r=(await db.query('select body from net.calls order by id')).rows.map(x=>x.body);await db.exec('delete from net.calls');return r;}
async function matches(){await db.exec('reset role');return(await db.query(`select user_id,reference_id from notifications where kind='match' order by user_id`)).rows;}
let checks=0;async function ok(label,fn){await fn();checks++;console.log('PASS',label);}

await ok('pending volunteer with AI on and a shared condition: no match yet',async()=>{
 await as(null);
 await db.query(`insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Story','pending_review')`,[id.vol]);
 await db.query('insert into user_conditions values($1,$2)',[id.vol,diabetes]);
 await db.query(`insert into ai_matching_agreements(user_id,version,enabled) values($1,'2026-11-05',true)`,[id.vol]);
 assert.equal((await matches()).length,0);await calls();
});
await ok('approval notifies only seekers who share a condition and have AI matching on',async()=>{
 await as('admin');await db.query('select review_volunteer_application($1,true,null)',[id.vol]);
 const m=await matches();assert.deepEqual(m.map(r=>r.user_id),[id.seeker]);assert.equal(m[0].reference_id,id.vol);
 const c=await calls();assert.ok(c.some(b=>b.user_id===id.seeker&&b.kind==='match'));assert.ok(c.some(b=>b.user_id===id.vol&&b.kind==='application'));
 assert.ok(!c.some(b=>b.user_id===id.seekerOther));
});
await ok('the seeker can now actually see that volunteer in matching',async()=>{
 await as('seeker');const ctx=(await db.query('select maak_matching_context() d')).rows[0].d;assert.ok(ctx.candidates.some(v=>v.user_id===id.vol));
});
await ok('no repeat: adding a shared condition or toggling AI off/on sends nothing new',async()=>{
 await as('vol');await db.query('select set_maak_ai_matching_enabled(false)');await db.query('select set_maak_ai_matching_enabled(true)');
 await as(null);await db.query('insert into user_conditions values($1,$2) on conflict do nothing',[id.vol,await cond('Hypertension')]);
 assert.equal((await matches()).length,1);
});
await ok('adding a condition notifies newly matching seekers',async()=>{
 await calls();await as(null);await db.query('insert into user_conditions values($1,$2)',[id.vol,asthma]);
 assert.deepEqual((await matches()).map(r=>r.user_id).sort(),[id.seeker,id.seekerOther].sort());
});
await ok('volunteer with AI matching off is never announced',async()=>{
 await as(null);await db.exec(`delete from match_notifications_sent; delete from notifications where kind='match'`);
 await as('vol');await db.query('select set_maak_ai_matching_enabled(false)');
 await as(null);await db.query('insert into user_conditions values($1,$2) on conflict do nothing',[id.vol,await cond('Asthma')]);
 assert.equal((await matches()).length,0);
 await as('vol');await db.query('select set_maak_ai_matching_enabled(true)');
 assert.equal((await matches()).length,2,'turning AI matching on announces them');
});
await ok('restricted seekers are skipped; reactivating a volunteer re-checks matches',async()=>{
 await as(null);await db.exec(`delete from match_notifications_sent; delete from notifications where kind='match'`);
 await as('admin');await db.query(`select admin_block_account($1,'Spam')`,[id.seekerOther]);await db.query(`select admin_block_account($1,'Check')`,[id.vol]);
 await db.query('select admin_reactivate_account($1)',[id.vol]);
 assert.deepEqual((await matches()).map(r=>r.user_id),[id.seeker]);
});
let appealId;
await ok('a restricted member can still appeal, and every admin gets a push',async()=>{
 await calls();await as('seekerOther');
 const r=(await db.query(`select submit_my_appeal('Please review') s`)).rows[0].s;assert.equal(r.appeals_used,1);
 await as(null);appealId=(await db.query('select id from account_block_appeals')).rows[0].id;
 const c=await calls();assert.deepEqual(c.map(b=>b.user_id).sort(),[id.admin,id.admin2].sort());
 assert.ok(c.every(b=>b.kind==='appeal'&&b.reference_id===appealId&&!JSON.stringify(b).includes('Please review')));
});
await ok('clients cannot call the new internal functions or read the sent list',async()=>{
 await as('seeker');
 await assert.rejects(db.query('select notify_maak_new_matches($1)',[id.vol]));
 await assert.rejects(db.query('select * from match_notifications_sent'));
});
console.log(`${checks} appeal/match notification checks passed`);
