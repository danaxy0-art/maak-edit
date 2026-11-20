// Profile pictures: avatar_path shape/ownership check and avatars bucket policies.
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');
const mig=f=>read('supabase/migrations/'+f);
const db=new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated; alter table storage.objects enable row level security;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;',''));
for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql']) await db.exec(mig(f));
await db.exec('alter table public.support_requests add column restricted_at timestamptz;');
for(const f of ['20261021_account_blocking.sql','20261022_account_moderation_visibility.sql','20261023_account_appeals.sql']) await db.exec(mig(f));
const pics=mig('20261107000000_profile_pictures.sql');await db.exec(pics);await db.exec(pics);

const a='a1111111-1111-4111-8111-111111111111',b='b2222222-2222-4222-8222-222222222222',admin='c3333333-3333-4333-8333-333333333333';
for(const [u,n] of [[a,'Dana'],[b,'Sara'],[admin,'Admin']]) await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)`,[u,`${n}@x.com`,JSON.stringify({full_name:n,role:'help_seeker'})]);
await db.query(`update profiles set role='admin' where id=$1`,[admin]);
async function as(u){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[u??'']);await db.exec(u?'set role authenticated':'reset role');}
const good=`${a}/0f8fad5b-d9cb-4f9f-9c3a-2f1e4b6d7a10.jpg`;
let checks=0;async function ok(label,fn){await fn();checks++;console.log('PASS',label);}

await ok('bucket is private with a 5 MB image-only limit',async()=>{
 await as(null);const r=(await db.query(`select public,file_size_limit,allowed_mime_types from storage.buckets where id='avatars'`)).rows[0];
 assert.equal(r.public,false);assert.equal(Number(r.file_size_limit),5242880);assert.deepEqual(r.allowed_mime_types,['image/png','image/jpeg','image/webp']);
});
await ok('a user can set and clear their own picture path',async()=>{
 await as(a);await db.query('update profiles set avatar_path=$1 where id=$2',[good,a]);
 assert.equal((await db.query('select avatar_path from profiles where id=$1',[a])).rows[0].avatar_path,good);
 await db.query('update profiles set avatar_path=null where id=$1',[a]);
});
await ok("paths outside the user's folder or in the wrong shape are rejected",async()=>{
 await as(a);
 for(const bad of [`${b}/0f8fad5b-d9cb-4f9f-9c3a-2f1e4b6d7a10.jpg`,`${a}/photo.jpg`,`${a}/0f8fad5b-d9cb-4f9f-9c3a-2f1e4b6d7a10.gif`,`${a}/../x.jpg`])
  await assert.rejects(db.query('update profiles set avatar_path=$1 where id=$2',[bad,a]),/invalid_avatar_path/);
});
await ok("uploads only into one's own folder",async()=>{
 await as(a);await db.query(`insert into storage.objects(bucket_id,name) values('avatars',$1)`,[good]);
 await assert.rejects(db.query(`insert into storage.objects(bucket_id,name) values('avatars',$1)`,[`${b}/0f8fad5b-d9cb-4f9f-9c3a-2f1e4b6d7a11.jpg`]));
});
await ok('other members can see a picture but cannot delete it',async()=>{
 await as(b);assert.equal((await db.query(`select * from storage.objects where bucket_id='avatars'`)).rows.length,1);
 await db.query(`delete from storage.objects where bucket_id='avatars'`);
 await as(admin);assert.equal((await db.query(`select * from storage.objects where bucket_id='avatars'`)).rows.length,1);
 await as(a);assert.equal((await db.query(`select * from storage.objects where bucket_id='avatars'`)).rows.length,1);
 await db.query(`delete from storage.objects where bucket_id='avatars' and name=$1`,[good]);
 assert.equal((await db.query(`select * from storage.objects where bucket_id='avatars'`)).rows.length,0);
});
await ok('a restricted account cannot upload a picture',async()=>{
 await as(admin);await db.query(`select admin_block_account($1,'Spam')`,[a]);
 await as(a);await assert.rejects(db.query(`insert into storage.objects(bucket_id,name) values('avatars',$1)`,[good]));
});
console.log(`${checks} profile picture checks passed`);

// Shared pictures (20261107010000).
await as(admin);await db.query(`select admin_reactivate_account($1)`,[a]);
await db.exec('reset role');
const shared=mig('20261107010000_shared_profile_pictures.sql');await db.exec(shared);await db.exec(shared);
await db.exec(pics); // re-running the first file afterwards must not hide pictures again
const bPic=`${b}/1f8fad5b-d9cb-4f9f-9c3a-2f1e4b6d7a10.png`;
await as(b);await db.query(`insert into storage.objects(bucket_id,name) values('avatars',$1)`,[bPic]);await db.query('update profiles set avatar_path=$1 where id=$2',[bPic,b]);
await ok('other members can now see a picture and look up its path',async()=>{
 await as(a);assert.equal((await db.query(`select * from storage.objects where bucket_id='avatars' and name=$1`,[bPic])).rows.length,1);
 const r=(await db.query('select * from maak_avatar_paths($1)',[[a,b,admin]])).rows;assert.deepEqual(r.map(x=>x.avatar_path),[bPic]);
 await assert.rejects(db.query(`delete from storage.objects where name=$1 returning 1`,[bPic]).then(x=>{if(!x.rows.length)throw new Error('nothing deleted');}));
});
await ok("a restricted member's picture is hidden from others, and they can't see others'",async()=>{
 await as(admin);await db.query(`select admin_block_account($1,'Check')`,[b]);
 await as(a);assert.equal((await db.query('select * from maak_avatar_paths($1)',[[b]])).rows.length,0);
 await as(admin);assert.equal((await db.query('select * from maak_avatar_paths($1)',[[b]])).rows.length,1,'admins still see it');
 await as(b);assert.equal((await db.query('select * from maak_avatar_paths($1)',[[b]])).rows.length,0,'restricted callers get nothing');
});
await ok('signed-out callers get nothing',async()=>{
 await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub','',false)");await db.exec('set role anon');
 await assert.rejects(db.query('select * from maak_avatar_paths($1)',[[b]]));
});
console.log(`${checks} profile picture checks passed (with sharing)`);
