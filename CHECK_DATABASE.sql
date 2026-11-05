-- Run in Supabase SQL Editor after supabase_schema.sql. No data changes.
select name,is_active from public.chronic_conditions order by sort_order,name;
select p.id,u.email,p.full_name,p.role,v.status,v.created_at
from public.profiles p join auth.users u on u.id=p.id
left join public.volunteer_profiles v on v.user_id=p.id
where p.role in ('volunteer','admin') order by v.created_at desc nulls last;
select u.email,'Registration incomplete: no submitted application' as issue
from auth.users u join public.profiles p on p.id=u.id
where p.role='volunteer' and not exists(select 1 from public.volunteer_profiles v where v.user_id=u.id);
