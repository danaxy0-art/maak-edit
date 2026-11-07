// Chat and request notifications carry names and message text, in the stored
// row and in the push. Real migration chain; pg_net and Vault are stubbed.
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
const detail=mig('20261106020000_detailed_chat_request_notifications.sql');await db.exec(detail);await db.exec(detail);

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

await ok('new request names the help seeker (row and push)',async()=>{
 await as('seeker');await db.query('select request_peer_support($1)',[id.vol]);
 await db.exec('reset role');request=(await db.query('select id from support_requests where volunteer_id=$1',[id.vol])).rows[0].id;
 const n=await last(id.vol);assert.equal(n.title,'New support request from Dana Ali');assert.equal(n.body,'Dana Ali would like to connect with you.');
 const p=(await pushes()).find(b=>b.user_id===id.vol);assert.equal(p.title,'New support request from Dana Ali');
});
await ok('accepted names the volunteer',async()=>{
 await as('vol');await db.query('select decide_support_request($1,true)',[request]);
 const n=await last(id.seeker);assert.equal(n.title,'Sara Omar accepted your support request');assert.equal(n.body,'You can now start a conversation with Sara Omar.');
});
await ok('declined and canceled name the other person',async()=>{
 await as('seeker');await db.query('select request_peer_support($1)',[id.vol2]);
 await db.exec('reset role');request2=(await db.query('select id from support_requests where volunteer_id=$1',[id.vol2])).rows[0].id;
 await as('seeker');await db.query('select cancel_support_request($1)',[request2]);
 assert.equal((await last(id.vol2)).title,'Dana Ali canceled their support request');
 await as('seeker');await db.query('select request_peer_support($1)',[id.vol2]);
 await db.exec('reset role');const r3=(await db.query(`select id from support_requests where volunteer_id=$1 and status='pending'`,[id.vol2])).rows[0].id;
 await as('vol2');await db.query('select decide_support_request($1,false)',[r3]);
 const n=await last(id.seeker);assert.equal(n.title,'Lina Saad declined your support request');assert.equal(n.body,'You can choose another volunteer.');
});
let msgId;
await ok('chat: title is the sender, body is the message, both directions',async()=>{
 await pushes();
 await as('seeker');msgId=(await db.query(`insert into messages(request_id,sender_id,body) values($1,auth.uid(),'Hi Sara,   how are you?') returning id`,[request])).rows[0].id;
 let n=await last(id.vol);assert.equal(n.title,'Dana Ali');assert.equal(n.body,'Hi Sara, how are you?');assert.equal(n.message_id,msgId);
 await as('vol');await db.query(`insert into messages(request_id,sender_id,body) values($1,auth.uid(),'Doing well!')`,[request]);
 n=await last(id.seeker);assert.equal(n.title,'Sara Omar');assert.equal(n.body,'Doing well!');
 const p=await pushes();assert.deepEqual(p.map(b=>[b.user_id,b.title,b.body]),[[id.vol,'Dana Ali','Hi Sara, how are you?'],[id.seeker,'Sara Omar','Doing well!']]);
});
await ok('long messages are shortened',async()=>{
 await as('seeker');await db.query(`insert into messages(request_id,sender_id,body) values($1,auth.uid(),$2)`,[request,'a'.repeat(500)]);
 const n=await last(id.vol);assert.equal(n.body.length,200);assert.ok(n.body.endsWith('…'));
});
await ok('photo, voice and video get labels instead of text',async()=>{
 await as(null);
 const types=[['image','image/png',100,null,'📷 Photo','Photo'],['voice','audio/wav',20000,1000,'🎤 Voice message','Voice message'],['video','video/mp4',100,null,'🎥 Video','Video']];
 for(const [t,mime,bytes,dur,label,body] of types){
  await db.query(`alter table messages disable trigger user`);
  const m=(await db.query(`insert into messages(request_id,sender_id,body,message_type,attachment_path,attachment_mime,attachment_bytes,duration_ms) values($1,$2,$8,$3,$4,$5,$6,$7) returning id`,[request,id.vol,t,`${request}/${t}`,mime,bytes,dur,body])).rows[0].id;
  await db.query(`alter table messages enable trigger user`);
  await db.query(`insert into notifications(user_id,title,body,kind,reference_id) values($1,'New message','x','message',$2)`,[id.seeker,request]);
  const n=await last(id.seeker);assert.equal(n.body,label);assert.equal(n.message_id,m);
 }
});
await ok('media with a caption shows the icon and the caption',async()=>{
 await as(null);await db.query(`alter table messages disable trigger user`);
 await db.query(`insert into messages(request_id,sender_id,body,message_type,attachment_path,attachment_mime,attachment_bytes) values($1,$2,'Look at this view','image',$3,'image/png',100)`,[request,id.vol,`${request}/cap`]);
 await db.query(`alter table messages enable trigger user`);
 await db.query(`insert into notifications(user_id,title,body,kind,reference_id) values($1,'New message','x','message',$2)`,[id.seeker,request]);
 assert.equal((await last(id.seeker)).body,'📷 Look at this view');
});
await ok('delete for everyone replaces the stored text',async()=>{
 await as('seeker');await db.query('select delete_maak_message($1,true)',[msgId]);
 await db.exec('reset role');const n=(await db.query('select body from notifications where message_id=$1',[msgId])).rows[0];assert.equal(n.body,'This message was deleted.');
});
await ok('recipient hiding a message replaces only their own copy',async()=>{
 await as('vol');const m=(await db.query(`insert into messages(request_id,sender_id,body) values($1,auth.uid(),'Private note') returning id`,[request])).rows[0].id;
 await as('seeker');await db.query('select delete_maak_message($1,false)',[m]);
 await db.exec('reset role');assert.equal((await db.query('select body from notifications where message_id=$1',[m])).rows[0].body,'This message was deleted.');
 assert.equal((await db.query(`select count(*)::int c from messages where id=$1 and body='Private note'`,[m])).rows[0].c,1);
});
await ok('other kinds are left as they were',async()=>{
 await as(null);await db.query(`insert into notifications(user_id,title,body,kind) values($1,'Application approved','You can now support help seekers.','application')`,[id.vol]);
 const n=await last(id.vol);assert.equal(n.title,'Application approved');
});
console.log(`${checks} detailed notification checks passed`);
