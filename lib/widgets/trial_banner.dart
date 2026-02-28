import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../screens/upgrade_screen.dart';

class TrialBanner extends StatelessWidget {
  final int daysRemaining;

  const TrialBanner({super.key, required this.daysRemaining});

  @override
  Widget build(BuildContext context) {
    if (daysRemaining <= 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const UpgradeScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6B8CAE), Color(0xFF1A1A2E)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_outlined, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              'Free Trial — $daysRemaining days remaining',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Upgrade',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
