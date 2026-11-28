CREATE OR REPLACE FUNCTION public.can_view_peer_presence(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT public.is_maak_active()
    AND EXISTS (
      SELECT 1
      FROM public.support_requests sr
      WHERE sr.status = 'accepted'
        AND sr.ended_at IS NULL
        AND sr.restricted_at IS NULL
        AND (
          (sr.seeker_id = auth.uid()
           AND sr.volunteer_id = p_user_id)
          OR
          (sr.volunteer_id = auth.uid()
           AND sr.seeker_id = p_user_id)
        )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.account_blocks b
      WHERE b.user_id = p_user_id
    );
$$;

REVOKE ALL ON FUNCTION public.can_view_peer_presence(uuid)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.can_view_peer_presence(uuid)
TO authenticated;

ALTER POLICY "presence_read_admin_or_owner"
ON realtime.messages
USING (
  extension IN ('presence', 'broadcast')
  AND public.is_maak_active()
  AND (
    (public.is_maak_admin()
     AND realtime.topic() LIKE 'presence:%')
    OR realtime.topic() = 'presence:' || auth.uid()::text
    OR (
      CASE
        WHEN realtime.topic() ~
          '^presence:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        THEN public.can_view_peer_presence(
          split_part(realtime.topic(), ':', 2)::uuid
        )
        ELSE false
      END
    )
  )
);