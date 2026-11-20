-- Minimal Supabase platform stub for an isolated test database. NOT for production.
\set ON_ERROR_STOP 1
-- Roles are cluster-wide, so they survive dropping and recreating the test database.
do $$ begin
 if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin noinherit; end if;
 if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin noinherit; end if;
 if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin noinherit bypassrls; end if;
end $$;
grant usage on schema public to anon,authenticated,service_role;
-- Supabase's default privileges: new public tables/functions/sequences are granted to all API roles.
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
alter default privileges in schema public grant all on functions to anon,authenticated,service_role;
alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;

create schema auth;
create table auth.users(id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb default '{}'::jsonb);
-- Same resolution as Supabase auth.uid(): the JWT "sub" claim, null without one.
create function auth.uid() returns uuid language sql stable as $$
 select nullif(coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),
  nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub'),'')::uuid $$;
grant usage on schema auth to anon,authenticated,service_role;
grant execute on function auth.uid() to anon,authenticated,service_role;

create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,owner uuid);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
 select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1] $$;
grant usage on schema storage to anon,authenticated,service_role;
grant select,insert on storage.objects to authenticated;
grant all on storage.objects,storage.buckets to service_role;
grant execute on function storage.foldername(text) to anon,authenticated,service_role;

create publication supabase_realtime;
