import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../backend/services/supabase_service.dart';
import '../patient/patient_shell.dart';
import '../volunteer/volunteer_shell.dart';
import '../volunteer/volunteer_pending_screen.dart';
import '../volunteer/volunteer_rejected_screen.dart';
import '../admin/admin_dashboard.dart';
import '../redesign/registration.dart';
import '../redesign/ui.dart';
import '../redesign/feedback.dart';
import 'blocked_account_screen.dart';
import 'welcome_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<Widget> _future;
  @override
  void initState() {
    super.initState();
    _future = _destination();
  }

  Future<Widget> _destination() async {
    try {
      return await _route();
    } catch (e) {
      // A saved session that can no longer be used (expired refresh token,
      // deleted user, or a session restored from an Android backup of an
      // earlier install) is not an error for the user: they just need to
      // log in again. Network problems still show the retry screen.
      if (!_isDeadSession(e)) rethrow;
      try {
        await SupabaseService.client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      return const WelcomeScreen();
    }
  }

  static bool _isDeadSession(Object e) {
    if (e is AuthRetryableFetchException) return false; // offline / timeout
    if (e is AuthException) return true;
    if (e is PostgrestException) {
      // PGRST301/PGRST303: JWT expired or invalid.
      return {'PGRST301', 'PGRST302', 'PGRST303'}.contains(e.code) ||
          e.message.contains('JWT');
    }
    return false;
  }

  Future<Widget> _route() async {
    // Signed out (or the session ended): start again from the welcome screen.
    if (SupabaseService.currentUser == null) return const WelcomeScreen();
    // Checked before role and profile routing: a blocked account cannot read
    // its profile details, so it would otherwise look like an unfinished one.
    final block = await SupabaseService.getMyBlockStatus();
    if (block != null) {
      return BlockedAccountScreen(
        reason: block['reason'] as String? ?? '',
        blockedAt: block['blocked_at'] as String?,
      );
    }
    final role = await SupabaseService.getMyRole();
    if (role == 'admin') return const AdminDashboardScreen();
    if (role != 'volunteer' && role != 'help_seeker') {
      throw ArgumentError(
        'Your account has no valid profile role. Please contact the administrator.',
      );
    }
    if (!await SupabaseService.hasCompletedProfile(role!)) {
      return RegistrationScreen(role: role, completionOnly: true);
    }
    if (role == 'help_seeker') return const PatientShell();
    final application = await SupabaseService.getMyVolunteerApplication();
    if (application == null) {
      return const RegistrationScreen(role: 'volunteer', completionOnly: true);
    }
    if (application['status'] == 'approved') return const VolunteerShell();
    if (application['status'] == 'rejected') {
      return VolunteerRejectedScreen(
        rejectionReason: application['rejection_reason'] as String? ?? '',
      );
    }
    return const VolunteerPendingScreen();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: _future,
    builder: (context, s) {
      if (s.hasError) {
        return BotanicalScaffold(
          body: Center(
            child: EmptyState(
              'Could not load your account',
              friendlyError(s.error!),
              retry: () => setState(() => _future = _destination()),
            ),
          ),
        );
      }
      return s.data ??
          const BotanicalScaffold(
            body: Center(child: CircularProgressIndicator()),
          );
    },
  );
}
