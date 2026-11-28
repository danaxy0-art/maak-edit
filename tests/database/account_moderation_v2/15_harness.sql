-- Test harness: run checks as a given API role and JWT subject, collect results.
\set ON_ERROR_STOP 1
create table test.results(n serial primary key,name text,ok boolean,detail text);
grant usage on schema test to anon,authenticated,service_role;
grant select,insert on test.results to anon,authenticated,service_role;
grant usage on sequence test.results_n_seq to anon,authenticated,service_role;

create function test.act(p_role text,p_sub uuid) returns void language plpgsql as $$
begin
 perform set_config('role','none',false);
 perform set_config('request.jwt.claims',case when p_sub is null then json_build_object('role',p_role)::text
  else json_build_object('sub',p_sub,'role',p_role)::text end,false);
 if p_role<>'postgres' then perform set_config('role',p_role,false); end if;
end $$;
create function test.as_user(p text) returns void language sql as $$ select test.act('authenticated',test.u(p)) $$;

-- expect: 'ok' | 'true' (query returns boolean) | 'error:<substring of message>'
create function test.check(p_name text,p_sql text,p_expect text) returns void language plpgsql as $$
declare v boolean; passed boolean; detail text;
begin
 begin
  if p_expect='true' then execute p_sql into v; passed:=coalesce(v,false); detail:=coalesce(v::text,'null');
  else execute p_sql; passed:=p_expect='ok'; detail:='succeeded'; end if;
 exception when others then
  passed:=p_expect like 'error:%' and position(substr(p_expect,7) in sqlerrm)>0; detail:=sqlerrm;
 end;
 insert into test.results(name,ok,detail) values(p_name,passed,detail);
end $$;

-- Simulates a SECURITY DEFINER RPC: runs as the owner (table privileges, no RLS)
-- while auth.uid() stays the calling user, so only triggers can refuse.
create function test.rpc(p_sql text) returns void language plpgsql security definer as $$
begin execute p_sql; end $$;

-- Owner-side lookups for assertions (run as the definer, bypassing RLS).
create function test.appeal(p_user text,p_attempt int) returns public.account_block_appeals
language sql security definer as $$
 select a.* from public.account_block_appeals a where a.user_id=test.u(p_user) and a.attempt=p_attempt
 order by a.submitted_at desc limit 1 $$;
create function test.appeal_id(p_user text) returns uuid language sql security definer as $$
 select id from public.account_block_appeals where user_id=test.u(p_user) order by submitted_at desc limit 1 $$;
create function test.blocked(p_user text) returns boolean language sql security definer as $$
 select exists(select 1 from public.account_blocks where user_id=test.u(p_user)) $$;
grant execute on all functions in schema test to anon,authenticated,service_role;
