-- Apply after the matching and condition-review migrations. Preserves decisions.
begin;
create or replace function public.ensure_maak_profile() returns text
language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); saved_role text; metadata jsonb;
begin
 if me is null then raise exception 'not_allowed'; end if;
 select role into saved_role from profiles where id=me;
 if found then return saved_role; end if;
 select raw_user_meta_data into metadata from auth.users where id=me;
 if not found then raise exception 'not_allowed'; end if;
 -- Never infer or grant admin privileges from user-editable auth metadata.
 saved_role:=case when exists(select 1 from volunteer_profiles where user_id=me)
   or metadata->>'role'='volunteer' then 'volunteer' else 'help_seeker' end;
 insert into profiles(id,role,full_name,username) values(me,saved_role,
   left(coalesce(metadata->>'full_name',''),80),
   'user_'||right(replace(me::text,'-',''),25)) on conflict(id) do nothing;
 select role into saved_role from profiles where id=me;
 return saved_role;
end; $$;
revoke all on function public.ensure_maak_profile() from public,anon;
grant execute on function public.ensure_maak_profile() to authenticated;
notify pgrst,'reload schema';
commit;
