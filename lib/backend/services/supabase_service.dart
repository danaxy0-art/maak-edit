import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../validation/password_policy.dart';
import '../validation/form_policy.dart';

class SupabaseService {
  SupabaseService._();
  static final profileRevision = ValueNotifier<int>(0);
  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;
  static String get userId =>
      currentUser?.id ?? (throw StateError('Log in first'));
  static Future<void> init() => Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://sldjrjmlvboqqnzpsxsy.supabase.co',
    ),
    publishableKey: const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: 'sb_publishable_goilsZcRhU8rzLowAmIbaQ_iSFm1ZPS',
    ),
  ).then((_) {});

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => client.auth.signInWithPassword(email: email.trim(), password: password);
  static Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
    String? username,
    String role = 'help_seeker',
  }) {
    final error = validateNewPassword(password);
    if (error != null) throw ArgumentError(error);
    return client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'username': username?.trim().toLowerCase(),
        'role': role == 'volunteer' ? 'volunteer' : 'help_seeker',
      },
    );
  }

  static Future<void> verifySignup(String email, String token) async {
    final response = await client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.signup,
    );
    if (response.session == null) throw StateError('Verify your email first');
  }

  static Future<void> resendSignup(String email) => client.auth
      .resend(type: OtpType.signup, email: email.trim())
      .then((_) {});
  static String? _recoveryUserId;
  static Future<void> sendPasswordReset(String email) async {
    _recoveryUserId = null;
    await client.auth.resetPasswordForEmail(email.trim());
  }

  static Future<void> verifyPasswordResetOtp(String email, String token) async {
    final response = await client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.recovery,
    );
    if (response.session == null || response.user == null) {
      throw StateError('Verification failed');
    }
    _recoveryUserId = response.user!.id;
  }

  static Future<void> setRecoveredPassword(String password) async {
    final error = validateNewPassword(password);
    if (error != null) throw ArgumentError(error);
    if (_recoveryUserId == null || currentUser?.id != _recoveryUserId) {
      throw StateError('Verify your code first');
    }
    await client.auth.updateUser(UserAttributes(password: password));
    _recoveryUserId = null;
  }

  static Future<void> endPasswordRecovery() async {
    _recoveryUserId = null;
    await client.auth.signOut(scope: SignOutScope.local);
  }

  static Future<void> signOut() async {
    _recoveryUserId = null;
    await client.auth.signOut();
  }

  static Future<String?> getMyRole() async {
    if (currentUser == null) return null;
    final row = await client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    return row?['role'] as String?;
  }

  static Future<String> getMyFullName() async {
    if (currentUser == null) return '';
    final row = await client
        .from('profiles')
        .select('full_name')
        .eq('id', userId)
        .maybeSingle();
    return row?['full_name'] as String? ??
        currentUser?.userMetadata?['full_name'] as String? ??
        '';
  }

  static Future<void> setRole(String role, {required String fullName}) async {
    // Role promotion is blocked by a database trigger. Admins are assigned in SQL.
    await client.from('profiles').upsert({
      'id': userId,
      'role': role,
      'full_name': fullName.trim(),
    });
  }

  static Future<Map<String, dynamic>> loadProfileForEdit({
    required String role,
  }) async {
    final profile = await client
        .from('profiles')
        .select('full_name, username')
        .eq('id', userId)
        .maybeSingle();
    final volunteer = role == 'volunteer';
    final row = await client
        .from(volunteer ? 'volunteer_profiles' : 'help_seeker_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return {
      'full_name': profile?['full_name'] ?? '',
      'username': profile?['username'] ?? '',
      'email': currentUser?.email ?? '',
      'condition':
          row?[volunteer ? 'condition_experience' : 'chronic_condition'],
      'preferred_language': row?['preferred_language'],
      'description': row?['description'],
      'experience': row?['experience_description'],
      'verification_document_url': row?['verification_document_url'],
      'status': row?['status'],
    };
  }

  static Future<void> updateFullName(String fullName) async {
    await client
        .from('profiles')
        .update({'full_name': fullName.trim()})
        .eq('id', userId);
    profileRevision.value++;
  }

  static Future<void> saveProfile({
    required String fullName,
    String? username,
    required String role,
    required String condition,
    required String language,
    String? description,
    String? document,
    bool reapply = false,
  }) async {
    // Keep legacy database compatibility without requesting a username.
    final profile = await client
        .from('profiles')
        .select('username')
        .eq('id', userId)
        .maybeSingle();
    final savedUsername =
        username ??
        profile?['username'] as String? ??
        'user_${userId.replaceAll('-', '').substring(0, 20)}';
    final error = validateUsername(savedUsername);
    if (error != null) throw ArgumentError(error);
    await client.rpc(
      'save_maak_profile',
      params: {
        'p_full_name': fullName.trim(),
        'p_username': savedUsername.trim().toLowerCase(),
        'p_role': role,
        'p_condition': condition,
        'p_language': language,
        'p_description': description?.trim() ?? '',
        'p_document': document,
        'p_reapply': reapply,
      },
    );
    profileRevision.value++;
  }

  static Future<bool> hasCompletedProfile(String role) async {
    if (role == 'admin') return true;
    final row = await client
        .from(
          role == 'volunteer' ? 'volunteer_profiles' : 'help_seeker_profiles',
        )
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  static Future<List<Map<String, dynamic>>> getConditions({
    bool activeOnly = true,
  }) async {
    var query = client.from('chronic_conditions').select();
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> saveCondition({
    String? id,
    required String name,
    bool active = true,
  }) async {
    final values = {'name': name.trim(), 'is_active': active};
    if (id == null) {
      await client.from('chronic_conditions').insert(values);
    } else {
      await client.from('chronic_conditions').update(values).eq('id', id);
    }
  }

  static Future<Map<String, dynamic>?> getMyVolunteerApplication() async =>
      await client
          .from('volunteer_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
  static Future<String?> getMyVolunteerApplicationStatus() async =>
      (await getMyVolunteerApplication())?['status'] as String?;
  static Future<List<Map<String, dynamic>>> getVolunteerApplications() async {
    final rows = await client.rpc('admin_volunteer_applications');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> sendVolunteerEmail({
  required String email,
  required String name,
  required String status,
  String? rejectionReason,
}) async {
  final response = await client.functions.invoke(
    'send-volunteer-email',
    body: {
      'email': email.trim(),
      'name': name.trim(),
      'status': status,
      if (rejectionReason != null)
        'rejectionReason': rejectionReason.trim(),
    },
  );

  if (response.status < 200 || response.status >= 300) {
    throw StateError('Unable to send volunteer email.');
  }
}

  static Future<void> approveVolunteerApplication(String id) async =>
      await client.rpc(
        'review_volunteer_application',
        params: {'p_user_id': id, 'p_approved': true, 'p_reason': null},
      );
  static Future<void> rejectVolunteerApplication({
    required String userId,
    required String reason,
  }) async {
    final error = validateReason(reason);
    if (error != null) throw ArgumentError(error);
    await client.rpc(
      'review_volunteer_application',
      params: {
        'p_user_id': userId,
        'p_approved': false,
        'p_reason': reason.trim(),
      },
    );
  }

  static Future<String> uploadVerificationDocument({
    required List<int> fileBytes,
    required String fileName,
  }) async {
    if (fileBytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Choose a document smaller than 5 MB.');
    }
    final ext = fileName.split('.').last.toLowerCase();
    if (!['pdf', 'png', 'jpg', 'jpeg'].contains(ext)) {
      throw ArgumentError('Choose a PDF, PNG or JPG file.');
    }
    final path = '$userId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await client.storage
        .from('verification-documents')
        .uploadBinary(
          path,
          Uint8List.fromList(fileBytes),
          fileOptions: FileOptions(
            contentType: ext == 'pdf'
                ? 'application/pdf'
                : ext == 'png'
                ? 'image/png'
                : 'image/jpeg',
          ),
        );
    return path;
  }

  static Future<String> verificationLink(String path) async {
    // Existing public URLs are converted to paths in the now-private bucket.
    if (path.startsWith('http')) {
      const marker = '/verification-documents/';
      if (!path.contains(marker)) {
        throw ArgumentError('Invalid document location.');
      }
      path = Uri.decodeComponent(path.split(marker).last.split('?').first);
    }
    return client.storage
        .from('verification-documents')
        .createSignedUrl(path, 120);
  }

  static Stream<List<Map<String, dynamic>>> notificationStream() {
    final id = currentUser?.id;
    if (id == null) return Stream.value(<Map<String, dynamic>>[]);
    return client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', id)
        .order('created_at', ascending: false);
  }

  static Future<void> markNotificationRead(String id) async => await client
      .from('notifications')
      .update({'is_read': true})
      .eq('user_id', userId)
      .eq('id', id);
  static Future<void> markAllNotificationsRead() async => await client
      .from('notifications')
      .update({'is_read': true})
      .eq('user_id', userId)
      .eq('is_read', false);
  static Future<List<Map<String, dynamic>>> getVolunteers() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('browse_volunteers') as List,
      );
  static Future<void> requestSupport(String volunteerId) async => await client
      .rpc('request_peer_support', params: {'p_volunteer_id': volunteerId});
  static Future<List<Map<String, dynamic>>> getRequests() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('my_support_requests') as List,
      );
  static Future<void> decideRequest(String id, bool accepted) async =>
      await client.rpc(
        'decide_support_request',
        params: {'p_request_id': id, 'p_accept': accepted},
      );
  static Stream<List<Map<String, dynamic>>> messageStream(String requestId) =>
      client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('request_id', requestId)
          .order('created_at');
  static Future<void> sendMessage(String requestId, String body) async {
    if (body.trim().isEmpty || body.trim().length > 2000) {
      throw ArgumentError('Use 1–2000 characters.');
    }
    await client.from('messages').insert({
      'request_id': requestId,
      'sender_id': userId,
      'body': body.trim(),
    });
  }

  static Future<List<Map<String, dynamic>>> getSessions() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('my_support_sessions') as List,
      );
  static Future<void> bookSession(String requestId, DateTime start) async =>
      await client.rpc(
        'book_support_session',
        params: {
          'p_request_id': requestId,
          'p_starts_at': start.toUtc().toIso8601String(),
        },
      );
  static Future<List<Map<String, dynamic>>> getResources() async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('resources')
            .select()
            .order('created_at', ascending: false),
      );

  // Compatibility for screens from the original project.
  static Future<void> submitHelpSeekerRegistration({
    required String chronicCondition,
    required String preferredLanguage,
    String? description,
  }) async {
    await client.from('help_seeker_profiles').upsert({
      'user_id': userId,
      'chronic_condition': chronicCondition,
      'preferred_language': preferredLanguage,
      'description': description,
    });
  }

  static Future<void> updateHelpSeekerProfile({
    required String chronicCondition,
    required String preferredLanguage,
    String? description,
  }) => submitHelpSeekerRegistration(
    chronicCondition: chronicCondition,
    preferredLanguage: preferredLanguage,
    description: description,
  );
  static Future<void> updateVolunteerProfile({
    required String conditionExperience,
    required String preferredLanguage,
    required String experienceDescription,
  }) async {
    await client
        .from('volunteer_profiles')
        .update({
          'condition_experience': conditionExperience,
          'preferred_language': preferredLanguage,
          'experience_description': experienceDescription,
        })
        .eq('user_id', userId);
  }

  static Future<void> submitVolunteerRegistration({
    required String conditionExperience,
    required String preferredLanguage,
    required String experienceDescription,
    String? verificationDocumentUrl,
  }) async {
    await client.from('volunteer_profiles').insert({
      'user_id': userId,
      'condition_experience': conditionExperience,
      'preferred_language': preferredLanguage,
      'experience_description': experienceDescription,
      'verification_document_url': verificationDocumentUrl,
      'status': 'pending_review',
    });
  }

  static Future<void> resubmitVolunteerApplication({
    required String conditionExperience,
    required String preferredLanguage,
    required String experienceDescription,
    String? verificationDocumentUrl,
  }) async {
    final data = await loadProfileForEdit(role: 'volunteer');
    await saveProfile(
      fullName: data['full_name'] as String,
      username: data['username'] as String,
      role: 'volunteer',
      condition: conditionExperience,
      language: preferredLanguage,
      description: experienceDescription,
      document: verificationDocumentUrl,
      reapply: true,
    );
  }
}
