import 'package:flutter/material.dart';
import '../redesign/profile.dart';

class EditProfileScreen extends StatelessWidget {
  final String role;
  const EditProfileScreen({super.key, required this.role});
  @override
  Widget build(BuildContext context) => EditProfilePage(role: role);
}
