import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon; create role authenticated;
create schema auth; create schema storage;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to anon,authenticated;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated;
grant select,insert on storage.objects to authenticated;`);
let sql=readFileSync(new URL('../../supabase_schema.sql', import.meta.url), 'utf8');
sql=sql.replace('create extension if not exists pgcrypto;','');
await db.exec(sql);
// Verify upgrade is safe to rerun.
await db.exec(sql);
const ids={admin:'00000000-0000-0000-0000-000000000001',seeker:'00000000-0000-0000-0000-000000000002',volunteer:'00000000-0000-0000-0000-000000000003',other:'00000000-0000-0000-0000-000000000004'};
for(const [name,id] of Object.entries(ids)) await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)`,[id,`${name}@example.com`,JSON.stringify({full_name:name,username:name,role:name==='volunteer'?'volunteer':'help_seeker'})]);
await db.query(`update public.profiles set role='admin' where id=$1`,[ids.admin]);
await db.query(`insert into storage.objects(bucket_id,name) values('verification-documents',$1)`,[`${ids.volunteer}/proof.pdf`]);
async function as(name){await db.exec('reset role'); await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[ids[name]||'']);await db.exec(`set role ${name==='anon'?'anon':'authenticated'}`);}
let checks=0;
async function ok(label,fn){await fn();checks++;console.log('PASS',label);}
async function fail(query,params=[]){let failed=false;try{await db.query(query,params)}catch(e){failed=true;}assert.equal(failed,true);}
const save=`select save_maak_profile($1,$2,$3,$4,$5,$6,$7,$8)`;
await ok('seeker profile persists atomically',async()=>{await as('seeker');await db.query(save,['Dana','dana','help_seeker','Diabetes','English','Support',null,false]);assert.equal((await db.query('select * from help_seeker_profiles')).rows.length,1);});
await ok('registration without username metadata completes and is visible to admin',async()=>{
await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub','',false)");const id='00000000-0000-0000-0000-000000000005';
await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,'new@example.com',$2)`,[id,JSON.stringify({full_name:'New volunteer',role:'volunteer'})]);
await db.query(`insert into storage.objects(bucket_id,name) values('verification-documents',$1)`,[`${id}/proof.pdf`]);
await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
await db.query(save,['New volunteer','user_00000000000000000000','volunteer','Asthma','English','My experience',`${id}/proof.pdf`,false]);
await as('admin');const rows=(await db.query('select * from admin_volunteer_applications()')).rows;assert.equal(rows.length,1);assert.equal(rows[0].admin_volunteer_applications.user_id,id);
await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub','',false)");await db.query('delete from auth.users where id=$1',[id]);
});
await ok('self role promotion rejected',async()=>{await as('seeker');await fail(`update profiles set role='admin' where id=$1`,[ids.seeker]);});
await ok('volunteer registration requires a stored document',async()=>{await as('volunteer');await fail(save,['Sara','sara','volunteer','Asthma','English','Experience',null,false]);await db.query(save,['Sara','sara','volunteer','Asthma','English','Experience',`${ids.volunteer}/proof.pdf`,false]);});
await ok('admin sees application and profile without brittle foreign-key joins',async()=>{await as('admin');const r=await db.query('select * from admin_volunteer_applications()');assert.equal(r.rows.length,1);assert.equal(r.rows[0].admin_volunteer_applications.profiles.full_name,'Sara');});
await ok('empty rejection reason keeps application pending',async()=>{await as('admin');await fail(`select review_volunteer_application($1,false,'  ')`,[ids.volunteer]);assert.equal((await db.query('select status from volunteer_profiles')).rows[0].status,'pending_review');});
await ok('reject stores reason and notification',async()=>{await as('admin');await db.query(`select review_volunteer_application($1,false,'Unclear document')`,[ids.volunteer]);await as('volunteer');const r=await db.query('select * from notifications');assert.equal(r.rows[0].title,'Application not approved');});
await ok('volunteer cannot approve themselves',async()=>{await as('volunteer');await fail(`update volunteer_profiles set status='approved' where user_id=$1`,[ids.volunteer]);await fail(`select review_volunteer_application($1,true,null)`,[ids.volunteer]);});
await ok('reapplication keeps document and returns to pending',async()=>{await as('volunteer');await db.query(save,['Sara','sara','volunteer','Asthma','English','Updated experience',null,true]);const r=await db.query('select * from volunteer_profiles');assert.equal(r.rows[0].status,'pending_review');assert.equal(r.rows[0].rejection_reason,null);assert.ok(r.rows[0].verification_document_url.endsWith('proof.pdf'));});
await ok('admin approval and duplicate decisions checked server-side',async()=>{await as('admin');await db.query(`select review_volunteer_application($1,true,null)`,[ids.volunteer]);await fail(`select review_volunteer_application($1,false,'Again')`,[ids.volunteer]);});
await ok('approved volunteer directory omits verification documents',async()=>{await as('seeker');const r=await db.query('select * from browse_volunteers()');assert.equal(r.rows.length,1);assert.equal(r.rows[0].browse_volunteers.verification_document_url,undefined);});
let request;
await ok('support request persists and duplicate request is rejected',async()=>{await as('seeker');await db.query('select request_peer_support($1)',[ids.volunteer]);await fail('select request_peer_support($1)',[ids.volunteer]);request=(await db.query('select id from support_requests')).rows[0].id;});
await ok('only the assigned volunteer can accept',async()=>{await as('other');await fail('select decide_support_request($1,true)',[request]);await as('volunteer');await db.query('select decide_support_request($1,true)',[request]);});
await ok('chat is private and message triggers recipient notification',async()=>{await as('seeker');await db.query(`insert into messages(request_id,sender_id,body) values($1,$2,'Hello')`,[request,ids.seeker]);await as('other');assert.equal((await db.query('select * from messages')).rows.length,0);await fail(`insert into messages(request_id,sender_id,body) values($1,$2,'Intrusion')`,[request,ids.other]);await as('volunteer');assert.equal((await db.query(`select * from notifications where kind='message'`)).rows.length,1);});
await ok('notification content cannot be changed by recipient',async()=>{await as('volunteer');await fail(`update notifications set title='forged'`);await db.query(`update notifications set is_read=true`);assert.equal((await db.query('select * from notifications where is_read=false')).rows.length,0);});
await ok('session scheduling rejects past and overlapping sessions',async()=>{await as('volunteer');await fail(`select book_support_session($1,now()-interval '1 hour')`,[request]);await db.query(`select book_support_session($1,now()+interval '1 day')`,[request]);await fail(`select book_support_session($1,now()+interval '1 day 10 minutes')`,[request]);await as('seeker');assert.equal((await db.query('select * from my_support_sessions()')).rows.length,1);});
await ok('condition rename propagates, disable preserves existing profile',async()=>{await as('admin');await db.query(`update chronic_conditions set name='Type 2 diabetes' where name='Diabetes'`);await db.query(`update chronic_conditions set is_active=false where name='Type 2 diabetes'`);await as('seeker');await db.query(save,['Dana','dana','help_seeker','Type 2 diabetes','Arabic','Updated',null,false]);await as('other');await fail(save,['Other','other','help_seeker','Type 2 diabetes','English','',null,false]);});
await ok('anonymous registration only sees active conditions',async()=>{await as('anon');const r=await db.query('select * from chronic_conditions');assert.equal(r.rows.every(r=>r.is_active),true);await fail('select * from profiles');});
console.log(`${checks} integration checks passed`);await db.close();
