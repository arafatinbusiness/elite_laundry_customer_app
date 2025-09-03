import 'package:flutter/material.dart';

class ActionSection extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const ActionSection({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildGetStartedButton(),
          const SizedBox(height: 16),
          _buildSignInButton(),
          const SizedBox(height: 24),
          _buildSecondaryActions(context),
        ],
      ),
    );
  }

  Widget _buildGetStartedButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade600,
            Colors.blue.shade700,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade600.withOpacity(0.3),
            offset: const Offset(0, 4),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onGetStarted,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Get Started',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return Container(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onSignIn,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.blue.shade700,
          side: BorderSide(
            color: Colors.blue.shade300,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login_rounded,
              color: Colors.blue.shade700,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Sign In',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSecondaryAction(
          icon: Icons.location_on_outlined,
          label: 'Find Branches',
          onTap: () => _handleFindBranches(context),
        ),
        Container(
          width: 1,
          height: 20,
          color: Colors.blue.shade200,
        ),
        _buildSecondaryAction(
          icon: Icons.info_outline_rounded,
          label: 'Learn More',
          onTap: () => _handleLearnMore(context),
        ),
        Container(
          width: 1,
          height: 20,
          color: Colors.blue.shade200,
        ),
        _buildSecondaryAction(
          icon: Icons.local_offer_outlined,
          label: 'View Offers',
          onTap: () => _handleViewOffers(context),
        ),
      ],
    );
  }

  Widget _buildSecondaryAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.blue.shade600,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleFindBranches(BuildContext context) {
    // Navigate to branch finder or location screen
    Navigator.pushNamed(context, '/select-location');
  }

  void _handleLearnMore(BuildContext context) {
    // Show info dialog or navigate to about page
    _showInfoDialog(context);
  }

  void _handleViewOffers(BuildContext context) {
    // Navigate to offers page or show offers dialog
    _showOffersDialog(context);
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Elite Laundry'),
        content: const Text(
          'Professional laundry service with international coverage. '
              'Real-time tracking, direct communication with branches, '
              'and premium quality guaranteed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showOffersDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Current Offers'),
        content: const Text(
          '🎉 New Customer: 20% off first order\n'
              '📦 Bulk Orders: 15% off orders over \$50\n'
              '⚡ Same Day: Free express delivery',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
