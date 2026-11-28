
-- Personal health reminders: Automatic recurrence

BEGIN;

-- 1. Add recurrence and completion history columns

ALTER TABLE public.personal_reminders
ADD COLUMN IF NOT EXISTS series_id uuid,
ADD COLUMN IF NOT EXISTS previous_occurrence_id uuid
    REFERENCES public.personal_reminders(id)
    ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS completed_at timestamptz;

-- Initialize series IDs for existing recurring reminders

UPDATE public.personal_reminders
SET series_id = id
WHERE repeat_type <> 'none'
  AND series_id IS NULL;

-- 2. Create recurrence indexes

CREATE INDEX IF NOT EXISTS personal_reminders_series_idx
ON public.personal_reminders (series_id);

CREATE UNIQUE INDEX IF NOT EXISTS personal_reminders_previous_idx
ON public.personal_reminders (previous_occurrence_id)
WHERE previous_occurrence_id IS NOT NULL;

-- 3. Complete reminder and generate next occurrence

CREATE OR REPLACE FUNCTION public.complete_personal_reminder(
    p_reminder_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_reminder public.personal_reminders%ROWTYPE;
    v_next public.personal_reminders%ROWTYPE;
    v_next_date timestamptz;
    v_series_id uuid;
BEGIN
    IF NOT public.is_maak_help_seeker() THEN
        RAISE EXCEPTION 'Access denied'
            USING ERRCODE = '42501';
    END IF;

    SELECT *
    INTO v_reminder
    FROM public.personal_reminders
    WHERE id = p_reminder_id
      AND user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reminder not found';
    END IF;

    IF v_reminder.is_completed THEN
        RETURN jsonb_build_object(
            'status', 'already_completed'
        );
    END IF;

    v_series_id := COALESCE(
        v_reminder.series_id,
        v_reminder.id
    );

    UPDATE public.personal_reminders
    SET
        is_completed = true,
        completed_at = now(),
        series_id = CASE
            WHEN repeat_type <> 'none'
            THEN v_series_id
            ELSE series_id
        END
    WHERE id = p_reminder_id;

    IF v_reminder.repeat_type = 'none' THEN
        RETURN jsonb_build_object(
            'status', 'completed',
            'next_reminder', NULL
        );
    END IF;

    CASE v_reminder.repeat_type
        WHEN 'daily' THEN
            v_next_date :=
                v_reminder.scheduled_at + INTERVAL '1 day';

        WHEN 'weekly' THEN
            v_next_date :=
                v_reminder.scheduled_at + INTERVAL '1 week';

        WHEN 'monthly' THEN
            v_next_date :=
                v_reminder.scheduled_at + INTERVAL '1 month';

        ELSE
            RAISE EXCEPTION 'Invalid repeat type';
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
        series_id,
        previous_occurrence_id
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
        v_series_id,
        v_reminder.id
    )
    RETURNING * INTO v_next;

    RETURN jsonb_build_object(
        'status', 'completed',
        'next_reminder', to_jsonb(v_next)
    );
END;
$$;

-- 4. Function permissions

REVOKE ALL ON FUNCTION
public.complete_personal_reminder(uuid)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
public.complete_personal_reminder(uuid)
TO authenticated;

COMMIT;
