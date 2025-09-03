import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CustomerBalanceScreen extends StatefulWidget {
  const CustomerBalanceScreen({Key? key}) : super(key: key);

  @override
  State<CustomerBalanceScreen> createState() => _CustomerBalanceScreenState();
}

class _CustomerBalanceScreenState extends State<CustomerBalanceScreen> with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // Real-time listener for balance updates
  StreamSubscription<DocumentSnapshot>? _balanceSubscription;

  // State variables
  Map<String, dynamic>? _balanceData;
  Map<String, dynamic>? _customerData; // Stores the current logged-in customer's data
  List<Map<String, dynamic>> _transactionHistory = [];
  bool _isLoading = true;
  bool _isLoadingHistory = false;
  String? _error; // To display any loading or authentication errors

  // State for customer search
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _searchPerformed = false; // To track if a search has been initiated

  // Controllers are now non-nullable and initialized in initState
  late final TabController _tabController;
  late final TextEditingController _sendAmountController;
  late final TextEditingController _sendNoteController;
  late final TextEditingController _customerSearchController;

  // State for the selected recipient
  String? _selectedCustomerId;
  String? _selectedCustomerBranchId;

  @override
  void initState() {
    super.initState();
    // Initialize controllers here to ensure they are never null
    _sendAmountController = TextEditingController();
    _sendNoteController = TextEditingController();
    _customerSearchController = TextEditingController();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadBalanceData();
  }

  void _onTabChanged() {
    if (_tabController.index == 2 && _transactionHistory.isEmpty && !_isLoadingHistory) {
      _loadTransactionHistory();
    }
  }

  @override
  void dispose() {
    _balanceSubscription?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _sendAmountController.dispose();
    _sendNoteController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  // Main function to load critical user and balance data.
  Future<void> _loadBalanceData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final customerDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!customerDoc.exists) throw Exception('Customer profile not found');

      final customerData = customerDoc.data();
      if (customerData == null || customerData['branchId'] == null) {
        throw Exception('Customer data or branch ID is missing');
      }

      if (mounted) setState(() => _customerData = customerData);

      _setupBalanceListener(user.uid, customerData['branchId']);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load data: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Sets up a real-time stream for the user's balance.
  void _setupBalanceListener(String userId, String branchId) {
    _balanceSubscription?.cancel();

    final balanceRef = _firestore
        .collection('branches')
        .doc(branchId)
        .collection('mobileUsers')
        .doc(userId)
        .collection('user_eBalance')
        .doc('balance');

    _balanceSubscription = balanceRef.snapshots().listen(
          (balanceDoc) async {
        if (!mounted) return;
        if (balanceDoc.exists) {
          setState(() {
            _balanceData = balanceDoc.data();
            _isLoading = false;
          });
        } else {
          await _createBalanceDocument(branchId, userId);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _error = 'Failed to listen for balance updates: $error';
            _isLoading = false;
          });
        }
      },
    );
  }

  // Creates the 'balance' document if it doesn't exist.
  Future<void> _createBalanceDocument(String branchId, String customerId) async {
    try {
      await _firestore
          .collection('branches')
          .doc(branchId)
          .collection('mobileUsers')
          .doc(customerId)
          .collection('user_eBalance')
          .doc('balance')
          .set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'main_balance': 0,
        'percent_balance': 0,
      });
    } catch (e) {
      print("Error creating balance document: $e");
    }
  }

  // Loads the transaction history for the current user.
  Future<void> _loadTransactionHistory() async {
    // FIX: Add a null check for _customerData before proceeding.
    if (_customerData == null || _isLoadingHistory || !mounted) return;
    setState(() => _isLoadingHistory = true);

    try {
      final user = _auth.currentUser;
      // FIX: Ensure user is not null and get branchId safely.
      final branchId = _customerData!['branchId'];
      if(user == null) throw Exception("User not found");

      final historySnapshot = await _firestore
          .collection('branches')
          .doc(branchId)
          .collection('mobileUsers')
          .doc(user.uid)
          .collection('balance_transactions')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      if (mounted) {
        setState(() {
          _transactionHistory = historySnapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
      print('Error loading transaction history: $e');
    }
  }

  // Performs a secure server-side search for customers.
  // Performs a secure server-side search for customers.
  // Performs a secure server-side search for customers.
  Future<void> _performCustomerSearch() async {
    final query = _customerSearchController.text.trim();
    if (query.length < 3) {
      _showErrorSnackBar('Please enter at least 3 characters to search.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _searchPerformed = true;
      _searchResults = [];
      _selectedCustomerId = null;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception("Not authenticated");

      final branchesSnapshot = await _firestore.collection('branches').get();
      // Ensure the Future list is correctly typed
      final List<Future<QuerySnapshot<Map<String, dynamic>>>> searchFutures = [];

      for (final branchDoc in branchesSnapshot.docs) {
        final mobileUsersRef = branchDoc.reference.collection('mobileUsers');
        searchFutures.add(mobileUsersRef.where('name', isGreaterThanOrEqualTo: query, isLessThanOrEqualTo: '$query\uf8ff').get());

        // --- THIS IS THE FIX ---
        // Corrected the typo from 'mobileUsers-ref' to 'mobileUsersRef'
        searchFutures.add(mobileUsersRef.where('phone', isGreaterThanOrEqualTo: query, isLessThanOrEqualTo: '$query\uf8ff').get());
      }

      final searchSnapshots = await Future.wait(searchFutures);
      final Map<String, Map<String, dynamic>> uniqueCustomers = {};

      for (int i = 0; i < searchSnapshots.length; i++) {
        final branchDoc = branchesSnapshot.docs[i ~/ 2];
        for (final customerDoc in searchSnapshots[i].docs) {
          final customerData = customerDoc.data();
          final branchData = branchDoc.data();

          if (customerData == null || branchData == null) {
            continue; // Skip this result if data is invalid
          }

          if (customerDoc.id != currentUser.uid && !uniqueCustomers.containsKey(customerDoc.id)) {
            customerData['uid'] = customerDoc.id;
            customerData['branchId'] = branchDoc.id;
            customerData['branchName'] = branchData['name'] ?? 'Unknown Branch';
            uniqueCustomers[customerDoc.id] = customerData;
          }
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = uniqueCustomers.values.toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        _showErrorSnackBar('Search failed: ${e.toString()}');
      }
    }
  }

  // Safely gets the main balance.
  double _getMainBalance() => (_balanceData?['main_balance'] ?? 0.0).toDouble();

  // Formats a Firestore Timestamp into a readable date string.
  String _formatDate(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateFormat('MMM dd, yyyy HH:mm').format(timestamp.toDate());
    }
    return 'Unknown Date';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My eBalance'),
        centerTitle: true,
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Balance', icon: Icon(Icons.account_balance_wallet)),
            Tab(text: 'Send Money', icon: Icon(Icons.send)),
            Tab(text: 'History', icon: Icon(Icons.history)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(fontSize: 16, color: Colors.red[700]), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadBalanceData, child: const Text('Retry')),
            ],
          ),
        ),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          _buildBalanceContent(),
          _buildSendMoneyContent(),
          _buildTransactionHistoryContent(),
        ],
      ),
    );
  }

  // Builds the UI for the "Balance" tab.
  Widget _buildBalanceContent() {
    return RefreshIndicator(
      onRefresh: _loadBalanceData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(colors: [Colors.blue[600]!, Colors.blue[400]!]),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.account_balance_wallet, color: Colors.white, size: 48),
                    const SizedBox(height: 12),
                    const Text('eBalance', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(_getMainBalance().toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: ElevatedButton.icon(onPressed: () => _tabController.animateTo(1), icon: const Icon(Icons.send), label: const Text('Send Money'))),
                const SizedBox(width: 16),
                Expanded(child: ElevatedButton.icon(onPressed: () => _tabController.animateTo(2), icon: const Icon(Icons.history), label: const Text('View History'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Builds the UI for the "Send Money" tab.
  Widget _buildSendMoneyContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCustomerSelection(),
          const SizedBox(height: 16),
          _buildSendAmountAndNote(),
          const SizedBox(height: 24),
          _buildSendButton(),
        ],
      ),
    );
  }

  // Builds the UI for selecting a customer to send money to.
  // Builds the UI for selecting a customer to send money to.
  Widget _buildCustomerSelection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Recipient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _customerSearchController,
              decoration: InputDecoration(
                labelText: 'Search by name or phone',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search), // Changed icon for clarity
                  tooltip: 'Search',
                  onPressed: _performCustomerSearch,
                ),
              ),
              onSubmitted: (_) => _performCustomerSearch(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : !_searchPerformed
                  ? const Center(child: Text('Enter a query and tap search to find customers.'))
                  : _searchResults.isEmpty
                  ? const Center(child: Text('No customers found.'))
                  : ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final customer = _searchResults[index];
                  final isSelected = _selectedCustomerId == customer['uid'];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? Colors.green : Colors.grey[300],
                      child: Icon(Icons.person, color: isSelected ? Colors.white : Colors.grey[600]),
                    ),
                    title: Text(customer['name'] ?? 'Unknown'),
                    // --- THIS IS THE UPDATED LINE ---
                    subtitle: Text(
                        'Branch: ${customer['branchName']}\nPhone: ${customer['phone'] ?? 'N/A'}'
                    ),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                    onTap: () => setState(() {
                      _selectedCustomerId = customer['uid'];
                      _selectedCustomerBranchId = customer['branchId'];
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Builds the UI for entering the transfer amount and note.
  Widget _buildSendAmountAndNote() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Amount & Note', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text('Available eBalance: ${_getMainBalance().toStringAsFixed(2)}', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            TextField(
              controller: _sendAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount to send', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(controller: _sendNoteController, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()), maxLines: 2),
          ],
        ),
      ),
    );
  }

  // Builds the "Send Money" button.
  Widget _buildSendButton() {
    return ElevatedButton.icon(
      onPressed: _canSendBalance() ? _processSendBalance : null,
      icon: const Icon(Icons.send),
      label: const Text('Send Money'),
      style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.blue[600],
          padding: const EdgeInsets.symmetric(vertical: 16)
      ),
    );
  }

  // Checks if all conditions to send money are met.
  bool _canSendBalance() {
    final amount = double.tryParse(_sendAmountController.text) ?? 0;
    return amount > 0 && _selectedCustomerId != null && amount <= _getMainBalance();
  }

  // Processes the money transfer request.
  Future<void> _processSendBalance() async {
    // FIX: Add comprehensive null checks before proceeding.
    final user = _auth.currentUser;
    final senderBranchId = _customerData?['branchId'];
    if (!_canSendBalance() || user == null || senderBranchId == null) {
      _showErrorSnackBar('Invalid data or insufficient balance.');
      return;
    }

    final amount = double.tryParse(_sendAmountController.text)!;
    final note = _sendNoteController.text;

    showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Processing...')])));

    try {
      final transferRequest = {
        'senderId': user.uid,
        'senderBranchId': senderBranchId,
        'recipientId': _selectedCustomerId,
        'recipientBranchId': _selectedCustomerBranchId,
        'amount': amount,
        'note': note,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('balance_transfers').add(transferRequest);

      if (mounted) Navigator.of(context).pop();
      _showSuccessSnackBar('Transfer initiated successfully!');

      _sendAmountController.clear();
      _sendNoteController.clear();
      _customerSearchController.clear();
      if (mounted) {
        setState(() {
          _selectedCustomerId = null;
          _searchResults = [];
          _searchPerformed = false;
        });
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorSnackBar('Failed to initiate transfer: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.green));
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  // Builds the UI for the "Transaction History" tab.
  Widget _buildTransactionHistoryContent() {
    return RefreshIndicator(
      onRefresh: _loadTransactionHistory,
      child: _isLoadingHistory
          ? const Center(child: CircularProgressIndicator())
          : _transactionHistory.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No Transaction History', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _transactionHistory.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildTransactionCard(_transactionHistory[index]),
      ),
    );
  }

  // Builds a single transaction card for the history list.
  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] ?? 0).toDouble();
    final type = transaction['type'] ?? 'transfer';
    final note = transaction['note'] ?? 'No note';
    final timestamp = _formatDate(transaction['timestamp']);
    final isPositive = type == 'receive' || type == 'refund';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(isPositive ? Icons.arrow_downward : Icons.arrow_upward, color: isPositive ? Colors.green : Colors.red),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (note.isNotEmpty && note != 'No note')
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(note, style: TextStyle(color: Colors.grey[600])),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(timestamp, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Text('${isPositive ? '+' : '-'}${amount.abs().toStringAsFixed(2)}', style: TextStyle(color: isPositive ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}