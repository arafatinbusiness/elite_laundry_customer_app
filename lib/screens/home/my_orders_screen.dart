import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'customer_order_tracking_screen.dart';
import '../invoice_pdf_viewer.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;
  bool _isCancellable(String status) {
    final cancellableStatuses = [
      'pending',
      'confirmed',
      'en_route',
      'arrived',
    ];
    return cancellableStatuses.contains(status);
  }

  // Cache for invoice amounts to prevent excessive Firestore calls
  final Map<String, double?> _invoiceAmountCache = {};
  
  // Stream subscriptions for proper disposal
  StreamSubscription<QuerySnapshot>? _activeOrdersSubscription;
  StreamSubscription<QuerySnapshot>? _orderHistorySubscription;
  
  // Add cache size limit to prevent unbounded growth
  static const int _maxCacheSize = 100;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize blinking animation
    _blinkController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    _blinkAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _blinkController,
      curve: Curves.easeInOut,
    ));
    
    // Start the blinking animation
    _blinkController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _blinkController.dispose();
    _activeOrdersSubscription?.cancel();
    _orderHistorySubscription?.cancel();
    _invoiceAmountCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
       appBar: AppBar(
        title: Text('My Orders'),
        backgroundColor: Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Active Orders'),
            Tab(text: 'Order History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveOrdersList(),
          _buildOrderHistoryList(),
        ],
      ),
    );
  }

  Widget _buildActiveOrdersList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Center(child: Text('Please login to view orders'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('mobileOrders')
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: [
        'pending', 'confirmed', 'en_route', 'arrived', 'collected',
        'customer_confirmed', 'at_laundry', 'delivered_to_shop',
        'processing', 'ready_for_delivery', 'delivery_assigned',
        'delivery_en_route', 'delivery_arrived', 'delivered'
      ])

          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading orders'));
        }
        final allOrders = snapshot.data?.docs ?? [];

        // Filter out and auto-cancel pending orders older than 3 hours
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
              // Auto-cancel the order
              _cancelPendingOrder(orderDoc);
              continue; // Skip this order from display
            }
          }

          validOrders.add(orderDoc);
        }

        // Sort orders: delivery orders first, then by creation date
        // Sort orders: latest orders first, with delivery status priority
        validOrders.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aStatus = aData['status'] ?? '';
          final bStatus = bData['status'] ?? '';
          final aTime = aData['createdAt'] as Timestamp?;
          final bTime = bData['createdAt'] as Timestamp?;

          // Special priority for delivery statuses (these always go to top)
          final deliveryStatuses = ['delivery_en_route', 'delivery_arrived'];
          final aIsDelivery = deliveryStatuses.contains(aStatus);
          final bIsDelivery = deliveryStatuses.contains(bStatus);

          if (aIsDelivery && !bIsDelivery) return -1;
          if (!aIsDelivery && bIsDelivery) return 1;

          // For all other cases, sort by creation time (newest first)
          if (aTime != null && bTime != null) {
            return bTime.compareTo(aTime); // This ensures newest orders are at top
          }

          return 0;
        });

        if (validOrders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text('No active orders', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: validOrders.length,
          itemBuilder: (context, index) {
            final orderDoc = validOrders[index];
            final order = orderDoc.data() as Map<String, dynamic>;
            final branchId = orderDoc.reference.parent.parent!.id;
            return _buildActiveOrderCard(context, order, orderDoc.id, branchId);
          },
        );
      },
    );
  }

// Add this method to handle cancellation
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

  Widget _buildOrderHistoryList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ ORDER HISTORY DEBUG: No user logged in. Aborting.');
      return Center(child: Text('Please login to view your order history'));
    }

    print('🔍 ORDER HISTORY DEBUG: Starting search for user: ${user.uid}');

    // This stream now queries directly by the user's unique ID for better accuracy and security.
    // It also specifically looks for terminal statuses that belong in a history view.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('mobileOrders')
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: ['completed', 'delivered', 'delivery_confirmed', 'cancelled'])
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        // 1. Handle Loading State
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('⏳ ORDER HISTORY DEBUG: Loading orders from Firestore...');
          return Center(child: CircularProgressIndicator());
        }

        // 2. Handle Error State
        if (snapshot.hasError) {
          print('❌ ORDER HISTORY DEBUG: An error occurred: ${snapshot.error}');
          return Center(
            child: Text(
              'Something went wrong while loading your history.',
              textAlign: TextAlign.center,
            ),
          );
        }

        final orders = snapshot.data?.docs ?? [];

        // 3. Handle Empty State
        if (orders.isEmpty) {
          print('📋 ORDER HISTORY DEBUG: No documents found for user ${user.uid} with history statuses.');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text(
                  'No completed or cancelled orders yet.',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                SizedBox(height: 8),
                Text(
                  'Your past orders will appear here.',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        // 4. Display the List of Orders
        print('✅ ORDER HISTORY DEBUG: Found ${orders.length} orders. Building list view.');
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final orderDoc = orders[index];
            final order = orderDoc.data() as Map<String, dynamic>;
            final branchId = orderDoc.reference.parent.parent!.id;

            // This widget now correctly handles displaying both completed and cancelled orders
            return _buildHistoryOrderCard(context, order, orderDoc.id, branchId);
          },
        );
      },
    );
  }

  Future<String?> _getUserPhoneNumber() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      // First try to get phone from user profile in Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final phone = userData['phone'];
        if (phone != null && phone.toString().isNotEmpty) {
          return phone.toString();
        }
      }

      // Fallback to Firebase Auth phone number
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        return user.phoneNumber;
      }

      return null;
    } catch (e) {
      print('❌ Error getting phone number: $e');
      return null;
    }
  }

  Future<String?> _getInvoiceNumber(String orderId, String branchId) async {
    try {
      // Search for invoice linked to this mobile order
      final invoiceQuery = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('invoices')
          .where('mobileOrderId', isEqualTo: orderId)
          .limit(1)
          .get();

      if (invoiceQuery.docs.isNotEmpty) {
        final invoiceData = invoiceQuery.docs.first.data();
        return invoiceData['invoiceNumber'] as String?;
      }
      return null;
    } catch (e) {
      print('❌ Error getting invoice number: $e');
      return null;
    }
  }

  Future<double?> _getInvoiceAmount(String orderId, String branchId, String status) async {
    // Check cache first
    final cacheKey = '$orderId-$branchId';
    if (_invoiceAmountCache.containsKey(cacheKey)) {
      return _invoiceAmountCache[cacheKey];
    }

    // Determine which field to use based on the order status
    bool isOrderHistory = ['completed', 'delivered', 'delivery_confirmed'].contains(status);
    String amountFieldToFetch = isOrderHistory ? 'amountPaid' : 'netPayable';

    print('✅ INVOICE ELIGIBLE: Order $orderId has status "$status"');
    print('   - Is History: $isOrderHistory, Fetching Field: "$amountFieldToFetch"');

    try {
      // Search for the invoice linked to this mobile order.
      // We don't need the isDelivered flag anymore, as having a linked invoice is enough.
      final invoiceQuery = await FirebaseFirestore.instance
          .collection('branches') // Always check 'branches' as that's where invoices live
          .doc(branchId)
          .collection('invoices')
          .where('mobileOrderId', isEqualTo: orderId)
          .limit(1)
          .get();

      print('📊 INVOICE SEARCH: Found ${invoiceQuery.docs.length} linked invoices');

      double? result;
      if (invoiceQuery.docs.isNotEmpty) {
        final invoiceData = invoiceQuery.docs.first.data();

        // Fetch the correct amount field based on our logic
        final finalAmount = (invoiceData[amountFieldToFetch] ?? 0.0).toDouble();

        print('✅ INVOICE FOUND:');
        print('   - InvoiceId: ${invoiceQuery.docs.first.id}');
        print('   - Fetched Field "$amountFieldToFetch": $finalAmount');

        result = finalAmount > 0 ? finalAmount : null;
      } else {
        print('⚠️ INVOICE SEARCH: No invoice found for orderId: $orderId');
        result = null;
      }

      // Cache the result with size management
      _cacheInvoiceAmount(cacheKey, result);
      return result;
    } catch (e) {
      print('❌ Error getting invoice amount: $e');
      _cacheInvoiceAmount(cacheKey, null);
      return null;
    }
  }

  void _cacheInvoiceAmount(String key, double? value) {
    if (_invoiceAmountCache.length >= _maxCacheSize) {
      final firstKey = _invoiceAmountCache.keys.first;
      _invoiceAmountCache.remove(firstKey);
    }
    _invoiceAmountCache[key] = value;
  }

  // my_orders_screen.dart

  Widget _buildActiveOrderCard(BuildContext context, Map<String, dynamic> order, String orderId, String branchId) {
    final status = order['status'] as String? ?? 'pending';
    final statusInfo = _getStatusInfo(status);

    // Determine if the blinking animation should be active for delivery statuses.
    final shouldBlink = status == 'delivery_en_route' || status == 'delivery_arrived';

    // The core card widget is built here.
    Widget cardWidget = Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias, // Ensures InkWell ripple effect respects the border radius
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Navigate to the detailed tracking screen when the card is tapped.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Section (Colored part with status)
              _buildCardHeader(context, status, statusInfo, orderId, branchId),

              // 2. Details Section (White part with amounts and estimates)
              _buildCardDetails(context, order, orderId, branchId, status),

              // 3. Footer Section (Date, status badge, and cancel button)
              _buildCardFooter(context, order, status, statusInfo, orderId, branchId),
            ],
          ),
        ),
      ),
    );

    // If the order status requires attention, wrap the card in the blinking animation.
    if (shouldBlink) {
      return AnimatedBuilder(
        animation: _blinkAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(_blinkAnimation.value * 0.4),
                  blurRadius: 10 * _blinkAnimation.value,
                  spreadRadius: 2 * _blinkAnimation.value,
                ),
              ],
            ),
            child: child,
          );
        },
        child: cardWidget,
      );
    }

    return cardWidget;
  }

  /// Builds the colored header section of the active order card.
  Widget _buildCardHeader(BuildContext context, String status, Map<String, dynamic> statusInfo, String orderId, String branchId) {
    final orderNumber = _generateOrderNumber(orderId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusInfo['headerColor'],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(statusInfo['icon'], color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String?>(
                  future: _getInvoiceNumber(orderId, branchId),
                  builder: (context, snapshot) {
                    final invoiceNumber = snapshot.data ?? orderNumber;
                    return Text(
                      'ORDER #$invoiceNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  statusInfo['text'],
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Blinking "COMING" or "ARRIVED" chip for active deliveries.
          if (status == 'delivery_en_route' || status == 'delivery_arrived')
            AnimatedBuilder(
              animation: _blinkAnimation,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2 + (_blinkAnimation.value * 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_shipping, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        status == 'delivery_en_route' ? 'COMING' : 'ARRIVED',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// Builds the main content area of the card with amount and delivery estimates.
  Widget _buildCardDetails(BuildContext context, Map<String, dynamic> order, String orderId, String branchId, String status) {
    final totalAmount = order['totalAmount']?.toDouble() ?? 0.0;
    final deliveryDaysEstimate = order['deliveryDaysEstimate'] as int?;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: Colors.white,
      child: Column(
        children: [
          // Row for displaying the total amount.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Amount',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    FutureBuilder<double?>(
                      future: _getInvoiceAmount(orderId, branchId, status),
                      builder: (context, snapshot) {
                        final displayAmount = snapshot.data ?? totalAmount;
                        final isInvoiceAmount = snapshot.data != null;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${displayAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isInvoiceAmount ? Colors.red[700] : Colors.green[700],
                              ),
                            ),
                            if (isInvoiceAmount)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'FINAL BILL',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Display for the estimated delivery days, if available.
          if (deliveryDaysEstimate != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Approx. Delivery in $deliveryDaysEstimate days',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the footer with date, status badge, and the conditional cancel button.
  Widget _buildCardFooter(BuildContext context, Map<String, dynamic> order, String status, Map<String, dynamic> statusInfo, String orderId, String branchId) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 8),
          // Row for the creation date and the status badge.
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                order['createdAt'] != null ? _formatDate(order['createdAt']) : 'No date',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusInfo['badgeColor'],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusInfo['badge'],
                  style: TextStyle(
                    color: statusInfo['badgeTextColor'],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          // Conditionally display the "Cancel Order" button.
          if (_isCancellable(status)) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                icon: Icon(Icons.cancel_outlined, color: Colors.red[700]),
                label: Text('Cancel Order', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold)),
                onPressed: () => _cancelOrder(orderId, branchId),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  backgroundColor: Colors.red[50],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  // my_orders_screen.dart

  /// Builds a card for an order in the "Order History" tab.
  /// This card is designed to display terminal statuses like 'completed' or 'cancelled'.
  Widget _buildHistoryOrderCard(BuildContext context, Map<String, dynamic> order, String orderId, String branchId) {
    final status = order['status'] as String? ?? 'completed';
    final statusInfo = _getStatusInfo(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Section (Colored part with final status)
            _buildHistoryCardHeader(context, statusInfo, orderId, branchId),

            // 2. Details Section (White part with final amounts)
            _buildHistoryCardDetails(context, order, orderId, branchId, status),

            // 3. Footer Section (Date and final status badge)
            _buildHistoryCardFooter(context, order, statusInfo),
          ],
        ),
      ),
    );
  }

  /// Builds the colored header section for the history card.
  Widget _buildHistoryCardHeader(BuildContext context, Map<String, dynamic> statusInfo, String orderId, String branchId) {
    final orderNumber = _generateOrderNumber(orderId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: statusInfo['headerColor']),
      child: Row(
        children: [
          Icon(statusInfo['icon'], color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String?>(
                  future: _getInvoiceNumber(orderId, branchId),
                  builder: (context, snapshot) {
                    final invoiceNumber = snapshot.data ?? orderNumber;
                    return Text(
                      'ORDER #$invoiceNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  statusInfo['text'], // Dynamic text: "Order Completed" or "Order Cancelled"
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the main content area of the history card.
  Widget _buildHistoryCardDetails(BuildContext context, Map<String, dynamic> order, String orderId, String branchId, String status) {
    final totalAmount = order['totalAmount']?.toDouble() ?? 0.0;
    final deliveryDaysEstimate = order['deliveryDaysEstimate'] as int?;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          // Row for amount and the conditional "View PDF" button.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // The label changes based on whether the order was paid or cancelled.
                      status == 'cancelled' ? 'Total Amount' : 'Total Paid',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    FutureBuilder<double?>(
                      future: _getInvoiceAmount(orderId, branchId, status),
                      builder: (context, snapshot) {
                        final displayAmount = snapshot.data ?? totalAmount;
                        return Text(
                          '${displayAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            // Completed orders are green, cancelled are grey.
                            color: status == 'completed' ? Colors.green[800] : Colors.grey[700],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // The "View PDF" button is only shown for completed orders.
              if (status != 'cancelled')
                GestureDetector(
                  onTap: () => _viewInvoicePDF(context, orderId, branchId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf, size: 16, color: Colors.red[700]),
                        const SizedBox(width: 6),
                        Text(
                          'View PDF',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          // Delivery estimate is only relevant for completed orders.
          if (status != 'cancelled' && deliveryDaysEstimate != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Delivered within $deliveryDaysEstimate day estimate',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the footer for the history card with date and the final status badge.
  Widget _buildHistoryCardFooter(BuildContext context, Map<String, dynamic> order, Map<String, dynamic> statusInfo) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                order['createdAt'] != null ? _formatDate(order['createdAt']) : 'No date',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusInfo['badgeColor'],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusInfo['badge'],
                  style: TextStyle(
                    color: statusInfo['badgeTextColor'],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _generateOrderNumber(String orderId) {
    // Generate a professional order number like the invoice format
    final hash = orderId.hashCode.abs();
    return '${hash.toString().substring(0, 5)}${DateTime.now().year.toString().substring(2)}';
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
        return {
          'icon': Icons.schedule,
          'text': 'Waiting for confirmation',
          'badge': 'PENDING',
          'headerColor': Colors.orange[600],
          'badgeColor': Colors.orange[100],
          'badgeTextColor': Colors.orange[800],
        };
      case 'confirmed':
        return {
          'icon': Icons.check_circle,
          'text': 'Driver assigned',
          'badge': 'CONFIRMED',
          'headerColor': Colors.blue[600],
          'badgeColor': Colors.blue[100],
          'badgeTextColor': Colors.blue[800],
        };
      case 'en_route':
        return {
          'icon': Icons.local_shipping,
          'text': 'Driver coming to collect',
          'badge': 'EN ROUTE',
          'headerColor': Colors.purple[600],
          'badgeColor': Colors.purple[100],
          'badgeTextColor': Colors.purple[800],
        };
      case 'arrived':
        return {
          'icon': Icons.location_on,
          'text': 'Driver at your location',
          'badge': 'ARRIVED',
          'headerColor': Colors.indigo[600],
          'badgeColor': Colors.indigo[100],
          'badgeTextColor': Colors.indigo[800],
        };
      case 'collected':
        return {
          'icon': Icons.inventory,
          'text': 'Items collected by driver',
          'badge': 'COLLECTED',
          'headerColor': Colors.teal[600],
          'badgeColor': Colors.teal[100],
          'badgeTextColor': Colors.teal[800],
        };
      case 'customer_confirmed':
        return {
          'icon': Icons.verified,
          'text': 'Collection confirmed',
          'badge': 'CONFIRMED',
          'headerColor': Colors.green[600],
          'badgeColor': Colors.green[100],
          'badgeTextColor': Colors.green[800],
        };
      case 'delivered_to_shop':
      case 'at_laundry':
        return {
          'icon': Icons.local_laundry_service,
          'text': 'Items at laundry shop',
          'badge': 'AT SHOP',
          'headerColor': Colors.cyan[600],
          'badgeColor': Colors.cyan[100],
          'badgeTextColor': Colors.cyan[800],
        };
      case 'processing':
        return {
          'icon': Icons.cleaning_services,
          'text': 'Items being processed',
          'badge': 'PROCESSING',
          'headerColor': Colors.lightBlue[600],
          'badgeColor': Colors.lightBlue[100],
          'badgeTextColor': Colors.lightBlue[800],
        };
      case 'ready_for_delivery':
        return {
          'icon': Icons.done_all,
          'text': 'Ready for delivery',
          'badge': 'READY',
          'headerColor': Colors.lime[700],
          'badgeColor': Colors.lime[100],
          'badgeTextColor': Colors.lime[800],
        };
      case 'delivery_en_route':
        return {
          'icon': Icons.delivery_dining,
          'text': 'Driver bringing clean clothes',
          'badge': 'DELIVERING',
          'headerColor': Colors.deepOrange[600],
          'badgeColor': Colors.deepOrange[100],
          'badgeTextColor': Colors.deepOrange[800],
        };
      case 'delivery_arrived':
        return {
          'icon': Icons.home,
          'text': 'Driver arrived with clothes',
          'badge': 'ARRIVED',
          'headerColor': Colors.red[600],
          'badgeColor': Colors.red[100],
          'badgeTextColor': Colors.red[800],
        };
      case 'delivered':
        return {
          'icon': Icons.check_circle_outline,
          'text': 'Items delivered',
          'badge': 'DELIVERED',
          'headerColor': Colors.green[700],
          'badgeColor': Colors.green[100],
          'badgeTextColor': Colors.green[800],
        };
      case 'completed':
        return {
          'icon': Icons.celebration,
          'text': 'Order completed',
          'badge': 'COMPLETED',
          'headerColor': Colors.green[800],
          'badgeColor': Colors.green[100],
          'badgeTextColor': Colors.green[800],
        };
      case 'cancelled':
        return {
          'icon': Icons.cancel,
          'text': 'Order was cancelled',
          'badge': 'CANCELLED',
          'headerColor': Colors.grey[600],
          'badgeColor': Colors.grey[200],
          'badgeTextColor': Colors.grey[800],
        };
      default:
        return {
          'icon': Icons.help_outline,
          'text': 'Unknown status',
          'badge': 'UNKNOWN',
          'headerColor': Colors.grey[600],
          'badgeColor': Colors.grey[100],
          'badgeTextColor': Colors.grey[800],
        };
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return 'Pending';
      case 'confirmed': return 'Driver Assigned';
      case 'en_route': return 'Driver En Route';
      case 'arrived': return 'Driver Arrived';
      case 'collected': return 'Items Collected';
      case 'customer_confirmed': return 'Customer Confirmed';
      case 'at_laundry': return 'At Laundry';
      case 'completed': return 'Completed';
      case 'delivered': return 'Delivered';
      default: return status.toUpperCase();
    }
  }

  String _formatDate(dynamic timestamp) {
    try {
      if (timestamp is Timestamp) {
        final DateTime date = timestamp.toDate();
        // You might need to add the intl package if not already present:
        // import 'package:intl/intl.dart';
        return DateFormat('MMM dd, yyyy').format(date);
      }
      return 'No date';
    } catch (e) {
      return 'Invalid date';
    }
  }

// Add this helper method
  String _formatFullDateTime(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final isYesterday = now.difference(date).inDays == 1;

    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (isToday) {
      return 'Today $timeStr';
    } else if (isYesterday) {
      return 'Yesterday $timeStr';
    } else {
      return '${date.day}/${date.month}/${date.year} $timeStr';
    }
  }

  Future<void> _viewInvoicePDF(BuildContext context, String orderId, String branchId) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating invoice PDF...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Get customer phone number (same method as order history)
      final phoneNumber = await _getUserPhoneNumber();
      QuerySnapshot invoiceDoc;

      // Search by specific mobileOrderId first (most accurate)
      invoiceDoc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('invoices')
          .where('mobileOrderId', isEqualTo: orderId)
          .limit(1)
          .get();

// If not found, fallback to phone number search
      if (invoiceDoc.docs.isEmpty && phoneNumber != null && phoneNumber.isNotEmpty) {
        invoiceDoc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('invoices')
            .where('customerInfo.mobile', isEqualTo: phoneNumber)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

        // Also try 'phone' field if mobile search fails
        if (invoiceDoc.docs.isEmpty) {
          invoiceDoc = await FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .collection('invoices')
              .where('customerInfo.phone', isEqualTo: phoneNumber)
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();
        }
      }


      navigator.pop(); // Close loading dialog

      if (invoiceDoc.docs.isEmpty) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Invoice not found for this order')),
        );
        return;
      }

      final data = invoiceDoc.docs.first.data();
      if (data == null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Invoice data is invalid')),
        );
        return;
      }
      
      final invoiceData = data as Map<String, dynamic>;
      
      navigator.push(
        MaterialPageRoute(
          builder: (context) => InvoicePDFViewer(
            invoiceData: invoiceData,
            invoiceId: invoiceDoc.docs.first.id,
          ),
        ),
      );
    } catch (e) {
      navigator.pop(); // Close loading dialog if still open
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error loading invoice: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _getDeliveryTimeColor(Timestamp expectedDelivery, String status) {
    final now = DateTime.now();
    final deliveryTime = expectedDelivery.toDate();
    final isOverdue = deliveryTime.isBefore(now);
    final isCompleted = ['delivered', 'completed', 'delivery_confirmed'].contains(status);

    if (isCompleted) {
      return Colors.green[50]!;
    } else if (isOverdue) {
      return Colors.red[50]!;
    } else {
      return Colors.blue[50]!;
    }
  }

  Color _getDeliveryTimeBorderColor(Timestamp expectedDelivery, String status) {
    final now = DateTime.now();
    final deliveryTime = expectedDelivery.toDate();
    final isOverdue = deliveryTime.isBefore(now);
    final isCompleted = ['delivered', 'completed', 'delivery_confirmed'].contains(status);

    if (isCompleted) {
      return Colors.green[200]!;
    } else if (isOverdue) {
      return Colors.red[200]!;
    } else {
      return Colors.blue[200]!;
    }
  }

  Color _getDeliveryTimeTextColor(Timestamp expectedDelivery, String status) {
    final now = DateTime.now();
    final deliveryTime = expectedDelivery.toDate();
    final isOverdue = deliveryTime.isBefore(now);
    final isCompleted = ['delivered', 'completed', 'delivery_confirmed'].contains(status);

    if (isCompleted) {
      return Colors.green[700]!;
    } else if (isOverdue) {
      return Colors.red[700]!;
    } else {
      return Colors.blue[700]!;
    }
  }

  IconData _getDeliveryTimeIcon(Timestamp expectedDelivery, String status) {
    final now = DateTime.now();
    final deliveryTime = expectedDelivery.toDate();
    final isOverdue = deliveryTime.isBefore(now);
    final isCompleted = ['delivered', 'completed', 'delivery_confirmed'].contains(status);

    if (isCompleted) {
      return Icons.check_circle;
    } else if (isOverdue) {
      return Icons.warning;
    } else {
      return Icons.schedule;
    }
  }

  String _getDeliveryTimeText(Timestamp expectedDelivery, String status) {
    final now = DateTime.now();
    final deliveryTime = expectedDelivery.toDate();
    final isOverdue = deliveryTime.isBefore(now);
    final isCompleted = ['delivered', 'completed', 'delivery_confirmed'].contains(status);
    
    final formattedTime = _formatDateTime(expectedDelivery);

    if (isCompleted) {
      return 'Delivered ✓';
    } else if (isOverdue) {
      return 'Overdue - Expected: $formattedTime';
    } else {
      final timeUntil = _getTimeUntilDelivery(deliveryTime);
      return 'Expected delivery: $formattedTime ($timeUntil)';
    }
  }

  String _formatDateTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = date.difference(now);
    
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Tomorrow ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == -1) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  String _getTimeUntilDelivery(DateTime deliveryTime) {
    final now = DateTime.now();
    final difference = deliveryTime.difference(now);
    
    if (difference.isNegative) {
      final overdueDuration = now.difference(deliveryTime);
      if (overdueDuration.inDays > 0) {
        return '${overdueDuration.inDays}d overdue';
      } else if (overdueDuration.inHours > 0) {
        return '${overdueDuration.inHours}h overdue';
      } else {
        return '${overdueDuration.inMinutes}m overdue';
      }
    }
    
    if (difference.inDays > 0) {
      return 'in ${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return 'in ${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return 'in ${difference.inMinutes}m';
    } else {
      return 'very soon';
    }
  }



  Future<void> _cancelOrder(String orderId, String branchId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text('Are you sure you want to cancel this order? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Cancel'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('mobileOrders')
            .doc(orderId)
            .update({
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'Cancelled by customer',
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order cancelled successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to cancel order: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }





}
