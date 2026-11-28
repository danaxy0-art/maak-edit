// ADDED: checks for supabase/migrations/20261105_message_reports.sql
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');
const db=new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;',''));
for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql']) await db.exec(read('supabase/migrations/'+f));
await db.exec('alter table public.support_requests add column restricted_at timestamptz;');
for(const f of ['20261021_account_blocking.sql','20261105000000_chat_end_reactions.sql','20261105010000_chat_reopen.sql','20261105020000_chat_media_ai_consent.sql','20261105030000_message_deletion_video.sql']) await db.exec(read('supabase/migrations/'+f));
const migration=read('supabase/migrations/20261105_message_reports.sql');
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

await check('RPT-17 the report keeps a snapshot of the message',async()=>{await as('');const r=(await db.query('select message_body,message_type,attachment_path,message_sent_at from reports where message_id=$1 and reporter_id=$2',[fromVol,ids.seeker])).rows[0];assert.equal(r.message_body,'a message from the volunteer');assert.equal(r.message_type,'text');assert.equal(r.attachment_path,null);assert.ok(r.message_sent_at);});
await check('RPT-18 deleting the message for everyone does not erase the evidence',async()=>{await as('vol');await db.query('select delete_maak_message($1,true)',[fromVol]);await as('');const m=(await db.query('select body,deleted_at from messages where id=$1',[fromVol])).rows[0];assert.ok(m.deleted_at);assert.notEqual(m.body,'a message from the volunteer');const r=(await db.query('select message_body from reports where message_id=$1 and reporter_id=$2',[fromVol,ids.seeker])).rows[0];assert.equal(r.message_body,'a message from the volunteer');});
await check('RPT-19 a deleted message cannot be reported',async()=>{await as('');const o=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id",[ids.other,ids.vol])).rows[0].id;await as('');const m=(await db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3) returning id',[o,ids.other,'gone soon'])).rows[0].id;await as('other');await db.query('select delete_maak_message($1,true)',[m]);await as('vol');await assert.rejects(()=>report(m,'spam',null),/message_deleted/);});
await check('RPT-20 deleting the reported account keeps the report',async()=>{await as('');const before=await count();await db.query('delete from auth.users where id=$1',[ids.vol]);assert.equal(await count(),before);const r=(await db.query('select reported_user_id,message_body from reports where reporter_id=$1 and message_id=$2',[ids.seeker,fromVol])).rows[0];assert.equal(r.reported_user_id,ids.vol);assert.equal(r.message_body,'a message from the volunteer');});
await check('RPT-21 deleting the reporter account keeps the report',async()=>{await as('');const before=await count();await db.query('delete from auth.users where id=$1',[ids.seeker]);assert.equal(await count(),before);});
await check('RPT-22 reports can be grouped per conversation',async()=>{await as('admin');const rows=(await db.query('select request_id,count(*)::int n from reports group by request_id order by n desc')).rows;assert.ok(rows.length>=1&&rows[0].n>=2);});
await check('RPT-23 a blocked account cannot file a report',async()=>{await as('');const x='10000000-0000-0000-0000-000000000009';await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[x,JSON.stringify({full_name:'x',role:'help_seeker'})]);await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Experience','approved')",[ids.other]).catch(()=>{});const r2=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id",[x,ids.other])).rows[0].id;const m=(await db.query('insert into messages(request_id,sender_id,body) values($1,$2,$3) returning id',[r2,ids.other,'hello'])).rows[0].id;await db.query("insert into account_blocks(user_id,reason) values($1,'test')",[x]);ids.x=x;await as('x');await assert.rejects(()=>report(m,'spam',null),/not_allowed|account_blocked/);await as('');assert.equal((await db.query('select count(*)::int n from reports where reporter_id=$1',[x])).rows[0].n,0);});
console.log(`${n} report checks passed`);await db.close();
