// ADDED: checks for supabase/migrations/20261105_message_reports.sql
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to anon,authenticated;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert on storage.objects to authenticated;`);
await db.exec(readFileSync(new URL('../../supabase_schema.sql',import.meta.url),'utf8').replace('create extension if not exists pgcrypto;',''));
const migration=readFileSync(new URL('../../supabase/migrations/20261105_message_reports.sql',import.meta.url),'utf8');
await db.exec(migration);await db.exec(migration); // idempotent

const ids={seeker:'10000000-0000-0000-0000-000000000001',vol:'10000000-0000-0000-0000-000000000002',other:'10000000-0000-0000-0000-000000000003',admin:'10000000-0000-0000-0000-000000000004'};
for(const [name,id] of Object.entries(ids))await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[id,JSON.stringify({full_name:name,role:name==='vol'?'volunteer':name==='admin'?'help_seeker':'help_seeker'})]);
await db.query("update profiles set role='admin' where id=$1",[ids.admin]);
await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Experience','approved')",[ids.vol]);
async function as(name){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]??'']);if(name)await db.exec('set role authenticated');}
await as('');
const req=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id",[ids.seeker,ids.vol])).rows[0].id;
const send=async(who,body)=>(await db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3) returning id',[req,ids[who],body])).rows[0].id;
const fromVol=await send('vol','a message from the volunteer'),fromSeeker=await send('seeker','a message from the seeker');
const report=(msg,reason,desc)=>db.query('select report_maak_message($1,$2,$3)',[msg,reason,desc]);
const count=async()=>{await as('');return Number((await db.query('select count(*) n from reports')).rows[0].n);};
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}

await check('RPT-01 seeker reports the other person\'s message with a reason',async()=>{await as('seeker');await report(fromVol,'harassment',null);assert.equal(await count(),1);});
await check('RPT-02 saved row has the right reason, reporter and reported user',async()=>{await as('');const r=(await db.query('select * from reports')).rows[0];assert.equal(r.reason,'harassment');assert.equal(r.reporter_id,ids.seeker);assert.equal(r.reported_user_id,ids.vol);assert.equal(r.description,null);assert.equal(r.status,'open');});
await check('RPT-03 reporting the same message twice is refused',async()=>{await as('seeker');await assert.rejects(()=>report(fromVol,'spam',null),/already_reported/);assert.equal(await count(),1);});
await check('RPT-04 cannot report your own message',async()=>{await as('seeker');await assert.rejects(()=>report(fromSeeker,'spam',null),/cannot_report_own_message/);});
await check('RPT-05 reason is required',async()=>{await as('vol');await assert.rejects(()=>report(fromSeeker,null,null),/invalid_report_reason/);});
await check('RPT-06 unknown reason is refused',async()=>{await as('vol');await assert.rejects(()=>report(fromSeeker,'because','x'),/invalid_report_reason/);});
await check('RPT-07 optional description is saved trimmed',async()=>{await as('vol');await report(fromSeeker,'other','  please review  ');await as('');const r=(await db.query('select description from reports where reporter_id=$1',[ids.vol])).rows[0];assert.equal(r.description,'please review');});
await check('RPT-08 blank description is stored as null',async()=>{await as('');const m=await send('vol','another');await as('seeker');await report(m,'spam','   ');await as('');const r=(await db.query('select description from reports where message_id=$1',[m])).rows[0];assert.equal(r.description,null);});
await check('RPT-09 description over 500 characters is refused',async()=>{await as('');const m=await send('vol','long one');await as('seeker');await assert.rejects(()=>report(m,'other','x'.repeat(501)),/invalid_report_description/);});
await check('RPT-10 description of exactly 500 characters is accepted',async()=>{await as('');const m=await send('vol','edge');await as('seeker');await report(m,'other','x'.repeat(500));});
await check('RPT-11 someone outside the conversation cannot report it',async()=>{await as('other');await assert.rejects(()=>report(fromVol,'spam',null),/not_allowed/);});
await check('RPT-12 clients cannot insert reports directly',async()=>{await as('seeker');await assert.rejects(()=>db.query("insert into reports(message_id,request_id,reporter_id,reported_user_id,reason) values($1,$2,$3,$4,'spam')",[fromVol,req,ids.seeker,ids.vol]));});
await check('RPT-13 a reporter sees only their own reports',async()=>{await as('seeker');const rows=(await db.query('select reporter_id from reports')).rows;assert.ok(rows.length>0&&rows.every(r=>r.reporter_id===ids.seeker));});
await check('RPT-14 an unrelated user sees no reports',async()=>{await as('other');assert.equal((await db.query('select * from reports')).rows.length,0);});
await check('RPT-15 admin can read all reports',async()=>{await as('admin');assert.ok((await db.query('select * from reports')).rows.length>=4);});
await check('RPT-16 anonymous cannot call the RPC',async()=>{await db.exec('reset role');await db.exec('set role anon');await assert.rejects(()=>report(fromVol,'spam',null));});
console.log(`${n} report checks passed`);await db.close();
