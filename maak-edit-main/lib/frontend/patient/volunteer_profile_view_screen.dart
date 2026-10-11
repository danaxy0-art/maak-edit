import 'package:flutter/material.dart';
import '../../backend/models/sample_data.dart';
import '../theme/app_theme.dart';
import '../shared/chat_screen.dart';
class VolunteerProfileViewScreen extends StatelessWidget {
  final SampleVolunteer volunteer;
  const VolunteerProfileViewScreen({super.key, required this.volunteer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.selectedCardFill,
                child: Icon(Icons.person, size: 36, color: AppColors.primaryNavy),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(volunteer.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    Text('${volunteer.specialty} · ${volunteer.experience}',
                        style: const TextStyle(color: AppColors.textMuted)),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text('${volunteer.rating} (${volunteer.reviewCount} reviews)',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Send message'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ChatScreen(contactName: volunteer.name)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Request sent!')),
              );
            },
            child: const Text('Request help'),
          ),
          const SizedBox(height: 24),
          const Text('About',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 16)),
          const SizedBox(height: 8),
          Text(volunteer.bio, style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
          const SizedBox(height: 24),
          const Text('Skills & Languages',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: volunteer.skills
                .map((s) => Chip(
                      label: Text(s),
                      backgroundColor: AppColors.selectedCardFill,
                      labelStyle: const TextStyle(color: AppColors.primaryNavy),
                      side: BorderSide.none,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
