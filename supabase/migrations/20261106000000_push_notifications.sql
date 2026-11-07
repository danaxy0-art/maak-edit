-- Push notifications (Firebase Cloud Messaging).
--
-- Every row inserted into public.notifications is also sent as a push to the
-- recipient's devices. The existing RPCs and triggers already insert those rows for:
--   * chat messages ................ notify_maak_message (kind 'message')
--   * volunteer approved/rejected .. review_volunteer_application (kind 'application')
--   * new volunteer application .... save_maak_profile, to every admin (kind 'application')
--   * new support request .......... request_peer_support, to the volunteer (kind 'request')
--   * request accepted/declined .... decide_support_request, to the seeker (kind 'request')
--   * account reactivated .......... admin_reactivate_account / appeal approval (kind 'account')
-- Account restriction writes no notification row (a blocked user cannot read them),
-- so an AFTER INSERT trigger on account_blocks sends that push directly.
--
-- Delivery: pg_net posts to the send-push Edge Function after the transaction
-- commits; a rolled-back action sends nothing. A push failure never fails the action.
--
-- One-time setup (SQL editor), before or after running this file:
--   select vault.create_secret('https://<project-ref>.supabase.co', 'maak_project_url');
--   select vault.create_secret('<long random string>', 'maak_push_secret');
-- and set the same random string as the PUSH_WEBHOOK_SECRET Edge Function secret.
begin;

create extension if not exists pg_net with schema extensions;

-- 1. Device tokens ------------------------------------------------------------
-- One row per app install. A token belongs to whoever signed in on that device
-- last. No RLS policies: clients use the two RPCs below; send-push uses the service role.
create table if not exists public.device_tokens (
  token text primary key check (char_length(token) between 20 and 4096),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'android' check (platform in ('android','ios','web')),
  updated_at timestamptz not null default now());
create index if not exists device_tokens_user on public.device_tokens(user_id);
alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;

create or replace function public.register_maak_device_token(p_token text,p_platform text default 'android')
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'not_allowed'; end if;
 if p_token is null or char_length(p_token) not between 20 and 4096 then raise exception 'invalid_token'; end if;
 if coalesce(p_platform,'') not in ('android','ios','web') then raise exception 'invalid_platform'; end if;
 insert into device_tokens(token,user_id,platform,updated_at) values(p_token,auth.uid(),p_platform,now())
 on conflict(token) do update set user_id=excluded.user_id,platform=excluded.platform,updated_at=now();
end; $$;

create or replace function public.unregister_maak_device_token(p_token text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'not_allowed'; end if;
 delete from device_tokens where token=p_token and user_id=auth.uid();
end; $$;

revoke all on function public.register_maak_device_token(text,text),public.unregister_maak_device_token(text) from public,anon;
grant execute on function public.register_maak_device_token(text,text),public.unregister_maak_device_token(text) to authenticated;

-- 2. Sender ---------------------------------------------------------------------
-- Queues one HTTP call to send-push. Internal only: never callable by clients.
create or replace function public.send_maak_push(p_user_id uuid,p_title text,p_body text,p_kind text,
  p_reference_id uuid default null,p_notification_id uuid default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare base_url text; secret text;
begin
 if p_user_id is null or not exists(select 1 from device_tokens where user_id=p_user_id) then return; end if;
 select decrypted_secret into base_url from vault.decrypted_secrets where name='maak_project_url';
 select decrypted_secret into secret from vault.decrypted_secrets where name='maak_push_secret';
 if base_url is null or secret is null then
  raise warning 'maak push skipped: vault secrets maak_project_url / maak_push_secret are missing';
  return;
 end if;
 perform net.http_post(
  url:=rtrim(base_url,'/')||'/functions/v1/send-push',
  headers:=jsonb_build_object('Content-Type','application/json','x-push-secret',secret),
  body:=jsonb_build_object('user_id',p_user_id,'title',p_title,'body',p_body,'kind',p_kind,
   'reference_id',p_reference_id,'notification_id',p_notification_id),
  timeout_milliseconds:=8000);
exception when others then
 raise warning 'maak push failed: %', sqlerrm;
end; $$;
revoke all on function public.send_maak_push(uuid,text,text,text,uuid,uuid) from public,anon,authenticated;

-- 3. Every new notification row becomes a push ------------------------------------
-- 'session' rows are hidden in the app (booking was removed), so they are skipped.
-- A restricted account only receives account-status pushes.
create or replace function public.push_maak_notification() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.kind='session' then return new; end if;
 if new.kind<>'account' and is_maak_account_blocked(new.user_id) then return new; end if;
 perform send_maak_push(new.user_id,new.title,new.body,new.kind,new.reference_id,new.id);
 return new;
end; $$;
drop trigger if exists maak_notification_push on public.notifications;
create trigger maak_notification_push after insert on public.notifications
 for each row execute function public.push_maak_notification();

-- 4. Account restriction -----------------------------------------------------------
-- The reason is shown on the in-app restricted screen, not on the lock screen.
create or replace function public.push_maak_account_block() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform send_maak_push(new.user_id,'Your account has been restricted',
  'Open Ma''ak to see the reason and submit an appeal.','account_blocked',null,null);
 return new;
end; $$;
drop trigger if exists maak_account_block_push on public.account_blocks;
create trigger maak_account_block_push after insert on public.account_blocks
 for each row execute function public.push_maak_account_block();

revoke all on function public.push_maak_notification(),public.push_maak_account_block() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
