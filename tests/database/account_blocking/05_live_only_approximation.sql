-- Approximation of the LIVE-only restriction feature (not in Git), reconstructed
-- from the reviewed descriptions. Exact live bodies were not available to this test.
\set ON_ERROR_STOP 1
begin;
alter table public.support_requests add column if not exists restricted_at timestamptz;
alter table public.support_requests add column if not exists restricted_by uuid;
alter table public.support_requests add column if not exists restriction_reason text;

-- Live body as reported (adds r.restricted_at is null).
create or replace function public.can_send_maak_message(p_request_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
select exists(
  select 1
  from support_requests r
  join volunteer_profiles v on v.user_id = r.volunteer_id
  where r.id = p_request_id
    and r.status = 'accepted'
    and v.status = 'approved'
    and r.restricted_at is null
    and (
      r.seeker_id = auth.uid()
      or r.volunteer_id = auth.uid()
    )
);
$$;

-- Repo body plus the reported live restricted_at check.
create or replace function public.book_support_session(p_request_id uuid,p_starts_at timestamptz) returns void language plpgsql security definer set search_path=public as $$
declare recipient uuid;
begin
  select r.seeker_id into recipient from support_requests r join volunteer_profiles v on v.user_id=r.volunteer_id
    where r.id=p_request_id and r.volunteer_id=auth.uid() and r.status='accepted' and v.status='approved'
      and r.restricted_at is null for update of r;
  if not found or p_starts_at<=now() then raise exception 'invalid_session'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  if exists(select 1 from support_sessions s join support_requests r on r.id=s.request_id where r.volunteer_id=auth.uid()
    and s.starts_at<p_starts_at+interval '1 hour' and s.starts_at+interval '1 hour'>p_starts_at) then raise exception 'session_overlap'; end if;
  insert into support_sessions(request_id,starts_at) values(p_request_id,p_starts_at);
  insert into notifications(user_id,title,body,kind,reference_id) values(recipient,'Support session scheduled','Check your journey for the session time.','session',p_request_id);
end; $$;

-- Admin-only: restricts an accepted request and notifies both participants.
create or replace function public.admin_restrict_conversation(p_request_id uuid,p_reason text) returns void
language plpgsql security definer set search_path=public as $$
declare req support_requests%rowtype;
begin
  if not is_maak_admin() then raise exception 'not_allowed'; end if;
  update support_requests set restricted_at=now(),restricted_by=auth.uid(),restriction_reason=trim(p_reason)
    where id=p_request_id and status='accepted' returning * into req;
  if not found then raise exception 'request_changed'; end if;
  insert into notifications(user_id,title,body,kind,reference_id) values
    (req.seeker_id,'Conversation restricted',trim(p_reason),'request',req.id),
    (req.volunteer_id,'Conversation restricted',trim(p_reason),'request',req.id);
end; $$;

-- Admin-only read.
create or replace function public.admin_support_requests() returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  if not is_maak_admin() then raise exception 'not_allowed'; end if;
  return query select to_jsonb(r) from support_requests r order by r.created_at desc;
end; $$;

revoke all on function public.can_send_maak_message(uuid),public.book_support_session(uuid,timestamptz),
 public.admin_restrict_conversation(uuid,text),public.admin_support_requests() from public,anon;
grant execute on function public.can_send_maak_message(uuid),public.book_support_session(uuid,timestamptz),
 public.admin_restrict_conversation(uuid,text),public.admin_support_requests() to authenticated;
commit;
