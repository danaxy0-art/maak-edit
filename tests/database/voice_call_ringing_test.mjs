// Checks for supabase/migrations/20261127030000_voice_call_ringing.sql:
// new calls push a ringing notification; unanswered calls leave a missed-call
// notification. Run: cd tests/database && npm install && node voice_call_ringing_test.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const read=f=>readFileSync(new URL('../../'+f,import.meta.url),'utf8');
const db=new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;',''));
for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql'])await db.exec(read('supabase/migrations/'+f));
const exported=read('tests/database/production_compat/05_production_definitions.sql');
await db.exec(exported.slice(exported.indexOf('begin;')+6,exported.indexOf('CREATE OR REPLACE FUNCTION')));
for(const f of ['20261021_account_blocking.sql','20261022_account_moderation_visibility.sql','20261023_account_appeals.sql','20261024_cancel_with_blocked_participant.sql','20261105000000_chat_end_reactions.sql'])await db.exec(read('supabase/migrations/'+f));
await db.exec(`create schema vault; create schema net;
 create table vault.decrypted_secrets(name text primary key, decrypted_secret text);
 insert into vault.decrypted_secrets values('maak_project_url','https://ref.supabase.co'),('maak_push_secret','s');
 create table net.calls(id serial, body jsonb);
 create function net.http_post(url text, body jsonb, params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
  returns bigint language sql as $$ insert into net.calls(body) values(body) returning id::bigint $$;`);
await db.exec(read('supabase/migrations/20261106000000_push_notifications.sql').replace('create extension if not exists pg_net with schema extensions;',''));
await db.exec(read('supabase/migrations/20261107020000_single_restriction_push.sql'));
await db.exec(read('supabase/migrations/20261121000000_voice_calls.sql'));
const migration=read('supabase/migrations/20261127030000_voice_call_ringing.sql');
await db.exec(migration);await db.exec(migration); // repeatable
const u=[1,2,3,4].map(n=>`20000000-0000-0000-0000-${String(n).padStart(12,'0')}`);
for(let i=0;i<4;i++)await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[u[i],`u${i}@example.com`,JSON.stringify({full_name:['Sara','Vera','Omar','Admin'][i],role:i===1?'volunteer':'help_seeker'})]);
await db.query("update profiles set role='admin' where id=$1",[u[3]]);
await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Experience','approved')",[u[1]]);
for(const i of [0,1])await db.query('insert into device_tokens(token,user_id) values($1,$2)',[`token-${i}`.padEnd(30,'x'),u[i]]);
const r='30000000-0000-0000-0000-000000000001';
await db.query("insert into support_requests(id,seeker_id,volunteer_id,status) values($1,$2,$3,'accepted')",[r,u[0],u[1]]);
async function as(i){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[u[i]]);await db.exec('set role authenticated');}
const offer={type:'offer',sdp:'test-offer-sdp-content'};
const answer={type:'answer',sdp:'test-answer-sdp-content'};
async function action(a,id=null,payload={},request=null){const res=await db.query('select voice_call_action($1,$2,$3,$4) as c',[a,id,request,payload]);return res.rows[0].c;}
let count=0;async function check(name,f){await f();console.log('PASS',name);count++;}
async function pushes(kind){await db.exec('reset role');return (await db.query("select body from net.calls where body->>'kind'=$1 order by id",[kind])).rows.map(x=>x.body);}
async function missed(i){await db.exec('reset role');return (await db.query("select title,body,reference_id from notifications where user_id=$1 and kind='voice_call_missed' order by created_at",[u[i]])).rows;}
let call;
await check('RING-01 a new call pushes "Incoming voice call" to the callee only',async()=>{await as(0);call=await action('start',null,offer,r);const p=await pushes('voice_call');assert.equal(p.length,1);assert.equal(p[0].user_id,u[1]);assert.equal(p[0].title,'Incoming voice call');assert.equal(p[0].body,"Sara is calling you. Open Ma'ak to answer.");assert.equal(p[0].reference_id,r);});
await check('RING-02 the ringing push is not stored in the notification list',async()=>{await db.exec('reset role');assert.equal((await db.query("select count(*)::int n from notifications where kind like 'voice_call%'")).rows[0].n,0);});
await check('MISS-01 caller hangs up before an answer: callee gets "Missed voice call", pushed',async()=>{await as(0);await action('end',call.id);const m=await missed(1);assert.equal(m.length,1);assert.equal(m[0].title,'Missed voice call');assert.equal(m[0].body,'Sara tried to call you.');assert.equal(m[0].reference_id,r);const p=await pushes('voice_call_missed');assert.equal(p.length,1);assert.equal(p[0].user_id,u[1]);assert.equal(p[0].reference_id,r);assert.equal((await missed(0)).length,0);});
await check('MISS-02 nobody answers in time: missed call after the server timeout',async()=>{await as(1);call=await action('start',null,offer,r);assert.equal((await pushes('voice_call')).filter(p=>p.user_id===u[0]).length,1);await db.exec('reset role');await db.query("update voice_calls set created_at=now()-interval '65 seconds' where id=$1",[call.id]);await as(1);await action('sync');const m=await missed(0);assert.equal(m.length,1);assert.equal(m[0].body,'Vera tried to call you.');});
await check('MISS-03 declining sends no missed call',async()=>{await as(0);call=await action('start',null,offer,r);await as(1);await action('reject',call.id);assert.equal((await missed(1)).length,1);});
await check('MISS-04 an answered call that ends sends no missed call',async()=>{await as(0);call=await action('start',null,offer,r);await as(1);await action('accept',call.id,answer);await action('end',call.id);assert.equal((await missed(1)).length,1);});
await check('MISS-05 a call ended because the chat was restricted sends no missed call',async()=>{await as(0);call=await action('start',null,offer,r);await db.exec('reset role');await db.query('update support_requests set restricted_at=now() where id=$1',[r]);await as(0);await action('sync');assert.equal((await db.query('select status,end_reason from voice_calls where id=$1',[call.id])).rows[0].end_reason,'conversation_unavailable');assert.equal((await missed(1)).length,1);await db.query('update support_requests set restricted_at=null where id=$1',[r]);});
await check('MISS-06 no device: nothing is pushed, the missed call is still listed in the app',async()=>{await db.exec('reset role');await db.query('delete from device_tokens where user_id=$1',[u[1]]);const before=(await pushes('voice_call')).length;await as(0);call=await action('start',null,offer,r);assert.equal((await pushes('voice_call')).length,before);await action('end',call.id);assert.equal((await missed(1)).length,2);});
await check('ROLL-01 rollback stops the pushes; migration re-applies',async()=>{await db.exec('reset role');await db.exec(read('supabase/rollbacks/20261127030000_voice_call_ringing_rollback.sql'));await db.query('insert into device_tokens(token,user_id) values($1,$2)',['token-1'.padEnd(30,'x'),u[1]]);const before=(await pushes('voice_call')).length;await as(0);call=await action('start',null,offer,r);await action('end',call.id);assert.equal((await pushes('voice_call')).length,before);assert.equal((await missed(1)).length,0);await db.exec('reset role');await db.exec(migration);});
console.log(`${count} voice call ringing checks passed`);await db.close();
