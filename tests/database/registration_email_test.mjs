import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema storage;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to anon,authenticated;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert on storage.objects to authenticated;`);
await db.exec(readFileSync(new URL('../../supabase_schema.sql',import.meta.url),'utf8').replace('create extension if not exists pgcrypto;',''));
await db.exec(readFileSync(new URL('../../supabase/migrations/20261018_matching.sql',import.meta.url),'utf8'));
const migration=readFileSync(new URL('../../supabase/migrations/20261018_condition_reviews.sql',import.meta.url),'utf8');
await db.exec(migration);await db.exec(migration);
await db.exec(readFileSync(new URL('../../supabase/migrations/20261021_matching_connections.sql',import.meta.url),'utf8'));
await db.exec(readFileSync(new URL('../../supabase/migrations/20261021_matching_connections.sql',import.meta.url),'utf8'));

const ids={seeker:'10000000-0000-0000-0000-000000000001',other:'10000000-0000-0000-0000-000000000002',a:'10000000-0000-0000-0000-000000000003',b:'10000000-0000-0000-0000-000000000004',c:'10000000-0000-0000-0000-000000000005',admin:'10000000-0000-0000-0000-000000000006'};
for(const [name,id] of Object.entries(ids))await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[id,JSON.stringify({full_name:name,role:['a','b','c'].includes(name)?'volunteer':'help_seeker'})]);
await db.query("update profiles set role='admin' where id=$1",[ids.admin]);
await db.query("insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English'),($2,'Other','English')",[ids.seeker,ids.other]);
for(const name of ['a','b','c'])await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,$2,'English','Experience','approved')",[ids[name],name==='c'?'Asthma':'Diabetes']);
await db.exec("insert into user_conditions(user_id,condition_id) select h.user_id,c.id from help_seeker_profiles h join chronic_conditions c on c.name=h.chronic_condition;insert into user_conditions(user_id,condition_id) select v.user_id,c.id from volunteer_profiles v join chronic_conditions c on c.name=v.condition_experience;");
async function as(name){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]??'']);if(name)await db.exec('set role authenticated');}
async function context(name='seeker'){await as(name);return(await db.query('select maak_matching_context() as data')).rows[0].data;}
await db.exec(readFileSync(new URL('../../FIX_CHAT.sql',import.meta.url),'utf8'));
await db.exec(readFileSync(new URL('../../FIX_CHAT.sql',import.meta.url),'utf8'));
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}
const candidateIds=d=>d.candidates.map(c=>c.user_id).sort();


await db.exec(readFileSync(new URL('../../FIX_REGISTRATION.sql',import.meta.url),'utf8'));
await db.exec(readFileSync(new URL('../../FIX_REGISTRATION.sql',import.meta.url),'utf8'));
await as('');await db.query('update auth.users set email=$1 where id=$2',['patient@example.com',ids.seeker]);await db.query('update auth.users set email=$1 where id=$2',['volunteer@example.com',ids.a]);
const hash='a'.repeat(64);
async function lookup(email,key=hash){return (await db.query('select check_maak_registration_email($1,$2) value',[email,key])).rows[0].value;}
await check('EMAIL-01 anonymous direct database lookup denied',async()=>{await db.exec('set role anon');await assert.rejects(()=>lookup('patient@example.com'));await db.exec('reset role');});
await check('EMAIL-02 authenticated direct lookup denied',async()=>{await as('seeker');await assert.rejects(()=>lookup('patient@example.com'));await as('');});
await db.exec('set role service_role');
await check('EMAIL-03 existing patient detected without role disclosure',async()=>assert.deepEqual(await lookup('patient@example.com'),{exists:true}));
await check('EMAIL-04 existing volunteer detected with identical response',async()=>assert.deepEqual(await lookup('volunteer@example.com'),{exists:true}));
await check('EMAIL-05 trim and case normalization',async()=>assert.deepEqual(await lookup('  PATIENT@EXAMPLE.COM  '),{exists:true}));
await check('EMAIL-06 new email available',async()=>assert.deepEqual(await lookup('new@example.com'),{exists:false}));
await check('EMAIL-07 malformed input rejected',async()=>{await assert.rejects(()=>lookup('bad'));await assert.rejects(()=>lookup('a'.repeat(250)+'@example.com'));await assert.rejects(()=>lookup('new@example.com','bad'));});
await check('EMAIL-08 persistent rate limit after thirty checks',async()=>{const key='b'.repeat(64);for(let i=0;i<30;i++)assert.deepEqual(await lookup('new@example.com',key),{exists:false});assert.deepEqual(await lookup('new@example.com',key),{limited:true});});
await check('EMAIL-09 rate window resets',async()=>{await db.exec('reset role');await db.query("update maak_registration_check_limits set window_start=now()-interval '11 minutes' where client_hash=$1",['b'.repeat(64)]);await db.exec('set role service_role');assert.deepEqual(await lookup('new@example.com','b'.repeat(64)),{exists:false});});
console.log(`${n} email checks passed`);await db.close();
