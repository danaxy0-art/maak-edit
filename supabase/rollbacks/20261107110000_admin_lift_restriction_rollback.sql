-- Rollback for 20261107110000_admin_lift_restriction.sql.
-- Removes the lift and history RPCs and the recording trigger. The history table
-- conversation_restriction_events is KEPT (it is an audit record); drop it
-- separately only after exporting it and with a team decision.
-- Restrictions already lifted stay lifted; current restrictions are unchanged.
begin;
set local lock_timeout = '10s';
drop function if exists public.admin_lift_conversation_restriction(uuid, text);
drop function if exists public.admin_conversation_restriction_history(uuid);
drop trigger if exists maak_record_restriction_event on public.support_requests;
drop function if exists public.record_maak_restriction_event();
notify pgrst, 'reload schema';
commit;
