// Push notifications: each of the six events queues exactly one send-push call
// to the right user. pg_net and Vault are stubbed; net.http_post records calls.
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';

const db=new PGlite();
await db.exec(`create role anon; create role authenticated;
create schema auth; create schema storage; create schema extensions; create schema vault; create schema net;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to anon,authenticated;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated;
grant select,insert on storage.objects to authenticated;
create table vault.decrypted_secrets(name text primary key, decrypted_secret text);
insert into vault.decrypted_secrets values('maak_project_url','https://ref.supabase.co/'),('maak_push_secret','s3cret');
create table net.calls(id serial, url text, headers jsonb, body jsonb);
create function net.http_post(url text, body jsonb, params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
 returns bigint language sql as $$ insert into net.calls(url,headers,body) values(url,headers,body) returning id::bigint $$;`);

let schema=readFileSync(new URL('../../supabase_schema.sql',import.meta.url),'utf8').replace('create extension if not exists pgcrypto;','');
await db.exec(schema);
// Minimal stand-in for the account_blocking migration pieces the push migration uses.
await db.exec(`create table public.account_blocks(user_id uuid primary key references public.profiles(id) on delete cascade, reason text not null);
create function public.is_maak_account_blocked(p_user_id uuid) returns boolean language sql stable security definer set search_path=public
 as $$ select exists(select 1 from account_blocks where user_id=p_user_id) $$;`);
const push=readFileSync(new URL('../../supabase/migrations/20261106000000_push_notifications.sql',import.meta.url),'utf8')
 .replace('create extension if not exists pg_net with schema extensions;','');
await db.exec(push);
await db.exec(push); // rerunnable

const ids={admin:'00000000-0000-0000-0000-000000000001',seeker:'00000000-0000-0000-0000-000000000002',volunteer:'00000000-0000-0000-0000-000000000003'};
for(const [name,id] of Object.entries(ids)) await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)`,[id,`${name}@example.com`,JSON.stringify({full_name:name,username:name,role:name==='volunteer'?'volunteer':'help_seeker'})]);
await db.query(`update public.profiles set role='admin' where id=$1`,[ids.admin]);
await db.query(`insert into storage.objects(bucket_id,name) values('verification-documents',$1)`,[`${ids.volunteer}/proof.pdf`]);

async function as(name){await db.exec('reset role');await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[ids[name]||'']);await db.exec(`set role ${name==='anon'?'anon':'authenticated'}`);}
async function asSystem(){await db.exec('reset role');await db.query(`select set_config('request.jwt.claim.sub','',false)`);}
async function calls(){await db.exec('reset role');const r=(await db.query('select url,headers,body from net.calls order by id')).rows;await db.exec('delete from net.calls');return r;}
async function fails(q,p=[]){try{await db.query(q,p);}catch{return true;}return false;}
let checks=0;
async function ok(label,fn){await fn();checks++;console.log('PASS',label);}
const token=n=>`fcm-token-${n}-`.padEnd(40,'x');

await ok('anon cannot register a token; signed-in users can',async()=>{
 await as('anon');assert.equal(await fails('select register_maak_device_token($1)',[token('a')]),true);
 for(const n of Object.keys(ids)){await as(n);await db.query(`select register_maak_device_token($1,'android')`,[token(n)]);}
 await as('seeker');assert.equal(await fails('select * from device_tokens'),true);
 assert.equal(await fails(`select register_maak_device_token('short')`),true);
 assert.equal(await fails(`select register_maak_device_token($1,'symbian')`,[token('z')]),true);
});
await ok('clients cannot call the internal sender',async()=>{
 await as('seeker');assert.equal(await fails(`select send_maak_push($1,'x','y','info')`,[ids.seeker]),true);
});
await ok('3. new volunteer application pushes to admins',async()=>{
 await calls();await as('volunteer');
 await db.query(`select save_maak_profile($1,$2,$3,$4,$5,$6,$7,$8)`,['Vol','volunteer','volunteer','Asthma','English','My story',`${ids.volunteer}/proof.pdf`,false]);
 const c=await calls();assert.equal(c.length,1);assert.equal(c[0].body.user_id,ids.admin);assert.equal(c[0].body.kind,'application');
 assert.equal(c[0].url,'https://ref.supabase.co/functions/v1/send-push');assert.equal(c[0].headers['x-push-secret'],'s3cret');
});
await ok('2. application decision pushes to the volunteer',async()=>{
 await as('admin');await db.query('select review_volunteer_application($1,true,null)',[ids.volunteer]);
 const c=await calls();assert.equal(c.length,1);assert.equal(c[0].body.user_id,ids.volunteer);assert.equal(c[0].body.title,'Application approved');
});
let request;
await ok('4. new support request pushes to the volunteer',async()=>{
 await as('seeker');await db.query(`select save_maak_profile($1,$2,$3,$4,$5,$6,$7,$8)`,['Dana','seeker','help_seeker','Diabetes','English','Hi',null,false]);await calls();
 await as('seeker');await db.query('select request_peer_support($1)',[ids.volunteer]);
 await db.exec('reset role');request=(await db.query('select id from support_requests')).rows[0].id;
 const c=await calls();assert.equal(c.length,1);assert.equal(c[0].body.user_id,ids.volunteer);assert.equal(c[0].body.kind,'request');assert.equal(c[0].body.reference_id,request);
});
await ok('5. accepting pushes to the help seeker',async()=>{
 await as('volunteer');await db.query('select decide_support_request($1,true)',[request]);
 const c=await calls();assert.equal(c.length,1);assert.equal(c[0].body.user_id,ids.seeker);assert.equal(c[0].body.title,'Your support request was accepted');
});
await ok('1. chat messages push to the other participant, both directions',async()=>{
 await as('seeker');await db.query(`insert into messages(request_id,sender_id,body) values($1,$2,'Hello')`,[request,ids.seeker]);
 await as('volunteer');await db.query(`insert into messages(request_id,sender_id,body) values($1,$2,'Hi!')`,[request,ids.volunteer]);
 const c=await calls();assert.equal(c.length,2);
 assert.deepEqual(c.map(x=>x.body.user_id),[ids.volunteer,ids.seeker]);
 assert.ok(c.every(x=>x.body.kind==='message'&&x.body.reference_id===request&&x.body.notification_id));
 assert.ok(!c.some(x=>JSON.stringify(x.body).includes('Hello')),'message text must not be in the push');
});
await ok('6. restriction pushes; blocked users get only account pushes; reactivation pushes',async()=>{
 await asSystem();await db.query(`insert into account_blocks(user_id,reason) values($1,'Spam')`,[ids.seeker]);
 let c=await calls();assert.equal(c.length,1);assert.equal(c[0].body.kind,'account_blocked');assert.ok(!JSON.stringify(c[0].body).includes('Spam'));
 await db.query(`insert into notifications(user_id,title,body,kind) values($1,'x','y','request')`,[ids.seeker]);
 assert.equal((await calls()).length,0);
 await db.query('delete from account_blocks where user_id=$1',[ids.seeker]);
 await db.query(`insert into notifications(user_id,title,body,kind) values($1,'Account reactivated','Welcome back.','account')`,[ids.seeker]);
 c=await calls();assert.equal(c.length,1);assert.equal(c[0].body.kind,'account');
});
await ok('no token or missing vault secrets: no call, action still succeeds',async()=>{
 await as('seeker');await db.query('select unregister_maak_device_token($1)',[token('seeker')]);
 await asSystem();await db.query(`insert into notifications(user_id,title,body,kind) values($1,'x','y','info')`,[ids.seeker]);
 assert.equal((await calls()).length,0);
 await db.exec(`delete from vault.decrypted_secrets`);
 await db.query(`insert into notifications(user_id,title,body,kind) values($1,'x','y','info')`,[ids.volunteer]);
 assert.equal((await calls()).length,0);
});
await ok('a token moves to whoever signed in last on the device',async()=>{
 await as('admin');await db.query('select register_maak_device_token($1)',[token('volunteer')]);
 await db.exec('reset role');const r=(await db.query('select user_id from device_tokens where token=$1',[token('volunteer')])).rows;
 assert.equal(r[0].user_id,ids.admin);
 await as('volunteer');await db.query('select unregister_maak_device_token($1)',[token('volunteer')]);
 await db.exec('reset role');assert.equal((await db.query('select 1 from device_tokens where token=$1',[token('volunteer')])).rows.length,1);
});
console.log(`${checks} push notification checks passed`);

// 20261107020000: one push per block, whatever order the block writes things in.
const single=readFileSync(new URL('../../supabase/migrations/20261107020000_single_restriction_push.sql',import.meta.url),'utf8');
await db.exec(single);await db.exec(single);
await db.exec(`reset role; insert into vault.decrypted_secrets values('maak_project_url','https://ref.supabase.co/'),('maak_push_secret','s3cret') on conflict do nothing`);
await ok('blocking sends only the restriction push, even if a notice is written first',async()=>{
 await as('volunteer');await db.query(`select register_maak_device_token($1)`,[token('volunteer')]);
 await calls();await asSystem();
 await db.exec('begin');
 await db.query(`insert into notifications(user_id,title,body,kind) values($1,'Account access updated','Your access changed.','account')`,[ids.volunteer]);
 await db.query(`insert into account_blocks(user_id,reason) values($1,'Spam')`,[ids.volunteer]);
 await db.exec('commit');
 const c=await calls();assert.deepEqual(c.map(x=>x.body.kind),['account_blocked']);
});
await ok('reactivation in one transaction is still pushed',async()=>{
 await asSystem();await db.exec('begin');
 await db.query('delete from account_blocks where user_id=$1',[ids.volunteer]);
 await db.query(`insert into notifications(user_id,title,body,kind) values($1,'Account reactivated','Welcome back.','account')`,[ids.volunteer]);
 await db.exec('commit');
 const c=await calls();assert.deepEqual(c.map(x=>x.body.title),['Account reactivated']);
});
console.log(`${checks} push notification checks passed (with single restriction push)`);
