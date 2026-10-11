import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import '../patient/patient_shell.dart';
import '../volunteer/volunteer_shell.dart';
import '../volunteer/volunteer_pending_screen.dart';
import '../volunteer/volunteer_rejected_screen.dart';
import '../admin/admin_dashboard.dart';
import '../redesign/registration.dart';
import '../redesign/ui.dart';
import '../redesign/feedback.dart';
import 'login_screen.dart';

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
    if (SupabaseService.currentUser == null) return const LoginScreen();
    final role = await SupabaseService.getMyRole();
    if (role == 'admin') return const AdminDashboardScreen();
    if (role != 'volunteer' && role != 'help_seeker') {
      return const LoginScreen();
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
