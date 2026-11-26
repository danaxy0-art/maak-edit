// Concurrency checks for 20261126100000_volunteer_ratings.sql and
// 20261126110000_volunteer_badges.sql on a REAL PostgreSQL server, with
// separate connections and overlapping transactions (PGlite cannot do this).
//
// Needs the `pg` client and either:
//   MAAK_PG_URL=postgres://user:pass@host:port/postgres  (a throwaway server), or
//   the `embedded-postgres` package (downloads PostgreSQL binaries).
// Neither is a project dependency. Example, from an empty folder:
//   npm install --no-save pg embedded-postgres
//   node <repo>/tests/database/volunteer_concurrency_test.mjs
// The script creates and drops its own database; never point it at production.
import {readFileSync, mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(join(process.cwd(),'noop.js'));
const pg=require('pg');
const base=fileURLToPath(new URL('../../',import.meta.url));
const read=f=>readFileSync(base+f,'utf8');
const mig=f=>read('supabase/migrations/'+f);

let server=null,adminUrl=process.env.MAAK_PG_URL;
if(!adminUrl){
  const EmbeddedPostgres=require('embedded-postgres').default;
  server=new EmbeddedPostgres({databaseDir:mkdtempSync(join(tmpdir(),'maak-pg-')),user:'postgres',password:'postgres',port:54329,persistent:false,initdbFlags:['--encoding=UTF8','--locale=C']});
  await server.initialise();await server.start();
  adminUrl='postgres://postgres:postgres@localhost:54329/postgres';
}
const dbName=`maak_concurrency_${Date.now()}`;
const admin=new pg.Client({connectionString:adminUrl});await admin.connect();
await admin.query(`create database ${dbName} encoding 'UTF8' template template0`);
const url=adminUrl.replace(/\/[^/]*$/,'/'+dbName);
const su=new pg.Client({connectionString:url});await su.connect();
const version=(await su.query('select version() v')).rows[0].v;

try{
  // The stub already creates the cluster-wide roles only when missing.
  await su.query(read('tests/database/account_blocking/00_supabase_stub.sql').replace(/^\\.*$/gm,''));
  await su.query('alter table storage.objects add column if not exists metadata jsonb;');
  await su.query(read('supabase_schema.sql'));
  for(const f of ['20261018_matching.sql','20261018_condition_reviews.sql','20261021090000_chat_reads_remove_booking.sql']) await su.query(mig(f));
  await su.query('alter table public.support_requests add column if not exists restricted_at timestamptz;');
  for(const f of ['20261021_account_blocking.sql','20261105000000_chat_end_reactions.sql','20261105010000_chat_reopen.sql',
    '20261126100000_volunteer_ratings.sql','20261126110000_volunteer_badges.sql']) await su.query(mig(f));

  const ids={};let k=0;
  for(const [name,role] of [['seeker','help_seeker'],['seeker2','help_seeker'],['vol','volunteer'],['vol2','volunteer']]){
    ids[name]=`b1000000-0000-4000-8000-${String(++k).padStart(12,'0')}`;
    await su.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[ids[name],`${name}@x.com`,JSON.stringify({full_name:name,role})]);
    if(role==='help_seeker') await su.query("insert into help_seeker_profiles(user_id,chronic_condition,preferred_language) values($1,'Diabetes','English')",[ids[name]]);
    else await su.query("insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,status) values($1,'Diabetes','English','Story','approved')",[ids[name]]);
  }
  async function chat(seeker,vol,{ended=true}={}){
    const r=(await su.query("insert into support_requests(seeker_id,volunteer_id,status) values($1,$2,'accepted') returning id",[ids[seeker],ids[vol]])).rows[0].id;
    await su.query("insert into messages(request_id,sender_id,body) values($1,$2,'hi')",[r,ids[vol]]);
    if(ended) await su.query('update support_requests set ended_at=now(),ended_by=seeker_id where id=$1',[r]);
    return r;
  }
  // A member connection: every statement runs as `authenticated` with that member's id.
  async function member(name){
    const c=new pg.Client({connectionString:url});await c.connect();
    c.begin=async()=>{await c.query('begin');await c.query('set local role authenticated');
      await c.query("select set_config('request.jwt.claim.sub',$1,true)",[ids[name]]);};
    return c;
  }
  const outcome=p=>p.then(()=> 'ok',e=>e.message);
  const waitUntilBlocked=async(c,label)=>{ // the other transaction is waiting on a lock
    for(let i=0;i<200;i++){
      const n=(await su.query("select count(*)::int n from pg_stat_activity where datname=$1 and wait_event_type='Lock'",[dbName])).rows[0].n;
      if(n>0) return;await new Promise(r=>setTimeout(r,25));
    }
    throw new Error(`${label}: second transaction never waited on a lock`);
  };
  let n=0;async function check(label,f){await f();n++;console.log('PASS',label);}

  await check('CONC-01 two overlapping first ratings: one is saved, the other gets already_rated',async()=>{
    const r=await chat('seeker','vol');
    const a=await member('seeker'),b=await member('seeker');
    await a.begin();await b.begin();
    await a.query('select rate_maak_volunteer($1,4)',[r]);            // A holds the new row, not committed
    const second=outcome(b.query('select rate_maak_volunteer($1,2)',[r])); // B must wait for A
    await waitUntilBlocked(b,'CONC-01');
    await a.query('commit');
    assert.match(await second,/already_rated/);await b.query('rollback');
    const rows=(await su.query('select stars from volunteer_ratings where request_id=$1',[r])).rows;
    assert.deepEqual(rows,[{stars:4}]);
    await a.end();await b.end();
  });
  await check('CONC-02 ten parallel first ratings from separate connections: exactly one row',async()=>{
    const r=await chat('seeker2','vol');
    const cs=await Promise.all(Array.from({length:10},()=>member('seeker2')));
    const results=await Promise.all(cs.map((c,i)=>outcome((async()=>{await c.begin();await c.query('select rate_maak_volunteer($1,$2)',[r,1+i%5]);await c.query('commit');})())));
    assert.equal(results.filter(x=>x==='ok').length,1,results.join(' | '));
    assert.ok(results.filter(x=>x!=='ok').every(x=>/already_rated/.test(x)),results.join(' | '));
    assert.equal((await su.query('select count(*)::int c from volunteer_ratings where request_id=$1',[r])).rows[0].c,1);
    await Promise.all(cs.map(c=>c.query('rollback').catch(()=>{}).then(()=>c.end())));
  });
  await check('CONC-03 two overlapping corrections: the first wins, the second gets correction_not_allowed',async()=>{
    const r=(await su.query('select request_id r from volunteer_ratings where seeker_id=$1',[ids.seeker])).rows[0].r;
    const a=await member('seeker'),b=await member('seeker');
    await a.begin();await b.begin();
    await a.query('select correct_maak_rating($1,3)',[r]);           // A holds the row lock
    const second=outcome(b.query('select correct_maak_rating($1,5)',[r]));
    await waitUntilBlocked(b,'CONC-03');
    await a.query('commit');
    assert.match(await second,/correction_not_allowed/);await b.query('rollback');
    const [row]=(await su.query('select stars,corrected_at from volunteer_ratings where request_id=$1',[r])).rows;
    assert.equal(row.stars,3);assert.ok(row.corrected_at,'corrected once');
    await a.end();await b.end();
  });
  await check('CONC-04 ten parallel corrections: exactly one applies, value and single correction kept',async()=>{
    const r=(await su.query('select request_id r from volunteer_ratings where seeker_id=$1',[ids.seeker2])).rows[0].r;
    const before=(await su.query('select stars from volunteer_ratings where request_id=$1',[r])).rows[0].stars;
    const targets=[1,2,3,4,5].filter(s=>s!==before);
    const cs=await Promise.all(Array.from({length:10},()=>member('seeker2')));
    const results=await Promise.all(cs.map((c,i)=>outcome((async()=>{await c.begin();await c.query('select correct_maak_rating($1,$2)',[r,targets[i%4]]);await c.query('commit');})())));
    assert.equal(results.filter(x=>x==='ok').length,1,results.join(' | '));
    assert.ok(results.filter(x=>x!=='ok').every(x=>/correction_not_allowed/.test(x)),results.join(' | '));
    const rows=(await su.query('select stars,corrected_at from volunteer_ratings where request_id=$1',[r])).rows;
    assert.equal(rows.length,1);assert.notEqual(rows[0].stars,before);assert.ok(rows[0].corrected_at);
    await Promise.all(cs.map(c=>c.query('rollback').catch(()=>{}).then(()=>c.end())));
  });
  await check('CONC-05 both members press End Chat at once: one completion record, one credit',async()=>{
    const r=await chat('seeker','vol2',{ended:false});
    const a=await member('seeker'),b=await member('vol2');
    await a.begin();await b.begin();
    await a.query('select end_maak_chat($1)',[r]);
    const second=outcome(b.query('select end_maak_chat($1)',[r]));
    await waitUntilBlocked(b,'CONC-05');
    await a.query('commit');
    assert.equal(await second,'ok','repeating End Chat is harmless');await b.query('commit');
    assert.equal((await su.query('select count(*)::int c from volunteer_support_completions where request_id=$1',[r])).rows[0].c,1);
    await a.end();await b.end();
  });
  console.log(`${n} concurrency checks passed on: ${version}`);
}finally{
  await su.end();await admin.query(`drop database if exists ${dbName}`);await admin.end();
  if(server) await server.stop();
}
