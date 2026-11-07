-- Apply after 20261021_account_blocking.sql and 20261023_account_appeals.sql. Repeatable.
--
-- 1. Appeals failed with "This account has been blocked".
--    guard_maak_blocked_actor rejects every write a restricted user's request makes
--    to the protected tables, notifications included. Submitting an appeal is a
--    restricted user's own action, so any notification written while it runs (for
--    example by a live-only trigger that tells admins or the user about the appeal)
--    made the whole appeal fail.
--    Notification INSERTs are now exempt. This is safe: users have no INSERT privilege
--    on notifications (supabase_schema.sql revokes it), so the only code that can insert
--    them is database functions and triggers. Updates and deletes are still guarded.
--
-- 2. Instant redirect to the restricted screen.
--    account_blocks stays unreadable to users (block reasons and the acting admin are
--    private). Instead, account_status_signals holds only (user_id, changed_at). A
--    trigger touches it whenever a block is added or removed, and it is streamed over
--    Realtime, so the app re-checks the account the moment an admin blocks it.
begin;
set local lock_timeout = '10s';

-- 1. Blocked-actor guard: same as 20261021, plus the notification INSERT exemption.
create or replace function public.guard_maak_blocked_actor() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare me uuid:=auth.uid();
begin
 -- Only database functions and triggers can insert notifications (see header).
 if TG_TABLE_NAME='notifications' and TG_OP='INSERT' then return new; end if;
 if me is not null then
  perform 1 from profiles where id=me for key share;
  if is_maak_account_blocked(me) then raise exception 'account_blocked'; end if;
 end if;
 if TG_OP='DELETE' then return old; end if;
 return new;
end; $$;
revoke all on function public.guard_maak_blocked_actor() from public,anon,authenticated;

-- 2. Account status signal ----------------------------------------------------------
create table if not exists public.account_status_signals (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 changed_at timestamptz not null default now());
alter table public.account_status_signals enable row level security;
revoke all on public.account_status_signals from public,anon,authenticated;
grant select on public.account_status_signals to authenticated;
-- Restricted users must still see their own row (that's the point), so no
-- is_maak_active() check here. The row carries no reason or admin.
drop policy if exists account_status_signal_read on public.account_status_signals;
create policy account_status_signal_read on public.account_status_signals
 for select to authenticated using(user_id=auth.uid());

create or replace function public.touch_maak_account_signal() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare target uuid:=case when TG_OP='DELETE' then old.user_id else new.user_id end;
begin
 if exists(select 1 from profiles where id=target) then
  insert into account_status_signals(user_id,changed_at) values(target,now())
  on conflict(user_id) do update set changed_at=excluded.changed_at;
 end if;
 return null;
end; $$;
revoke all on function public.touch_maak_account_signal() from public,anon,authenticated;
drop trigger if exists maak_account_signal on public.account_blocks;
create trigger maak_account_signal after insert or update or delete on public.account_blocks
 for each row execute function public.touch_maak_account_signal();

-- Stream it over Realtime (skipped where the publication doesn't exist, e.g. tests).
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime')
    and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
                   and schemaname='public' and tablename='account_status_signals') then
  alter publication supabase_realtime add table public.account_status_signals;
 end if;
end $$;

notify pgrst,'reload schema';
commit;
