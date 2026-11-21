import 'package:flutter/material.dart';

import 'health_library_page.dart';

/// Entry point for the Health Library section.
/// The existing class name is preserved to avoid breaking navigation.
class ResourcesScreen extends StatelessWidget {
  const ResourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const HealthLibraryPage();
  }
}
