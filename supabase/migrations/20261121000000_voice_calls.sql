-- Voice-only peer calls. Apply after existing Ma'ak chat/account migrations.
begin;
create table public.voice_calls (
 id uuid primary key default gen_random_uuid(),
 request_id uuid not null references public.support_requests(id) on delete cascade,
 caller_id uuid not null references auth.users(id),
 callee_id uuid not null references auth.users(id),
 status text not null default 'calling' check(status in ('calling','connected','ended','missed')),
 offer jsonb not null, answer jsonb,
 accepted_at timestamptz, connected_at timestamptz, ended_at timestamptz,
 caller_connected boolean not null default false, callee_connected boolean not null default false,
 caller_seen timestamptz not null default now(), callee_seen timestamptz not null default now(),
 end_reason text,
 created_at timestamptz not null default now(),
 check(caller_id <> callee_id)
);
create index voice_calls_request_time on public.voice_calls(request_id,created_at desc);
create index voice_calls_callee on public.voice_calls(callee_id,status);
create table public.voice_call_candidates (
 id bigint generated always as identity primary key,
 call_id uuid not null references public.voice_calls(id) on delete cascade,
 sender_id uuid not null references auth.users(id), candidate jsonb not null
);
create table public.voice_call_issues (
 id uuid primary key default gen_random_uuid(),
 call_id uuid not null references public.voice_calls(id) on delete cascade,
 reporter_id uuid not null references auth.users(id),
 category text not null check(category in ('No audio','Poor audio','Disconnected','Could not connect','Other')),
 description text not null check(length(btrim(description)) between 10 and 2000),
 status text not null default 'open' check(status in ('open','reviewing','resolved','dismissed')),
 admin_note text, reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 created_at timestamptz not null default now(), unique(call_id,reporter_id)
);
alter table public.voice_calls enable row level security;
alter table public.voice_call_candidates enable row level security;
alter table public.voice_call_issues enable row level security;
revoke all on public.voice_calls,public.voice_call_candidates,public.voice_call_issues from anon,authenticated;
grant select on public.voice_calls,public.voice_call_candidates,public.voice_call_issues to authenticated;
create policy voice_participant_read on public.voice_calls for select to authenticated
 using (auth.uid() in (caller_id,callee_id) and public.is_maak_active());
create policy voice_candidate_read on public.voice_call_candidates for select to authenticated
 using(exists(select 1 from public.voice_calls c where c.id=call_id and auth.uid() in (c.caller_id,c.callee_id)));
create policy voice_issue_read on public.voice_call_issues for select to authenticated
 using(public.is_maak_active() and (reporter_id=auth.uid() or public.is_maak_admin()));

-- All session mutations use this RPC; direct writes and participant spoofing are denied.
create function public.voice_call_action(p_action text,p_call_id uuid default null,p_request_id uuid default null,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c public.voice_calls; r public.support_requests; peer uuid;
begin
 if auth.uid() is null or not public.is_maak_active() then raise exception 'not_allowed'; end if;
 -- Serialize start/transition operations to prevent simultaneous outgoing/incoming calls.
 perform pg_advisory_xact_lock(731921,1);
 update public.voice_calls set status=case when accepted_at is null then 'missed' else 'ended' end,
 ended_at=now(),end_reason='timeout',offer='{}',answer=null
 where status in ('calling','connected') and (
 (status='calling' and created_at < now()-interval '60 seconds') or
 (status='connected' and least(caller_seen,callee_seen)<now()-interval '90 seconds'));
 delete from public.voice_call_candidates ice using public.voice_calls vc where vc.id=ice.call_id and vc.status in ('ended','missed');
 if p_action='start' then
  select * into r from public.support_requests where id=p_request_id for update;
  if not found or not public.can_send_maak_message(p_request_id) then raise exception 'conversation_unavailable'; end if;
  peer:=case when r.seeker_id=auth.uid() then r.volunteer_id else r.seeker_id end;
  if exists(select 1 from public.voice_calls where status in ('calling','connected')
    and (caller_id in (auth.uid(),peer) or callee_id in (auth.uid(),peer))) then raise exception 'participant_busy'; end if;
  if p_payload->>'type' is distinct from 'offer' or length(coalesce(p_payload->>'sdp','')) not between 10 and 100000 then raise exception 'invalid_offer'; end if;
  insert into public.voice_calls(request_id,caller_id,callee_id,offer) values(p_request_id,auth.uid(),peer,p_payload) returning * into c;
 elsif p_action='sync' then
  -- End active calls whose conversation was ended/restricted or whose member was blocked.
  update public.voice_calls vc set status='ended',ended_at=now(),end_reason='conversation_unavailable',offer='{}',answer=null
  where vc.status in ('calling','connected') and auth.uid() in (vc.caller_id,vc.callee_id)
  and (not public.can_send_maak_message(vc.request_id) or exists(select 1 from public.account_blocks b where b.user_id in (vc.caller_id,vc.callee_id)));
  return coalesce((select to_jsonb(vc) from public.voice_calls vc where auth.uid() in(vc.caller_id,vc.callee_id)
    and vc.status in ('calling','connected') order by vc.created_at desc limit 1),'null'::jsonb);
 else
  select * into c from public.voice_calls where id=p_call_id for update;
  if not found or auth.uid() not in(c.caller_id,c.callee_id) then raise exception 'not_allowed'; end if;
  if p_action in ('accept','connected','candidate','heartbeat') and c.status not in ('calling','connected') then return to_jsonb(c); end if;
  if p_action in ('accept','connected','candidate','heartbeat') and not public.can_send_maak_message(c.request_id) then raise exception 'conversation_unavailable'; end if;
  if p_action='accept' then
   if auth.uid()<>c.callee_id or c.accepted_at is not null or p_payload->>'type' is distinct from 'answer'
      or length(coalesce(p_payload->>'sdp','')) not between 10 and 100000 then raise exception 'invalid_answer'; end if;
   update public.voice_calls set answer=p_payload,accepted_at=now() where id=c.id;
  elsif p_action='connected' then
   if c.accepted_at is null then raise exception 'not_accepted'; end if;
   update public.voice_calls set caller_connected=caller_connected or auth.uid()=caller_id,
    callee_connected=callee_connected or auth.uid()=callee_id where id=c.id;
   update public.voice_calls set status='connected',connected_at=coalesce(connected_at,now()) where id=c.id and caller_connected and callee_connected;
  elsif p_action in ('end','reject') then
   if p_action='reject' and (auth.uid()<>c.callee_id or c.accepted_at is not null) then raise exception 'not_allowed'; end if;
   update public.voice_calls set status='ended',ended_at=now(),end_reason=case when p_action='reject' then 'rejected' else 'hangup' end,
    offer='{}',answer=null where id=c.id and status in ('calling','connected');
   delete from public.voice_call_candidates where call_id=c.id;
  elsif p_action='heartbeat' then
   update public.voice_calls set caller_seen=case when caller_id=auth.uid() then now() else caller_seen end,
    callee_seen=case when callee_id=auth.uid() then now() else callee_seen end where id=c.id;
  elsif p_action='candidate' then
   if length(coalesce(p_payload->>'candidate','')) not between 1 and 5000 then raise exception 'invalid_candidate'; end if;
   if (select count(*) from public.voice_call_candidates where call_id=c.id and sender_id=auth.uid())>=100 then raise exception 'too_many_candidates'; end if;
   insert into public.voice_call_candidates(call_id,sender_id,candidate) values(c.id,auth.uid(),p_payload);
  else raise exception 'invalid_action'; end if;
  select * into c from public.voice_calls where id=c.id;
 end if;
 return to_jsonb(c);
end $$;
revoke all on function public.voice_call_action(text,uuid,uuid,jsonb) from public,anon;
grant execute on function public.voice_call_action(text,uuid,uuid,jsonb) to authenticated;

create function public.report_voice_call(p_call_id uuid,p_category text,p_description text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;
begin
 if not public.is_maak_active() or not exists(select 1 from public.voice_calls where id=p_call_id and auth.uid() in(caller_id,callee_id)) then raise exception 'not_allowed'; end if;
 insert into public.voice_call_issues(call_id,reporter_id,category,description) values(p_call_id,auth.uid(),p_category,btrim(p_description)) returning id into result;
 return result;
end $$;
create function public.review_voice_call_issue(p_issue_id uuid,p_status text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.is_maak_admin() or not public.is_maak_active() then raise exception 'not_allowed'; end if;
 if p_status not in ('reviewing','resolved','dismissed') or length(btrim(p_note)) not between 3 and 2000 then raise exception 'invalid_review'; end if;
 update public.voice_call_issues set status=p_status,admin_note=btrim(p_note),reviewed_by=auth.uid(),reviewed_at=now() where id=p_issue_id;
 if not found then raise exception 'issue_not_found'; end if;
end $$;
revoke all on function public.report_voice_call(uuid,text,text),public.review_voice_call_issue(uuid,text,text) from public,anon;
grant execute on function public.report_voice_call(uuid,text,text),public.review_voice_call_issue(uuid,text,text) to authenticated;
commit;
