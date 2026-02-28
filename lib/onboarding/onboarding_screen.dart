import 'package:flutter/material.dart';
import 'welcome_screen.dart';
import 'privacy_screen.dart';
import 'permission_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: PageView(
        controller: _pageController,
        physics:
            const NeverScrollableScrollPhysics(), // Disable swipe gestures to force button usage
        children: [
          WelcomeScreen(onNext: _nextPage),
          PrivacyScreen(onNext: _nextPage),
          const PermissionScreen(), // handles its own navigation out of flow
        ],
      ),
    );
  }
}
