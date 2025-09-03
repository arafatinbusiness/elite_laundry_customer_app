import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceSelectionScreen extends StatefulWidget {
  final Map<String, dynamic> locationData;

  const ServiceSelectionScreen({Key? key, required this.locationData}) : super(key: key);

  @override
  State<ServiceSelectionScreen> createState() => _ServiceSelectionScreenState();
}

class _ServiceSelectionScreenState extends State<ServiceSelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // State is now simpler: just categories, services, and loading status.
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> services = [];
  bool isLoading = true;
  String? selectedCategoryId;

  String get branchId => widget.locationData['branchData']['id'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Fetches categories and services from Firestore. This logic remains the same.
  Future<void> _loadData() async {
    try {
      final categoriesSnapshot = await _firestore
          .collection('branches')
          .doc(branchId)
          .collection('categories')
          .get();

      final servicesSnapshot = await _firestore
          .collection('branches')
          .doc(branchId)
          .collection('services')
          .get();

      if (!mounted) return;

      setState(() {
        categories = categoriesSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        services = servicesSnapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showError('Failed to load services. Please try again.');
    }
  }

  // Filters the services based on the selected category tab. This logic remains the same.
  List<Map<String, dynamic>> get filteredServices {
    if (selectedCategoryId == null) return services;
    return services.where((service) => service['categoryId'] == selectedCategoryId).toList();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchName = widget.locationData['branchData']['name'] ?? 'Selected Branch';

    return Scaffold(
      // MODIFIED: AppBar is simpler, with no "Skip" button.
      appBar: AppBar(
        title: Text('Services at $branchName'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // NEW: An informational header to guide the user.
          _buildInfoHeader(),
          _buildCategoryTabs(),
          // MODIFIED: The services list is now read-only.
          Expanded(child: _buildServicesList()),
        ],
      ),
      // MODIFIED: The bottom bar is now a single, clear action button.
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // NEW: A clear, informational card at the top of the screen.
  Widget _buildInfoHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        color: Theme.of(context).primaryColor.withOpacity(0.05),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.2)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 32),
              SizedBox(height: 8),
              Text(
                'Services Available',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4),
              Text(
                'You can order these services right after creating your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // This widget remains unchanged.
  Widget _buildCategoryTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: categories.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildCategoryChip('All', null);
            }
            final category = categories[index - 1];
            return _buildCategoryChip(category['name'], category['id']);
          },
        ),
      ),
    );
  }

  // This widget remains unchanged.
  Widget _buildCategoryChip(String name, String? categoryId) {
    final isSelected = selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(name),
        selected: isSelected,
        onSelected: (_) => setState(() => selectedCategoryId = categoryId),
        showCheckmark: false,
        selectedColor: Theme.of(context).primaryColor.withOpacity(0.8),
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
      ),
    );
  }

  // MODIFIED: This is the core change. The list is now for display only.
  Widget _buildServicesList() {
    if (filteredServices.isEmpty && !isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text("No services available for this category.", style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      itemCount: filteredServices.length,
      itemBuilder: (context, index) {
        final service = filteredServices[index];
        final price = service['unitPrice'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,

          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            leading: Icon(Icons.local_laundry_service_outlined, color: Theme.of(context).primaryColor),
            title: Text(service['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            // REMOVED: All interactive elements like buttons and quantity controls.
            // The trailing widget now simply displays the price.
            trailing: Text(
              price != null ? '${price.toStringAsFixed(2)}' : 'N/A',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ),
        );
      },
    );
  }

  // MODIFIED: Replaced the complex bottom bar with a single, clear button.
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        // The button's only job is to navigate to the signup screen.
        onPressed: () {
          Navigator.pushNamed(
            context,
            '/signup',
            arguments: widget.locationData,
          );
        },
        child: const Text(
          'Proceed to Create Account',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}