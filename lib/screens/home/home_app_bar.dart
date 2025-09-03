import 'package:elite_laundry_customer_app/screens/home/profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../conversation_list_screen.dart';
import '../../services/message_service.dart';
import '../order_screen.dart';
import 'my_orders_screen.dart';
import 'customer_balance_screen.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E40AF),
            Color(0xFF3B82F6),
            Color(0xFF60A5FA),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1E40AF).withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildAppBarItem(Icons.home_outlined, 'Home', () => _onHomeTap(context)),
            _buildAppBarItem(Icons.shopping_cart_outlined, 'Order', () => _onOrderTap(context)),
            _buildAppBarItem(Icons.receipt_long_outlined, 'Orders', () => _onMyOrdersTap(context)),
            _buildMessageIconWithBadge(context),
            _buildMoreMenu(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBarItem(IconData icon, String label, VoidCallback onTap, {double iconSize = 22}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withOpacity(0.1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize),
            if (label.isNotEmpty)
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9, 
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageIconWithBadge(BuildContext context) {
    return StreamBuilder<int>(
      stream: MessageService().getUnreadCount(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return GestureDetector(
          onTap: () => _onMessageTap(context),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.1),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.message_outlined, size: 22),
                    Text(
                      'Chat',
                      style: const TextStyle(
                        fontSize: 9, 
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: -2,
                    child: Container(
                      padding: EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.red[500],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      constraints: BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoreMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) => _onMoreMenuSelected(context, value),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'ebalance',
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet, size: 16, color: Colors.green),
              SizedBox(width: 8),
              Text('My eBalance', style: TextStyle(color: Colors.green)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              Icon(Icons.person, size: 16),
              SizedBox(width: 8),
              Text('Profile'),
            ],
          ),
        ),
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
    );
  }

  void _onHomeTap(BuildContext context) {
    // Already on home
  }

  void _onOrderTap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OrderScreen()),
    );
  }

  void _onMyOrdersTap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MyOrdersScreen()),
    );
  }




  void _onMessageTap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationListScreen(),
      ),
    );
  }

  void _onMoreMenuSelected(BuildContext context, String value) {
    switch (value) {
      case 'ebalance':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CustomerBalanceScreen()),
        );
        break;
      case 'profile':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProfileScreen()),
        );
        break;
      case 'logout':
        _handleLogout(context);
        break;
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
