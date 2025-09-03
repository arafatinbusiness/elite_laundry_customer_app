import 'package:flutter/material.dart';

class LocationPreview extends StatelessWidget {
  const LocationPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withOpacity(0.5),
            offset: const Offset(0, 4),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildLocationGrid(),
          const SizedBox(height: 16),
          _buildDeliveryInfo(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.public_rounded,
            color: Colors.blue.shade600,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Worldwide',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
              Text(
                'Find services in your area',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationGrid() {
    final locations = [
      {'country': 'USA', 'cities': '50+ Cities', 'flag': '🇺🇸'},
      {'country': 'Canada', 'cities': '25+ Cities', 'flag': '🇨🇦'},
      {'country': 'UK', 'cities': '30+ Cities', 'flag': '🇬🇧'},
      {'country': 'Bangladesh', 'cities': '15+ Cities', 'flag': '🇧🇩'},
      {'country': 'India', 'cities': '40+ Cities', 'flag': '🇮🇳'},
      {'country': 'Australia', 'cities': '20+ Cities', 'flag': '🇦🇺'},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 8,
      ),
      itemCount: locations.length,
      itemBuilder: (context, index) {
        final location = locations[index];
        return _buildLocationCard(location);
      },
    );
  }

  Widget _buildLocationCard(Map<String, String> location) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.blue.shade100,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            location['flag']!,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  location['country']!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
                Text(
                  location['cities']!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade50,
            Colors.blue.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.shade100,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.local_shipping_outlined,
                color: Colors.blue.shade600,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Smart Delivery Pricing',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildDeliveryFeature(
                icon: Icons.location_on_outlined,
                text: 'Location-based rates',
              ),
              const SizedBox(width: 16),
              _buildDeliveryFeature(
                icon: Icons.schedule_outlined,
                text: 'Same-day available',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildDeliveryFeature(
                icon: Icons.local_offer_outlined,
                text: 'Special offers',
              ),
              const SizedBox(width: 16),
              _buildDeliveryFeature(
                icon: Icons.track_changes_outlined,
                text: 'Real-time tracking',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryFeature({
    required IconData icon,
    required String text,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.blue.shade600,
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
