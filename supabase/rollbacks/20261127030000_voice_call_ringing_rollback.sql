-- Rollback for 20261127030000_voice_call_ringing.sql: calls stop ringing on the
-- phone and no missed-call notifications are written. Stored missed-call
-- notifications are deleted.
begin;
drop trigger if exists maak_voice_call_ring on public.voice_calls;
drop trigger if exists maak_voice_call_missed on public.voice_calls;
drop function if exists public.maak_voice_call_push();
delete from public.notifications where kind = 'voice_call_missed';
commit;
