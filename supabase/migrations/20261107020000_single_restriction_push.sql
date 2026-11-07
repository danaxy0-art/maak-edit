-- Apply after 20261106000000_push_notifications.sql. Repeatable.
--
-- Blocking a member sent two pushes: "Your account has been restricted" (from the
-- account_blocks trigger) and "Account access updated" (a notification row written
-- by a function that exists only in the live database). Only the first is wanted.
--
-- The notification push trigger now runs when the transaction commits (a deferred
-- constraint trigger) instead of at insert time. By then the block row exists
-- whatever order the live function wrote things in, so any notification for a
-- restricted member is skipped and only the restriction push is sent.
-- Reactivation removes the block in the same transaction, so "Account reactivated"
-- is still pushed.
--
-- The "Account access updated" row itself is still stored. To find what writes it:
--   select p.proname from pg_proc p
--   where p.pronamespace='public'::regnamespace and p.prosrc ilike '%Account access updated%';
begin;

create or replace function public.push_maak_notification() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.kind='session' then return new; end if;
 -- The account_blocks trigger sends the one push a restricted member gets.
 if is_maak_account_blocked(new.user_id) then return new; end if;
 -- The row may have been deleted later in the same transaction.
 if not exists(select 1 from notifications where id=new.id) then return new; end if;
 perform send_maak_push(new.user_id,new.title,new.body,new.kind,new.reference_id,new.id);
 return new;
end; $$;

drop trigger if exists maak_notification_push on public.notifications;
create constraint trigger maak_notification_push after insert on public.notifications
 deferrable initially deferred
 for each row execute function public.push_maak_notification();

revoke all on function public.push_maak_notification() from public,anon,authenticated;
commit;
