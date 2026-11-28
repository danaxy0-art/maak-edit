ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "presence_read_admin_or_owner"
ON realtime.messages;

CREATE POLICY "presence_read_admin_or_owner"
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  extension IN ('presence', 'broadcast')
  AND public.is_maak_active()
  AND (
    (
      public.is_maak_admin()
      AND realtime.topic() LIKE 'presence:%'
    )
    OR realtime.topic() = 'presence:' || auth.uid()::text
  )
);

DROP POLICY IF EXISTS "presence_write_owner"
ON realtime.messages;

CREATE POLICY "presence_write_owner"
ON realtime.messages
FOR INSERT
TO authenticated
WITH CHECK (
  extension = 'presence'
  AND public.is_maak_active()
  AND realtime.topic() = 'presence:' || auth.uid()::text
);