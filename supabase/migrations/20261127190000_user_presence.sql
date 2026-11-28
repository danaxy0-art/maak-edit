ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.admin_list_accounts()
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
 if not is_maak_admin() then
   raise exception 'not_allowed';
 end if;

 return query select jsonb_build_object(
  'user_id',p.id,
  'full_name',p.full_name,
  'username',p.username,
  'email',u.email,
  'role',p.role,
  'created_at',p.created_at,
  'volunteer_status',v.status,
  'is_blocked',b.user_id is not null,
  'blocked_at',b.blocked_at,
  'can_block',b.user_id is null,
  'last_seen_at',p.last_seen_at,
  'is_online',(
    p.last_seen_at is not null
    and p.last_seen_at >= now() - interval '60 seconds'
    and b.user_id is null
  )
 )
 from profiles p
 left join auth.users u on u.id=p.id
 left join volunteer_profiles v on v.user_id=p.id
 left join account_blocks b on b.user_id=p.id
 where p.role in ('help_seeker','volunteer')
 order by p.created_at desc nulls last;
end;
$function$;