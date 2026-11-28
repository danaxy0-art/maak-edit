-- Voice calls ring on the phone, even when Ma'ak is closed.
-- Apply after 20261121000000_voice_calls.sql and
-- 20261107020000_single_restriction_push.sql. Repeatable (safe to run twice).
-- Needs the updated send-push Edge Function (supabase functions deploy send-push)
-- and the updated app (it creates the ringtone channel).
--
-- 1. A new call pushes "Incoming voice call" to the person being called
--    (kind 'voice_call', reference_id = the support request). send-push sends
--    it on the 'maak_calls' channel, which plays the phone's ringtone, tagged
--    call-<request id>, valid for 45 seconds. It is not stored as a
--    notification row, so the notification list doesn't fill with calls.
-- 2. When a call that was never answered ends because the caller hung up or
--    nobody answered in time, the callee gets "Missed voice call" (kind
--    'voice_call_missed', stored, pushed with the same tag, so it replaces the
--    ringing notification on the phone). Declining is the callee's own
--    choice and sends nothing; neither does a call ended because the
--    conversation was closed or restricted.
-- Restricted members get neither push (send-push and push_maak_notification
-- already skip them).
begin;

create or replace function public.maak_voice_call_push() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_name text;
begin
  select nullif(btrim(full_name), '') into v_name from profiles where id = new.caller_id;
  v_name := coalesce(v_name, 'Someone');
  if tg_op = 'INSERT' then
    if new.status = 'calling' then
      perform send_maak_push(new.callee_id, 'Incoming voice call',
        v_name || ' is calling you. Open Ma''ak to answer.',
        'voice_call', new.request_id);
    end if;
  elsif old.status = 'calling' and old.accepted_at is null
        and new.status in ('ended', 'missed') and new.accepted_at is null
        and coalesce(new.end_reason, '') in ('hangup', 'timeout') then
    insert into notifications(user_id, title, body, kind, reference_id)
    values (new.callee_id, 'Missed voice call', v_name || ' tried to call you.',
            'voice_call_missed', new.request_id);
  end if;
  return new;
end; $$;
revoke all on function public.maak_voice_call_push() from public, anon, authenticated;

drop trigger if exists maak_voice_call_ring on public.voice_calls;
create trigger maak_voice_call_ring after insert on public.voice_calls
  for each row execute function public.maak_voice_call_push();
drop trigger if exists maak_voice_call_missed on public.voice_calls;
create trigger maak_voice_call_missed after update of status on public.voice_calls
  for each row execute function public.maak_voice_call_push();

commit;
