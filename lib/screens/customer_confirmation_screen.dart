import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomerConfirmationScreen extends StatefulWidget {
  final String orderId;
  final String branchId;
  final Map<String, dynamic> orderData;
  final bool isDelivery;
  final String? initialPaymentMethod;

  const CustomerConfirmationScreen({
    Key? key,
    required this.orderId,
    required this.branchId,
    required this.orderData,
    this.isDelivery = false,
    this.initialPaymentMethod,
  }) : super(key: key);

  @override
  State<CustomerConfirmationScreen> createState() => _CustomerConfirmationScreenState();
}

class _CustomerConfirmationScreenState extends State<CustomerConfirmationScreen> {
  bool _isConfirming = false;
  bool _showPayment = false;
  String _selectedPaymentMethod = '';
  Map<String, dynamic>? _customerData;
  double _amountPaid = 0.0;
  bool _isPaymentProcessing = false;
  double _paymentProgress = 0.0;
  String _progressMessage = '';
  @override
  void initState() {
    super.initState();
    if (widget.isDelivery) {
      _loadCustomerData();
      _loadInvoiceAmount();
      // Auto-show payment if initial payment method is provided
      if (widget.initialPaymentMethod != null) {
        _selectedPaymentMethod = widget.initialPaymentMethod!;
        _showPayment = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDelivery ? 'Confirm Delivery' : 'Confirm Collection'),
        backgroundColor: Color(0xFF1E40AF),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDriverInfo(),
                    SizedBox(height: 24),
                    _buildOrderInfo(),
                    SizedBox(height: 24),
                    if (widget.isDelivery && !_showPayment)
                      _buildDeliveryInfo(),
                    if (widget.isDelivery && !_showPayment)
                      SizedBox(height: 24),
                    if (widget.isDelivery && _showPayment)
                      _buildPaymentSection(),
                    if (widget.isDelivery && _showPayment)
                      SizedBox(height: 24),
                    if (!widget.isDelivery)
                      _buildConfirmationSection(),
                    if (!widget.isDelivery)
                      SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: _buildActionButtons(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverInfo() {
    final driverData = widget.orderData;
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_shipping, color: Color(0xFF1E40AF), size: 24),
                SizedBox(width: 8),
                Text(
                  'Driver Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text('Driver ID: ${driverData['driverId']?.substring(0, 8) ?? 'N/A'}'),
            Text('Status: Items collected'),
            Text('Time: ${_formatTime(driverData['collectedAt'])}'),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderInfo() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt, color: Color(0xFF1E40AF), size: 24),
                SizedBox(width: 8),
                Text(
                  'Order Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text('Order #${widget.orderId.substring(0, 8)}'),
            if (widget.orderData['orderType'] == 'smart') ...[
              Text('Type: Smart Order'),
              Text('Services: To be determined by staff'),
            ] else ...[
              Text('Services: ${widget.orderData['services']?.length ?? 0} items'),
              Text('Total: ${widget.orderData['totalAmount']?.toStringAsFixed(2) ?? '0.00'}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationSection() {
    return Card(
      elevation: 2,
      color: Colors.orange[50],
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.orange[700], size: 24),
                SizedBox(width: 8),
                Text(
                  'Confirmation Required',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'The driver has marked your items as collected. Please confirm that:',
              style: TextStyle(color: Colors.orange[800]),
            ),
            SizedBox(height: 12),
            _buildChecklistItem('Driver arrived at your location'),
            _buildChecklistItem('You handed over your laundry items'),
            _buildChecklistItem('You are satisfied with the service'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Text(
                'By confirming, you agree that the driver has successfully collected your items and can proceed to the laundry.',
                style: TextStyle(
                  color: Colors.orange[800],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistItem(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.orange[700], size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.orange[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (widget.isDelivery) {
      return _buildDeliveryActionButtons();
    } else {
      return _buildCollectionActionButtons();
    }
  }

  Widget _buildCollectionActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isConfirming ? null : () {
              print('🔥 Confirm Collection button pressed');
              _confirmCollection();
            },
            child: _isConfirming
                ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Confirming...'),
              ],
            )
                : Text(
              'Confirm Collection',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
          ),
        ),
        SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _isConfirming ? null : () {
              print('🔥 Report Issue button pressed');
              _reportIssue();
            },
            child: Text('Report Issue'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red),
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryActionButtons() {
    if (!_showPayment) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _showPayment = true;
                });
              },
              child: Text(
                'Proceed to Payment',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                _reportIssue();
              },
              child: Text('Report Issue'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: BorderSide(color: Colors.red),
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedPaymentMethod.isEmpty || _isPaymentProcessing) ? null : () {
                _processPayment();
              },
              child: _isPaymentProcessing
                  ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      value: _paymentProgress,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '${(_paymentProgress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _progressMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
                  : Text(
                'Pay ${_amountPaid.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isPaymentProcessing ? null : () {
                    setState(() {
                      _showPayment = false;
                      _selectedPaymentMethod = '';
                    });
                  },
                  child: Text('Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isPaymentProcessing ? null : () {
                    _reportIssue();
                  },
                  child: Text('Report Issue'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }
  }

  Future<void> _processPayment() async {
    if (_isPaymentProcessing) return;

    setState(() => _isPaymentProcessing = true);

    try {
      bool paymentSuccess = false;

      switch (_selectedPaymentMethod) {
        case 'eBalance':
          paymentSuccess = await _processEBalancePayment();
          break;
        case 'Cash':
          paymentSuccess = await _processCashPayment();
          break;
        case 'Bank':
          paymentSuccess = await _processBankPayment();
          break;
        case 'Sabaka Machine':
          paymentSuccess = await _processSabakaPayment();
          break;
        default:
          throw Exception('Invalid payment method');
      }

      if (paymentSuccess) {
        await _confirmDelivery();
      }
    } catch (e) {
      print('❌ Payment error: $e');
      _showErrorDialog('Payment failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isPaymentProcessing = false;
          _paymentProgress = 0.0; // Reset progress
          _progressMessage = '';   // Reset message
        });
      }
    }

  }

  Future<bool> _processEBalancePayment() async {
    try {
      setState(() {
        _paymentProgress = 0.1;
        _progressMessage = 'Validating payment...';
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      setState(() {
        _paymentProgress = 0.3;
        _progressMessage = 'Processing customer payment...';
      });

      // Customer payment transaction
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final customerBalanceRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('mobileUsers')
            .doc(user.uid)
            .collection('user_eBalance')
            .doc('balance');

        final branchBalanceRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('branch_eBalance')
            .doc('balance');

        final customerSnapshot = await transaction.get(customerBalanceRef);
        final branchSnapshot = await transaction.get(branchBalanceRef);

        final customerBalance = (customerSnapshot.data()?['main_balance'] ?? 0.0).toDouble();
        final branchWithdrawBalance = (branchSnapshot.data()?['withdraw_balance'] ?? 0.0).toDouble();

        if (customerBalance < _amountPaid) {
          throw Exception('Insufficient balance');
        }

        transaction.update(customerBalanceRef, {
          'main_balance': customerBalance - _amountPaid,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        transaction.update(branchBalanceRef, {
          'withdraw_balance': branchWithdrawBalance + _amountPaid,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });

      setState(() {
        _paymentProgress = 0.7;
        _progressMessage = 'Transferring driver commission...';
      });

      await _transferDriverCommission();

      setState(() {
        _paymentProgress = 1.0;
        _progressMessage = 'Payment completed!';
      });

      await Future.delayed(Duration(milliseconds: 500));
      return true;
    } catch (e) {
      print('❌ eBalance payment error: $e');
      return false;
    }
  }




  Future<bool> _processCashPayment() async {
  try {
  print('💵 Processing cash payment of ${_amountPaid.toStringAsFixed(2)}');
  
  // Simulate payment processing delay
  await Future.delayed(Duration(seconds: 1));
  
  // Transfer commission to driver
  await _transferDriverCommission();
  
  print('✅ Cash payment confirmed');
  
  ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('✅ Cash payment confirmed!'),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 2),
    ),
    );
  
  return true;
  } catch (e) {
      print('❌ Cash payment error: $e');
      return false;
    }
  }

  Future<bool> _processBankPayment() async {
    try {
      print('🏦 Processing bank payment of ${_amountPaid.toStringAsFixed(2)}');

      // Show confirmation dialog
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Bank Payment'),
          content: Text('Please confirm that you have transferred ${_amountPaid.toStringAsFixed(2)} via bank transfer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Confirmed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
      // Simulate processing delay
      await Future.delayed(Duration(seconds: 2));
      
      // Transfer commission to driver
      await _transferDriverCommission();
      
      print('✅ Bank payment successful');
      
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Bank payment successful!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
        );
        
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Bank payment error: $e');
      return false;
    }
  }

  Future<bool> _processSabakaPayment() async {
    try {
      print('💳 Processing Sabaka machine payment of ${_amountPaid.toStringAsFixed(2)}');

      // Show confirmation dialog
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Sabaka Payment'),
          content: Text('Please complete the payment of ${_amountPaid.toStringAsFixed(2)} on the Sabaka machine.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Payment Complete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
      // Simulate processing delay
      await Future.delayed(Duration(seconds: 3));
      
      // Transfer commission to driver
      await _transferDriverCommission();
      
      print('✅ Sabaka payment successful');
      
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Sabaka payment successful!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
        );
        
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Sabaka payment error: $e');
      return false;
    }
  }

  Future<void> _transferDriverCommission() async {
    try {
      final driverId = widget.orderData['driverId'];
      if (driverId == null) {
        print('⚠️ No driver ID found, skipping commission transfer');
        return;
      }

      final commission = _amountPaid * 0.05; // 5% commission
      print('💰 Transferring ${commission.toStringAsFixed(2)} commission to driver: $driverId');

      // Static city agent ID from your example
      const cityAgentId = 'ZEpjngzKmuhfoAnDdNeAIeL0A192';
      final driverBalancePath = '/cityAgents/$cityAgentId/drivers/$driverId/driver_eBalance/balance';

      // Get references to Firestore documents
      final adminRef = FirebaseFirestore.instance.doc('/admin_eBalance/admin_eBalance');
      final driverRef = FirebaseFirestore.instance.doc(driverBalancePath);

      // Run the transaction
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Get current balances
        final adminSnapshot = await transaction.get(adminRef);
        final driverSnapshot = await transaction.get(driverRef);

        final adminPercentBalance = (adminSnapshot.data()?['percent_balance'] ?? 0.0).toDouble();
        final driverWithdrawBalance = (driverSnapshot.data()?['withdraw_balance'] ?? 0.0).toDouble();

        // Verify admin has sufficient balance
        if (adminPercentBalance < commission) {
          throw Exception('Admin has insufficient balance for commission');
        }

        // Update only the specified fields
        transaction.update(adminRef, {
          'percent_balance': adminPercentBalance - commission,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        // Update ONLY the withdraw_balance field, preserving all others
        transaction.update(driverRef, {
          'withdraw_balance': driverWithdrawBalance + commission,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        // Create transaction record
        final transactionRef = FirebaseFirestore.instance.collection('commissionTransactions').doc();
        transaction.set(transactionRef, {
          'orderId': widget.orderId,
          'cityAgentId': cityAgentId,
          'driverId': driverId,
          'amount': commission,
          'amountPaid': _amountPaid,
          'percentage': 5,
          'adminBalanceBefore': adminPercentBalance,
          'adminBalanceAfter': adminPercentBalance - commission,
          'driverBalanceBefore': driverWithdrawBalance,
          'driverBalanceAfter': driverWithdrawBalance + commission,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'completed',
          'paymentMethod': _selectedPaymentMethod,
          'branchId': widget.branchId,
        });

        print('✅ Commission transferred successfully. Driver $driverId received ${commission.toStringAsFixed(2)}');
        print('📊 Admin percent_balance: ${(adminPercentBalance - commission).toStringAsFixed(2)}');
        print('📊 Driver withdraw_balance: ${(driverWithdrawBalance + commission).toStringAsFixed(2)}');
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Commission transferred: ${commission.toStringAsFixed(2)} to driver'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('❌ Commission transfer failed: $e');

      rethrow;
    }
  }

  Future<void> _confirmDelivery() async {
    try {
      print('🎯 Confirming delivery and completing order');
      print('🎯 Branch ID: ${widget.branchId}');
      print('🎯 Order ID: ${widget.orderId}');
      
      // Update the order status in the database
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('mobileOrders')
          .doc(widget.orderId)
          .update({
        'status': 'delivery_confirmed',
        'deliveryConfirmedAt': FieldValue.serverTimestamp(),
        'paymentMethod': _selectedPaymentMethod,
        'finalAmountPaid': _amountPaid,
        'paymentCompleted': true, // Add this flag
      });

      await Future.delayed(Duration(milliseconds: 300)); // Allow status to propagate
      _showDeliverySuccessDialog();
      
      print('✅ Order completed successfully - database updated');
      
      _showDeliverySuccessDialog();
    } catch (e) {
      print('❌ Error completing order: $e');
      _showErrorDialog('Failed to complete order: $e');
    }
  }

  void _showDeliverySuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Order Completed',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Thank you! Your payment has been processed and the order is now complete.',
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.payment, color: Colors.green[700], size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Paid ${_amountPaid.toStringAsFixed(2)} via $_selectedPaymentMethod',
                          style: TextStyle(
                            color: Colors.green[800],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.local_shipping, color: Colors.green[600], size: 16),

                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false); // Go to home and clear stack
              },
              child: Text('Continue'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCollection() async {
    if (_isConfirming) return; // Prevent multiple taps

    setState(() => _isConfirming = true);

    try {
      print('🔄 Confirming collection for orderId: ${widget.orderId}');
      print('🔄 Branch ID: ${widget.branchId}');

      // Update the order status in the database
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('mobileOrders')
          .doc(widget.orderId)
          .update({
        'status': 'customer_confirmed',
        'customerConfirmedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Collection confirmed successfully - database updated');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Collection confirmed successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      _showSuccessDialog();
    } catch (e) {
      print('❌ Error confirming collection: $e');
      _showErrorDialog('Failed to confirm collection: $e');
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
  }

  void _reportIssue() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report Issue'),
        content: Text('Please contact customer service for assistance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Collection Confirmed',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Thank you! The driver can now proceed to the laundry with your items.',
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.green[700], size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You will be notified when your items are ready for pickup.',
                      style: TextStyle(
                        color: Colors.green[800],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to tracking screen
              },
              child: Text('Continue'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCustomerData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final customerBalanceDoc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('mobileUsers')
            .doc(user.uid)
            .collection('user_eBalance')
            .doc('balance')
            .get();

        if (customerBalanceDoc.exists) {
          setState(() {
            _customerData = customerBalanceDoc.data();
          });
        }
      }
    } catch (e) {
      print('Error loading customer data: $e');
    }
  }

  Future<void> _loadInvoiceAmount() async {
    try {
      print('🔍 Loading invoice amount for orderId: ${widget.orderId}');

      // First check if the mobile order has amountPaid directly
      if (widget.orderData['amountPaid'] != null) {
        final amountPaid = (widget.orderData['amountPaid']).toDouble();
        print('✅ Invoice amount found in order data: $amountPaid');
        setState(() {
          _amountPaid = amountPaid;
        });
        return;
      }

      // Fallback: try to find invoice in invoices collection
      final invoiceQuery = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('invoices')
          .where('mobileOrderId', isEqualTo: widget.orderId)
          .where('isDelivered', isEqualTo: true)
          .get();

      if (invoiceQuery.docs.isNotEmpty) {
        final invoice = invoiceQuery.docs.first.data();
        final netPayable = (invoice['netPayable'] ?? 0.0).toDouble();
        final amountPaid = (invoice['amountPaid'] ?? 0.0).toDouble();
        final remainingAmount = netPayable - amountPaid;

        print('✅ Invoice found: netPayable=$netPayable, amountPaid=$amountPaid, remaining=$remainingAmount');

        setState(() {
          _amountPaid = remainingAmount > 0 ? remainingAmount : 0.0;
        });
        return;
      }

      // Fallback: try bills collection
      final billsQuery = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('bills')
          .where('mobileOrderId', isEqualTo: widget.orderId)
          .where('status', whereIn: ['partial', 'Partial'])
          .get();

      if (billsQuery.docs.isNotEmpty) {
        final bill = billsQuery.docs.first.data();
        final total = (bill['totalAmount'] ?? 0.0).toDouble();
        final paid = (bill['amountPaid'] ?? 0.0).toDouble();

        print('✅ Bill found: total=$total, paid=$paid, remaining=${total - paid}');

        setState(() {
          _amountPaid = total - paid;
        });
        return;
      }

      print('⚠️ No invoice or bill found for orderId: ${widget.orderId}');

      // If no invoice found, set a default amount from order data
      final orderAmount = widget.orderData['totalAmount']?.toDouble() ?? 0.0;
      if (orderAmount > 0) {
        setState(() {
          _amountPaid = orderAmount;
        });
        print('📝 Using order amount as fallback: $orderAmount');
      }

    } catch (e) {
      print('❌ Error loading invoice amount: $e');

      // Fallback to order amount if everything fails
      final orderAmount = widget.orderData['totalAmount']?.toDouble() ?? 0.0;
      if (orderAmount > 0) {
        setState(() {
          _amountPaid = orderAmount;
        });
      }
    }
  }

  Widget _buildDeliveryInfo() {
    return Card(
      elevation: 2,
      color: Colors.green[50],
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.home_filled, color: Colors.green[700], size: 24),
                SizedBox(width: 8),
                Text(
                  'Delivery Completed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Your laundry items have been delivered. Payment is required to complete the order.',
              style: TextStyle(color: Colors.green[800]),
            ),
            if (_amountPaid > 0) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[300]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Amount Due:',
                      style: TextStyle(
                        color: Colors.green[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_amountPaid.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.green[800],
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    print('🎯 Building payment section: amountPaid=$_amountPaid, customerData=${_customerData != null}');

    // Show debug info if amount is 0
    if (_amountPaid <= 0) {
      return Card(
        elevation: 2,
        color: Colors.orange[50],
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 48),
              SizedBox(height: 16),
              Text(
                'Payment Amount Not Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Unable to load invoice amount for this order.\nPlease contact support.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange[700]),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _showPayment = false;
                  });
                },
                child: Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: Color(0xFF1E40AF), size: 24),
                SizedBox(width: 8),
                Text(
                  'Payment Method',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              'Amount to pay: ${_amountPaid.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.green[700],
              ),
            ),
            SizedBox(height: 16),
            _buildPaymentOption(
              'eBalance',
              'Pay from your account balance',
              Icons.account_balance_wallet,
              (_customerData?['main_balance'] ?? 0.0) >= _amountPaid,
            ),
            _buildPaymentOption('Cash', 'Pay with cash', Icons.money, true),
            _buildPaymentOption('Bank', 'Bank transfer', Icons.account_balance, true),
            _buildPaymentOption('Sabaka Machine', 'Payment terminal', Icons.credit_card, true),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption(String method, String description, IconData icon, bool enabled) {
    final isSelected = _selectedPaymentMethod == method;
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: enabled ? () {
          setState(() {
            _selectedPaymentMethod = method;
          });
        } : null,
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: enabled
                ? (isSelected ? Colors.blue[50] : Colors.grey[50])
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? (isSelected ? Colors.blue : Colors.grey[300]!)
                  : Colors.grey[200]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled
                    ? (isSelected ? Colors.blue : Colors.grey[600])
                    : Colors.grey[400],
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: enabled ? Colors.grey[800] : Colors.grey[400],
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? Colors.grey[600] : Colors.grey[400],
                      ),
                    ),
                    if (method == 'eBalance' && _customerData != null) ...[
                      SizedBox(height: 4),
                      Text(
                        'Balance: ${(_customerData!['main_balance'] ?? 0.0).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: enabled ? Colors.green[600] : Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (enabled && isSelected)
                Icon(Icons.check_circle, color: Colors.blue),
              if (!enabled)
                Icon(Icons.block, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      }
      return timestamp.toString();
    } catch (e) {
      return 'Invalid time';
    }
  }
}