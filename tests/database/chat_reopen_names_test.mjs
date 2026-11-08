// Chat reopen notifications name the other participant, in the stored row and
// in the push. Real migration chain; pg_net and Vault are stubbed.
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
await db.exec(mig('20261106000000_push_notifications.sql').replace('create extension if not exists pg_net with schema extensions;',''));
await db.exec(mig('20261106010000_appeal_and_match_notifications.sql'));
const detail=mig('20261106020000_detailed_chat_request_notifications.sql');await db.exec(detail);
const names2=mig('20261108000000_named_chat_reopen_notifications.sql');await db.exec(names2);await db.exec(names2);

const id={seeker:'b0000000-0000-4000-8000-000000000001',vol:'c0000000-0000-4000-8000-000000000001',vol2:'c0000000-0000-4000-8000-000000000002'};
const names={seeker:'Dana Ali',vol:'Sara Omar',vol2:'Lina Saad'};
for(const n of Object.keys(id)) await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)`,[id[n],`${n}@x.com`,JSON.stringify({full_name:names[n],role:n==='seeker'?'help_seeker':'volunteer'})]);
await db.query(`update profiles set full_name=$2 where id=$1`,[id.seeker,names.seeker]);
for(const n of ['vol','vol2']) await db.query(`update profiles set full_name=$2 where id=$1`,[id[n],names[n]]);
await db.query(`insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English')`,[id.seeker]);
for(const n of ['vol','vol2']) await db.query(`insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Story','approved')`,[id[n]]);
for(const n of Object.keys(id)){
 await db.query(`insert into ai_matching_agreements(user_id,version,enabled) values($1,'2026-11-05',true)`,[id[n]]);
 await db.query('insert into device_tokens(token,user_id) values($1,$2)',[`tok-${n}`.padEnd(30,'x'),id[n]]);
}
async function as(n){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[n?id[n]:'']);await db.exec(n?'set role authenticated':'reset role');}
async function last(user){await db.exec('reset role');return(await db.query('select * from notifications where user_id=$1 order by created_at desc, title limit 1',[user])).rows[0];}
async function pushes(){await db.exec('reset role');const r=(await db.query('select body from net.calls order by id')).rows.map(x=>x.body);await db.exec('delete from net.calls');return r;}
let checks=0;async function ok(label,fn){await fn();checks++;console.log('PASS',label);}
let request,request2;

await ok('setup: an accepted chat the volunteer ends',async()=>{
 await as('seeker');await db.query('select request_peer_support($1)',[id.vol]);
 await db.exec('reset role');request=(await db.query('select id from support_requests where volunteer_id=$1',[id.vol])).rows[0].id;
 await as('vol');await db.query('select decide_support_request($1,true)',[request]);
 await db.query('select end_maak_chat($1)',[request]);await pushes();
});
await ok('reopen request names the requester; title keeps the Accept/Decline buttons',async()=>{
 await as('vol');await db.query('select request_maak_chat_reopen($1)',[request]);
 const n=await last(id.seeker);assert.equal(n.kind,'chat_reopen');
 assert.equal(n.title,'Chat reopen request');assert.equal(n.body,'Sara Omar would like to reopen your conversation.');
 const p=(await pushes()).find(b=>b.user_id===id.seeker);assert.equal(p.body,'Sara Omar would like to reopen your conversation.');
});
await ok('accepted names the person who accepted',async()=>{
 await as('seeker');await db.query('select decide_maak_chat_reopen($1,true)',[request]);
 const n=await last(id.vol);assert.equal(n.title,'Dana Ali accepted your reopen request');assert.equal(n.body,'You can continue chatting.');
 const p=(await pushes()).find(b=>b.user_id===id.vol);assert.equal(p.title,'Dana Ali accepted your reopen request');
});
await ok('declined names the person who declined (help seeker asks this time)',async()=>{
 await as('seeker');await db.query('select end_maak_chat($1)',[request]);
 await db.query('select request_maak_chat_reopen($1)',[request]);
 assert.equal((await last(id.vol)).body,'Dana Ali would like to reopen your conversation.');
 await as('vol');await db.query('select decide_maak_chat_reopen($1,false)',[request]);
 const n=await last(id.seeker);assert.equal(n.title,'Sara Omar declined your reopen request');assert.equal(n.body,'The conversation remains closed.');
});
await ok('other kinds and unknown names are left alone',async()=>{
 await db.exec('reset role');
 await db.query(`insert into notifications(user_id,title,body,kind,reference_id) values($1,'Hi','There','info',$2)`,[id.seeker,request]);
 const n=await last(id.seeker);assert.equal(n.title,'Hi');
 await db.query(`update profiles set full_name='' where id=$1`,[id.vol]);
 await db.query(`insert into notifications(user_id,title,body,kind,reference_id) values($1,'Reopen request declined','Your peer declined. The conversation remains closed.','chat_reopen',$2)`,[id.seeker,request]);
 assert.equal((await last(id.seeker)).body,'Your peer declined. The conversation remains closed.');
});
console.log(`${checks} chat reopen name checks passed`);
