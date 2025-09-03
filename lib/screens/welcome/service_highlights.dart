import 'package:flutter/material.dart';

class ServiceHighlights extends StatelessWidget {
  const ServiceHighlights({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(),
          const SizedBox(height: 20),
          _buildHighlightsList(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Why Choose Elite Laundry?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Premium service features that set us apart',
          style: TextStyle(
            fontSize: 14,
            color: Colors.blue.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightsList() {
    final highlights = [
      {
        'icon': Icons.public_rounded,
        'title': 'Global Network',
        'subtitle': 'Available in 50+ countries worldwide',
        'color': Colors.blue,
      },
      {
        'icon': Icons.track_changes_rounded,
        'title': 'Real-time Tracking',
        'subtitle': 'Live pickup & delivery updates',
        'color': Colors.green,
      },
      {
        'icon': Icons.chat_bubble_outline_rounded,
        'title': 'Direct Communication',
        'subtitle': 'Chat with local branches instantly',
        'color': Colors.orange,
      },
      {
        'icon': Icons.flash_on_rounded,
        'title': 'Express Service',
        'subtitle': 'Same-day delivery available',
        'color': Colors.purple,
      },
      {
        'icon': Icons.verified_user_rounded,
        'title': 'Quality Assured',
        'subtitle': 'Professional branch management',
        'color': Colors.teal,
      },
      {
        'icon': Icons.local_offer_rounded,
        'title': 'Smart Pricing',
        'subtitle': 'Location-based competitive rates',
        'color': Colors.red,
      },
    ];

    return Column(
      children: highlights.map((highlight) => _buildHighlightCard(highlight)).toList(),
    );
  }

  Widget _buildHighlightCard(Map<String, dynamic> highlight) {
    final color = highlight['color'] as MaterialColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.shade100,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.shade50,
            offset: const Offset(0, 2),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          _buildIconContainer(highlight['icon'], color),
          const SizedBox(width: 16),
          Expanded(
            child: _buildContentSection(
              highlight['title'],
              highlight['subtitle'],
              color,
            ),
          ),
          _buildArrowIcon(color),
        ],
      ),
    );
  }

  Widget _buildIconContainer(IconData icon, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.shade100,
          width: 1,
        ),
      ),
      child: Icon(
        icon,
        color: color.shade600,
        size: 24,
      ),
    );
  }

  Widget _buildContentSection(String title, String subtitle, MaterialColor color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color.shade800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: color.shade600,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildArrowIcon(MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.arrow_forward_ios_rounded,
        color: color.shade400,
        size: 14,
      ),
    );
  }
}
