import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  final VoidCallback onNext;

  const PrivacyScreen({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    size: 40,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.black26,
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.smartphone_outlined,
                    size: 48,
                    color: Color(0xFF6B8CAE),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.black26,
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.search, size: 40, color: Colors.black54),
                ],
              ),
              const SizedBox(height: 48),
              Text(
                'Your photos never leave your phone.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6B8CAE),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Allow Photo Access',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No account required. Ever.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 16), // Match spacing from WelcomeScreen
            ],
          ),
        ),
      ),
    );
  }
}
