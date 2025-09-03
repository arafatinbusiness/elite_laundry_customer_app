// lib/screens/home/home_screen.dart (UPDATED with new animation and text)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:elite_laundry_customer_app/screens/conversation_list_screen.dart';
import 'package:elite_laundry_customer_app/screens/order_screen.dart';
import 'package:elite_laundry_customer_app/screens/home/my_orders_screen.dart';
import 'package:elite_laundry_customer_app/screens/home/customer_balance_screen.dart';
import 'package:elite_laundry_customer_app/screens/home/profile_screen.dart';
import 'package:elite_laundry_customer_app/services/notification_service.dart';
import 'home_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _showWelcome = true;
  String _userName = '';
  late AnimationController _glowController;
  String _deliveryMessage = '';
  bool _isLoadingDeliveryInfo = true;

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _startWelcomeTimer();
    _setupGlowAnimation();
    _fetchUpcomingDelivery();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _initializeUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _userName = user.displayName ?? 'User';
      });
    }
  }

  void _startWelcomeTimer() {
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showWelcome = false;
        });
      }
    });
  }

  void _setupGlowAnimation() {
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )
      ..repeat(reverse: true);
  }

  /// Fetches the delivery estimate for the user's most recent "processing" order.
  Future<void> _fetchUpcomingDelivery() async {
    print("🚚 [DEBUG] Starting to fetch delivery info...");
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("🚚 [DEBUG] User not logged in, aborting fetch.");
      if (mounted) setState(() => _isLoadingDeliveryInfo = false);
      return;
    }

    try {
      print("🚚 [DEBUG] Running query for user's newest 'processing' order: ${user.uid}");
      final querySnapshot = await FirebaseFirestore.instance
          .collectionGroup('mobileOrders')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'processing')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      print("🚚 [DEBUG] Firestore query completed successfully.");

      if (querySnapshot.docs.isNotEmpty) {
        final lastActiveOrder = querySnapshot.docs.first;
        print("🚚 [DEBUG] Found newest processing order: ${lastActiveOrder.id}");

        final orderData = lastActiveOrder.data();
        final deliveryDays = orderData['deliveryDaysEstimate'] as int?;

        if (deliveryDays != null) {
          print("✅ [SUCCESS] Found delivery estimate: $deliveryDays days.");
          if (mounted) {
            setState(() {
              // ===== TEXT HAS BEEN UPDATED HERE =====
              _deliveryMessage = 'Your latest order will be delivered in $deliveryDays days\n'
                  'سيتم توصيل طلبك الأخير خلال $deliveryDays أيام';
            });
          }
        } else {
          print("ℹ️ [INFO] 'processing' order found, but 'deliveryDaysEstimate' field is not set for it yet.");
        }
      } else {
        print("🚚 [DEBUG] No orders with status 'processing' found for this user.");
      }
    } catch (e) {
      print("❌ [CRITICAL] Error fetching order: $e");
      print("❌ [CRITICAL] This is likely a MISSING FIRESTORE INDEX. Please ensure the correct index is created.");
    } finally {
      if (mounted) {
        print("🚚 [DEBUG] Fetch process finished.");
        setState(() => _isLoadingDeliveryInfo = false);
      }
    }
  }

  /// Builds the animated delivery message text with a new "pulse" animation.
  Widget _buildDeliveryMessage() {
    if (_isLoadingDeliveryInfo || _deliveryMessage.isEmpty) {
      return const SizedBox.shrink();
    }

    // ===== ANIMATION HAS BEEN UPDATED HERE =====
    // We now use an AnimatedBuilder to create a more eye-catching "glow" or "pulse"
    // effect by animating the box shadow instead of just the opacity.
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        // The glow effect will pulse by changing the spread radius of the shadow
        final double spread = 2.0 + (_glowController.value * 6.0); // Will animate between 2.0 and 8.0
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade600, Colors.green.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.4),
                blurRadius: 12,
                spreadRadius: spread, // This is the animated property
              ),
            ],
          ),
          child: child, // The child (Text widget) is passed in for efficiency
        );
      },
      child: Text(
        _deliveryMessage,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  void _navigateToScreen(String route) {
    switch (route) {
      case 'home':
        break;
      case 'order':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const OrderScreen()));
        break;
      case 'orders':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
        break;
      case 'messages':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => ConversationListScreen()));
        break;
      case 'ebalance':
        Navigator.push(context, MaterialPageRoute(
            builder: (context) => const CustomerBalanceScreen()));
        break;
      case 'profile':
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const ProfileScreen()));
        break;
    }
  }

  void _onMoreMenuSelected(String value) {
    if (value == 'logout') {
      _handleLogout();
    }
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Logout failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E40AF),
        elevation: 2,
        title: const Text(
          'Elite Laundry Station',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E40AF),
          ),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMoreMenuSelected,
            itemBuilder: (context) =>
            [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFC),
              Color(0xFFF1F5F9),
              Color(0xFFE2E8F0),
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (_showWelcome) _buildWelcomeMessage(),
              _buildDeliveryMessage(),
              _buildMenuGrid(),
              HomeContent(userName: _userName),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeMessage() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.95),
            Colors.white.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E40AF).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.waving_hand,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hi $_userName! Welcome back',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid() {
    final menuItems = [
      _MenuItem(icon: Icons.home_outlined,
          label: 'Home\nالرئيسية',
          route: 'home',
          color: const Color(0xFF3B82F6)),
      _MenuItem(icon: Icons.add_shopping_cart_outlined,
          label: 'New Order\nطلب جديد',
          route: 'order',
          color: const Color(0xFF10B981)),
      _MenuItem(icon: Icons.receipt_long_outlined,
          label: 'My Orders\nطلباتي',
          route: 'orders',
          color: const Color(0xFFF59E0B)),
      _MenuItem(icon: Icons.account_balance_wallet_outlined,
          label: 'eBalance\nرصيدي',
          route: 'ebalance',
          color: const Color(0xFFEC4899)),
      _MenuItem(icon: Icons.person_outlined,
          label: 'Profile\nملفي',
          route: 'profile',
          color: const Color(0xFF6366F1)),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: menuItems.length,
        itemBuilder: (context, index) {
          final item = menuItems[index];
          return _buildMenuCard(item);
        },
      ),
    );
  }

  Widget _buildMenuCard(_MenuItem item) {
    final labels = item.label.split('\n');
    final englishLabel = labels.isNotEmpty ? labels[0] : '';
    final arabicLabel = labels.length > 1 ? labels[1] : '';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToScreen(item.route),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                item.color.withOpacity(0.1),
                item.color.withOpacity(0.05),
              ],
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.icon,
                    size: 20,
                    color: item.color,
                  ),
                ),
                const SizedBox(height: 8),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$englishLabel\n',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                          height: 1.2,
                        ),
                      ),
                      TextSpan(
                        text: arabicLabel,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                          height: 1.2,
                        ),
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
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String route;
  final Color color;

  _MenuItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.color,
  });
}