
CREATE OR REPLACE FUNCTION public.delete_personal_reminder(
    p_reminder_id uuid,
    p_scope text DEFAULT 'single'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_reminder public.personal_reminders%ROWTYPE;
    v_next public.personal_reminders%ROWTYPE;
    v_series_id uuid;
    v_next_date timestamptz;
    v_deleted_ids uuid[];
BEGIN
    -- Verify user permissions
    IF NOT public.is_maak_help_seeker() THEN
        RAISE EXCEPTION 'Access denied'
            USING ERRCODE = '42501';
    END IF;

    -- Validate deletion scope
    IF p_scope IS NULL OR
       p_scope NOT IN ('single', 'future', 'all') THEN
        RAISE EXCEPTION 'Invalid deletion scope'
            USING ERRCODE = '22023';
    END IF;

    -- Find the selected reminder
    SELECT *
    INTO v_reminder
    FROM public.personal_reminders
    WHERE id = p_reminder_id
      AND user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reminder not found';
    END IF;

    v_series_id := COALESCE(
        v_reminder.series_id,
        v_reminder.id
    );

    -- Option 1: Delete this occurrence only
    IF p_scope = 'single' THEN

        -- Preserve recurrence when deleting the
        -- last upcoming recurring occurrence
        IF NOT v_reminder.is_completed
           AND v_reminder.repeat_type <> 'none'
           AND NOT EXISTS (
               SELECT 1
               FROM public.personal_reminders
               WHERE user_id = auth.uid()
                 AND series_id = v_series_id
                 AND scheduled_at > v_reminder.scheduled_at
                 AND is_completed = false
           )
        THEN
            CASE v_reminder.repeat_type
                WHEN 'daily' THEN
                    v_next_date :=
                        v_reminder.scheduled_at
                        + INTERVAL '1 day';

                WHEN 'weekly' THEN
                    v_next_date :=
                        v_reminder.scheduled_at
                        + INTERVAL '1 week';

                WHEN 'monthly' THEN
                    v_next_date :=
                        v_reminder.scheduled_at
                        + INTERVAL '1 month';
            END CASE;

            INSERT INTO public.personal_reminders (
                user_id,
                title,
                type,
                notes,
                scheduled_at,
                repeat_type,
                remind_before_minutes,
                is_completed,
                series_id
            )
            VALUES (
                v_reminder.user_id,
                v_reminder.title,
                v_reminder.type,
                v_reminder.notes,
                v_next_date,
                v_reminder.repeat_type,
                v_reminder.remind_before_minutes,
                false,
                v_series_id
            )
            RETURNING * INTO v_next;
        END IF;

        DELETE FROM public.personal_reminders
        WHERE id = p_reminder_id
          AND user_id = auth.uid();

        v_deleted_ids := ARRAY[p_reminder_id];

    -- Option 2: Delete this and future occurrences
    ELSIF p_scope = 'future' THEN

        WITH deleted AS (
            DELETE FROM public.personal_reminders
            WHERE user_id = auth.uid()
              AND (
                  series_id = v_series_id
                  OR id = v_series_id
              )
              AND scheduled_at >= v_reminder.scheduled_at
            RETURNING id
        )
        SELECT array_agg(id)
        INTO v_deleted_ids
        FROM deleted;

    -- Option 3: Delete all occurrences
    ELSIF p_scope = 'all' THEN

        WITH deleted AS (
            DELETE FROM public.personal_reminders
            WHERE user_id = auth.uid()
              AND (
                  series_id = v_series_id
                  OR id = v_series_id
              )
            RETURNING id
        )
        SELECT array_agg(id)
        INTO v_deleted_ids
        FROM deleted;

    END IF;

    RETURN jsonb_build_object(
        'status', 'deleted',
        'scope', p_scope,
        'deleted_ids', COALESCE(
            v_deleted_ids,
            ARRAY[]::uuid[]
        ),
        'next_reminder',
        CASE
            WHEN v_next.id IS NOT NULL
            THEN to_jsonb(v_next)
            ELSE NULL
        END
    );
END;
$$;

REVOKE ALL ON FUNCTION
public.delete_personal_reminder(uuid, text)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
public.delete_personal_reminder(uuid, text)
TO authenticated;
