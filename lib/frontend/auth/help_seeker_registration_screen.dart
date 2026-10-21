import 'package:flutter/material.dart';
import '../redesign/registration.dart';

// Language choices are static; conditions are loaded from Supabase by ConditionField.
const kLanguages = languages;

class HelpSeekerRegistrationScreen extends StatelessWidget {
  const HelpSeekerRegistrationScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const RegistrationScreen(role: 'help_seeker');
}
