
CREATE OR REPLACE FUNCTION public.admin_get_analytics_dashboard(
    p_days integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_since timestamptz;
BEGIN

    -- Admin authorization
    IF NOT COALESCE(public.is_maak_admin(), false) THEN
        RAISE EXCEPTION 'Access denied'
            USING ERRCODE = '42501';
    END IF;

    -- Validate time filter
    IF p_days IS NOT NULL AND p_days NOT IN (7, 30) THEN
        RAISE EXCEPTION 'Invalid time filter'
            USING ERRCODE = '22023';
    END IF;

    v_since := CASE
        WHEN p_days IS NULL THEN '-infinity'::timestamptz
        ELSE now() - make_interval(days => p_days)
    END;

    RETURN jsonb_build_object(

        -- USERS
        'users', (
            SELECT jsonb_build_object(
                'registered', COUNT(*),
                'volunteers', COUNT(*) FILTER (
                    WHERE p.role = 'volunteer'
                ),
                'help_seekers', COUNT(*) FILTER (
                    WHERE p.role = 'help_seeker'
                ),
                'active', COUNT(*) FILTER (
                    WHERE b.user_id IS NULL
                ),
                'deactivated', COUNT(*) FILTER (
                    WHERE b.user_id IS NOT NULL
                ),
                'active_volunteers', COUNT(*) FILTER (
                    WHERE p.role = 'volunteer'
                    AND b.user_id IS NULL
                ),
                'active_help_seekers', COUNT(*) FILTER (
                    WHERE p.role = 'help_seeker'
                    AND b.user_id IS NULL
                ),
                'new_registrations', COUNT(*) FILTER (
                    WHERE p.created_at >= v_since
                )
            )
            FROM public.profiles p
            LEFT JOIN (
                SELECT DISTINCT user_id
                FROM public.account_blocks
            ) b ON b.user_id = p.id
            WHERE p.role IN ('volunteer', 'help_seeker')
        ),

        -- VOLUNTEER APPLICATIONS
        'applications', (
            SELECT jsonb_build_object(
                'total', COUNT(*),
                'pending', COUNT(*) FILTER (
                    WHERE status = 'pending_review'
                ),
                'approved', COUNT(*) FILTER (
                    WHERE status = 'approved'
                ),
                'rejected', COUNT(*) FILTER (
                    WHERE status = 'rejected'
                )
            )
            FROM public.volunteer_profiles
        ),

        -- SUPPORT CONNECTIONS
        'connections', (
            SELECT jsonb_build_object(
                'total', COUNT(*),
                'pending', COUNT(*) FILTER (
                    WHERE status = 'pending'
                ),
                'active', COUNT(*) FILTER (
                    WHERE status = 'accepted'
                    AND ended_at IS NULL
                    AND restricted_at IS NULL
                ),
                'ended', COUNT(*) FILTER (
                    WHERE status = 'accepted'
                    AND ended_at IS NOT NULL
                ),
                'restricted', COUNT(*) FILTER (
                    WHERE status = 'accepted'
                    AND ended_at IS NULL
                    AND restricted_at IS NOT NULL
                ),
                'declined', COUNT(*) FILTER (
                    WHERE status = 'declined'
                ),
                'canceled', COUNT(*) FILTER (
                    WHERE status = 'canceled'
                )
            )
            FROM public.support_requests
        ),

        -- SESSION BOOKINGS
        'sessions', (
            SELECT jsonb_build_object(
                'total', COUNT(*),
                'pending', COUNT(*) FILTER (
                    WHERE status = 'pending'
                ),
                'confirmed', COUNT(*) FILTER (
                    WHERE status = 'accepted'
                ),
                'rejected', COUNT(*) FILTER (
                    WHERE status = 'rejected'
                ),
                'canceled', COUNT(*) FILTER (
                    WHERE status = 'canceled'
                )
            )
            FROM public.session_bookings
            WHERE created_at >= v_since
        ),

        -- VOICE CALLS
        'calls', (
            SELECT jsonb_build_object(
                'total', COUNT(*),
                'connected', COUNT(*) FILTER (
                    WHERE connected_at IS NOT NULL
                ),
                'missed', COUNT(*) FILTER (
                    WHERE status = 'missed'
                ),
                'total_duration_seconds', COALESCE(
                    ROUND(SUM(
                        EXTRACT(EPOCH FROM (
                            ended_at - connected_at
                        ))
                    ) FILTER (
                        WHERE connected_at IS NOT NULL
                        AND ended_at >= connected_at
                    )), 0
                ),
                'average_duration_seconds', COALESCE(
                    ROUND(AVG(
                        EXTRACT(EPOCH FROM (
                            ended_at - connected_at
                        ))
                    ) FILTER (
                        WHERE connected_at IS NOT NULL
                        AND ended_at >= connected_at
                    )), 0
                )
            )
            FROM public.voice_calls
            WHERE created_at >= v_since
        ),

        -- SAFETY AND MODERATION
        'safety', jsonb_build_object(
            'total_reports', (
                SELECT COUNT(*)
                FROM public.reports
                WHERE created_at >= v_since
            ),
            'open_reports', (
                SELECT COUNT(*)
                FROM public.reports
                WHERE status = 'open'
            ),
            'reviewed_reports', (
                SELECT COUNT(*)
                FROM public.reports
                WHERE status = 'reviewed'
                AND created_at >= v_since
            ),
            'dismissed_reports', (
                SELECT COUNT(*)
                FROM public.reports
                WHERE status = 'dismissed'
                AND created_at >= v_since
            ),
            'conversation_ended_reports', (
                SELECT COUNT(*)
                FROM public.reports
                WHERE status = 'conversation_ended'
                AND created_at >= v_since
            ),
            'blocked_accounts', (
                SELECT COUNT(DISTINCT user_id)
                FROM public.account_blocks
            ),
            'total_appeals', (
                SELECT COUNT(*)
                FROM public.account_block_appeals
                WHERE submitted_at >= v_since
            ),
            'pending_appeals', (
                SELECT COUNT(*)
                FROM public.account_block_appeals
                WHERE status = 'pending'
            )
        ),

        -- VOLUNTEER RATINGS
        'ratings', (
            SELECT jsonb_build_object(
                'total', COUNT(*),
                'average', ROUND(AVG(stars), 1)
            )
            FROM public.volunteer_ratings
            WHERE created_at >= v_since
        ),

        -- REGISTRATION GROWTH
        'growth', (
            SELECT COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'date', g.day,
                        'count', g.total
                    )
                    ORDER BY g.day
                ),
                '[]'::jsonb
            )
            FROM (
                SELECT
                    (created_at AT TIME ZONE
                        'Asia/Riyadh')::date AS day,
                    COUNT(*) AS total
                FROM public.profiles
                WHERE role IN ('volunteer', 'help_seeker')
                AND created_at >= v_since
                GROUP BY 1
            ) g
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION
public.admin_get_analytics_dashboard(integer)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
public.admin_get_analytics_dashboard(integer)
TO authenticated;
