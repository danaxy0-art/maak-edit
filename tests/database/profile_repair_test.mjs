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
const updates=readFileSync(new URL('../../APPLY_UPDATES.sql',import.meta.url),'utf8');
await db.exec(updates);await db.exec(updates);
let count=0;
async function check(name,fn){await fn();count++;console.log('PASS',name);}
async function login(id,role='authenticated'){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec(`set role ${role}`);}
async function fails(sql){await assert.rejects(()=>db.query(sql));}
const seeker='10000000-0000-0000-0000-000000000001',volunteer='10000000-0000-0000-0000-000000000002',admin='10000000-0000-0000-0000-000000000003',fake='10000000-0000-0000-0000-000000000004';
for(const [id,role] of [[seeker,'help_seeker'],[volunteer,'volunteer'],[admin,'help_seeker'],[fake,'admin']]) await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[id,JSON.stringify({role,full_name:'Test user'})]);
await db.query("update profiles set role='admin' where id=$1",[admin]);
await db.query('delete from profiles where id=any($1::uuid[])',[[seeker,volunteer,fake]]);
await check('PROFILE-01 missing seeker base row repaired for current auth user',async()=>{await login(seeker);assert.equal((await db.query('select ensure_maak_profile() as role')).rows[0].role,'help_seeker');assert.equal((await db.query('select full_name from profiles')).rows[0].full_name,'Test user');});
await check('PROFILE-02 role-specific detail is not invented by repair',async()=>{assert.equal((await db.query('select * from help_seeker_profiles')).rows.length,0);await db.query("select save_maak_profile_reviewable('Test user','seeker_profile','help_seeker',ARRAY['Diabetes'],'English','',null,false,false,null)");assert.equal((await db.query('select * from help_seeker_profiles')).rows.length,1);});
await check('PROFILE-03 repeated repair preserves existing selections',async()=>{await db.query('select ensure_maak_profile()');assert.equal((await db.query('select chronic_condition from help_seeker_profiles')).rows[0].chronic_condition,'Diabetes');});
await check('PROFILE-04 missing volunteer gets correct role without approval',async()=>{await login(volunteer);assert.equal((await db.query('select ensure_maak_profile() as role')).rows[0].role,'volunteer');assert.equal((await db.query('select * from volunteer_profiles')).rows.length,0);});
await check('PROFILE-05 editable admin metadata never grants admin',async()=>{await login(fake);assert.equal((await db.query('select ensure_maak_profile() as role')).rows[0].role,'help_seeker');assert.equal((await db.query('select is_maak_admin() as allowed')).rows[0].allowed,false);});
await check('PROFILE-06 existing admin role is preserved',async()=>{await login(admin);assert.equal((await db.query('select ensure_maak_profile() as role')).rows[0].role,'admin');});
await check('PROFILE-07 non-admin cannot create a chronic condition',async()=>{await login(seeker);await fails("insert into chronic_conditions(name) values('Unauthorized condition')");});
await check('PROFILE-08 admin can add condition and it is visible to registration',async()=>{await login(admin);await db.query("insert into chronic_conditions(name) values('Reviewed condition')");await login('', 'anon');assert.equal((await db.query("select name from chronic_conditions where name='Reviewed condition'")).rows.length,1);});
await check('PROFILE-09 anonymous repair denied',async()=>{await fails('select ensure_maak_profile()');});
console.log(`${count} profile repair checks passed`);await db.close();
