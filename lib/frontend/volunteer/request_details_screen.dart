import 'package:flutter/material.dart';
import '../../backend/models/sample_data.dart';
import '../theme/app_theme.dart';
import '../shared/chat_screen.dart';
class RequestDetailsScreen extends StatelessWidget {
  final SampleRequest request;
  const RequestDetailsScreen({super.key, required this.request});

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
          const CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.selectedCardFill,
            child: Icon(Icons.person, size: 40, color: AppColors.primaryNavy),
          ),
          const SizedBox(height: 14),
          Text(request.name,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 4),
          Text('${request.gender} · ${request.age} years',
              style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(
            '${request.distanceKm.toStringAsFixed(0)} km · ${request.hoursPerWeek}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          const Text('About',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 16)),
          const SizedBox(height: 8),
          Text(request.description, style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
          const SizedBox(height: 20),
          const Text('Preferred language',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 14)),
          const SizedBox(height: 6),
          const Chip(
            label: Text('Arabic'),
            backgroundColor: AppColors.selectedCardFill,
            labelStyle: TextStyle(color: AppColors.primaryNavy),
            side: BorderSide.none,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ChatScreen(contactName: request.name)),
                  ),
                  child: const Text('Message'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Request accepted!')),
                    );
                    Navigator.of(context).maybePop();
                  },
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
