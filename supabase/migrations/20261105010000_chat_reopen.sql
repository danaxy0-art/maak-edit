
-- ============================================================
-- Ma'ak | Sprint 3
-- Request to Reopen Chat
--
-- Maximum 3 requests per chat closure.
-- Only the participant who ended the chat can request.
-- The other participant must accept before chat reopens.
--
-- Requires the earlier chat_end_reactions migration.
-- ============================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

-- ------------------------------------------------------------
-- 1. Track who ended the conversation
-- ------------------------------------------------------------

ALTER TABLE public.support_requests
ADD COLUMN IF NOT EXISTS ended_by uuid;

-- ------------------------------------------------------------
-- 2. Store chat reopen requests
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.chat_reopen_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  request_id uuid NOT NULL
    REFERENCES public.support_requests(id)
    ON DELETE CASCADE,

  requested_by uuid NOT NULL
    REFERENCES auth.users(id),

  recipient_id uuid NOT NULL
    REFERENCES auth.users(id),

  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined')),

  created_at timestamptz NOT NULL DEFAULT now(),

  decided_at timestamptz,

  CONSTRAINT chat_reopen_different_participants
    CHECK (requested_by <> recipient_id)
);

CREATE INDEX IF NOT EXISTS
chat_reopen_requests_request_created_idx
ON public.chat_reopen_requests (
  request_id,
  created_at
);

-- Only one pending request per conversation.
CREATE UNIQUE INDEX IF NOT EXISTS
chat_reopen_one_pending_per_chat_idx
ON public.chat_reopen_requests (request_id)
WHERE status = 'pending';

-- ------------------------------------------------------------
-- 3. Row Level Security
-- ------------------------------------------------------------

ALTER TABLE public.chat_reopen_requests
ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS
maak_chat_reopen_participants_read
ON public.chat_reopen_requests;

CREATE POLICY maak_chat_reopen_participants_read
ON public.chat_reopen_requests
FOR SELECT
TO authenticated
USING (
  public.is_maak_active()
  AND (
    requested_by = auth.uid()
    OR recipient_id = auth.uid()
  )
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

REVOKE ALL ON public.chat_reopen_requests
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.chat_reopen_requests
TO authenticated;

-- ------------------------------------------------------------
-- 4. Update End Chat to record who ended it
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.end_maak_chat(
  p_request_id uuid
)
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
  SET
    ended_at = now(),
    ended_by = auth.uid()
  WHERE id = p_request_id
    AND status = 'accepted'
    AND ended_at IS NULL
    AND (
      seeker_id = auth.uid()
      OR volunteer_id = auth.uid()
    );

  IF NOT FOUND AND NOT EXISTS (
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
END;
$$;

-- ------------------------------------------------------------
-- 5. Request to Reopen Chat
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.request_maak_chat_reopen(
  p_request_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r public.support_requests%ROWTYPE;
  target_user uuid;
  attempts integer;
BEGIN
  IF NOT public.is_maak_active() THEN
    RAISE EXCEPTION 'not_allowed';
  END IF;

  SELECT *
  INTO r
  FROM public.support_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND
     OR r.status <> 'accepted'
     OR r.ended_at IS NULL
     OR r.ended_by IS DISTINCT FROM auth.uid()
     OR r.restricted_at IS NOT NULL
  THEN
    RAISE EXCEPTION 'chat_unavailable';
  END IF;

  target_user := CASE
    WHEN r.seeker_id = auth.uid()
      THEN r.volunteer_id
    ELSE r.seeker_id
  END;

  IF EXISTS (
    SELECT 1
    FROM public.account_blocks b
    WHERE b.user_id IN (auth.uid(), target_user)
  )
  OR NOT EXISTS (
    SELECT 1
    FROM public.volunteer_profiles v
    WHERE v.user_id = r.volunteer_id
      AND v.status = 'approved'
  )
  THEN
    RAISE EXCEPTION 'participant_unavailable';
  END IF;

  -- Count only requests from the current closure.
  SELECT count(*)
  INTO attempts
  FROM public.chat_reopen_requests c
  WHERE c.request_id = p_request_id
    AND c.created_at >= r.ended_at;

  IF attempts >= 3 THEN
    RAISE EXCEPTION 'reopen_request_limit_reached';
  END IF;

  -- Do not allow another request while one is pending.
  IF EXISTS (
    SELECT 1
    FROM public.chat_reopen_requests c
    WHERE c.request_id = p_request_id
      AND c.status = 'pending'
  )
  THEN
    RAISE EXCEPTION 'reopen_request_pending';
  END IF;

  INSERT INTO public.chat_reopen_requests (
    request_id,
    requested_by,
    recipient_id
  )
  VALUES (
    p_request_id,
    auth.uid(),
    target_user
  );

  -- Notify the other participant.
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notifications'
      AND column_name = 'event'
  )
  THEN
    EXECUTE
      'INSERT INTO public.notifications
       (user_id, title, body, kind, event, reference_id)
       VALUES ($1, $2, $3, $4, $5, $6)'
    USING
      target_user,
      'Chat reopen request',
      'Your peer would like to reopen your conversation.',
      'chat_reopen',
      'chat_reopen_requested',
      p_request_id;
  ELSE
    INSERT INTO public.notifications (
      user_id,
      title,
      body,
      kind,
      reference_id
    )
    VALUES (
      target_user,
      'Chat reopen request',
      'Your peer would like to reopen your conversation.',
      'chat_reopen',
      p_request_id
    );
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- 6. Accept or Decline Reopen Request
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.decide_maak_chat_reopen(
  p_request_id uuid,
  p_accept boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r public.support_requests%ROWTYPE;
  c public.chat_reopen_requests%ROWTYPE;
BEGIN
  IF NOT public.is_maak_active() THEN
    RAISE EXCEPTION 'not_allowed';
  END IF;

  SELECT *
  INTO r
  FROM public.support_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND
     OR r.status <> 'accepted'
     OR r.ended_at IS NULL
     OR r.restricted_at IS NOT NULL
  THEN
    RAISE EXCEPTION 'chat_unavailable';
  END IF;

  SELECT *
  INTO c
  FROM public.chat_reopen_requests
  WHERE request_id = p_request_id
    AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND
     OR c.recipient_id IS DISTINCT FROM auth.uid()
     OR c.requested_by IS DISTINCT FROM r.ended_by
  THEN
    RAISE EXCEPTION 'reopen_request_unavailable';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.account_blocks b
    WHERE b.user_id IN (
      c.requested_by,
      c.recipient_id
    )
  )
  OR NOT EXISTS (
    SELECT 1
    FROM public.volunteer_profiles v
    WHERE v.user_id = r.volunteer_id
      AND v.status = 'approved'
  )
  THEN
    RAISE EXCEPTION 'participant_unavailable';
  END IF;

  UPDATE public.chat_reopen_requests
  SET
    status = CASE
      WHEN p_accept THEN 'accepted'
      ELSE 'declined'
    END,
    decided_at = now()
  WHERE id = c.id;

  IF p_accept THEN
    UPDATE public.support_requests
    SET
      ended_at = NULL,
      ended_by = NULL
    WHERE id = p_request_id;
  END IF;

  -- Notify the original requester of the decision.
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notifications'
      AND column_name = 'event'
  )
  THEN
    EXECUTE
      'INSERT INTO public.notifications
       (user_id, title, body, kind, event, reference_id)
       VALUES ($1, $2, $3, $4, $5, $6)'
    USING
      c.requested_by,
      CASE
        WHEN p_accept THEN 'Conversation reopened'
        ELSE 'Reopen request declined'
      END,
      CASE
        WHEN p_accept
          THEN 'Your peer accepted. You can continue chatting.'
        ELSE 'Your peer declined. The conversation remains closed.'
      END,
      'chat_reopen',
      CASE
        WHEN p_accept THEN 'chat_reopen_accepted'
        ELSE 'chat_reopen_declined'
      END,
      p_request_id;
  ELSE
    INSERT INTO public.notifications (
      user_id,
      title,
      body,
      kind,
      reference_id
    )
    VALUES (
      c.requested_by,
      CASE
        WHEN p_accept THEN 'Conversation reopened'
        ELSE 'Reopen request declined'
      END,
      CASE
        WHEN p_accept
          THEN 'Your peer accepted. You can continue chatting.'
        ELSE 'Your peer declined. The conversation remains closed.'
      END,
      'chat_reopen',
      p_request_id
    );
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- 7. Function permissions
-- ------------------------------------------------------------

REVOKE ALL ON FUNCTION
public.end_maak_chat(uuid)
FROM PUBLIC, anon;

REVOKE ALL ON FUNCTION
public.request_maak_chat_reopen(uuid)
FROM PUBLIC, anon;

REVOKE ALL ON FUNCTION
public.decide_maak_chat_reopen(uuid, boolean)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
public.end_maak_chat(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION
public.request_maak_chat_reopen(uuid)
TO authenticated;

GRANT EXECUTE ON FUNCTION
public.decide_maak_chat_reopen(uuid, boolean)
TO authenticated;

-- ------------------------------------------------------------
-- 8. Refresh API schema cache
-- ------------------------------------------------------------

NOTIFY pgrst, 'reload schema';

COMMIT;
