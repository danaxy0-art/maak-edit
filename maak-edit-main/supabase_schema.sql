-- Ma'ak complete, idempotent schema / upgrade. Run ONCE in Supabase SQL Editor.
-- Keeps existing profile data. Run the entire file together.
begin;
create extension if not exists pgcrypto;
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text, full_name text, username text, created_at timestamptz default now());
alter table public.profiles add column if not exists username text;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('help_seeker','volunteer','admin'));
create unique index if not exists profiles_username_unique on public.profiles(lower(username)) where username is not null;
create table if not exists public.help_seeker_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  chronic_condition text not null, preferred_language text not null, description text,
  created_at timestamptz default now());
create table if not exists public.volunteer_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  condition_experience text not null, preferred_language text not null,
  experience_description text not null, verification_document_url text,
  status text default 'pending_review' check (status in ('pending_review','approved','rejected')),
  rejection_reason text, created_at timestamptz default now());
alter table public.volunteer_profiles add column if not exists rejection_reason text;
create table if not exists public.chronic_conditions (
  id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 80),
  is_active boolean not null default true, sort_order integer not null default 0,
  created_at timestamptz not null default now());
create unique index if not exists conditions_name_unique on public.chronic_conditions(lower(name));
insert into public.chronic_conditions(name,sort_order)
values ('Diabetes',1),('Hypertension',2),('Asthma',3),('Chronic kidney disease',4),('Rheumatoid arthritis',5),('Other',6)
on conflict do nothing;
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  title text not null, body text not null, kind text not null default 'info', reference_id uuid,
  is_read boolean not null default false, created_at timestamptz not null default now());
create index if not exists notifications_user_date on public.notifications(user_id,created_at desc);
create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(), seeker_id uuid not null references auth.users(id) on delete cascade,
  volunteer_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(), check(seeker_id <> volunteer_id));
create unique index if not exists one_open_request on public.support_requests(seeker_id,volunteer_id) where status in ('pending','accepted');
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(), request_id uuid not null references public.support_requests(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check(length(trim(body)) between 1 and 2000), created_at timestamptz not null default now());
create index if not exists messages_request_date on public.messages(request_id,created_at);
create table if not exists public.support_sessions (
  id uuid primary key default gen_random_uuid(), request_id uuid not null references public.support_requests(id) on delete cascade,
  starts_at timestamptz not null, duration_minutes integer not null default 60,
  created_at timestamptz not null default now(), unique(request_id,starts_at));
create table if not exists public.resources (
  id uuid primary key default gen_random_uuid(), title text not null, summary text not null,
  url text not null check(url like 'https://%'), created_at timestamptz not null default now());

create or replace function public.is_maak_admin() returns boolean language sql stable security definer
set search_path = public as $$ select exists(select 1 from profiles where id=auth.uid() and role='admin'); $$;
revoke all on function public.is_maak_admin() from public;
grant execute on function public.is_maak_admin() to anon, authenticated;
create or replace function public.guard_maak_profile() returns trigger language plpgsql set search_path=public as $$
begin
  if auth.uid() is not null then
    if TG_OP='INSERT' then
      if new.id<>auth.uid() or new.role not in ('help_seeker','volunteer') then raise exception 'role_not_allowed'; end if;
    elsif new.id<>old.id or new.role is distinct from old.role then raise exception 'role_not_allowed'; end if;
  end if;
  if new.username is not null then
    new.username := lower(trim(new.username));
    if new.username !~ '^[a-z0-9_]{3,30}$' then raise exception 'invalid_username'; end if;
  end if;
  if new.full_name is not null and length(trim(new.full_name))>80 then raise exception 'invalid_full_name'; end if;
  return new;
end; $$;
drop trigger if exists maak_profile_guard on public.profiles;
create trigger maak_profile_guard before insert or update on public.profiles for each row execute function public.guard_maak_profile();
create or replace function public.seed_maak_account() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,full_name,username,role) values(new.id,
    left(coalesce(new.raw_user_meta_data->>'full_name',''),80),
    nullif(lower(trim(new.raw_user_meta_data->>'username')),''),
    case when new.raw_user_meta_data->>'role'='volunteer' then 'volunteer' else 'help_seeker' end)
  on conflict(id) do nothing;
  return new;
end; $$;
drop trigger if exists maak_auth_profile on auth.users;
create trigger maak_auth_profile after insert on auth.users for each row execute function public.seed_maak_account();
-- Repair accounts created before this trigger was installed; preserve existing rows.
insert into public.profiles(id,full_name,username,role)
select u.id,left(coalesce(u.raw_user_meta_data->>'full_name',''),80),
  'user_'||replace(u.id::text,'-','')::varchar(20),
  case when exists(select 1 from public.volunteer_profiles v where v.user_id=u.id)
    or u.raw_user_meta_data->>'role'='volunteer' then 'volunteer' else 'help_seeker' end
from auth.users u where not exists(select 1 from public.profiles p where p.id=u.id)
on conflict(id) do nothing;
-- Internal identifier for legacy compatibility; never requested at registration.
update public.profiles set username='user_'||replace(id::text,'-','')::varchar(20) where username is null;

create or replace function public.guard_volunteer_decision() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or is_maak_admin() then return new; end if;
  if new.user_id<>auth.uid() then raise exception 'not_allowed'; end if;
  if TG_OP='INSERT' then
    if new.status<>'pending_review' or nullif(new.rejection_reason,'') is not null then raise exception 'not_allowed'; end if;
  elsif new.status is distinct from old.status or new.rejection_reason is distinct from old.rejection_reason then
    if not (old.status='rejected' and new.status='pending_review' and nullif(new.rejection_reason,'') is null) then
      raise exception 'not_allowed';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists maak_volunteer_guard on public.volunteer_profiles;
create trigger maak_volunteer_guard before insert or update on public.volunteer_profiles for each row execute function public.guard_volunteer_decision();

-- Remove old broad policies before installing explicit permissions.
do $$ declare t text; p record; begin
  foreach t in array array['profiles','help_seeker_profiles','volunteer_profiles','chronic_conditions','notifications','support_requests','messages','support_sessions','resources'] loop
    execute format('alter table public.%I enable row level security',t);
    for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
      execute format('drop policy %I on public.%I',p.policyname,t);
    end loop;
  end loop;
end $$;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or is_maak_admin());
create policy profiles_insert on public.profiles for insert to authenticated with check(id=auth.uid() and role in ('help_seeker','volunteer'));
create policy profiles_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy seekers_owner_read on public.help_seeker_profiles for select to authenticated using(user_id=auth.uid());
create policy volunteers_read on public.volunteer_profiles for select to authenticated using(user_id=auth.uid() or is_maak_admin());
-- Profile writes use an atomic RPC, so callers cannot bypass condition validation.
create policy conditions_read on public.chronic_conditions for select to anon, authenticated using(is_active or is_maak_admin());
create policy conditions_admin_write on public.chronic_conditions for all to authenticated using(is_maak_admin()) with check(is_maak_admin());
create policy notification_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy notification_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy requests_read on public.support_requests for select to authenticated using(seeker_id=auth.uid() or volunteer_id=auth.uid());
create policy messages_read on public.messages for select to authenticated using(exists(select 1 from support_requests r where r.id=request_id and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())));
create or replace function public.can_send_maak_message(p_request_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from support_requests r join volunteer_profiles v on v.user_id=r.volunteer_id
    where r.id=p_request_id and r.status='accepted' and v.status='approved'
      and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid()));
$$;
revoke all on function public.can_send_maak_message(uuid) from public,anon;
grant execute on function public.can_send_maak_message(uuid) to authenticated;
create policy messages_send on public.messages for insert to authenticated
  with check(sender_id=auth.uid() and can_send_maak_message(request_id));
create policy sessions_read on public.support_sessions for select to authenticated using(exists(select 1 from support_requests r where r.id=request_id and (r.seeker_id=auth.uid() or r.volunteer_id=auth.uid())));
create policy resources_read on public.resources for select to authenticated using(true);
create policy resources_admin on public.resources for all to authenticated using(is_maak_admin()) with check(is_maak_admin());
grant select,insert,update on public.profiles to authenticated;
grant select on public.help_seeker_profiles,public.volunteer_profiles,public.support_requests,public.support_sessions to authenticated;
revoke insert,update,delete on public.help_seeker_profiles,public.volunteer_profiles,public.support_requests,public.support_sessions from anon,authenticated;
grant select on public.chronic_conditions to anon,authenticated;
grant insert,update,delete on public.chronic_conditions to authenticated;
grant select on public.notifications to authenticated;
revoke insert,delete,update on public.notifications from authenticated;
grant update(is_read) on public.notifications to authenticated;
grant select,insert on public.messages to authenticated;
grant select,insert,update,delete on public.resources to authenticated;

create or replace function public.save_maak_profile(p_full_name text,p_username text,p_role text,p_condition text,p_language text,
  p_description text default '',p_document text default null,p_reapply boolean default false)
returns void language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); saved_role text; previous_condition text; previous_status text; previous_document text;
begin
  if me is null then raise exception 'not_allowed'; end if;
  select role into saved_role from profiles where id=me for update;
  if saved_role is null or saved_role<>p_role or p_role not in ('help_seeker','volunteer') then raise exception 'role_not_allowed'; end if;
  if p_username is null or p_username !~ '^[a-zA-Z0-9_]{3,30}$' then raise exception 'invalid_username'; end if;
  if p_full_name is null or p_language is null or p_description is null or length(trim(p_full_name)) not between 1 and 80 or p_language not in ('Arabic','English','French') or length(p_description)>300 then raise exception 'invalid_profile'; end if;
  if p_role='help_seeker' then select chronic_condition into previous_condition from help_seeker_profiles where user_id=me;
  else select condition_experience,status,verification_document_url into previous_condition,previous_status,previous_document from volunteer_profiles where user_id=me; end if;
  perform 1 from chronic_conditions where name=p_condition and is_active for share;
  if not found and p_condition is distinct from previous_condition then raise exception 'condition_inactive'; end if;
  if p_condition is null or trim(p_condition)='' then raise exception 'condition_inactive'; end if;
  update profiles set full_name=trim(p_full_name),username=lower(trim(p_username)) where id=me;
  if p_role='help_seeker' then
    insert into help_seeker_profiles(user_id,chronic_condition,preferred_language,description) values(me,p_condition,p_language,p_description)
    on conflict(user_id) do update set chronic_condition=excluded.chronic_condition,preferred_language=excluded.preferred_language,description=excluded.description;
  else
    if length(trim(p_description))=0 then raise exception 'invalid_profile'; end if;
    if p_document is not null and (split_part(p_document,'/',1)<>me::text or not exists(select 1 from storage.objects where bucket_id='verification-documents' and name=p_document)) then raise exception 'invalid_document'; end if;
    if coalesce(p_document,previous_document) is null then raise exception 'document_required'; end if;
    if p_reapply and previous_status is distinct from 'rejected' then raise exception 'application_changed'; end if;
    insert into volunteer_profiles(user_id,condition_experience,preferred_language,experience_description,verification_document_url,status)
    values(me,p_condition,p_language,p_description,p_document,'pending_review')
    on conflict(user_id) do update set condition_experience=excluded.condition_experience,preferred_language=excluded.preferred_language,
      experience_description=excluded.experience_description,verification_document_url=coalesce(p_document,volunteer_profiles.verification_document_url),
      status=case when p_reapply then 'pending_review' else volunteer_profiles.status end,
      rejection_reason=case when p_reapply then null else volunteer_profiles.rejection_reason end;
    if previous_status is null or p_reapply then
      insert into notifications(user_id,title,body,kind) select id,'New volunteer application','A volunteer application is ready for review.','application' from profiles where role='admin';
    end if;
  end if;
end; $$;

create or replace function public.admin_volunteer_applications() returns setof jsonb language plpgsql security definer set search_path=public as $$
begin if not is_maak_admin() then raise exception 'not_allowed'; end if;
  return query select to_jsonb(v)||jsonb_build_object('profiles',jsonb_build_object('full_name',p.full_name,'username',p.username))
    from volunteer_profiles v left join profiles p on p.id=v.user_id order by v.created_at desc;
end; $$;
create or replace function public.review_volunteer_application(p_user_id uuid,p_approved boolean,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_maak_admin() then raise exception 'not_allowed'; end if;
  if not p_approved and (p_reason is null or length(trim(p_reason)) not between 1 and 500) then raise exception 'reason_required'; end if;
  update volunteer_profiles set status=case when p_approved then 'approved' else 'rejected' end,
    rejection_reason=case when p_approved then null else trim(p_reason) end where user_id=p_user_id and status='pending_review';
  if not found then raise exception 'application_changed'; end if;
  insert into notifications(user_id,title,body,kind) values(p_user_id,
    case when p_approved then 'Application approved' else 'Application not approved' end,
    case when p_approved then 'You can now support help seekers.' else trim(p_reason) end,'application');
end; $$;
create or replace function public.browse_volunteers() returns setof jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('user_id',v.user_id,'full_name',p.full_name,'condition',v.condition_experience,
    'language',v.preferred_language,'description',v.experience_description)
  from volunteer_profiles v left join profiles p on p.id=v.user_id
  where auth.uid() is not null and v.status='approved' order by p.full_name;
$$;
create or replace function public.request_peer_support(p_volunteer_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare req uuid;
begin
  if not exists(select 1 from help_seeker_profiles where user_id=auth.uid()) or not exists(select 1 from volunteer_profiles where user_id=p_volunteer_id and status='approved') then raise exception 'not_allowed'; end if;
  insert into support_requests(seeker_id,volunteer_id) values(auth.uid(),p_volunteer_id) returning id into req;
  insert into notifications(user_id,title,body,kind,reference_id) values(p_volunteer_id,'New support request','Someone would like to connect with you.','request',req);
end; $$;
create or replace function public.my_support_requests() returns setof jsonb language sql stable security definer set search_path=public as $$
  select to_jsonb(r)||jsonb_build_object('contact_name',p.full_name,'condition',h.chronic_condition,
    'description',h.description,'last_message',(select body from messages where request_id=r.id order by created_at desc limit 1))
  from support_requests r join profiles p on p.id=case when r.seeker_id=auth.uid() then r.volunteer_id else r.seeker_id end
  join help_seeker_profiles h on h.user_id=r.seeker_id where r.seeker_id=auth.uid() or r.volunteer_id=auth.uid() order by r.created_at desc;
$$;
create or replace function public.decide_support_request(p_request_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path=public as $$
declare seeker uuid;
begin
  if not exists(select 1 from volunteer_profiles where user_id=auth.uid() and status='approved') then raise exception 'not_allowed'; end if;
  update support_requests set status=case when p_accept then 'accepted' else 'declined' end
    where id=p_request_id and volunteer_id=auth.uid() and status='pending' returning seeker_id into seeker;
  if not found then raise exception 'application_changed'; end if;
  insert into notifications(user_id,title,body,kind,reference_id) values(seeker,
    case when p_accept then 'Your support request was accepted' else 'Support request declined' end,
    case when p_accept then 'You can now start a conversation.' else 'You can choose another volunteer.' end,'request',p_request_id);
end; $$;
create or replace function public.notify_maak_message() returns trigger language plpgsql security definer set search_path=public as $$
declare recipient uuid; sender_name text;
begin
  select case when seeker_id=new.sender_id then volunteer_id else seeker_id end into recipient from support_requests where id=new.request_id;
  select full_name into sender_name from profiles where id=new.sender_id;
  insert into notifications(user_id,title,body,kind,reference_id) values(recipient,'New message from '||coalesce(sender_name,'your peer'),
    'Open your conversation to read the message.','message',new.request_id);
  return new;
end; $$;
drop trigger if exists maak_message_notification on public.messages;
create trigger maak_message_notification after insert on public.messages for each row execute function public.notify_maak_message();
create or replace function public.book_support_session(p_request_id uuid,p_starts_at timestamptz) returns void language plpgsql security definer set search_path=public as $$
declare recipient uuid;
begin
  select r.seeker_id into recipient from support_requests r join volunteer_profiles v on v.user_id=r.volunteer_id
    where r.id=p_request_id and r.volunteer_id=auth.uid() and r.status='accepted' and v.status='approved' for update of r;
  if not found or p_starts_at<=now() then raise exception 'invalid_session'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  if exists(select 1 from support_sessions s join support_requests r on r.id=s.request_id where r.volunteer_id=auth.uid()
    and s.starts_at<p_starts_at+interval '1 hour' and s.starts_at+interval '1 hour'>p_starts_at) then raise exception 'session_overlap'; end if;
  insert into support_sessions(request_id,starts_at) values(p_request_id,p_starts_at);
  insert into notifications(user_id,title,body,kind,reference_id) values(recipient,'Support session scheduled','Check your journey for the session time.','session',p_request_id);
end; $$;
create or replace function public.my_support_sessions() returns setof jsonb language sql stable security definer set search_path=public as $$
  select to_jsonb(s)||jsonb_build_object('contact_name',p.full_name) from support_sessions s join support_requests r on r.id=s.request_id
    join profiles p on p.id=case when r.seeker_id=auth.uid() then r.volunteer_id else r.seeker_id end
    where r.seeker_id=auth.uid() or r.volunteer_id=auth.uid() order by s.starts_at;
$$;
-- Rename a condition without stranding saved profiles; disabling preserves history.
create or replace function public.sync_condition_name() returns trigger language plpgsql security definer set search_path=public as $$
begin if new.name is distinct from old.name then
  update help_seeker_profiles set chronic_condition=new.name where chronic_condition=old.name;
  update volunteer_profiles set condition_experience=new.name where condition_experience=old.name;
end if; return new; end; $$;
drop trigger if exists maak_condition_rename on public.chronic_conditions;
create trigger maak_condition_rename after update of name on public.chronic_conditions for each row execute function public.sync_condition_name();

-- Private verification files, owner uploads and short-lived admin/owner downloads.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('verification-documents','verification-documents',false,5242880,array['application/pdf','image/png','image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['application/pdf','image/png','image/jpeg'];
drop policy if exists "verification-documents: owner upload" on storage.objects;
drop policy if exists "verification-documents: public read" on storage.objects;
drop policy if exists maak_document_upload on storage.objects;
drop policy if exists maak_document_read on storage.objects;
create policy maak_document_upload on storage.objects for insert to authenticated with check(bucket_id='verification-documents' and auth.uid()::text=(storage.foldername(name))[1]);
create policy maak_document_read on storage.objects for select to authenticated using(bucket_id='verification-documents' and (auth.uid()::text=(storage.foldername(name))[1] or is_maak_admin()));

-- Explicit RPC grants. No anonymous access to private data or decisions.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in ('save_maak_profile','admin_volunteer_applications','review_volunteer_application',
    'browse_volunteers','request_peer_support','my_support_requests','decide_support_request','book_support_session','my_support_sessions') loop
    execute format('revoke all on function %s from public,anon',f.sig);
    execute format('grant execute on function %s to authenticated',f.sig);
  end loop;
end $$;
-- Realtime for unread badges and chat. Poll-free, filtered by RLS.
do $$ declare t text; begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach t in array array['notifications','messages'] loop
      if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
        execute format('alter publication supabase_realtime add table public.%I',t);
      end if;
    end loop;
  end if;
end $$;
notify pgrst, 'reload schema';
commit;
-- Assign an EXISTING user's admin role only in SQL Editor (replace email):
-- update public.profiles set role='admin' where id=(select id from auth.users where email='admin@example.com');
