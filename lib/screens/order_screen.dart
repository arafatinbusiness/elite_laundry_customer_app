import 'package:elite_laundry_customer_app/screens/widgets/order_widgets.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/order_logic.dart';
import 'home/customer_order_tracking_screen.dart';
import 'select_branch_for_order_screen.dart'; // <-- 1. IMPORT THE NEW SCREEN

class OrderScreen extends StatefulWidget {
  const OrderScreen({Key? key}) : super(key: key);

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final OrderLogic _orderLogic;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _orderLogic = OrderLogic(
      // === FIX: MAKE THE CALLBACK SAFER ===
      onStateChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
      onError: _showError,
    );
    _loadUserDataAndServices();
  }

  Future<void> _loadUserDataAndServices() async {
    await _loadUserData();
    await _orderLogic.loadData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          _nameController.text = userData['name'] ?? user.displayName ?? '';
          _phoneController.text = userData['phone'] ?? '';
        } else if (user.displayName != null) {
          _nameController.text = user.displayName!;
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _orderLogic.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _onSearchChanged(String query) => _orderLogic.updateSearchQuery(query);

  void _onCategorySelected(String? categoryId) =>
      _orderLogic.selectCategory(categoryId);

  void _onServiceToggle(Map<String, dynamic> service) =>
      _orderLogic.toggleService(service);

  void _onQuantityUpdate(String serviceId, int quantity) =>
      _orderLogic.updateQuantity(serviceId, quantity);

  // === 2. NEW MASTER FUNCTION TO HANDLE ORDER PLACEMENT ===
  Future<void> _handleOrderPlacement(bool isSmartOrder) async {
    // Validate that we have customer data
    if (_nameController.text
        .trim()
        .isEmpty || _phoneController.text
        .trim()
        .isEmpty) {
      _showError(
          'Please complete your profile with name and phone number to place orders');
      return;
    }

    // The minimum order check is now REMOVED from here.

    // REQUIREMENT: Re-confirm Location Before Order
    final selectedBranch = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
          builder: (context) => const SelectBranchForOrderScreen()),
    );

    if (selectedBranch == null || !mounted) return; // User cancelled

    final newBranchId = selectedBranch['id'] as String;
    final currentBranchId = _orderLogic
        .getCurrentBranchId(); // Use the new getter
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showError('You must be logged in to place an order.');
      return;
    }

    // REQUIREMENT: Branch Switching & User Migration Logic
    if (newBranchId != currentBranchId) {
      final migrationSuccess = await _handleUserMigration(
        userId: user.uid,
        oldBranchId: currentBranchId!,
        newBranchId: newBranchId,
      );

      if (!migrationSuccess) {
        _showError('Could not switch branch. Please try again.');
        return;
      }

      await _orderLogic.updateBranch(newBranchId);
      _orderLogic.clearSelection(); // Clear the cart after switching

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Branch updated! Showing services for your new location.'),
          backgroundColor: Colors.blue,
        ),
      );
      // Stop the flow. The user now sees the new services and must tap the order button again.
      return;
    }

    // If the branch is the same, proceed with the original flow
    final confirmed = isSmartOrder
        ? await _showSmartOrderConfirmationDialog()
        : await _showOrderConfirmationDialog();

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final success = isSmartOrder
        ? await _orderLogic.submitSmartOrder(
      customerName: _nameController.text.trim(),
      customerPhone: _phoneController.text.trim(),
      customerEmail: user.email,
    )
        : await _orderLogic.submitOrder(
      customerName: _nameController.text.trim(),
      customerPhone: _phoneController.text.trim(),
      customerEmail: user.email,
    );

    setState(() => _isSubmitting = false);

    if (success) {
      _showSuccessSnackbar(isSmartOrder);
      _orderLogic.clearSelection();
    }
  }

  // === 3. NEW MIGRATION FUNCTION ===
  Future<bool> _handleUserMigration({
    required String userId,
    required String oldBranchId,
    required String newBranchId,
  }) async {
    setState(() => _isSubmitting = true);
    final firestore = FirebaseFirestore.instance;

    try {
      // First, check if the user exists in the old branch
      final oldUserDoc = await firestore
          .collection('branches')
          .doc(oldBranchId)
          .collection('mobileUsers')
          .doc(userId)
          .get();

      if (!oldUserDoc.exists) {
        // User doesn't exist in old branch, just update main user document
        await firestore.collection('users').doc(userId).update({
          'branchId': newBranchId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print(
            'ℹ️ User not found in old branch $oldBranchId, only updated main user document');
        setState(() => _isSubmitting = false);
        return true;
      }

      final oldUserData = oldUserDoc.data()!;

      // Check if balance exists in old branch
      final oldBalanceDoc = await firestore
          .collection('branches')
          .doc(oldBranchId)
          .collection('mobileUsers')
          .doc(userId)
          .collection('user_eBalance')
          .doc('balance')
          .get();

      // Use individual operations instead of a single transaction to avoid timeout issues
      final batch = firestore.batch();

      // 1. Create user in new branch
      batch.set(
        firestore.collection('branches').doc(newBranchId).collection(
            'mobileUsers').doc(userId),
        oldUserData,
      );

      // 2. Delete user from old branch
      batch.delete(
        firestore.collection('branches').doc(oldBranchId).collection(
            'mobileUsers').doc(userId),
      );

      // 3. Update main user document
      batch.update(
        firestore.collection('users').doc(userId),
        {'branchId': newBranchId},
      );

      // 4. Handle balance migration
      if (oldBalanceDoc.exists) {
        final oldBalanceData = oldBalanceDoc.data()!;
        batch.set(
          firestore.collection('branches').doc(newBranchId).collection(
              'mobileUsers').doc(userId).collection('user_eBalance').doc(
              'balance'),
          oldBalanceData,
        );
        batch.delete(
          firestore.collection('branches').doc(oldBranchId).collection(
              'mobileUsers').doc(userId).collection('user_eBalance').doc(
              'balance'),
        );
        print('✅ eBalance migrated from $oldBranchId to $newBranchId');
      } else {
        // Create default balance in new branch
        batch.set(
          firestore.collection('branches').doc(newBranchId).collection(
              'mobileUsers').doc(userId).collection('user_eBalance').doc(
              'balance'),
          {
            'main_balance': 0,
            'percent_balance': 0,
            'lastUpdated': FieldValue.serverTimestamp(),
          },
        );
        print('✅ Default eBalance created in new branch $newBranchId');
      }

      // Commit the batch
      await batch.commit();

      print('✅ User migration successful from $oldBranchId to $newBranchId');
      setState(() => _isSubmitting = false);
      return true;
    } catch (e) {
      print('❌ User migration failed: $e');
      print('❌ Stack trace: ${e.toString()}');
      _showError('Failed to migrate user data. Please try again. Error: ${e
          .toString()}');
      setState(() => _isSubmitting = false);
      return false;
    }
  }

  // === 4. REPLACE OLD METHODS WITH SIMPLE CALLS TO THE NEW MASTER FUNCTION ===
  Future<void> _onPlaceOrder() async => await _handleOrderPlacement(false);

  Future<void> _onPlaceSmartOrder() async => await _handleOrderPlacement(true);

  // Helper for success snackbar
  void _showSuccessSnackbar(bool isSmartOrder) {
    final latestOrderId = _orderLogic.lastOrderId;
    final message = isSmartOrder
        ? 'Smart order placed! Bring your items to the branch.'
        : 'Order submitted successfully!';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        action: latestOrderId != null ? SnackBarAction(
          label: 'Track Order',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    CustomerOrderTrackingScreen(
                      orderId: latestOrderId,
                      branchId: _orderLogic.branchId!,
                    ),
              ),
            );
          },
        ) : null,
      ),
    );
  }

  // === 5. ADD MINIMUM ORDER NOTICE TO CONFIRMATION DIALOG ===
  Future<bool?> _showOrderConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AlertDialog(
            title: const Text('Confirm Your Order'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Your existing content for customer and order summary...
                  Container(/* Customer Details Widget */),
                  const SizedBox(height: 16),
                  Container(/* Order Summary Widget */),
                  const SizedBox(height: 16),

                  // NEW NOTICE WIDGET
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[800]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'A minimum order amount of \$20.00 is required.',
                            style: TextStyle(color: Colors.orange[800],
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Confirm Order')),
            ],
          ),
    );
  }

  Future<bool?> _showSmartOrderConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Color(0xFF059669)),
                SizedBox(width: 8),
                Text('Confirm Smart Order'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer info display (read-only)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customer Details:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.person, size: 16,
                                color: Colors.blue[600]),
                            const SizedBox(width: 8),
                            Text(_nameController.text.trim()),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                                Icons.phone, size: 16, color: Colors.blue[600]),
                            const SizedBox(width: 8),
                            Text(_phoneController.text.trim()),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Smart Order Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF059669).withOpacity(0.3)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb, color: Color(0xFF059669),
                                size: 20),
                            SizedBox(width: 8),
                            Text(
                              'How Smart Order Works:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Text('1. Place your smart order now',
                            style: TextStyle(fontSize: 14)),
                        Text('2. Bring your items to the laundry',
                            style: TextStyle(fontSize: 14)),
                        Text('3. Our staff will determine the best services',
                            style: TextStyle(fontSize: 14)),
                        Text(
                            '4. Final price calculated based on actual services',
                            style: TextStyle(fontSize: 14)),
                        SizedBox(height: 12),
                        Text(
                          '✨ Perfect for mixed loads or when unsure!',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF059669),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===============================================
                  // === NEW MINIMUM ORDER NOTICE WIDGET IS HERE ===
                  // ===============================================
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[800]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Please note: The final invoice is subject to our standard \$20.00 minimum order amount.',
                            style: TextStyle(
                              color: Colors.orange[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ===============================================
                  // === END OF NEW WIDGET =========================
                  // ===============================================

                  const SizedBox(height: 16),

                  // Final total info box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Total amount: To be determined by staff based on your items.',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm Smart Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Order Now'),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _orderLogic.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Use a StatefulBuilder to preserve search bar state
          _buildSearchBar(),
          // Use a StatefulBuilder to preserve category tabs state
          _buildCategoryTabs(),
          Expanded(
            child: OrderWidgets.buildServicesList(
              services: _orderLogic.filteredServices,
              selectedServices: _orderLogic.selectedServices,
              onServiceToggle: _onServiceToggle,
              onQuantityUpdate: _onQuantityUpdate,
            ),
          ),
          if (_orderLogic.selectedServices.isNotEmpty)
            OrderWidgets.buildOrderSummary(
              selectedServices: _orderLogic.selectedServices,
              total: _orderLogic.calculateTotal(),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search services...',
          prefixIcon: const Icon(Icons.search, color: Color(0xFF1E40AF)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E40AF)),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _orderLogic.categories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCategoryChip('All', null);
          }
          final category = _orderLogic.categories[index - 1];
          return _buildCategoryChip(
            category['name'] ?? 'Category',
            category['id'],
          );
        },
      ),
    );
  }

  Widget _buildCategoryChip(String name, String? categoryId) {
    final isSelected = _orderLogic.selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(name),
        selected: isSelected,
        onSelected: (_) => _onCategorySelected(categoryId),
        selectedColor: const Color(0xFF1E40AF).withOpacity(0.2),
        checkmarkColor: const Color(0xFF1E40AF),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    if (_orderLogic.selectedServices.isNotEmpty) {
      // Show regular order button when services are selected
      return OrderWidgets.buildBottomBar(
        total: _orderLogic.calculateTotal(),
        onPlaceOrder: _isSubmitting ? null : _onPlaceOrder,
        isLoading: _isSubmitting,
      );
    } else {
      // Show smart order option when no services selected
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Professional Smart Order Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _onPlaceSmartOrder,
                  icon: _isSubmitting
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Icon(Icons.auto_awesome, size: 22),
                  label: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _isSubmitting ? 'Placing Order...\n' : 'Let Cashier Decide\n',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                            height: 1.3,
                          ),
                        ),
                        TextSpan(
                          text: _isSubmitting ? 'جاري إرسال الطلب...' : 'دع الكاشير يقرر',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 18, // Bigger font size for Arabic
                            fontWeight: FontWeight.bold, // Bold Arabic
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    shadowColor: const Color(0xFF059669).withOpacity(0.3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFD1FAE5),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFF059669)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            const TextSpan(
                              text: 'For mixed items or when unsure\n',
                              style: TextStyle(
                                color: Color(0xFF065F46),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                            const TextSpan(
                              text: 'للأصناف المختلطة أو عند عدم التأكد',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                color: Color(0xFF065F46),
                                fontSize: 14, // Bigger font size for Arabic
                                fontWeight: FontWeight.bold, // Bold Arabic
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}
