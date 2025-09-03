import 'package:flutter/material.dart';

class OrderWidgets {
  static Widget buildSearchBar({
    required TextEditingController controller,
    required Function(String) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
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
        onChanged: onChanged,
      ),
    );
  }

  static Widget buildCategoryTabs({
    required List<Map<String, dynamic>> categories,
    required String? selectedCategoryId,
    required Function(String?) onCategorySelected,
  }) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCategoryChip('All', null, selectedCategoryId, onCategorySelected);
          }
          final category = categories[index - 1];
          return _buildCategoryChip(
            category['name'] ?? 'Category',
            category['id'],
            selectedCategoryId,
            onCategorySelected,
          );
        },
      ),
    );
  }

  static Widget _buildCategoryChip(
      String name,
      String? categoryId,
      String? selectedCategoryId,
      Function(String?) onCategorySelected,
      ) {
    final isSelected = selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(name),
        selected: isSelected,
        onSelected: (_) => onCategorySelected(categoryId),
        selectedColor: const Color(0xFF1E40AF).withOpacity(0.2),
        checkmarkColor: const Color(0xFF1E40AF),
      ),
    );
  }

  static Widget buildServicesList({
    required List<Map<String, dynamic>> services,
    required List<Map<String, dynamic>> selectedServices,
    required Function(Map<String, dynamic>) onServiceToggle,
    required Function(String, int) onQuantityUpdate,
  }) {
    if (services.isEmpty) {
      return const Center(
        child: Text('No services found'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        final isSelected = selectedServices.any((s) => s['id'] == service['id']);
        final selectedService = selectedServices.firstWhere(
              (s) => s['id'] == service['id'],
          orElse: () => {'quantity': 0},
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(
              service['name'] ?? 'Service',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            subtitle: Text(
              '${service['unitPrice']?.toStringAsFixed(2) ?? '0.00'}',
              style: const TextStyle(
                color: Color(0xFF1E40AF),
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: isSelected
                ? _buildQuantityControls(service['id'], selectedService['quantity'], onQuantityUpdate)
                : IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFF1E40AF)),
              onPressed: () => onServiceToggle(service),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildQuantityControls(
      String serviceId,
      int quantity,
      Function(String, int) onQuantityUpdate,
      ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle, color: Color(0xFF1E40AF)),
          onPressed: () => onQuantityUpdate(serviceId, quantity - 1),
        ),
        Text(
          '$quantity',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle, color: Color(0xFF1E40AF)),
          onPressed: () => onQuantityUpdate(serviceId, quantity + 1),
        ),
      ],
    );
  }

  static Widget buildOrderSummary({
    required List<Map<String, dynamic>> selectedServices,
    required double total,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          ...selectedServices.map((service) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${service['name']} x${service['quantity']}'),
                Text('${((service['unitPrice'] ?? 0) * service['quantity']).toStringAsFixed(2)}'),
              ],
            ),
          )),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget buildBottomBar({
    required double total,
    required Future<void> Function()? onPlaceOrder,
    bool isLoading = false,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading || onPlaceOrder == null ? null : () => onPlaceOrder(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF1E40AF),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: isLoading
            ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Submitting...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        )
            : Text(
          'Place Order - ${total.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

}
