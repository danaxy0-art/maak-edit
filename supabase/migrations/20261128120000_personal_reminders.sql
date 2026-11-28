-- Personal Health Reminders & Appointments

CREATE TABLE public.personal_reminders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id uuid NOT NULL
        REFERENCES public.profiles(id) ON DELETE CASCADE,

    title text NOT NULL
        CHECK (char_length(trim(title)) BETWEEN 1 AND 150),

    type text NOT NULL
        CHECK (type IN (
            'medication',
            'doctor_appointment',
            'medical_test',
            'other'
        )),

    notes text NOT NULL DEFAULT '',

    scheduled_at timestamptz NOT NULL,

    repeat_type text NOT NULL DEFAULT 'none'
        CHECK (repeat_type IN (
            'none',
            'daily',
            'weekly',
            'monthly'
        )),

    remind_before_minutes integer NOT NULL DEFAULT 0
        CHECK (remind_before_minutes >= 0),

    is_completed boolean NOT NULL DEFAULT false,

    created_at timestamptz NOT NULL DEFAULT now(),

    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS

ALTER TABLE public.personal_reminders
ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.personal_reminders
FROM PUBLIC, anon, authenticated;

-- Index

CREATE INDEX personal_reminders_user_schedule_idx
ON public.personal_reminders (user_id, scheduled_at);

-- Help Seeker authorization

CREATE OR REPLACE FUNCTION public.is_maak_help_seeker()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT public.is_maak_active()
    AND EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
        AND p.role = 'help_seeker'
    );
$$;

REVOKE ALL ON FUNCTION public.is_maak_help_seeker()
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_maak_help_seeker()
TO authenticated;

-- SELECT policy

CREATE POLICY "personal_reminders_select_own"
ON public.personal_reminders
FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()
    AND public.is_maak_help_seeker()
);

-- INSERT policy

CREATE POLICY "personal_reminders_insert_own"
ON public.personal_reminders
FOR INSERT
TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND public.is_maak_help_seeker()
);

-- UPDATE policy

CREATE POLICY "personal_reminders_update_own"
ON public.personal_reminders
FOR UPDATE
TO authenticated
USING (
    user_id = auth.uid()
    AND public.is_maak_help_seeker()
)
WITH CHECK (
    user_id = auth.uid()
    AND public.is_maak_help_seeker()
);

-- DELETE policy

CREATE POLICY "personal_reminders_delete_own"
ON public.personal_reminders
FOR DELETE
TO authenticated
USING (
    user_id = auth.uid()
    AND public.is_maak_help_seeker()
);

-- Table permissions

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.personal_reminders
TO authenticated;

-- Automatic timestamp update

CREATE OR REPLACE FUNCTION public.update_personal_reminder_timestamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER personal_reminders_updated_at
BEFORE UPDATE ON public.personal_reminders
FOR EACH ROW
EXECUTE FUNCTION public.update_personal_reminder_timestamp();
