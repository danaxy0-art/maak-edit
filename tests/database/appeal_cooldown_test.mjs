// Checks for supabase/migrations/20261107120000_appeal_cooldown.sql (repeating
// 90-day appeal cooldown). Isolated in-memory PGlite database with account blocking,
// visibility, appeals and the appeal/block fixes. Time is simulated by back-dating
// the stored rejection timestamp (test-only: the history guard is paused for that
// one UPDATE; the migration itself never does this).
// Run: cd tests/database && npm install && node appeal_cooldown_test.mjs
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const base = fileURLToPath(new URL('../../', import.meta.url));
const read = f => readFileSync(base + f, 'utf8').replace(/^\\.*$/gm, '');
const COOLDOWN = 'supabase/migrations/20261107120000_appeal_cooldown.sql';
const ROLLBACK = 'supabase/rollbacks/20261107120000_appeal_cooldown_rollback.sql';
const VERIFY = 'supabase/checks/20261107120000_appeal_cooldown_verify.sql';

const db = new PGlite();
await db.exec(read('tests/database/account_blocking/00_supabase_stub.sql'));
await db.exec('alter table storage.objects add column metadata jsonb; grant delete on storage.objects to authenticated;');
await db.exec(read('supabase_schema.sql').replace('create extension if not exists pgcrypto;', ''));
for (const f of ['20261018_matching.sql', '20261018_condition_reviews.sql', '20261021090000_chat_reads_remove_booking.sql'])
  await db.exec(read('supabase/migrations/' + f));
await db.exec('alter table public.support_requests add column restricted_at timestamptz;');
for (const f of ['20261021_account_blocking.sql', '20261022_account_moderation_visibility.sql', '20261023_account_appeals.sql',
  '20261107030000_appeal_and_block_fixes.sql'])
  await db.exec(read('supabase/migrations/' + f));
// Stand-in for production-only code that notifies on every appeal (as in Shayma's tests).
await db.exec(`create function public.live_only_appeal_notice() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into notifications(user_id,title,body,kind) select id,'Appeal submitted','x','appeal' from profiles where role='admin'; return new; end $$;
create trigger live_only_appeal_notice after insert on public.account_block_appeals for each row execute function public.live_only_appeal_notice();`);

let k = 0; const uid = () => `70000000-0000-0000-0000-${String(++k).padStart(12, '0')}`;
const users = {};
async function user(name, admin = false) {
  const id = uid(); users[name] = id;
  await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)', [id, `${name}@t`, JSON.stringify({full_name: name, role: 'help_seeker'})]);
  if (admin) await db.query("update profiles set role='admin' where id=$1", [id]);
  return id;
}
async function as(name) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [users[name] ?? '']);
  if (name) await db.exec('set role authenticated');
}
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const status = async who => { await as(who); return (await one('select my_appeal_status() s')).s; };
const submit = async (who, msg = 'Please review my case.') => { await as(who); return (await one('select submit_my_appeal($1) s', [msg])).s; };
const pendingId = async who => { await as(''); return (await one("select id from account_block_appeals where user_id=$1 and status='pending'", [users[who]])).id; };
const decide = async (who, approve, note = 'Not enough information.') => {
  const id = await pendingId(who); await as('admin'); await db.query('select admin_decide_appeal($1,$2,$3)', [id, approve, approve ? null : note]);
};
const block = async who => { await as('admin'); await db.query("select admin_block_account($1,'Repeated spam')", [users[who]]); };
// Back-date the latest decided appeal of a member (simulates time passing).
async function ageLatestDecision(who, interval) {
  await as('');
  await db.exec('alter table account_block_appeals disable trigger maak_appeal_update_guard');
  await db.query(`update account_block_appeals set submitted_at = now() - interval '${interval}' - interval '1 hour',
     decided_at = now() - interval '${interval}'
   where id = (select id from account_block_appeals where user_id=$1 and status<>'pending' order by attempt desc limit 1)`, [users[who]]);
  await db.exec('alter table account_block_appeals enable trigger maak_appeal_update_guard');
}
const count = async who => { await as(''); return (await one('select count(*)::int n from account_block_appeals where user_id=$1', [users[who]])).n; };
let n = 0; async function check(label, f) { await f(); n++; console.log('PASS', label); }

await user('admin', true);
for (const name of ['old', 'mona', 'lina', 'rami']) await user(name);

// An exhausted history BEFORE the migration: three rejections, the last 120 days ago.
await block('old');
for (let i = 0; i < 3; i++) { await submit('old'); await decide('old', false); }
await ageLatestDecision('old', '120 days');
await assert.rejects(() => submit('old'), /appeal_limit_reached/, 'old rule before migration');

await check('COOL-01 migration applies twice; verify all true; an old exhausted history uses its stored rejection time', async () => {
  await as('');
  await db.exec(read(COOLDOWN)); await db.exec(read(COOLDOWN));
  for (const [kk, v] of Object.entries(await one(read(VERIFY)))) assert.equal(v, true, kk);
  const s = await status('old');
  assert.equal(s.can_appeal, true, '120 days > 90: open now'); assert.equal(s.appeals_remaining, 1);
  assert.equal(s.in_cooldown_cycle, true); assert.equal(s.unavailable_reason, null);
  assert.equal(await count('old'), 3, 'history untouched');
});

await check('COOL-02 the first three appeals work as before (one pending at a time)', async () => {
  await block('mona');
  let s = await status('mona');
  assert.equal(s.appeals_remaining, 3); assert.equal(s.can_appeal, true); assert.equal(s.in_cooldown_cycle, false);
  s = await submit('mona');
  assert.equal(s.unavailable_reason, 'appeal_pending'); assert.equal(s.can_appeal, false);
  await assert.rejects(() => submit('mona'), /appeal_pending/);
  await decide('mona', false); await submit('mona'); await decide('mona', false);
  s = await status('mona'); assert.equal(s.appeals_remaining, 1); assert.equal(s.can_appeal, true);
});

await check('COOL-03 the third rejection starts a 90-day cooldown from its server timestamp', async () => {
  await submit('mona'); await decide('mona', false);
  const s = await status('mona');
  assert.equal(s.can_appeal, false); assert.equal(s.unavailable_reason, 'appeal_cooldown');
  assert.equal(s.appeals_remaining, 0); assert.equal(s.cooldown_days_remaining, 90);
  await as('');
  const decided = (await one("select decided_at from account_block_appeals where user_id=$1 and attempt=3", [users.mona])).decided_at;
  assert.equal(new Date(s.cooldown_until).getTime(), new Date(decided).getTime() + 90 * 86400000);
  await assert.rejects(() => submit('mona'), /appeal_cooldown/);
  assert.equal(await count('mona'), 3);
});

await check('COOL-04 at 89 days the wait is not over (1 day remaining, submission refused)', async () => {
  await ageLatestDecision('mona', '89 days');
  const s = await status('mona');
  assert.equal(s.can_appeal, false); assert.equal(s.cooldown_days_remaining, 1);
  await assert.rejects(() => submit('mona'), /appeal_cooldown/);
  await ageLatestDecision('mona', '89 days 23 hours 59 minutes');
  assert.equal((await status('mona')).cooldown_days_remaining, 1, 'never shows 0 while waiting');
  await assert.rejects(() => submit('mona'), /appeal_cooldown/);
});

await check('COOL-05 at exactly 90 days ONE additional appeal is allowed', async () => {
  await ageLatestDecision('mona', '90 days');
  let s = await status('mona');
  assert.equal(s.can_appeal, true); assert.equal(s.appeals_remaining, 1); assert.equal(s.cooldown_days_remaining, null);
  s = await submit('mona', 'Fourth appeal after waiting.');
  assert.equal(s.appeals[0].attempt, 4); assert.equal(s.unavailable_reason, 'appeal_pending');
  await assert.rejects(() => submit('mona'), /appeal_pending/, 'still one pending at a time');
});

await check('COOL-06 rejecting that appeal starts a NEW 90-day cooldown from its own rejection', async () => {
  await decide('mona', false);
  const s = await status('mona');
  assert.equal(s.unavailable_reason, 'appeal_cooldown'); assert.equal(s.cooldown_days_remaining, 90);
  await as('');
  const fourth = (await one("select decided_at from account_block_appeals where user_id=$1 and attempt=4", [users.mona])).decided_at;
  assert.equal(new Date(s.cooldown_until).getTime(), new Date(fourth).getTime() + 90 * 86400000);
  await assert.rejects(() => submit('mona'), /appeal_cooldown/);
});

await check('COOL-07 the cycle repeats indefinitely: 90 days -> 1 appeal -> rejection (three more cycles)', async () => {
  for (const attempt of [5, 6, 7]) {
    await ageLatestDecision('mona', '45 days');
    await assert.rejects(() => submit('mona'), /appeal_cooldown/, `cycle ${attempt}: day 45 refused`);
    await ageLatestDecision('mona', '90 days');
    const s = await submit('mona', `Appeal ${attempt}`);
    assert.equal(s.appeals[0].attempt, attempt);
    await assert.rejects(() => submit('mona'), /appeal_pending/, `cycle ${attempt}: only one appeal, not three`);
    await decide('mona', false);
    const after = await status('mona');
    assert.equal(after.unavailable_reason, 'appeal_cooldown'); assert.equal(after.cooldown_days_remaining, 90);
  }
  assert.equal(await count('mona'), 7, 'complete history kept');
  const s = await status('mona');
  assert.deepEqual(s.appeals.map(a => a.attempt), [7, 6, 5, 4, 3, 2, 1]);
  assert.ok(s.appeals.every(a => a.status === 'rejected'));
});

await check('COOL-08 approving an appeal in the cycle reactivates the account; cooldown no longer applies', async () => {
  await ageLatestDecision('mona', '90 days');
  await submit('mona', 'Appeal 8'); await decide('mona', true);
  const s = await status('mona');
  assert.equal(s.blocked, false); assert.equal(s.unavailable_reason, 'account_active');
  await as(''); assert.equal((await one('select count(*)::int n from account_blocks where user_id=$1', [users.mona])).n, 0);
  assert.equal(await count('mona'), 8);
});

await check('COOL-09 a new block starts its own fresh set of three appeals', async () => {
  await block('mona');
  const s = await status('mona');
  assert.equal(s.appeals_used, 0); assert.equal(s.appeals_remaining, 3); assert.equal(s.can_appeal, true);
  assert.equal(await count('mona'), 8, 'earlier history kept');
});

await check('COOL-10 the countdown never unblocks; manual reactivation ends the cooldown', async () => {
  await block('lina');
  for (let i = 0; i < 3; i++) { await submit('lina'); await decide('lina', false); }
  await ageLatestDecision('lina', '365 days');
  await as(''); assert.equal((await one('select count(*)::int n from account_blocks where user_id=$1', [users.lina])).n, 1, 'still blocked after a year');
  assert.equal((await status('lina')).can_appeal, true);
  await as('admin'); await db.query('select admin_reactivate_account($1,null)', [users.lina]);
  assert.equal((await status('lina')).unavailable_reason, 'account_active');
  await assert.rejects(() => submit('lina'), /account_active/);
});

await check('COOL-11 bypass attempts are refused by the database', async () => {
  await block('rami');
  for (let i = 0; i < 3; i++) { await submit('rami'); await decide('rami', false); }
  await as('');
  const ev = (await one('select block_event_id from account_blocks where user_id=$1', [users.rami])).block_event_id;
  const ins = (attempt) => db.query('insert into account_block_appeals(user_id,block_event_id,attempt,message) values($1,$2,$3,$4)', [users.rami, ev, attempt, 'sneaky']);
  await assert.rejects(() => ins(4), /appeal_cooldown/, 'direct insert during cooldown');
  await assert.rejects(() => ins(9), /appeal_attempt_invalid/, 'skipping attempt numbers');
  await assert.rejects(() => ins(2), /appeal_attempt_invalid/, 'reusing an attempt number');
  await assert.rejects(() => db.query("update account_block_appeals set decided_at = decided_at - interval '100 days' where user_id=$1 and attempt=3", [users.rami]), /appeal_history_immutable/, 'cannot back-date the rejection');
  await assert.rejects(() => db.query('delete from account_block_appeals where user_id=$1', [users.rami]), /appeal_history_immutable/, 'cannot delete history');
  await as('rami');
  await assert.rejects(() => db.query('insert into account_block_appeals(user_id,block_event_id,attempt,message) values($1,$2,4,$3)', [users.rami, ev, 'x']), /permission denied/);
  await assert.rejects(() => db.query('select maak_appeal_cooldown_until($1)', [ev]), /permission denied/);
  assert.equal(await count('rami'), 3);
});

await check('COOL-12 rollback refuses while 4th+ appeals exist; nothing changes', async () => {
  await as('');
  await assert.rejects(() => db.exec(read(ROLLBACK)), /beyond attempt 3/);
  await db.exec('rollback');
  for (const [kk, v] of Object.entries(await one(read(VERIFY)))) assert.equal(v, true, kk);
});

console.log(`${n} appeal cooldown checks passed`);
await db.close();
