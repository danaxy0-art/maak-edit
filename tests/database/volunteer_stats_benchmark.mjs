// Benchmark (not a pass/fail test) for maak_volunteer_stats with a full batch
// of 100 volunteers. Compares the shipped set-based query with the earlier
// per-volunteer design (count over support_requests + messages for each
// volunteer). Runs on PGlite (single-process WASM PostgreSQL), so absolute
// times are only indicative; the relative difference and plans are the point.
//   node tests/database/volunteer_stats_benchmark.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');
const mig=f=>read('supabase/migrations/'+f);
const db=new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
await db.exec('alter table storage.objects add column metadata jsonb;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;',''));
for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql']) await db.exec(mig(f));
await db.exec('alter table public.support_requests add column restricted_at timestamptz;');
for(const f of ['20261021_account_blocking.sql','20261105000000_chat_end_reactions.sql','20261105010000_chat_reopen.sql',
 '20261126100000_volunteer_ratings.sql','20261126110000_volunteer_badges.sql']) await db.exec(mig(f));

const V=100,PER=30; // 100 volunteers x 30 conversations = 3000 conversations, 6000 messages
const t0=Date.now();
await db.exec(`
 insert into auth.users(id,email,raw_user_meta_data)
  select ('e0000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'v'||i||'@x.com','{"role":"volunteer","full_name":"V"}' from generate_series(1,${V}) i;
 insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status)
  select ('e0000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Diabetes','English','Story','approved' from generate_series(1,${V}) i;
 insert into auth.users(id,email,raw_user_meta_data)
  select ('f0000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'s'||i||'@x.com','{"role":"help_seeker","full_name":"S"}' from generate_series(1,${V*PER}) i;
 insert into help_seeker_profiles(user_id,chronic_condition,preferred_language)
  select ('f0000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Diabetes','English' from generate_series(1,${V*PER}) i;
 insert into support_requests(seeker_id,volunteer_id,status)
  select ('f0000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
         ('e0000000-0000-4000-8000-'||lpad((1+(i-1)%${V})::text,12,'0'))::uuid,'accepted' from generate_series(1,${V*PER}) i;
 insert into messages(request_id,sender_id,body) select id,seeker_id,'hello' from support_requests;
 insert into messages(request_id,sender_id,body) select id,volunteer_id,'hi' from support_requests;
 update support_requests set ended_at=now(),ended_by=seeker_id;   -- fires the completion trigger
 insert into volunteer_ratings(request_id,seeker_id,volunteer_id,stars)
  select id,seeker_id,volunteer_id,1+(abs(hashtext(id::text))%5) from support_requests;
 analyze;`);
console.log(`seeded ${V} volunteers, ${V*PER} conversations, ${V*PER*2} messages in ${Date.now()-t0} ms`);

// The earlier design, kept here only for comparison.
await db.exec(`
create function public.bench_old_count(p uuid) returns int language sql stable as $$
  select count(distinct r.seeker_id)::int from support_requests r
  where r.volunteer_id=p and public.maak_request_had_support(r.id) and not public.is_maak_account_blocked(r.seeker_id) $$;
create function public.bench_old_stats(p_volunteer_ids uuid[]) returns setof jsonb language sql stable as $$
  select jsonb_build_object('volunteer_id',v.user_id,'rating_count',coalesce(s.n,0),
   'badge',public.maak_badge_for(public.bench_old_count(v.user_id)))
  from (select distinct unnest(p_volunteer_ids) id) ids
  join volunteer_profiles v on v.user_id=ids.id and v.status='approved'
  left join lateral (select count(*)::int n from volunteer_ratings x where x.volunteer_id=v.user_id) s on true
  where not public.is_maak_account_blocked(v.user_id) $$;`);

const idsSql=`(select array_agg(user_id) from volunteer_profiles)`;
await db.query("select set_config('request.jwt.claim.sub','f0000000-0000-4000-8000-000000000001',false)");
async function time(label,sql,runs=10){
  await db.query(sql); // warm up
  const t=performance.now();for(let i=0;i<runs;i++) await db.query(sql);
  const ms=(performance.now()-t)/runs;
  console.log(`${label.padEnd(44)} ${ms.toFixed(1).padStart(8)} ms per call (avg of ${runs})`);
  return ms;
}
const a=await time('earlier design (per-volunteer counts)',`select count(*) from bench_old_stats(${idsSql})`,3);
const b=await time('shipped maak_volunteer_stats (set-based)',`select count(*) from maak_volunteer_stats(${idsSql})`);
console.log(`speed-up: ${(a/b).toFixed(1)}x`);
const same=(await db.query(`select (select jsonb_agg(j->>'badge' order by j->>'volunteer_id') from bench_old_stats(${idsSql}) j)
  = (select jsonb_agg(j->>'badge' order by j->>'volunteer_id') from maak_volunteer_stats(${idsSql}) j) ok`)).rows[0].ok;
console.log(`same badges from both: ${same}`);

for(const [label,sql] of [
 ['plan: completion count for a batch',`explain select c.volunteer_id,count(distinct c.seeker_id) from volunteer_support_completions c
   join support_requests r on r.id=c.request_id and r.restricted_at is null where c.volunteer_id=any((${idsSql})::uuid[]) group by 1`],
 ['plan: rating aggregate for a batch',`explain select volunteer_id,count(*),avg(stars) from volunteer_ratings where volunteer_id=any((${idsSql})::uuid[]) group by 1`],
 ['plan: earlier per-volunteer lookup',`explain select count(*) from support_requests r where r.volunteer_id='e0000000-0000-4000-8000-000000000001'`]]){
  console.log(`\n${label}`);
  for(const row of (await db.query(sql)).rows) console.log('  '+row['QUERY PLAN']);
}
