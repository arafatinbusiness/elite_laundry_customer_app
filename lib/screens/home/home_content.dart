// lib/screens/home/home_content.dart (UPDATED to show only the last 5 active orders)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home/customer_order_tracking_screen.dart';

class HomeContent extends StatefulWidget {
  final String userName;

  const HomeContent({Key? key, required this.userName}) : super(key: key);

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Use fromLTRB to remove top padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSectionTitle('Recent Active Orders'), // Title updated for clarity
          const SizedBox(height: 12),
          _buildActiveOrders(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1E293B),
      ),
    );
  }

  Widget _buildActiveOrders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _buildEmptyState('Please login to view orders');

    return StreamBuilder<QuerySnapshot>(
      // ===== THIS QUERY IS THE CORE CHANGE =====
      stream: FirebaseFirestore.instance
          .collectionGroup('mobileOrders')
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: ['pending', 'confirmed', 'en_route', 'arrived', 'collected'])
      // 1. Sort by newest first ON THE SERVER (more efficient)
          .orderBy('createdAt', descending: true)
      // 2. Limit the results to a maximum of 5 documents
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }
        if (snapshot.hasError) {
          print("❌ CRITICAL ERROR in HomeContent: ${snapshot.error}");
          print("   This is very likely a missing Firestore index.");
          return _buildErrorState('Error loading orders');
        }
        final allOrders = snapshot.data?.docs ?? [];

        // Auto-cancellation logic can remain as it checks the fetched documents
        final validOrders = <QueryDocumentSnapshot>[];
        final now = DateTime.now();

        for (final orderDoc in allOrders) {
          final order = orderDoc.data() as Map<String, dynamic>;
          final status = order['status'] ?? '';
          final createdAt = order['createdAt'] as Timestamp?;

          if (status == 'pending' && createdAt != null) {
            final orderTime = createdAt.toDate();
            final hoursSinceCreated = now.difference(orderTime).inHours;

            if (hoursSinceCreated >= 3) {
              _cancelPendingOrder(orderDoc);
              continue;
            }
          }
          validOrders.add(orderDoc);
        }

        // ===== THIS MANUAL SORT IS NO LONGER NEEDED =====
        // The query now handles sorting for us.
        // validOrders.sort((a, b) => ...);

        if (validOrders.isEmpty) {
          return _buildEmptyState('No active orders');
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: validOrders.length, // This will now be 5 or less
          itemBuilder: (context, index) {
            final orderDoc = validOrders[index];
            final order = orderDoc.data() as Map<String, dynamic>;
            final branchId = orderDoc.reference.parent.parent!.id;
            return _buildOrderCard(context, order, orderDoc.id, branchId);
          },
        );
      },
    );
  }

  // ... (All other methods like _cancelPendingOrder, _buildOrderCard, etc. remain unchanged)
  Future<void> _cancelPendingOrder(QueryDocumentSnapshot orderDoc) async {
    try {
      await orderDoc.reference.update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': 'Auto-cancelled: No driver confirmation within 3 hours',
      });
      print('✅ Auto-cancelled pending order: ${orderDoc.id}');
    } catch (e) {
      print('❌ Error auto-cancelling order ${orderDoc.id}: $e');
    }
  }

  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order, String orderId, String branchId) {
    final status = order['status'] ?? 'pending';
    final totalAmount = order['totalAmount']?.toStringAsFixed(2) ?? '0.00';
    final createdAt = _formatOrderDate(order['createdAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CustomerOrderTrackingScreen(
                  orderId: orderId,
                  branchId: branchId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '#${orderId.substring(0, 6)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                              fontSize: 14,
                            ),
                          ),
                          _buildStatusChip(status),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$totalAmount',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3B82F6),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            createdAt,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Color(0xFFF59E0B);
      case 'confirmed':
        return Color(0xFF10B981);
      case 'en_route':
        return Color(0xFF3B82F6);
      case 'arrived':
        return Color(0xFF8B5CF6);
      case 'collected':
        return Color(0xFF6366F1);
      default:
        return Color(0xFF64748B);
    }
  }

  String _formatOrderDate(dynamic timestamp) {
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return 'Unknown date';
      }
      final now = DateTime.now();
      final difference = now.difference(date);
      final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday $timeStr';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.day}/${date.month}/${date.year} $timeStr';
      }
    } catch (e) {
      return 'Invalid date';
    }
  }

  Widget _buildStatusChip(String status) {
    List<Color> gradientColors;
    Color textColor;
    IconData? icon;
    switch (status.toLowerCase()) {
      case 'pending':
        gradientColors = [Color(0xFFFEF3C7), Color(0xFFFDE68A)];
        textColor = const Color(0xFF92400E);
        icon = Icons.hourglass_empty;
        break;
      case 'confirmed':
        gradientColors = [Color(0xFFDBEAFE), Color(0xFFBFDBFE)];
        textColor = const Color(0xFF1D4ED8);
        icon = Icons.check_circle_outline;
        break;
      case 'en_route':
        gradientColors = [Color(0xFFDDD6FE), Color(0xFFC4B5FD)];
        textColor = const Color(0xFF7C3AED);
        icon = Icons.local_shipping_outlined;
        break;
      case 'arrived':
        gradientColors = [Color(0xFFBBF7D0), Color(0xFFA7F3D0)];
        textColor = const Color(0xFF047857);
        icon = Icons.location_on_outlined;
        break;
      case 'collected':
        gradientColors = [Color(0xFFD1FAE5), Color(0xFFA7F3D0)];
        textColor = const Color(0xFF065F46);
        icon = Icons.check_circle;
        break;
      default:
        gradientColors = [Color(0xFFF1F5F9), Color(0xFFE2E8F0)];
        textColor = const Color(0xFF475569);
        icon = Icons.circle_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: textColor.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: textColor.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: textColor,
            ),
            SizedBox(width: 4),
          ],
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.red[600],
            ),
          ),
        ],
      ),
    );
  }
}