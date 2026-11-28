// Checks for supabase/migrations/20261126110000_volunteer_badges.sql (US3, US4).
// Real migration chain on PGlite, same setup as volunteer_ratings_test.mjs.
// PGlite runs one connection: concurrent transactions are not exercised here
// (see volunteer_concurrency_test.mjs for that).
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
await db.exec(mig('20261126100000_volunteer_ratings.sql'));
const migration=mig('20261126110000_volunteer_badges.sql');

const ids={};let k=0;
const add=async(name,role,status='approved')=>{
  ids[name]=`d0000000-0000-4000-8000-${String(++k).padStart(12,'0')}`;
  await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[ids[name],`${name}@x.com`,JSON.stringify({full_name:name,role})]);
  if(role==='help_seeker') await db.query("insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English')",[ids[name]]);
  else await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Story',$2)",[ids[name],status]);
};
const seekers=Array.from({length:17},(_,i)=>`s${i+1}`);
for(const s of seekers) await add(s,'help_seeker');
for(const v of ['vol','vol2','volOld']) await add(v,'volunteer');
await add('volPending','volunteer','pending_review');

async function as(name){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[name?ids[name]:'']);if(name)await db.exec('set role authenticated');}
async function su(){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub','',false)");}
const end=async r=>{await su();await db.query("update support_requests set ended_at=now(),ended_by=seeker_id where id=$1",[r]);};
const reopen=async r=>{await su();await db.query('update support_requests set ended_at=null,ended_by=null where id=$1',[r]);};
async function chat(seeker,vol,{volMsg=true,ended=true,restricted=false}={}){
  await su();
  const r=(await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id",[ids[seeker],ids[vol]])).rows[0].id;
  await db.query("insert into messages(request_id,sender_id,body) values($1,$2,'hello')",[r,ids[seeker]]);
  if(volMsg) await db.query("insert into messages(request_id,sender_id,body) values($1,$2,'hi')",[r,ids[vol]]);
  if(restricted) await db.query('update support_requests set restricted_at=now() where id=$1',[r]);
  if(ended) await end(r);
  return r;
}
const stats=async(who,list)=>{await as(who);return (await db.query('select maak_volunteer_stats($1::uuid[]) j',[list.map(n=>ids[n])])).rows.map(x=>x.j);};
const badge=async(vol='vol',who='s17')=>(await stats(who,[vol]))[0]?.badge??null;
const progress=async who=>{await as(who);return (await db.query('select my_maak_badge_progress() j')).rows[0].j;};
const supported=async(vol='vol')=>(await progress(vol)).supported;
const completions=async r=>{await su();return (await db.query('select * from volunteer_support_completions where request_id=$1',[r])).rows;};
const rejects=(f,msg)=>assert.rejects(f,e=>new RegExp(msg).test(e.message),`expected ${msg}`);
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}

// History that exists before the migration is applied (for the backfill).
const oldEnded=await chat('s1','volOld');                       // ended now, volunteer replied
const oldSilent=await chat('s2','volOld',{volMsg:false});        // ended, no reply
const oldReopened=await chat('s3','volOld');await reopen(oldReopened); // ended once, reopened now
const oldOpen=await chat('s4','volOld',{ended:false});           // never ended
await db.exec(migration);await db.exec(migration); // repeatable

await check('BDG-00 backfill: only conversations ended now that meet the rule, with their stored end time',async()=>{
  assert.equal((await completions(oldEnded)).length,1);
  await su();const stored=(await db.query('select ended_at from support_requests where id=$1',[oldEnded])).rows[0].ended_at;
  assert.equal((await completions(oldEnded))[0].completed_at.getTime(),stored.getTime(),'no invented timestamp');
  for(const r of [oldSilent,oldReopened,oldOpen]) assert.equal((await completions(r)).length,0);
  assert.equal(await supported('volOld'),1);
  await end(oldReopened);assert.equal(await supported('volOld'),2,'a reopened chat earns credit when it next ends');
});

// Completed conversations for vol with s1..s<count>, created on demand.
const done=[];
const supportUpTo=async count=>{while(done.length<count){const s=seekers[done.length];done.push(await chat(s,'vol'));}};

await check('BDG-01 no badge before any completed support (open, unanswered or restricted chats do not count)',async()=>{
  assert.equal(await badge(),null);
  const open=await chat('s16','vol2',{ended:false});
  const silent=await chat('s15','vol2',{volMsg:false});
  const restricted=await chat('s14','vol2',{restricted:true});
  assert.equal(await badge('vol2'),null);
  assert.deepEqual(await progress('vol2'),{supported:0,badge:null,next_badge:'beginner',next_min:1});
  await su();for(const r of [open,silent,restricted]) await db.query('delete from support_requests where id=$1',[r]);
});
await check('BDG-02 Beginner at the first completed conversation',async()=>{
  await supportUpTo(1);assert.equal(await badge(),'beginner');
  assert.deepEqual(await progress('vol'),{supported:1,badge:'beginner',next_badge:'intermediate',next_min:5});
});
await check('BDG-03 Intermediate at 5, still Beginner at 4',async()=>{
  await supportUpTo(4);assert.equal(await badge(),'beginner');
  await supportUpTo(5);assert.equal(await badge(),'intermediate');
  assert.deepEqual(await progress('vol'),{supported:5,badge:'intermediate',next_badge:'expert',next_min:15});
});
await check('BDG-04 Expert at 15, still Intermediate at 14, stays Expert above',async()=>{
  await supportUpTo(14);assert.equal(await badge(),'intermediate');
  await supportUpTo(15);assert.equal(await badge(),'expert');
  assert.deepEqual(await progress('vol'),{supported:15,badge:'expert',next_badge:null,next_min:null});
  await supportUpTo(16);assert.equal(await badge(),'expert');
});
await check('BDG-05 reopening keeps earned credit; repeated end/reopen never adds credit',async()=>{
  const before=await supported();
  for(let i=0;i<3;i++){await reopen(done[0]);assert.equal(await supported(),before,'kept while reopened');await end(done[0]);}
  assert.equal(await supported(),before);
  assert.equal((await completions(done[0])).length,1,'one record per conversation');
  const first=(await completions(done[0]))[0].completed_at;
  await reopen(done[0]);await end(done[0]);
  assert.equal((await completions(done[0]))[0].completed_at.getTime(),first.getTime(),'first completion time is kept');
});
await check('BDG-06 a chat first ended without a reply earns credit only when it later ends with one',async()=>{
  const r=await chat('s17','vol2',{volMsg:false});
  assert.equal((await completions(r)).length,0);
  await reopen(r);
  await su();await db.query("insert into messages(request_id,sender_id,body) values($1,$2,'sorry, here now')",[r,ids.vol2]);
  assert.equal(await supported('vol2'),0,'not until it ends');
  await end(r);assert.equal(await supported('vol2'),1);
  await su();await db.query('delete from support_requests where id=$1',[r]);
  assert.equal(await supported('vol2'),0,'credit goes with a deleted conversation');
});
await check('BDG-06b the app\'s own End Chat RPC records the completion (as the volunteer or the help seeker)',async()=>{
  for(const who of ['s17','vol2']){
    const r=await chat('s17','vol2',{ended:false});
    await as(who);await db.query('select end_maak_chat($1)',[r]);
    const [c]=await completions(r);
    assert.equal(c.volunteer_id,ids.vol2);assert.equal(c.seeker_id,ids.s17);
    await su();await db.query('delete from support_requests where id=$1',[r]);
  }
});
await check('BDG-07 a help seeker blocked later does not remove the volunteer\'s credit',async()=>{
  const before=await supported();
  await su();await db.query("insert into account_blocks(user_id,reason) values($1,'Unrelated misconduct'),($2,'Unrelated misconduct')",[ids.s1,ids.s2]);
  assert.equal(await supported(),before);assert.equal(await badge(),'expert');
  await su();await db.query('delete from account_blocks where user_id in ($1,$2)',[ids.s1,ids.s2]);
});
await check('BDG-08 an administrator restriction excludes that conversation; lifting it restores the credit',async()=>{
  await su();await db.query('update support_requests set restricted_at=now() where id in ($1,$2)',[done[0],done[1]]);
  assert.equal(await supported(),14);assert.equal(await badge(),'intermediate');
  await su();await db.query('update support_requests set restricted_at=null where id in ($1,$2)',[done[0],done[1]]);
  assert.equal(await supported(),16);assert.equal(await badge(),'expert');
});
await check('BDG-08b the PRODUCTION admin_restrict_conversation (exported definition) also excludes the credit',async()=>{
  // Verbatim from tests/database/production_compat/05_production_definitions.sql
  // (production SQL Editor export). Only defined in production, never in a migration.
  const exported=read('tests/database/production_compat/05_production_definitions.sql');
  const start=exported.indexOf('CREATE OR REPLACE FUNCTION public.admin_restrict_conversation');
  const fn=exported.slice(start,exported.indexOf('end; $$;',start)+'end; $$;'.length);
  assert.ok(start>0&&fn.includes('restricted_at=now()'),'production definition found');
  await su();
  await db.exec(`alter table public.support_requests add column if not exists restricted_by uuid;
    alter table public.support_requests add column if not exists restriction_reason text;`);
  await db.exec(fn);
  await add('admin','volunteer');await db.query("update profiles set role='admin' where id=$1",[ids.admin]);
  const before=await supported();
  await as('admin');await db.query("select admin_restrict_conversation($1,'Safety review')",[done[2]]);
  await su();const [r]=(await db.query('select ended_at,restricted_at,restriction_reason from support_requests where id=$1',[done[2]])).rows;
  assert.ok(r.ended_at&&r.restricted_at,'an ended conversation, restricted by production');
  assert.equal(await supported(),before-1,'its credit is excluded');
  assert.equal((await completions(done[2])).length,1,'the record is kept for a later lift');
  // Restricting an OPEN conversation (production does not end it) never creates credit.
  const open=await chat('s17','vol2',{ended:false});
  await as('admin');await db.query("select admin_restrict_conversation($1,'Safety review')",[open]);
  await end(open);
  assert.equal(await supported('vol2'),0,'ended while restricted: recorded but not counted');
  // Lifting (what admin_lift_conversation_restriction does to the row) restores it.
  await su();await db.query('update support_requests set restricted_at=null,restricted_by=null,restriction_reason=null where id=$1',[done[2]]);
  assert.equal(await supported(),before);
  await su();await db.query('delete from support_requests where id=$1',[open]);
});
await check('BDG-09 a deleted help seeker account removes its conversations and their credit',async()=>{
  await su();await db.query('delete from auth.users where id in ($1,$2)',[ids.s15,ids.s16]);
  assert.equal(await supported(),14);assert.equal(await badge(),'intermediate');
  done.splice(14);
});
await check('BDG-10 no duplicate or contradictory awards: one value per volunteer, one conversation per pair',async()=>{
  const rows=await stats('s17',['vol','vol','vol2']);
  assert.equal(rows.filter(r=>r.volunteer_id===ids.vol).length,1);
  assert.equal(typeof rows.find(r=>r.volunteer_id===ids.vol).badge,'string');
  await su();
  await rejects(()=>db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted')",[ids.s3,ids.vol]),'one_open_request');
  await rejects(()=>db.query('insert into volunteer_support_completions values($1,$2,$3,now())',[done[0],ids.vol,ids.s1]),'duplicate key');
});
await check('BDG-11 members cannot read or write completions, thresholds, or call the internal functions',async()=>{
  for(const who of ['vol','s17']){
    await as(who);
    await rejects(()=>db.query('select * from volunteer_support_completions'),'permission denied');
    await rejects(()=>db.query('insert into volunteer_support_completions values($1,$2,$3,now())',[oldOpen,ids.volOld,ids.s4]),'permission denied');
    await rejects(()=>db.query("update volunteer_support_completions set completed_at=now()"),'permission denied');
    await rejects(()=>db.query('delete from volunteer_support_completions'),'permission denied');
    await rejects(()=>db.query("update volunteer_badge_levels set min_supported=1"),'permission denied');
    await rejects(()=>db.query("insert into volunteer_badge_levels values('expert',3,1)"),'permission denied');
    await rejects(()=>db.query("delete from volunteer_badge_levels"),'permission denied');
    await rejects(()=>db.query('select maak_volunteer_supported_counts($1::uuid[])',[[ids.vol]]),'permission denied');
    await rejects(()=>db.query('select maak_badge_for(99)'),'permission denied');
    await rejects(()=>db.query('select record_maak_support_completion()'),'permission denied');
    assert.equal((await db.query('select count(*)::int c from volunteer_badge_levels')).rows[0].c,3,'thresholds are readable');
  }
});
await check('BDG-12 a volunteer cannot fake a completion through the conversation tables',async()=>{
  const r=await chat('s17','vol2',{volMsg:false,ended:false});
  await as('vol2');
  await db.query('update support_requests set ended_at=now() where id=$1',[r]).catch(()=>{});
  await su();assert.equal((await db.query('select ended_at from support_requests where id=$1',[r])).rows[0].ended_at,null,'no direct update of the conversation');
  await as('vol2');
  await rejects(()=>db.query('select request_peer_support($1)',[ids.vol2]),'.');
  await rejects(()=>db.query("insert into messages(request_id,sender_id,body) values($1,$2,'fake')",[done[0],ids.vol2]),'.');
  assert.equal(await supported('vol2'),0);assert.equal((await completions(r)).length,0);
  await su();await db.query('delete from support_requests where id=$1',[r]);
});
await check('BDG-13 thresholds are configurable, and must keep their order',async()=>{
  await su();await db.query("update volunteer_badge_levels set min_supported=14 where level='expert'");
  assert.equal(await badge(),'expert');
  await su();await rejects(()=>db.query("update volunteer_badge_levels set min_supported=3 where level='expert'"),'badge_thresholds_out_of_order');
  await rejects(()=>db.query("update volunteer_badge_levels set min_supported=0 where level='beginner'"),'check');
  await db.query("update volunteer_badge_levels set min_supported=15 where level='expert'");
  assert.equal(await badge(),'intermediate');
});
await check('BDG-14 visible to help seekers and volunteers; only for approved, active volunteers',async()=>{
  assert.equal(await badge('vol','s17'),'intermediate');
  assert.equal(await badge('vol','vol2'),'intermediate');
  assert.deepEqual(await stats('s17',['volPending']),[]);
  await su();await db.query("insert into account_blocks(user_id,reason) values($1,'Test')",[ids.vol]);
  assert.deepEqual(await stats('s17',['vol']),[]);
  await rejects(()=>progress('vol'),'not_allowed');
  await su();await db.query('delete from account_blocks where user_id=$1',[ids.vol]);
  assert.equal(await progress('s17'),null,'help seekers have no progress');
  assert.equal(await progress('volPending'),null,'not yet approved');
  await su();await db.exec('set role anon');
  await rejects(()=>db.query('select my_maak_badge_progress()'),'permission denied');
  await db.exec('reset role');
});
await check('BDG-15 ratings are unchanged: same rating fields next to the badge; 100-id limit kept',async()=>{
  const [s]=await stats('s17',['vol']);
  assert.deepEqual(Object.keys(s).sort(),['average_rating','badge','rating_count','volunteer_id']);
  assert.equal(s.rating_count,0);assert.equal(s.average_rating,null);
  await as('s17');
  const many=Array.from({length:101},(_,i)=>`c0000000-0000-4000-8000-${String(i).padStart(12,'0')}`);
  await rejects(()=>db.query('select maak_volunteer_stats($1::uuid[])',[many]),'too_many_volunteers');
  assert.deepEqual(await stats('s17',[]),[]);
});
await check('SQL-01 re-running keeps thresholds and records; rollback restores the ratings summary',async()=>{
  await su();await db.query("update volunteer_badge_levels set min_supported=6 where level='intermediate'");
  const before=(await db.query('select count(*)::int c from volunteer_support_completions')).rows[0].c;
  await db.exec(migration);
  assert.equal((await db.query("select min_supported from volunteer_badge_levels where level='intermediate'")).rows[0].min_supported,6);
  assert.equal((await db.query('select count(*)::int c from volunteer_support_completions')).rows[0].c,before);
  await db.exec(read('supabase/rollbacks/20261126110000_volunteer_badges_rollback.sql'));
  for(const t of ['volunteer_badge_levels','volunteer_support_completions'])
    assert.equal((await db.query(`select to_regclass('public.${t}') t`)).rows[0].t,null);
  const [s]=await stats('s17',['vol']);
  assert.deepEqual(Object.keys(s).sort(),['average_rating','rating_count','volunteer_id']);
  await su();assert.ok((await db.query("select to_regclass('public.volunteer_ratings') t")).rows[0].t);
  // Applied again from scratch: default thresholds, backfilled from ended chats (14 -> Intermediate).
  await su();await db.exec(migration);assert.equal(await badge(),'intermediate');
});
console.log(`${n} volunteer badge checks passed`);
