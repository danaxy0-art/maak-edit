BEGIN;

ALTER TABLE public.personal_reminders
ADD COLUMN IF NOT EXISTS anchor_day integer
CHECK (anchor_day BETWEEN 1 AND 31);

UPDATE public.personal_reminders
SET anchor_day = EXTRACT(DAY FROM scheduled_at AT TIME ZONE 'Asia/Riyadh')::integer
WHERE repeat_type = 'monthly' AND anchor_day IS NULL;

CREATE OR REPLACE FUNCTION public.next_monthly_reminder_date(
    p_scheduled_at timestamptz, p_anchor_day integer
)
RETURNS timestamptz LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_local timestamp;
    v_next_month date;
    v_last_day integer;
    v_target_day integer;
BEGIN
    v_local := p_scheduled_at AT TIME ZONE 'Asia/Riyadh';
    v_next_month := (date_trunc('month', v_local) + INTERVAL '1 month')::date;
    v_last_day := EXTRACT(DAY FROM (v_next_month + INTERVAL '1 month' - INTERVAL '1 day'))::integer;
    v_target_day := LEAST(p_anchor_day, v_last_day);
    RETURN ((v_next_month + (v_target_day - 1)) + v_local::time) AT TIME ZONE 'Asia/Riyadh';
END;
$$;

CREATE OR REPLACE FUNCTION public.set_personal_reminder_anchor_day()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
    IF NEW.repeat_type <> 'monthly' THEN
        NEW.anchor_day := NULL;
    ELSIF TG_OP = 'INSERT' THEN
        IF NEW.anchor_day IS NULL THEN
            NEW.anchor_day := EXTRACT(DAY FROM NEW.scheduled_at AT TIME ZONE 'Asia/Riyadh')::integer;
        END IF;
    ELSIF NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
       OR OLD.repeat_type <> 'monthly' OR NEW.anchor_day IS NULL THEN
        NEW.anchor_day := EXTRACT(DAY FROM NEW.scheduled_at AT TIME ZONE 'Asia/Riyadh')::integer;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS personal_reminders_anchor_day ON public.personal_reminders;
CREATE TRIGGER personal_reminders_anchor_day
BEFORE INSERT OR UPDATE ON public.personal_reminders
FOR EACH ROW EXECUTE FUNCTION public.set_personal_reminder_anchor_day();

CREATE OR REPLACE FUNCTION public.complete_personal_reminder(p_reminder_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                public.next_monthly_reminder_date(
                    v_reminder.scheduled_at,
                    v_reminder.anchor_day
                );

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
        anchor_day,
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
        v_reminder.anchor_day,
        v_series_id,
        v_reminder.id
    )
    RETURNING * INTO v_next;

    RETURN jsonb_build_object(
        'status', 'completed',
        'next_reminder', to_jsonb(v_next)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_personal_reminder(p_reminder_id uuid, p_scope text DEFAULT 'single'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                        public.next_monthly_reminder_date(
                    v_reminder.scheduled_at,
                    v_reminder.anchor_day
                );
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
                anchor_day,
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
                v_reminder.anchor_day,
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
$function$;

COMMIT;
