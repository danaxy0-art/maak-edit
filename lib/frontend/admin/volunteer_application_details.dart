import 'package:flutter/material.dart';
import '../redesign/admin.dart';

class VolunteerApplicationDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> application;
  const VolunteerApplicationDetailsScreen({
    super.key,
    required this.application,
  });
  @override
  Widget build(BuildContext context) =>
      ApplicationDetailPage(application: application);
}
