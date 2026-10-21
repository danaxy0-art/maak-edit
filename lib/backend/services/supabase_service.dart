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
  }) => client.auth.signInWithPassword(
    email: normalizeEmail(email),
    password: password,
  );

  static Future<bool> registrationEmailExists(String email) async {
    final response = await client.functions
        .invoke(
          'check-registration-email',
          body: {'email': normalizeEmail(email)},
        )
        .timeout(const Duration(seconds: 15));
    final data = response.data;
    if (data is! Map || data['exists'] is! bool)
      throw ArgumentError('Could not check this email. Please try again.');
    return data['exists'] as bool;
  }

  static Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
    String? username,
    String role = 'help_seeker',
  }) async {
    final nameError = validateName(fullName);
    if (nameError != null) throw ArgumentError(nameError);
    final emailError = validateEmail(email);
    if (emailError != null) throw ArgumentError(emailError);
    final error = validateNewPassword(password);
    if (error != null) throw ArgumentError(error);
    if (await registrationEmailExists(email))
      throw ArgumentError('This email is already registered. Please log in.');
    final response = await client.auth.signUp(
      email: normalizeEmail(email),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'username': username?.trim().toLowerCase(),
        'role': role == 'volunteer' ? 'volunteer' : 'help_seeker',
      },
    );
    if (response.user?.identities?.isEmpty == true)
      throw ArgumentError('This email is already registered. Please log in.');
    return response;
  }

  static Future<void> verifySignup(String email, String token) async {
    final response = await client.auth.verifyOTP(
      email: normalizeEmail(email),
      token: token.trim(),
      type: OtpType.signup,
    );
    if (response.session == null) throw StateError('Verify your email first');
  }

  static Future<void> resendSignup(String email) => client.auth
      .resend(type: OtpType.signup, email: normalizeEmail(email))
      .then((_) {});
  static String? _recoveryUserId;
  static Future<void> sendPasswordReset(String email) async {
    _recoveryUserId = null;
    await client.auth.resetPasswordForEmail(normalizeEmail(email));
  }

  static Future<void> verifyPasswordResetOtp(String email, String token) async {
    final response = await client.auth.verifyOTP(
      email: normalizeEmail(email),
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

  /// Permanently deletes the currently authenticated user's account.
  /// Supports both Help Seekers and Volunteers.
  static Future<void> deleteAccount() async {
    // Ensure the user is signed in before requesting account deletion.
    if (currentUser == null) {
      throw StateError('Please sign in to delete your account.');
    }

    // Call the secure Supabase Edge Function to delete the account.
    // The server verifies the user's identity and performs the deletion.
    final response = await client.functions.invoke(
      'delete-account',
      method: HttpMethod.post,
      body: <String, dynamic>{},
    );

    // Stop the process if the server could not complete the deletion.
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Unable to delete your account. Please try again.');
    }

    // Clear recovery state and remove the local session after success.
    _recoveryUserId = null;
    await client.auth.signOut(scope: SignOutScope.local);
  }

  static Future<String?> getMyRole() async {
    if (currentUser == null) return null;
    final row = await client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    if (row != null) return row['role'] as String?;
    // Repair only the authenticated user's missing base row on the server.
    return await client.rpc('ensure_maak_profile') as String;
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
    final actualRole = await getMyRole();
    if (actualRole != role) {
      throw ArgumentError(
        'Your account role has changed. Sign out and log in again.',
      );
    }
    final profile = await client
        .from('profiles')
        .select('full_name, username')
        .eq('id', userId)
        .single();
    final volunteer = role == 'volunteer';
    final row = await client
        .from(volunteer ? 'volunteer_profiles' : 'help_seeker_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    final legacy =
        row?[volunteer ? 'condition_experience' : 'chronic_condition']
            as String?;
    List<String> names = [];
    var setupIncomplete = false;
    try {
      final conditions = await client.rpc('my_maak_conditions') as List;
      names = conditions.map((c) => c['name'] as String).toList();
    } on PostgrestException catch (e) {
      if (!{'PGRST202', '42883', '42P01', 'PGRST205'}.contains(e.code)) rethrow;
      // A missing optional migration must not hide the existing basic profile.
      setupIncomplete = true;
    }
    if (names.isEmpty && legacy != null && legacy.trim().isNotEmpty)
      names = [legacy];
    List<Map<String, dynamic>> reviews = [];
    try {
      final data = await client
          .from('condition_review_requests')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(10);
      reviews = List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (e) {
      if (!{'42P01', 'PGRST205'}.contains(e.code)) rethrow;
      setupIncomplete = true;
    }
    final pending = reviews.where((r) => r['status'] == 'pending').toList();
    return {
      'profile_complete': row != null,
      'setup_incomplete': setupIncomplete,
      'condition_reviews': reviews,
      'other_name': pending.isEmpty ? '' : pending.first['submitted_name'],
      'conditions': names,
      'ai_matching_consent': row?['ai_matching_consent'] == true,
      'full_name':
          profile['full_name'] ?? currentUser?.userMetadata?['full_name'] ?? '',
      'username': profile['username'] ?? '',
      'email': currentUser?.email ?? '',
      'condition': legacy,
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
    List<String>? conditions,
    bool aiConsent = false,
    String? otherName,
    required String language,
    String? description,
    String? document,
    bool reapply = false,
  }) async {
    final actualRole = await getMyRole();
    if (actualRole != role)
      throw ArgumentError('Sign in with the correct account role.');
    // Keep legacy database compatibility without requesting a username.
    final profile = await client
        .from('profiles')
        .select('username')
        .eq('id', userId)
        .maybeSingle();
    final savedUsername =
        username ??
        profile?['username'] as String? ??
        'user_${userId.replaceAll('-', '').substring(7)}';
    final error = validateUsername(savedUsername);
    if (error != null) throw ArgumentError(error);
    await client.rpc(
      'save_maak_profile_reviewable',
      params: {
        'p_full_name': fullName.trim(),
        'p_username': savedUsername.trim().toLowerCase(),
        'p_role': role,
        'p_conditions': conditions ?? [condition],
        'p_ai_consent': aiConsent,
        'p_other_name': otherName,
        'p_language': language,
        'p_description': description?.trim() ?? '',
        'p_document': document,
        'p_reapply': reapply,
      },
    );
    profileRevision.value++;
  }

  static Future<List<Map<String, dynamic>>> getConditionRequests() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('admin_condition_requests') as List,
      );
  static Future<void> reviewConditionRequest(
    String id,
    String action, {
    String? conditionId,
    String? name,
    String? reason,
  }) async {
    await client.rpc(
      'review_maak_condition',
      params: {
        'p_request_id': id,
        'p_action': action,
        'p_condition_id': conditionId,
        'p_name': name,
        'p_reason': reason,
      },
    );
  }

  static Future<String> checkConditionName(String id) async {
    try {
      final response = await client.functions.invoke(
        'review-condition-name',
        body: {'request_id': id},
      );
      if (response.status != 200 || response.data is! Map) {
        return 'AI check could not complete. Manual review is still available.';
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['state'] == 'health')
        return 'AI check completed: the name appears health-related. You still decide whether to accept or link it.';
      if (data['state'] == 'warning')
        return 'AI check completed: please review this name carefully. No decision was made automatically.';
      return data['notice'] as String? ??
          'AI could not determine the name. Please review it manually.';
    } on FunctionException catch (e) {
      if (e.status == 401)
        throw ArgumentError(
          'Your session has expired. Sign out and log in again.',
        );
      if (e.status == 403)
        throw ArgumentError('Only an administrator can check condition names.');
      if (e.status == 409)
        throw ArgumentError(
          'This request has already changed. Refresh the list.',
        );
      if (e.status == 503)
        return 'AI is not configured. The administrator needs to add GEMINI_API_KEY to Supabase Secrets. You can review this request manually.';
      if (e.status == 429)
        return 'Please wait before another AI check. Manual review remains available.';
      if (e.status == 404)
        return 'The AI check function is not deployed. Deploy review-condition-name; manual review remains available.';
      return 'The AI service is temporarily unavailable. Please review this request manually.';
    } catch (_) {
      return 'Could not reach the AI service. Check your connection or review this request manually.';
    }
  }

  static Future<Map<String, dynamic>> getMatches({bool useAi = false}) async {
    try {
      final response = await client.functions.invoke(
        'match-volunteers',
        body: {'use_ai': useAi},
      );
      if (response.status != 200 || response.data is! Map) {
        throw StateError('Matching unavailable');
      }
      return Map<String, dynamic>.from(response.data as Map);
    } catch (_) {
      throw ArgumentError(
        'Could not load matches. Check your connection or ask the administrator to finish matching setup.',
      );
    }
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
    if (await client.rpc('is_maak_admin') != true) {
      throw ArgumentError(
        'Only an administrator can add or edit conditions. Sign in with your admin account.',
      );
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError('Enter a condition name of 1–80 characters.');
    }
    final values = {'name': trimmed, 'is_active': active};

    if (id == null) {
      final saved = await client
          .from('chronic_conditions')
          .insert(values)
          .select('id')
          .maybeSingle();

      if (saved == null) {
        throw ArgumentError(
          'The condition could not be added. Check your Admin permissions.',
        );
      }
    } else {
      final saved = await client
          .from('chronic_conditions')
          .update(values)
          .eq('id', id)
          .select('id')
          .maybeSingle();

      if (saved == null) {
        throw ArgumentError(
          'The condition was not updated. Refresh the list and check your Admin permissions.',
        );
      }
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

  /// Asks the server to email a volunteer about their application.
  /// The server resolves the recipient, name and rejection reason itself:
  /// 'pending' goes to the signed-in volunteer; 'approved'/'rejected' need an
  /// admin session and the reviewed volunteer's [volunteerId].
  static Future<void> sendVolunteerEmail({
    required String status,
    String? volunteerId,
  }) async {
    final response = await client.functions.invoke(
      'send-volunteer-email',
      body: {
        'status': status,
        if (volunteerId != null) 'volunteerId': volunteerId,
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
        .order('created_at', ascending: false)
        .map((rows) => rows.where((r) => r['kind'] != 'session').toList());
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
  static Future<void> decideRequest(String id, bool accepted) async {
    try {
      await client.rpc(
        'decide_support_request',
        params: {'p_request_id': id, 'p_accept': accepted},
      );
    } catch (error, stack) {
      // A committed response can be lost in transit. Confirm the saved decision
      // before reporting failure; never repeat a mutation blindly.
      try {
        final row = await client
            .from('support_requests')
            .select('status,volunteer_id')
            .eq('id', id)
            .maybeSingle();
        if (row?['volunteer_id'] == userId &&
            row?['status'] == (accepted ? 'accepted' : 'declined'))
          return;
      } catch (_) {
        /* Keep the original failure when verification fails. */
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Stream<int> unreadMessageCount() {
    final me = currentUser?.id;
    if (me == null) return Stream.value(0);
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .asyncMap(
          (_) async =>
              (await client.rpc('my_maak_unread_message_count') as num).toInt(),
        )
        .distinct();
  }

  static Future<void> markMessagesRead(
    String requestId,
    List<String> ids,
  ) async {
    for (var start = 0; start < ids.length; start += 500) {
      await client.rpc(
        'mark_maak_messages_read',
        params: {
          'p_request_id': requestId,
          'p_message_ids': ids.sublist(
            start,
            (start + 500).clamp(0, ids.length),
          ),
        },
      );
    }
  }

  static Future<void> cancelRequest(String id) async =>
      await client.rpc('cancel_support_request', params: {'p_request_id': id});

  static Stream<List<Map<String, dynamic>>> messageStream(String requestId) =>
      client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('request_id', requestId)
          .order('created_at', ascending: true);
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
