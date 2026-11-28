-- Rollback for 20261121100000_session_scheduling.sql (Razan). Removes only the
-- objects that file created. Existing chat/request data is not touched.
begin;
drop function if exists public.my_maak_sessions();
drop function if exists public.reschedule_maak_session(uuid,uuid);
drop function if exists public.cancel_maak_session(uuid);
drop function if exists public.decide_maak_session(uuid,boolean);
drop function if exists public.request_maak_session(uuid);
drop function if exists public.volunteer_available_slots(uuid);
drop function if exists public.my_maak_time_slots();
drop function if exists public.remove_maak_time_slot(uuid);
drop function if exists public.add_maak_time_slot(timestamptz,timestamptz);
drop function if exists public.maak_session_label(timestamptz);
drop function if exists public.maak_session_notify(uuid,text,text,uuid);
drop table if exists public.session_bookings;
drop table if exists public.volunteer_time_slots;
notify pgrst, 'reload schema';
commit;
