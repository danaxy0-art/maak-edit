import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');
const db=new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;',''));
for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql']) await db.exec(read('supabase/migrations/'+f));
await db.exec('alter table public.support_requests add column restricted_at timestamptz;');
for(const f of ['20261021_account_blocking.sql','20261105000000_chat_end_reactions.sql','20261105010000_chat_reopen.sql','20261105020000_chat_media_ai_consent.sql']) await db.exec(read('supabase/migrations/'+f));
const patch=read('supabase/migrations/20261105030000_message_deletion_video.sql');await db.exec(patch);await db.exec(patch);
const a='11111111-1111-4111-8111-111111111111',b='22222222-2222-4222-8222-222222222222',c='33333333-3333-4333-8333-333333333333';
await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,'a@example.com','{"full_name":"Dana","role":"help_seeker"}'),($2,'b@example.com','{"full_name":"Dalal","role":"volunteer"}'),($3,'c@example.com','{"full_name":"Other","role":"volunteer"}')`,[a,b,c]);
await db.query(`insert into help_seeker_profiles(user_id,chronic_condition,preferred_language,description) values($1,'Diabetes','English','Support')`,[a]);
for(const id of [b,c]) await db.query(`insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Experience','approved')`,[id]);
const request=(await db.query(`insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id`,[a,b])).rows[0].id;
let checks=0;
async function as(id){await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id??'']);await db.exec(id?'set role authenticated':'set role anon');}
async function ok(label,fn){await fn();checks++;console.log('PASS',label);}
async function send(body){return(await db.query(`insert into messages(request_id,sender_id,body) values($1,auth.uid(),$2) returning id`,[request,body])).rows[0].id;}
async function chat(){return(await db.query('select * from my_maak_chat_messages($1)',[request])).rows;}
async function count(){return Number((await db.query('select my_maak_unread_message_count() n')).rows[0].n);}
async function del(id,everyone=false){await db.query('select delete_maak_message($1,$2)',[id,everyone]);}
await as(a);const text=await send('Original secret text');
await ok('recipient receives text and unread badge',async()=>{await as(b);assert.equal((await chat())[0].body,'Original secret text');assert.equal(await count(),1);});
await ok('delete for me returns a scrubbed placeholder and clears own unread',async()=>{await del(text);const rows=await chat();assert.equal(rows[0].body,'You deleted this message.');assert.ok(rows[0].deleted_at);assert.equal(await count(),0);assert.equal((await db.query('select * from messages where id=$1',[text])).rows.length,0);});
await ok('sender still retains original text',async()=>{await as(a);assert.equal((await chat())[0].body,'Original secret text');});
await ok('received message cannot be deleted for everyone',async()=>{await as(b);await assert.rejects(del(text,true),/sender_only/);});
await ok('owner deletes for everyone without reviving own hidden copy',async()=>{await as(a);await del(text,true);assert.equal((await chat())[0].body,'This message was deleted.');await as(b);assert.equal((await chat())[0].body,'You deleted this message.');});
await ok('repeated deletion preserves original tombstone time',async()=>{await as(a);const time=(await chat())[0].deleted_at;await del(text,true);assert.deepEqual((await chat())[0].deleted_at,time);});
const media=[];
for(const [kind,mime,ext,size,duration] of [['image','image/png','png',128,null],['voice','audio/wav','wav',32044,1000],['video','video/mp4','mp4',128,null]]) {
 await as(a);const id=(await db.query('select gen_random_uuid() id')).rows[0].id;const path=`${request}/${a}/${id}.${ext}`;
 await db.query(`insert into storage.objects(bucket_id,name,metadata) values('chat-media',$1,$2)`,[path,JSON.stringify({size,mimetype:mime})]);
 await db.query(`insert into messages(id,request_id,sender_id,body,message_type,attachment_path,attachment_mime,attachment_bytes,duration_ms) values($1,$2,auth.uid(),$3,$3,$4,$5,$6,$7)`,[id,request,kind,path,mime,size,duration]);media.push({id,path,kind});
 await ok(`${kind}: other participant can read sent private object`,async()=>{await as(b);assert.equal((await db.query('select * from storage.objects where name=$1',[path])).rows.length,1);});
 await ok(`${kind}: personal delete scrubs data and prevents new object access only for that reader`,async()=>{await del(id);const m=(await chat()).find(x=>x.id===id);assert.equal(m.body,'You deleted this message.');assert.equal(m.attachment_path,null);assert.equal((await db.query('select * from storage.objects where name=$1',[path])).rows.length,0);await as(a);assert.equal((await db.query('select * from storage.objects where name=$1',[path])).rows.length,1);});
 await ok(`${kind}: global deletion revokes object for both and preserves placeholder`,async()=>{await del(id,true);const m=(await chat()).find(x=>x.id===id);assert.equal(m.body,'This message was deleted.');assert.equal(m.message_type,'text');assert.equal(m.attachment_path,null);assert.equal((await db.query('select * from storage.objects where name=$1',[path])).rows.length,0);await as(b);assert.equal((await db.query('select * from storage.objects where name=$1',[path])).rows.length,0);});
}
await ok('nonparticipant cannot read or delete',async()=>{await as(c);await assert.rejects(chat(),/not_allowed/);await assert.rejects(del(text,true),/message_unavailable/);assert.equal((await db.query('select * from messages')).rows.length,0);assert.equal((await db.query('select * from chat_message_hides')).rows.length,0);});
await ok('anonymous delete denied',async()=>{await as(null);await assert.rejects(del(text),/permission denied/);});
await ok('direct deletion/update bypasses denied',async()=>{await as(a);await assert.rejects(db.query('delete from messages where id=$1',[text]),/permission denied/);await assert.rejects(db.query("update messages set body='Forged' where id=$1",[text]),/permission denied/);});
await ok('no new notification generated by deletion',async()=>{await as(b);const n=(await db.query('select count(*) n from notifications')).rows[0].n;await as(a);await del(text,true);await as(b);assert.equal((await db.query('select count(*) n from notifications')).rows[0].n,n);});
await ok('preview is local tombstone with no original text',async()=>{await as(b);const r=(await db.query('select * from my_support_requests()')).rows[0].my_support_requests;assert.equal(r.last_message,'You deleted this message.');});
await ok('new messages after deletions remain visible and counted',async()=>{await as(a);await send('New message');await as(b);assert.equal((await chat()).at(-1).body,'New message');assert.equal(await count(),1);});
await ok('global deletion updates both unread count and recipient notification without a prior personal hide',async()=>{
 const id=(await chat()).at(-1).id;
 await as(a);await del(id,true);await as(b);assert.equal(await count(),0);
 assert.equal((await chat()).at(-1).body,'This message was deleted.');
 assert.equal(Number((await db.query("select count(*) n from notifications where kind='message' and not is_read")).rows[0].n),0);
});
await ok('reaction feature works on a live message and rejects deleted messages',async()=>{
 await as(a);const id=await send('React here');await as(b);
 await db.query('select toggle_maak_reaction($1,$2,$3)',[request,id,'👍']);
 assert.equal((await db.query('select * from message_reactions where message_id=$1',[id])).rows.length,1);
 await as(a);await del(id,true);await as(b);
 assert.equal((await db.query('select * from message_reactions where message_id=$1',[id])).rows.length,0);
 await assert.rejects(db.query('select toggle_maak_reaction($1,$2,$3)',[request,id,'👍']),/message_unavailable/);
});
await ok('End Chat still retains history and blocks new sends',async()=>{await as(a);await db.query('select end_maak_chat($1)',[request]);assert.ok((await chat()).length>=4);await assert.rejects(send('Not allowed'),/chat_closed|row-level security/);});
await ok('individual deletion remains possible in ended chat',async()=>{await del(text);assert.equal((await chat())[0].body,'You deleted this message.');});
await ok('support connection and End Chat remain intact after every deletion',async()=>{const row=(await db.query('select status,ended_at from support_requests where id=$1',[request])).rows[0];assert.equal(row.status,'accepted');assert.ok(row.ended_at);});


await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub','',false)");
await db.exec(read('supabase/migrations/20261021_matching_connections.sql'));
const toggle=read('supabase/migrations/20261105040000_ai_matching_toggle.sql');await db.exec(toggle);await db.exec(toggle);
async function setting(){return(await db.query('select has_maak_ai_consent() enabled')).rows[0].enabled;}
async function set(value){await db.query('select set_maak_ai_matching_enabled($1)',[value]);}
async function context(){return(await db.query('select maak_matching_context() data')).rows[0].data;}
await ok('AI off seeker cannot query matches',async()=>{await as(a);assert.equal(await setting(),false);await assert.rejects(context(),/ai_matching_disabled/);});
await ok('AI activates and persists for seeker',async()=>{await set(true);assert.equal(await setting(),true);});
await ok('inactive volunteers excluded from matches',async()=>assert.equal((await context()).candidates.length,0));
await ok('volunteer activates and appears as suitable candidate',async()=>{await as(c);await set(true);await as(a);assert.equal((await context()).candidates[0].user_id,c);});
await ok('already accepted connection still excluded',async()=>{await as(b);await set(true);await as(a);assert.ok(!(await context()).candidates.some(v=>v.user_id===b));});
await ok('volunteer can turn off after enabling',async()=>{await as(c);await set(false);assert.equal(await setting(),false);await as(a);assert.equal((await context()).candidates.length,0);});
await ok('direct request to off volunteer is denied',async()=>await assert.rejects(db.query('select request_peer_support($1)',[c]),/volunteer_matching_disabled/));
await ok('seeker can turn off and both browse and matching require activation',async()=>{await set(false);await assert.rejects(context(),/ai_matching_disabled/);await assert.rejects(db.query('select * from browse_volunteers()'),/ai_matching_disabled/);});
await ok('seeker and volunteer can re-enable and timestamps stay stable',async()=>{await as(c);await set(true);const before=(await db.query('select accepted_at from ai_matching_agreements')).rows[0].accepted_at;await set(false);await set(true);assert.deepEqual((await db.query('select accepted_at from ai_matching_agreements')).rows[0].accepted_at,before);await as(a);await set(true);assert.equal((await context()).candidates[0].user_id,c);});
await ok('stale profile updates cannot turn disabled matching back on',async()=>{await as(c);await set(false);await db.exec('reset role');await db.query('update volunteer_profiles set ai_matching_consent=true where user_id=$1',[c]);await as(c);assert.equal((await db.query('select ai_matching_consent from volunteer_profiles where user_id=$1',[c])).rows[0].ai_matching_consent,false);await set(true);});
await ok('private wrappers cannot be bypassed directly',async()=>{await as(a);await assert.rejects(db.query('select maak_matching_context_before_toggle()'),/permission denied/);await assert.rejects(db.query('select * from browse_volunteers_before_toggle()'),/permission denied/);});
await ok('active accounts can request support and accepted chats still work after AI off',async()=>{await db.query('select request_peer_support($1)',[c]);await as(c);const req=(await db.query('select id from support_requests where volunteer_id=$1',[c])).rows[0].id;await db.query('select decide_support_request($1,true)',[req]);await set(false);await as(a);await set(false);await db.query("insert into messages(request_id,sender_id,body) values($1,auth.uid(),'Existing chat remains available')",[req]);assert.ok((await db.query('select * from my_maak_chat_messages($1)',[req])).rows.some(m=>m.body==='Existing chat remains available'));});
console.log(`${checks} schema integration checks passed, including 12 toggle/availability checks and 26 deletion/chat checks.`);await db.close();
