// Checks for supabase/migrations/20261127010000_member_profiles.sql.
// Run: cd tests/database && npm install && node member_profiles_test.mjs
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
await db.exec(read('supabase/migrations/20261021_account_blocking.sql'));
const migration=read('supabase/migrations/20261127010000_member_profiles.sql');
await db.exec(migration);await db.exec(migration); // repeatable

const ids={admin:'50000000-0000-0000-0000-000000000001',s1:'50000000-0000-0000-0000-000000000002',s2:'50000000-0000-0000-0000-000000000003',
 v1:'50000000-0000-0000-0000-000000000004',v2:'50000000-0000-0000-0000-000000000005',pend:'50000000-0000-0000-0000-000000000006'};
const names={admin:'Admin',s1:'Sara',s2:'Omar',v1:'Vera',v2:'Vic',pend:'Pending'};
for(const [k,id] of Object.entries(ids))await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[id,JSON.stringify({full_name:names[k],role:k[0]==='v'||k==='pend'?'volunteer':'help_seeker'})]);
await db.query("update profiles set role='admin' where id=$1",[ids.admin]);
await db.query("insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English'),($2,'Asthma','Arabic')",[ids.s1,ids.s2]);
await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Lived with it 10 years','approved'),($2,'Asthma','Arabic','x','approved'),($3,'Diabetes','English','x','pending_review')",[ids.v1,ids.v2,ids.pend]);
await db.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted')",[ids.s1,ids.v1]);
async function as(name){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]??'']);if(name)await db.exec('set role authenticated');}
const profile=async(who,target)=>{await as(who);return (await db.query('select get_maak_member_profile($1) p',[ids[target]])).rows[0].p;};
const rejects=async(f,msg)=>assert.rejects(f,e=>new RegExp(msg).test(e.message),`expected ${msg}`);
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}

await check('PROF-01 anyone sees an approved volunteer with experience (browse keys)',async()=>{for(const who of ['s2','v2']){const p=await profile(who,'v1');assert.equal(p.full_name,'Vera');assert.equal(p.role,'volunteer');assert.equal(p.condition,'Diabetes');assert.equal(p.language,'English');assert.equal(p.description,'Lived with it 10 years');assert.equal(p.user_id,ids.v1);assert.equal(p.approved,true);}});
await check('PROF-02 a stranger sees only name and role of a help seeker',async()=>{for(const who of ['s2','v2']){const p=await profile(who,'s1');assert.equal(p.full_name,'Sara');assert.equal(p.role,'help_seeker');assert.equal(p.condition,undefined);assert.equal(p.language,undefined);assert.equal(p.connected,false);}});
await check('PROF-03 the connected volunteer, the member and admins see the help seeker\'s condition',async()=>{for(const who of ['v1','s1','admin']){const p=await profile(who,'s1');assert.equal(p.condition,'Diabetes',who);assert.equal(p.language,'English');}assert.equal((await profile('v1','s1')).connected,true);assert.equal((await profile('s1','s1')).is_self,true);});
await check('PROF-04 pending volunteer is unavailable to others, visible to self and admin',async()=>{await as('s1');await rejects(()=>db.query('select get_maak_member_profile($1)',[ids.pend]),'profile_unavailable');assert.equal((await profile('pend','pend')).approved,false);assert.equal((await profile('admin','pend')).role,'volunteer');});
await check('PROF-05 admin accounts and unknown ids are unavailable',async()=>{await as('s1');await rejects(()=>db.query('select get_maak_member_profile($1)',[ids.admin]),'profile_unavailable');await rejects(()=>db.query('select get_maak_member_profile($1)',['50000000-0000-0000-0000-0000000000ff']),'profile_unavailable');});
await check('PROF-06 restricted accounts are unavailable; a restricted caller is refused',async()=>{await as('');await db.query("insert into account_blocks(user_id,reason,blocked_by) values($1,'spam',$2)",[ids.v2,ids.admin]);await as('s1');await rejects(()=>db.query('select get_maak_member_profile($1)',[ids.v2]),'profile_unavailable');await as('v2');await rejects(()=>db.query('select get_maak_member_profile($1)',[ids.v1]),'account_blocked');assert.equal((await profile('admin','v2')).full_name,'Vic');await as('');await db.query('delete from account_blocks where user_id=$1',[ids.v2]);});
await check('PROF-07 signed-out callers cannot use it',async()=>{await as('');await db.exec('set role anon');await assert.rejects(()=>db.query('select get_maak_member_profile($1)',[ids.v1]));});
await check('ROLL-01 rollback removes the function',async()=>{await as('');await db.exec(read('supabase/rollbacks/20261127010000_member_profiles_rollback.sql'));assert.equal((await db.query("select to_regprocedure('public.get_maak_member_profile(uuid)') f")).rows[0].f,null);await db.exec(migration);});
console.log(`\n${n} checks passed`);
