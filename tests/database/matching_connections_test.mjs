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
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}
const candidateIds=d=>d.candidates.map(c=>c.user_id).sort();
await check('CONNECTION-01 multiple eligible volunteers returned before connecting',async()=>assert.deepEqual(candidateIds(await context()),[ids.a,ids.b]));
let accepted,pending;
await check('CONNECTION-02 accepted connection removed, another eligible volunteer remains',async()=>{await as('');accepted=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id",[ids.seeker,ids.a])).rows[0].id;await db.query("insert into messages(request_id,sender_id,body) values($1,$2,'Hello')",[accepted,ids.seeker]);assert.deepEqual(candidateIds(await context()),[ids.b]);});
await check('CONNECTION-03 repeated lookup does not restore accepted volunteer',async()=>assert.deepEqual(candidateIds(await context()),[ids.b]));
await check('CONNECTION-04 pending request excluded and empty result has no recycled connection',async()=>{await as('');pending=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'pending') returning id",[ids.seeker,ids.b])).rows[0].id;assert.deepEqual(candidateIds(await context()),[]);});
await check('CONNECTION-05 canceled request becomes eligible again',async()=>{await as('');await db.query("update support_requests set status='canceled' where id=$1",[pending]);assert.deepEqual(candidateIds(await context()),[ids.b]);});
await check('CONNECTION-06 another seeker relationship never hides a candidate for this seeker',async()=>{await as('');await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'pending')",[ids.other,ids.b]);assert.deepEqual(candidateIds(await context()),[ids.b]);});
await check('CONNECTION-07 accepted conversation and message remain accessible',async()=>{await as('seeker');const rows=(await db.query('select * from my_support_requests()')).rows.map(r=>r.my_support_requests);assert.equal(rows.find(r=>r.id===accepted).status,'accepted');assert.equal((await db.query('select body from messages where request_id=$1',[accepted])).rows[0].body,'Hello');});
await check('CONNECTION-08 general mode excludes open relationships too',async()=>{await as('');await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted')",[ids.other,ids.a]);const d=await context('other');assert.equal(d.general_mode,true);assert.deepEqual(candidateIds(d),[ids.c]);assert.equal(JSON.stringify(d).includes('Hello'),false);});
await check('CONNECTION-09 declined request does not block new recommendations',async()=>{await as('');await db.query("update support_requests set status='declined' where id=$1",[pending]);assert.deepEqual(candidateIds(await context()),[ids.b]);});
await check('CONNECTION-10 volunteers cannot obtain matching context',async()=>{await as('a');await assert.rejects(()=>db.query('select maak_matching_context()'));});
console.log(`${n} matching connection checks passed`);await db.close();
