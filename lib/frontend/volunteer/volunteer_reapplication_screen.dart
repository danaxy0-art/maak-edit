import 'package:flutter/material.dart';
import '../redesign/profile.dart';

class VolunteerReapplicationScreen extends StatelessWidget {
  const VolunteerReapplicationScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const EditProfilePage(role: 'volunteer', reapply: true);
}
