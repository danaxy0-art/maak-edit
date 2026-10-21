-- OPTIONAL, NOT PART OF THE DEPLOYMENT. A deliberate team decision only.
--
-- In production, my_support_sessions() has no EXECUTE for authenticated users.
-- The Flutter app calls it (SupabaseService.getSessions) on the Home page,
-- together with the support requests, and on the Schedule page. Without the grant
-- those calls fail with "permission denied". The repository schema grants it to
-- authenticated. The function is SECURITY DEFINER and only returns sessions of
-- conversations the caller takes part in (and nothing for blocked accounts).
--
-- Run this only after the team confirms the missing grant is a mistake.
grant execute on function public.my_support_sessions() to authenticated;
notify pgrst,'reload schema';
