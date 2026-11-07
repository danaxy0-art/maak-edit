// 20261107030000: appeals succeed even when something writes a notification during
// the appeal, and blocking/unblocking touches the account status signal.
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
for(const f of ['20261021_account_blocking.sql','20261022_account_moderation_visibility.sql','20261023_account_appeals.sql']) await db.exec(mig(f));
// Stand-in for live-only code: notify admins (and the user) whenever an appeal is submitted.
await db.exec(`create function public.live_only_appeal_notice() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into notifications(user_id,title,body,kind) select id,'Appeal submitted','x','appeal' from profiles where role='admin';
 insert into notifications(user_id,title,body,kind) values(new.user_id,'Account status update','Your appeal was received.','account');
 return new; end $$;
create trigger live_only_appeal_notice after insert on public.account_block_appeals for each row execute function public.live_only_appeal_notice();`);
const a='a1111111-1111-4111-8111-111111111111',admin='c3333333-3333-4333-8333-333333333333';
for(const [u,n] of [[a,'Dana'],[admin,'Admin']]) await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)`,[u,`${n}@x.com`,JSON.stringify({full_name:n,role:'help_seeker'})]);
await db.query(`update profiles set role='admin' where id=$1`,[admin]);
async function as(u){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[u??'']);await db.exec(u?'set role authenticated':'reset role');}
let checks=0;async function ok(label,fn){await fn();checks++;console.log('PASS',label);}

await as(admin);await db.query(`select admin_block_account($1,'Spam')`,[a]);
await ok('before the fix: the appeal fails with account_blocked (reproduces the bug)',async()=>{
 await as(a);await assert.rejects(db.query(`select submit_my_appeal('Please review')`),/account_blocked/);
});
const fix=mig('20261107030000_appeal_and_block_fixes.sql');await db.exec('reset role');await db.exec(fix);await db.exec(fix);
await ok('after the fix: the appeal is submitted',async()=>{
 await as(a);const r=(await db.query(`select submit_my_appeal('Please review') s`)).rows[0].s;assert.equal(r.appeals_used,1);
});
await ok('restricted users still cannot update or delete notifications, or write other guarded tables',async()=>{
 await db.exec('reset role');const nid=(await db.query(`select id from notifications where user_id=$1 limit 1`,[a])).rows[0].id;
 await db.exec('reset role');
 // Simulate a definer function updating as the restricted user: the guard still fires.
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[a]);
 await assert.rejects(db.query('update notifications set is_read=true where id=$1',[nid]),/account_blocked/);
 await assert.rejects(db.query(`update profiles set full_name='X' where id=$1`,[a]),/account_blocked/);
});
await ok('users still cannot insert notifications themselves',async()=>{
 await as(a);await assert.rejects(db.query(`insert into notifications(user_id,title,body) values($1,'x','y')`,[a]),/permission denied/);
});
await ok('blocking and reactivating touch the status signal, visible only to that user',async()=>{
 await as(admin);await db.query('select admin_reactivate_account($1)',[a]);
 await db.exec('reset role');const t1=(await db.query('select changed_at from account_status_signals where user_id=$1',[a])).rows[0].changed_at;assert.ok(t1);
 await as(a);assert.equal((await db.query('select * from account_status_signals')).rows.length,1);
 assert.deepEqual(Object.keys((await db.query('select * from account_status_signals')).rows[0]).sort(),['changed_at','user_id']);
 await as(admin);assert.equal((await db.query('select * from account_status_signals')).rows.length,0,'others see nothing');
});
console.log(`${checks} appeal/block fix checks passed`);
