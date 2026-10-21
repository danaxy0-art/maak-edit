import 'dart:async';
import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';

/// Shared account name for home and profile, refreshed after profile edits.
class CurrentUserName extends StatefulWidget {
  final String prefix;
  final TextStyle? style;
  const CurrentUserName({super.key, this.prefix = '', this.style});

  @override
  State<CurrentUserName> createState() => _CurrentUserNameState();
}

class _CurrentUserNameState extends State<CurrentUserName> {
  String _name = '';
  int _request = 0;
  StreamSubscription<dynamic>? _authSubscription;

  @override
  void initState() {
    super.initState();
    SupabaseService.profileRevision.addListener(_reload);
    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) setState(() => _name = '');
      _reload();
    });
    _reload();
  }

  Future<void> _reload() async {
    final request = ++_request;
    final userId = SupabaseService.currentUser?.id;
    final name = await SupabaseService.getMyFullName();
    if (!mounted ||
        request != _request ||
        userId != SupabaseService.currentUser?.id) {
      return;
    }
    setState(() => _name = name);
  }

  @override
  void dispose() {
    SupabaseService.profileRevision.removeListener(_reload);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _name.isEmpty
        ? widget.prefix.trimRight()
        : '${widget.prefix}$_name';
    return Text(text, style: widget.style);
  }
}
