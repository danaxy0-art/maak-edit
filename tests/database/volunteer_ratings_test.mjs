// Checks for supabase/migrations/20261126100000_volunteer_ratings.sql (US1, US2).
// Real migration chain on PGlite, same setup as the other chat tests.
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
for(const f of ['20261021_account_blocking.sql','20261105000000_chat_end_reactions.sql','20261105010000_chat_reopen.sql']) await db.exec(mig(f));
const migration=mig('20261126100000_volunteer_ratings.sql');
await db.exec(migration);await db.exec(migration); // repeatable

const ids={};
const people=['seeker','seeker2','seeker3','seeker4','outsider','vol','vol2','vol3','volPending'];
people.forEach((n,i)=>ids[n]=`a0000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
const isVol=n=>n.startsWith('vol');
for(const n of people) await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[ids[n],`${n}@x.com`,JSON.stringify({full_name:n,role:isVol(n)?'volunteer':'help_seeker'})]);
for(const n of people.filter(n=>!isVol(n))) await db.query("insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English')",[ids[n]]);
for(const n of people.filter(isVol)) await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Story',$2)",[ids[n],n==='volPending'?'pending_review':'approved']);

async function as(name){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[name?ids[name]:'']);if(name)await db.exec('set role authenticated');}
async function su(){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub','',false)");}
// A conversation: accepted, optional messages from each side, optionally ended.
async function chat(seeker,vol,{volMsg=true,seekerMsg=true,ended=true,restricted=false}={}){
  await su();
  const r=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id",[ids[seeker],ids[vol]])).rows[0].id;
  if(seekerMsg) await db.query("insert into messages(request_id,sender_id,body) values($1,$2,'hello')",[r,ids[seeker]]);
  if(volMsg) await db.query("insert into messages(request_id,sender_id,body) values($1,$2,'hi, I am here')",[r,ids[vol]]);
  if(ended) await db.query('update support_requests set ended_at=now(),ended_by=$2 where id=$1',[r,ids[seeker]]);
  if(restricted) await db.query('update support_requests set restricted_at=now() where id=$1',[r]);
  return r;
}
const rate=async(who,r,stars)=>{await as(who);return (await db.query('select rate_maak_volunteer($1,$2) j',[r,stars])).rows[0].j;};
const state=async(who,r)=>{await as(who);return (await db.query('select my_maak_rating($1) j',[r])).rows[0].j;};
const stats=async(who,list)=>{await as(who);return (await db.query('select maak_volunteer_stats($1::uuid[]) j',[list.map(n=>ids[n])])).rows.map(x=>x.j);};
const rejects=(f,msg)=>assert.rejects(f,e=>new RegExp(msg).test(e.message),`expected ${msg}`);
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}

const main=await chat('seeker','vol');
let fresh; // seeker2 + vol, unrated until VIEW-03 (a pair has one conversation)
await check('RATE-01 eligible help seeker sees eligible state and submits a rating',async()=>{
  const s=await state('seeker',main);
  assert.equal(s.state,'eligible');assert.equal(s.volunteer_id,ids.vol);assert.equal(s.stars,null);
  assert.equal(s.correction_window_seconds,24*3600,'the app words the window from this value');
  const j=await rate('seeker',main,4);
  assert.equal(j.state,'rated');assert.equal(j.stars,4);assert.equal(j.volunteer_id,ids.vol);
  assert.equal(j.can_correct,true);assert.ok(j.correct_until,'the correction deadline is returned');
  await su();const created=(await db.query('select created_at from volunteer_ratings where request_id=$1',[main])).rows[0].created_at;
  assert.equal(new Date(j.correct_until).getTime(),created.getTime()+24*3600e3,'deadline = submitted + window, from the server clock');
  assert.equal((await state('seeker',main)).state,'rated');assert.equal((await state('seeker',main)).stars,4);
});
await check('RATE-02 duplicate submission is rejected and the first rating is kept',async()=>{
  await rejects(()=>rate('seeker',main,1),'already_rated');
  await su();assert.equal((await db.query('select stars from volunteer_ratings where request_id=$1',[main])).rows[0].stars,4);
});
await check('RATE-03 volunteer cannot rate themselves on their own conversation',async()=>{
  assert.equal((await state('vol',main)).state,'not_seeker');
  await rejects(()=>rate('vol',main,5),'already_rated|rating_not_allowed');
  fresh=await chat('seeker2','vol');
  await rejects(()=>rate('vol',fresh,5),'rating_not_allowed');
});
await check('RATE-04 non-participant cannot rate or learn anything about the conversation',async()=>{
  const r=await chat('seeker3','vol2');
  assert.deepEqual(await state('outsider',r),{state:'unavailable'});
  await rejects(()=>rate('outsider',r,5),'rating_not_allowed');
  await rejects(()=>rate('outsider','b0000000-0000-4000-8000-000000000999',5),'rating_not_allowed');
  await su();await db.query('delete from support_requests where id=$1',[r]);
});
await check('RATE-05 stars outside 1-5 are rejected (0, 6, -1, null); 1 and 5 are accepted',async()=>{
  const r=await chat('seeker4','vol');
  for(const s of [0,6,-1,null]) await rejects(()=>rate('seeker4',r,s),'invalid_rating');
  assert.equal((await rate('seeker4',r,5)).stars,5);
  const low=await chat('seeker4','vol3');
  assert.equal((await rate('seeker4',low,1)).stars,1);
});
await check('RATE-06 conversation still open is not eligible',async()=>{
  const r=await chat('seeker3','vol',{ended:false});
  assert.equal((await state('seeker3',r)).state,'not_ended');
  await rejects(()=>rate('seeker3',r,5),'rating_not_allowed');
  await su();await db.query('delete from support_requests where id=$1',[r]);
});
await check('RATE-07 volunteer never replied: not eligible (seeker-only messages do not count)',async()=>{
  const r=await chat('seeker3','vol',{volMsg:false});
  assert.equal((await state('seeker3',r)).state,'no_support');
  await rejects(()=>rate('seeker3',r,5),'rating_not_allowed');
  await su();await db.query('delete from support_requests where id=$1',[r]);
});
await check('RATE-08 conversation restricted by an administrator is not eligible',async()=>{
  const r=await chat('seeker3','vol',{restricted:true});
  assert.equal((await state('seeker3',r)).state,'restricted');
  await rejects(()=>rate('seeker3',r,5),'rating_not_allowed');
  await su();await db.query('delete from support_requests where id=$1',[r]);
});
await check('RATE-09 pending, declined and canceled requests are not eligible',async()=>{
  for(const st of ['pending','declined','canceled']){
    await su();
    const r=(await db.query('insert into support_requests(seeker_id,volunteer_id,status,ended_at) values($1,$2,$3,now()) returning id',[ids.seeker3,ids.vol,st])).rows[0].id;
    await rejects(()=>rate('seeker3',r,5),'rating_not_allowed');
    await su();await db.query('delete from support_requests where id=$1',[r]);
  }
});
await check('RATE-10 volunteer no longer approved, or blocked: not eligible',async()=>{
  const r=await chat('seeker3','volPending');
  await rejects(()=>rate('seeker3',r,5),'rating_not_allowed');
  await su();await db.query('delete from support_requests where id=$1',[r]);
  const r2=await chat('seeker3','vol2');
  await su();await db.query("insert into account_blocks(user_id,reason,blocked_by) values($1,'Test block reason',null)",[ids.vol2]);
  assert.equal((await state('seeker3',r2)).state,'unavailable');
  await rejects(()=>rate('seeker3',r2,5),'rating_not_allowed');
  await su();await db.query('delete from account_blocks where user_id=$1',[ids.vol2]);
  await db.query('delete from support_requests where id=$1',[r2]);
});
await check('RATE-11 a blocked help seeker cannot rate',async()=>{
  const r=await chat('seeker3','vol');
  await su();await db.query("insert into account_blocks(user_id,reason,blocked_by) values($1,'Test block reason',null)",[ids.seeker3]);
  await rejects(()=>rate('seeker3',r,5),'not_allowed');
  await su();await db.query('delete from account_blocks where user_id=$1',[ids.seeker3]);
  await db.query('delete from support_requests where id=$1',[r]);
});
await check('RATE-12 rating is kept, and cannot be repeated, after the chat is reopened',async()=>{
  await su();await db.query('update support_requests set ended_at=null where id=$1',[main]);
  assert.equal((await state('seeker',main)).state,'rated');
  await rejects(()=>rate('seeker',main,2),'already_rated');
  await su();await db.query('update support_requests set ended_at=now() where id=$1',[main]);
});
await check('RATE-13 direct insert, update and delete are denied; members read only their own rows',async()=>{
  await as('seeker');
  await rejects(()=>db.query("insert into volunteer_ratings(request_id,seeker_id,volunteer_id,stars) values($1,$2,$3,5)",[main,ids.seeker,ids.vol]),'permission denied');
  await rejects(()=>db.query('update volunteer_ratings set stars=5'),'permission denied');
  await rejects(()=>db.query('delete from volunteer_ratings'),'permission denied');
  assert.equal((await db.query('select * from volunteer_ratings')).rows.length,1);
  await as('vol');assert.equal((await db.query('select * from volunteer_ratings')).rows.length,0,'volunteer cannot see who rated them');
  await as('outsider');assert.equal((await db.query('select * from volunteer_ratings')).rows.length,0);
  await rejects(()=>db.query('select maak_rating_state($1)',[main]),'permission denied');
  await rejects(()=>db.query('select maak_request_had_support($1)',[main]),'permission denied');
});
await check('RATE-14 signed-out caller cannot call any rating function',async()=>{
  await su();await db.exec('set role anon');
  await rejects(()=>db.query('select my_maak_rating($1)',[main]),'permission denied');
  await rejects(()=>db.query('select rate_maak_volunteer($1,5)',[main]),'permission denied');
  await rejects(()=>db.query("select maak_volunteer_stats('{}'::uuid[])"),'permission denied');
  await db.exec('reset role');
});

// One correction (vol3 only, so the averages checked below are unaffected).
const correct=async(who,r,stars)=>{await as(who);return (await db.query('select correct_maak_rating($1,$2) j',[r,stars])).rows[0].j;};
const ratingRow=async r=>{await su();return (await db.query('select * from volunteer_ratings where request_id=$1',[r])).rows;};
const fix=await chat('seeker3','vol3');
await check('CORR-01 no rating yet: nothing to correct',async()=>{
  await rejects(()=>correct('seeker3',fix,4),'rating_not_found');
});
await check('CORR-02 the rater corrects once; the same row changes, no second rating is created',async()=>{
  await rate('seeker3',fix,2);
  await rejects(()=>correct('seeker3',fix,2),'rating_unchanged');
  for(const s of [0,6,null]) await rejects(()=>correct('seeker3',fix,s),'invalid_rating');
  const j=await correct('seeker3',fix,4);
  assert.equal(j.stars,4);assert.equal(j.can_correct,false);assert.equal(j.correct_until,null);
  const rows=await ratingRow(fix);assert.equal(rows.length,1);assert.equal(rows[0].stars,4);assert.ok(rows[0].corrected_at);
});
await check('CORR-03 a second correction is refused',async()=>{
  await rejects(()=>correct('seeker3',fix,5),'correction_not_allowed');
  assert.equal((await ratingRow(fix))[0].stars,4);
  assert.equal((await state('seeker3',fix)).can_correct,false);
});
await check('CORR-04 after the 24-hour window the rating is final',async()=>{
  const r=await chat('seeker2','vol3');await rate('seeker2',r,3);
  await su();await db.query("update volunteer_ratings set created_at=now()-interval '24 hours 1 minute' where request_id=$1",[r]);
  assert.equal((await state('seeker2',r)).can_correct,false);
  await rejects(()=>correct('seeker2',r,5),'correction_not_allowed');
  await su();await db.query("update volunteer_ratings set created_at=now()-interval '23 hours 59 minutes' where request_id=$1",[r]);
  assert.equal((await state('seeker2',r)).can_correct,true,'just inside the window');
  await su();await db.query('delete from support_requests where id=$1',[r]);
});
await check('CORR-05 nobody else can correct a rating (volunteer, other members)',async()=>{
  const r=await chat('seeker2','vol3');await rate('seeker2',r,3);
  for(const who of ['vol3','outsider','seeker3']) await rejects(()=>correct(who,r,1),'rating_not_found');
  assert.equal((await ratingRow(r))[0].stars,3);
  await su();await db.query('delete from support_requests where id=$1',[r]);
});
await check('CORR-06 blocked help seeker, or volunteer blocked or no longer approved: no correction',async()=>{
  const r=await chat('seeker2','vol3');await rate('seeker2',r,3);
  await su();await db.query("insert into account_blocks(user_id,reason) values($1,'Test block reason')",[ids.vol3]);
  assert.equal((await state('seeker2',r)).can_correct,false);
  await rejects(()=>correct('seeker2',r,5),'correction_not_allowed');
  await su();await db.query('delete from account_blocks where user_id=$1',[ids.vol3]);
  await db.query("update volunteer_profiles set status='rejected' where user_id=$1",[ids.vol3]);
  await rejects(()=>correct('seeker2',r,5),'correction_not_allowed');
  await su();await db.query("update volunteer_profiles set status='approved' where user_id=$1",[ids.vol3]);
  await db.query("insert into account_blocks(user_id,reason) values($1,'Test block reason')",[ids.seeker2]);
  await rejects(()=>correct('seeker2',r,5),'not_allowed');
  await su();await db.query('delete from account_blocks where user_id=$1',[ids.seeker2]);
  assert.equal((await correct('seeker2',r,5)).stars,5,'allowed again once both are active');
  await su();await db.query('delete from support_requests where id=$1',[r]);
});
await check('CORR-07 correction works after the chat is reopened, and signed-out callers are refused',async()=>{
  const r=await chat('seeker2','vol3');await rate('seeker2',r,2);
  await su();await db.query('update support_requests set ended_at=null where id=$1',[r]);
  assert.equal((await correct('seeker2',r,3)).stars,3);
  await su();await db.exec('set role anon');
  await rejects(()=>db.query('select correct_maak_rating($1,4)',[r]),'permission denied');
  await db.exec('reset role');await db.query('delete from support_requests where id=$1',[r]);
});

await check('VIEW-01 volunteer with no ratings: count 0, no average (not zero stars)',async()=>{
  const [s]=await stats('seeker',['vol2']);
  assert.deepEqual(s,{volunteer_id:ids.vol2,rating_count:0,average_rating:null});
});
await check('VIEW-02 below the minimum the count is shown but the average is hidden',async()=>{
  // vol now has 2 ratings (4 from RATE-01, 5 from RATE-05).
  const [s]=await stats('outsider',['vol']);
  assert.equal(s.rating_count,2);assert.equal(s.average_rating,null);
});
await check('VIEW-03 at the minimum the average appears and updates with each new rating',async()=>{
  await rate('seeker2',fresh,3); // 4,5,3 -> 4.0
  let [s]=await stats('seeker',['vol']);assert.equal(s.rating_count,3);assert.equal(Number(s.average_rating),4);
  const r2=await chat('seeker3','vol');await rate('seeker3',r2,2); // 4,5,3,2 -> 3.5
  [s]=await stats('vol',['vol']);assert.equal(s.rating_count,4);assert.equal(Number(s.average_rating),3.5);
});
await check('VIEW-04 average is rounded to one decimal',async()=>{
  const r=await chat('outsider','vol');await rate('outsider',r,5); // 4,5,3,2,5 -> 3.8
  const [s]=await stats('seeker',['vol']);assert.equal(Number(s.average_rating),3.8);
});
await check('VIEW-05 summary exposes only aggregate fields',async()=>{
  const [s]=await stats('seeker',['vol']);assert.deepEqual(Object.keys(s).sort(),['average_rating','rating_count','volunteer_id']);
});
await check('VIEW-08 a correction changes the average but not the count',async()=>{
  await correct('seeker',main,1); // 4->1: 1,5,3,2,5 -> 3.2
  const [s]=await stats('seeker2',['vol']);assert.equal(s.rating_count,5);assert.equal(Number(s.average_rating),3.2);
});
await check('VIEW-06 one row per approved, active volunteer; others and duplicates are left out',async()=>{
  const rows=await stats('seeker',['vol','vol','vol2','volPending','seeker']);
  assert.deepEqual(rows.map(r=>r.volunteer_id).sort(),[ids.vol,ids.vol2].sort());
  await su();await db.query("insert into account_blocks(user_id,reason,blocked_by) values($1,'Test block reason',null)",[ids.vol2]);
  assert.deepEqual((await stats('seeker',['vol','vol2'])).map(r=>r.volunteer_id),[ids.vol]);
  await su();await db.query('delete from account_blocks where user_id=$1',[ids.vol2]);
  assert.deepEqual(await stats('seeker',[]),[]);
});
await check('VIEW-07 more than 100 ids in one call is rejected',async()=>{
  await as('seeker');
  const many=Array.from({length:101},(_,i)=>`c0000000-0000-4000-8000-${String(i).padStart(12,'0')}`);
  await rejects(()=>db.query('select maak_volunteer_stats($1::uuid[])',[many]),'too_many_volunteers');
});
await check('SQL-01 rollback removes only its own objects and the migration applies again',async()=>{
  await su();
  await db.exec(read('supabase/rollbacks/20261126100000_volunteer_ratings_rollback.sql'));
  assert.equal((await db.query("select to_regclass('public.volunteer_ratings') t")).rows[0].t,null);
  assert.ok((await db.query("select to_regclass('public.support_requests') t")).rows[0].t);
  await db.exec(migration);
  assert.equal((await db.query('select count(*)::int c from volunteer_ratings')).rows[0].c,0);
});
console.log(`${n} volunteer rating checks passed`);
