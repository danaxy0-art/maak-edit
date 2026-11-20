
-- ============================================================
-- Ma'ak | SWE 444 | Sprint 3
-- End Chat + Emoji Reactions
--
-- IMPORTANT:
-- Test on a separate Supabase database first.
-- Review before applying to shared production.
-- Do NOT re-run older production migrations.
-- ============================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

-- ------------------------------------------------------------
-- 1. Preserve chat history when a conversation ends
-- ------------------------------------------------------------

ALTER TABLE public.support_requests
ADD COLUMN IF NOT EXISTS ended_at timestamptz;

-- Keep status = 'accepted' for compatibility with
-- existing support-request and matching functionality.


-- ------------------------------------------------------------
-- 2. Preserve existing message authorization rules
--    and add the End Chat condition
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION
public.can_send_maak_message(p_request_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.is_maak_active()
  AND EXISTS (
    SELECT 1
    FROM public.support_requests r
    JOIN public.volunteer_profiles v
      ON v.user_id = r.volunteer_id
    WHERE r.id = p_request_id
      AND r.status = 'accepted'
      AND v.status = 'approved'
      AND r.restricted_at IS NULL
      AND r.ended_at IS NULL
      AND (
        r.seeker_id = auth.uid()
        OR r.volunteer_id = auth.uid()
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.account_blocks b
        WHERE b.user_id IN (
          r.seeker_id,
          r.volunteer_id
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION
public.can_send_maak_message(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
public.can_send_maak_message(uuid)
TO authenticated;


-- ------------------------------------------------------------
-- 3. Prevent concurrent messages from passing End Chat
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION
public.maak_reject_ended_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN

  -- FOR SHARE coordinates with the End Chat UPDATE.
  -- A message insertion and chat ending cannot pass
  -- this check simultaneously without synchronization.

  PERFORM 1
  FROM public.support_requests r
  WHERE r.id = NEW.request_id
    AND r.status = 'accepted'
    AND r.ended_at IS NULL
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'chat_closed';
  END IF;

  RETURN NEW;

END;
$$;

DROP TRIGGER IF EXISTS
maak_reject_ended_chat_message
ON public.messages;

CREATE TRIGGER maak_reject_ended_chat_message
BEFORE INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION
public.maak_reject_ended_chat_message();

REVOKE ALL ON FUNCTION
public.maak_reject_ended_chat_message()
FROM PUBLIC, anon, authenticated;


-- ------------------------------------------------------------
-- 4. End Chat RPC
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION
public.end_maak_chat(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN

  IF NOT public.is_maak_active() THEN
    RAISE EXCEPTION 'not_allowed';
  END IF;

  UPDATE public.support_requests
  SET ended_at = now()
  WHERE id = p_request_id
    AND status = 'accepted'
    AND ended_at IS NULL
    AND (
      seeker_id = auth.uid()
      OR volunteer_id = auth.uid()
    );

  IF NOT FOUND THEN

    -- Repeating End Chat is harmless for a participant
    -- whose conversation has already ended.

    IF NOT EXISTS (
      SELECT 1
      FROM public.support_requests
      WHERE id = p_request_id
        AND ended_at IS NOT NULL
        AND (
          seeker_id = auth.uid()
          OR volunteer_id = auth.uid()
        )
    ) THEN
      RAISE EXCEPTION 'chat_unavailable';
    END IF;

  END IF;

END;
$$;


-- ------------------------------------------------------------
-- 5. Emoji Reactions table
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS
public.message_reactions (

  request_id uuid NOT NULL
    REFERENCES public.support_requests(id)
    ON DELETE CASCADE,

  message_id uuid NOT NULL
    REFERENCES public.messages(id)
    ON DELETE CASCADE,

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  emoji text NOT NULL
    CHECK (
      emoji IN ('❤️', '👍', '😊', '🙏', '💗')
    ),

  created_at timestamptz NOT NULL
    DEFAULT now(),

  PRIMARY KEY (message_id, user_id)

);

CREATE INDEX IF NOT EXISTS
message_reactions_request
ON public.message_reactions(request_id);

ALTER TABLE public.message_reactions
ENABLE ROW LEVEL SECURITY;


-- ------------------------------------------------------------
-- 6. Reactions RLS
-- ------------------------------------------------------------

DROP POLICY IF EXISTS
maak_reactions_read
ON public.message_reactions;

CREATE POLICY maak_reactions_read
ON public.message_reactions
FOR SELECT
TO authenticated
USING (

  public.is_maak_active()

  AND EXISTS (
    SELECT 1
    FROM public.support_requests r
    WHERE r.id = request_id
      AND (
        r.seeker_id = auth.uid()
        OR r.volunteer_id = auth.uid()
      )
  )

);

-- Clients may read permitted reactions.
-- All reaction writes go through the secured RPC.

REVOKE ALL ON public.message_reactions
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.message_reactions
TO authenticated;


-- ------------------------------------------------------------
-- 7. Emoji Reactions RPC
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION
public.toggle_maak_reaction(
  p_request_id uuid,
  p_message_id uuid,
  p_emoji text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN

  IF p_emoji IS NULL
    OR p_emoji NOT IN (
      '❤️', '👍', '😊', '🙏', '💗'
    )
  THEN
    RAISE EXCEPTION 'invalid_emoji';
  END IF;

  -- Lock the request row so reactions cannot be added
  -- concurrently with a completed End Chat.

  PERFORM 1
  FROM public.support_requests r
  WHERE r.id = p_request_id
    AND r.status = 'accepted'
    AND r.ended_at IS NULL
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'chat_unavailable';
  END IF;

  -- Reuse existing authorization checks,
  -- including account blocking and restrictions.

  IF NOT public.can_send_maak_message(p_request_id)
  THEN
    RAISE EXCEPTION 'chat_unavailable';
  END IF;

  -- Lock the message row to serialize concurrent
  -- reaction changes for the same message.

  PERFORM 1
  FROM public.messages m
  WHERE m.id = p_message_id
    AND m.request_id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'message_unavailable';
  END IF;

  -- Selecting the same emoji again removes the reaction.
  -- Selecting a different emoji replaces the previous one.

  IF EXISTS (
    SELECT 1
    FROM public.message_reactions
    WHERE message_id = p_message_id
      AND user_id = auth.uid()
      AND emoji = p_emoji
  ) THEN

    DELETE FROM public.message_reactions
    WHERE message_id = p_message_id
      AND user_id = auth.uid()
      AND emoji = p_emoji;

  ELSE

    INSERT INTO public.message_reactions (
      request_id,
      message_id,
      user_id,
      emoji
    )
    VALUES (
      p_request_id,
      p_message_id,
      auth.uid(),
      p_emoji
    )

    ON CONFLICT (message_id, user_id)
    DO UPDATE
    SET
      emoji = EXCLUDED.emoji,
      created_at = now();

  END IF;

END;
$$;


-- ------------------------------------------------------------
-- 8. RPC permissions
-- ------------------------------------------------------------

REVOKE ALL ON FUNCTION
public.end_maak_chat(uuid)
FROM PUBLIC, anon;

REVOKE ALL ON FUNCTION
public.toggle_maak_reaction(uuid, uuid, text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
public.end_maak_chat(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION
public.toggle_maak_reaction(uuid, uuid, text)
TO authenticated;


-- ------------------------------------------------------------
-- 9. Enable Realtime for emoji reactions
-- ------------------------------------------------------------

DO $$
BEGIN

  IF EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'supabase_realtime'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'message_reactions'
  ) THEN

    ALTER PUBLICATION supabase_realtime
    ADD TABLE public.message_reactions;

  END IF;

END;
$$;


-- ------------------------------------------------------------
-- 10. Refresh PostgREST schema cache
-- ------------------------------------------------------------

NOTIFY pgrst, 'reload schema';

COMMIT;
