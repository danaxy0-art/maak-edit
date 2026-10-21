begin;
create table if not exists public.maak_registration_check_limits (
 client_hash text primary key,
 window_start timestamptz not null,
 attempts integer not null
);
alter table public.maak_registration_check_limits enable row level security;
revoke all on public.maak_registration_check_limits from public,anon,authenticated;
create or replace function public.check_maak_registration_email(p_email text,p_client_hash text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare n integer; normalized text:=lower(trim(p_email));
begin
 if normalized is null or length(normalized)>254 or normalized !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 or p_client_hash is null or p_client_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_email'; end if;
 insert into maak_registration_check_limits as rate(client_hash,window_start,attempts)
 values(p_client_hash,now(),1)
 on conflict(client_hash) do update set
 attempts=case when rate.window_start<now()-interval '10 minutes' then 1 else rate.attempts+1 end,
 window_start=case when rate.window_start<now()-interval '10 minutes' then now() else rate.window_start end
 returning attempts into n;
 delete from maak_registration_check_limits where window_start<now()-interval '1 day';
 if n>30 then return jsonb_build_object('limited',true); end if;
 return jsonb_build_object('exists',exists(select 1 from auth.users where lower(email)=normalized));
end; $$;
revoke all on function public.check_maak_registration_email(text,text) from public,anon,authenticated;
grant execute on function public.check_maak_registration_email(text,text) to service_role;
notify pgrst,'reload schema';
commit;
