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
await db.exec(readFileSync(new URL('../../FIX_CHAT.sql',import.meta.url),'utf8'));
await db.exec(readFileSync(new URL('../../FIX_CHAT.sql',import.meta.url),'utf8'));
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}
const candidateIds=d=>d.candidates.map(c=>c.user_id).sort();

await as('');
const req=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id",[ids.seeker,ids.a])).rows[0].id;
const send=async(who,body)=>(await db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3) returning id',[req,ids[who],body])).rows[0].id;
const m1=await send('seeker','hi'),m2=await send('seeker','hello'),own=await send('a','bay');
async function count(who){await as(who);return Number((await db.query('select my_maak_unread_message_count() n')).rows[0].n);}
await check('CHAT-01 recipient counts incoming messages only',async()=>assert.equal(await count('a'),2));
await check('CHAT-02 sender has only their incoming count',async()=>assert.equal(await count('seeker'),1));
await check('CHAT-03 unrelated account cannot see unread count',async()=>assert.equal(await count('b'),0));
await check('CHAT-04 bell mark-all does not read conversation',async()=>{await as('a');await db.exec('update notifications set is_read=true');assert.equal(await count('a'),2);});
await check('CHAT-05 unrelated account cannot acknowledge chat',async()=>{await as('b');await assert.rejects(()=>db.query('select mark_maak_messages_read($1,$2::uuid[])',[req,[m1]]));});
await check('CHAT-06 acknowledgement reads only displayed incoming IDs',async()=>{await as('a');await db.query('select mark_maak_messages_read($1,$2::uuid[])',[req,[m1,own]]);assert.equal(await count('a'),1);assert.equal(await count('seeker'),1);});
await check('CHAT-07 repeated read acknowledgement is safe',async()=>{await as('a');await db.query('select mark_maak_messages_read($1,$2::uuid[])',[req,[m1]]);assert.equal(await count('a'),1);});
await check('CHAT-08 new messages racing acknowledgement remain unread',async()=>{await as('');await send('seeker','new');await as('a');await db.query('select mark_maak_messages_read($1,$2::uuid[])',[req,[m2]]);assert.equal(await count('a'),1);});
await check('CHAT-09 booking is disabled',async()=>{await as('a');await assert.rejects(()=>db.query("select book_support_session($1,now()+interval '1 day')",[req]));});
await check('CHAT-10 direct read timestamp updates blocked',async()=>{await as('a');await assert.rejects(()=>db.exec('update messages set read_at=now()'));});
await check('CHAT-11 acceptance persists and can be verified after a lost response',async()=>{await as('');const pending=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'pending') returning id",[ids.seeker,ids.b])).rows[0].id;await as('b');await db.query('select decide_support_request($1,true)',[pending]);const row=(await db.query('select status,volunteer_id from support_requests where id=$1',[pending])).rows[0];assert.equal(row.status,'accepted');assert.equal(row.volunteer_id,ids.b);});
await check('CHAT-12 decline persists and can be verified after a lost response',async()=>{await as('');const pending=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'pending') returning id",[ids.seeker,ids.c])).rows[0].id;await as('c');await db.query('select decide_support_request($1,false)',[pending]);assert.equal((await db.query('select status from support_requests where id=$1',[pending])).rows[0].status,'declined');});
console.log(`${n} chat checks passed`);await db.close();
