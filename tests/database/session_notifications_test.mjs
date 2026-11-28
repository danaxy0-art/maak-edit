// Checks for supabase/migrations/20261127000000_session_notifications.sql:
// session notifications are shown and pushed, with times in each recipient's
// device time (Riyadh time when unknown). Set PREV_MIGRATION to an earlier
// copy of the file to also check the upgrade.
// Run: cd tests/database && npm install && node session_notifications_test.mjs
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
await db.exec(`create schema vault; create schema net;
 create table vault.decrypted_secrets(name text primary key, decrypted_secret text);
 insert into vault.decrypted_secrets values('maak_project_url','https://ref.supabase.co'),('maak_push_secret','s');
 create table net.calls(id serial, body jsonb);
 create function net.http_post(url text, body jsonb, params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
  returns bigint language sql as $$ insert into net.calls(body) values(body) returning id::bigint $$;`);
await db.exec(read('supabase/migrations/20261106000000_push_notifications.sql').replace('create extension if not exists pg_net with schema extensions;',''));
await db.exec(read('supabase/migrations/20261107020000_single_restriction_push.sql'));
await db.exec(read('supabase/migrations/20261121100000_session_scheduling.sql'));
const migration=read('supabase/migrations/20261127000000_session_notifications.sql');
const rollback=read('supabase/rollbacks/20261127000000_session_notifications_rollback.sql');
const previous=process.env.PREV_MIGRATION?readFileSync(process.env.PREV_MIGRATION,'utf8'):null;

const ids={s1:'40000000-0000-0000-0000-000000000001',v1:'40000000-0000-0000-0000-000000000002'};
await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2),($3,$4)',[ids.s1,JSON.stringify({full_name:'Sara',role:'help_seeker'}),ids.v1,JSON.stringify({full_name:'Vera',role:'volunteer'})]);
await db.query("insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English')",[ids.s1]);
await db.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','x','approved')",[ids.v1]);
await db.query("insert into device_tokens(token,user_id) values($1,$2),($3,$4)",['tok-s1'.padEnd(30,'x'),ids.s1,'tok-v1'.padEnd(30,'x'),ids.v1]);
async function as(name){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]??'']);if(name)await db.exec('set role authenticated');}
let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}

// A slot tomorrow at 15:00 UTC = 18:00 Riyadh.
const day=new Date(Date.now()+2*86400e3);day.setUTCHours(15,0,0,0);
const end=new Date(day.getTime()+3600e3);
const local=(d,mins)=>{const r=new Date(d.getTime()+mins*60e3);const wd=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][r.getUTCDay()];const mo=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][r.getUTCMonth()];const h=r.getUTCHours();return `${wd} ${r.getUTCDate()} ${mo} ${r.getUTCFullYear()}, ${h%12||12}:${String(r.getUTCMinutes()).padStart(2,'0')} ${h<12?'AM':'PM'}`;};
const riyadh=d=>{const r=new Date(d.getTime()+3*3600e3);const wd=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][r.getUTCDay()];const mo=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][r.getUTCMonth()];const h=r.getUTCHours();return `${wd} ${r.getUTCDate()} ${mo} ${r.getUTCFullYear()}, ${h%12||12}:${String(r.getUTCMinutes()).padStart(2,'0')} ${h<12?'AM':'PM'} (Riyadh time)`;};
const pushes=async()=>{await as('');return (await db.query("select body from net.calls")).rows.map(r=>r.body);};

// Before the fix: one old booking-era row and one scheduling request with a UTC time.
await as('');
await db.query("insert into notifications(user_id,title,body,kind) values($1,'Old booking','legacy','session')",[ids.s1]);
await as('v1');const slot1=(await db.query('select add_maak_time_slot($1,$2) id',[day.toISOString(),end.toISOString()])).rows[0].id;
await as('s1');const booking1=(await db.query('select request_maak_session($1) id',[slot1])).rows[0].id;
await as('');
const before=(await db.query("select kind,body from notifications where reference_id=$1",[booking1])).rows[0];
await check('BEFORE: the old label says UTC and the push is skipped',async()=>{assert.equal(before.kind,'session');assert.match(before.body,/\d{4}-\d{2}-\d{2} 15:00 UTC/);assert.equal((await pushes()).filter(p=>p.kind==='session').length,0);});

if(previous)await db.exec(previous);
await db.exec(migration);await db.exec(migration); // repeatable

await check('MIG-01 earlier scheduling notifications move to support_session with Riyadh time',async()=>{await as('');const r=(await db.query("select kind,body from notifications where reference_id=$1",[booking1])).rows[0];assert.equal(r.kind,'support_session');assert.ok(r.body.includes(riyadh(day)),r.body);assert.ok(!/UTC/.test(r.body));});
await check('MIG-02 old booking-era session rows stay hidden (kind session)',async()=>{await as('');assert.equal((await db.query("select kind from notifications where title='Old booking'")).rows[0].kind,'session');});
await check('MIG-03 moved rows are not pushed again',async()=>{assert.equal((await pushes()).filter(p=>p.kind==='support_session').length,0);});
await check('LABEL-01 unknown offset: 15:00 UTC shows as 6:00 PM (Riyadh time)',async()=>{await as('');const r=(await db.query("select maak_session_localize(maak_session_label('2026-11-30 15:00+00'),$1) x",[ids.v1])).rows[0].x;assert.equal(r,'Mon 30 Nov 2026, 6:00 PM (Riyadh time)');const am=(await db.query("select maak_session_localize('At '||maak_session_label('2026-12-01 06:05+00')||'.',$1) x",[ids.v1])).rows[0].x;assert.equal(am,'At Tue 1 Dec 2026, 9:05 AM (Riyadh time).');});
await check('TZ-01 members report their device offset; invalid offsets are rejected',async()=>{await as('s1');await db.query('select set_maak_utc_offset(60)');await db.query('select set_maak_utc_offset(60)');for(const bad of [7,-780,900]){await assert.rejects(()=>db.query('select set_maak_utc_offset($1)',[bad]),/invalid_utc_offset/);}await assert.rejects(()=>db.query('select * from member_time_zones'));await as('');assert.equal((await db.query('select utc_offset_minutes m from member_time_zones where user_id=$1',[ids.s1])).rows[0].m,60);await db.exec('set role anon');await assert.rejects(()=>db.query('select set_maak_utc_offset(0)'));await db.exec('reset role');});
await check('TZ-02 known offset: device time without a suffix (also half-hour and negative zones)',async()=>{await as('');const f=async(m)=>{await db.query("insert into member_time_zones(user_id,utc_offset_minutes) values($1,$2) on conflict(user_id) do update set utc_offset_minutes=$2",[ids.s1,m]);return (await db.query("select maak_session_localize(maak_session_label('2026-11-30 15:00+00'),$1) x",[ids.s1])).rows[0].x;};assert.equal(await f(60),'Mon 30 Nov 2026, 4:00 PM');assert.equal(await f(330),'Mon 30 Nov 2026, 8:30 PM');assert.equal(await f(-300),'Mon 30 Nov 2026, 10:00 AM');assert.equal(await f(600),'Tue 1 Dec 2026, 1:00 AM');await f(60);});
await check('NEW-01 accepting: the help seeker (offset +60) gets their device time, pushed',async()=>{await as('v1');await db.query('select decide_maak_session($1,true)',[booking1]);await as('');const r=(await db.query("select title,body,kind from notifications where user_id=$1 and kind='support_session' order by created_at desc limit 1",[ids.s1])).rows[0];assert.equal(r.kind,'support_session');assert.ok(r.body.includes(local(day,60)),r.body);assert.ok(!/Riyadh|UTC|maak-time/.test(r.body),r.body);const p=(await pushes()).filter(x=>x.kind==='support_session');assert.equal(p.length,1);assert.equal(p[0].user_id,ids.s1);assert.equal(p[0].body,r.body);});
await check('NEW-02 a new request notifies the volunteer and pushes it',async()=>{const d2=new Date(day.getTime()+86400e3);await as('v1');const s2=(await db.query('select add_maak_time_slot($1,$2) id',[d2.toISOString(),new Date(d2.getTime()+3600e3).toISOString()])).rows[0].id;await as('s1');await db.query('select request_maak_session($1)',[s2]);await as('');const r=(await db.query("select title,body from notifications where user_id=$1 and kind='support_session' order by created_at desc limit 1",[ids.v1])).rows[0];assert.equal(r.title,'New session request');assert.ok(r.body.includes(riyadh(d2)),r.body);assert.ok((await pushes()).some(x=>x.kind==='support_session'&&x.user_id===ids.v1));});
await check('NEW-03 a reschedule localizes both times for each side',async()=>{await as('');await db.query("insert into member_time_zones(user_id,utc_offset_minutes) values($1,-300) on conflict(user_id) do update set utc_offset_minutes=-300",[ids.v1]);const d3=new Date(day.getTime()+3*86400e3);await as('v1');const s3=(await db.query('select add_maak_time_slot($1,$2) id',[d3.toISOString(),new Date(d3.getTime()+3600e3).toISOString()])).rows[0].id;await as('s1');await db.query('select reschedule_maak_session($1,$2)',[booking1,s3]);await as('');const r=(await db.query("select body from notifications where user_id=$1 and kind='support_session' order by created_at desc limit 1",[ids.v1])).rows[0];assert.ok(r.body.includes(local(day,-300))&&r.body.includes(local(d3,-300)),r.body);assert.equal((await db.query("select count(*)::int n from notifications where body like '%maak-time%' or title like '%maak-time%'")).rows[0].n,0);});
await check('ROLL-01 rollback returns to kind session; migration re-applies',async()=>{await as('');await db.exec(rollback);assert.equal((await db.query("select count(*)::int n from notifications where kind='support_session'")).rows[0].n,0);assert.match((await db.query("select maak_session_label('2026-11-30 15:00+00') x")).rows[0].x,/UTC$/);assert.equal((await db.query("select to_regclass('public.member_time_zones') t")).rows[0].t,null);await db.exec(migration);assert.ok((await db.query("select count(*)::int n from notifications where kind='support_session'")).rows[0].n>=3);});
console.log(`\n${n} checks passed`);
