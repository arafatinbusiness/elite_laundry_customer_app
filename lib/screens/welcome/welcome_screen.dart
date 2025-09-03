import 'package:flutter/material.dart';
import 'hero_section.dart';
import 'service_highlights.dart';
import 'trust_indicators.dart';
import 'location_preview.dart';
import 'action_section.dart';
import 'quick_auth.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const HeroSection(),
              const SizedBox(height: 32),
              const ServiceHighlights(),
              const SizedBox(height: 32),
              const TrustIndicators(),
              const SizedBox(height: 32),
              const LocationPreview(),
              const SizedBox(height: 40),
              ActionSection(
                onGetStarted: () => _handleGetStarted(context),
                onSignIn: () => Navigator.pushNamed(context, '/login'),

              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _handleGetStarted(BuildContext context) {
    Navigator.pushNamed(context, '/select-location');
  }

  void _handleSignIn(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const QuickAuth(),
    );
  }
}
