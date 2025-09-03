import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class OrderLogic {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final VoidCallback onStateChanged;
  final Function(String) onError;
  String? _branchId; // Make it dynamic
  String? get branchId => _branchId;
  String? lastOrderId; // ADD this line



  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> services = [];
  List<Map<String, dynamic>> filteredServices = [];
  List<Map<String, dynamic>> selectedServices = [];
  bool isLoading = true;
  String? selectedCategoryId;
  String searchQuery = '';

  OrderLogic({
    required this.onStateChanged,
    required this.onError,
  });

  Future<void> loadData() async {
    try {
      // First, get the user's branch ID
      await _loadUserBranchId();

      if (_branchId == null) {
        throw Exception('No branch selected. Please select a location first.');
      }

      print('🏢 Loading data for branch: $_branchId');

      // Load categories and services for the user's branch
      final categoriesSnapshot = await _firestore
          .collection('branches')
          .doc(_branchId!)
          .collection('categories')
          .get();

      final servicesSnapshot = await _firestore
          .collection('branches')
          .doc(_branchId!)
          .collection('services')
          .get();

      categories = categoriesSnapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();

      services = servicesSnapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();

      print('📊 Loaded ${categories.length} categories and ${services.length} services');

      _applyFilters();
      isLoading = false;
      onStateChanged();
    } catch (e) {
      print('❌ Error loading data: $e');
      isLoading = false;
      onStateChanged();
      onError('Failed to load services: $e');
    }
  }

  // This allows the OrderScreen to command a branch change.
  Future<void> updateBranch(String newBranchId) async {
    print('🔄 Switching OrderLogic to new branch: $newBranchId');
    _branchId = newBranchId;

    // Clear all existing data to prevent mixing services from different branches
    categories.clear();
    services.clear();
    selectedServices.clear();
    filteredServices.clear();
    selectedCategoryId = null;

    // Set loading state and notify UI to show a spinner
    isLoading = true;
    onStateChanged();

    // Reload data for the new branch
    await loadData();
  }

  // METHOD 2: Add this new public method.
  // This is a helper to clear the cart after a successful migration,
  // forcing the user to re-select services from the new branch.
  void clearSelection() {
    selectedServices.clear();
    onStateChanged();
  }

  // METHOD 3: Add this new public method.
  // This is used for the user migration logic in OrderScreen
  // to get the current branch ID before switching.
  String? getCurrentBranchId() {
    return _branchId;
  }


  Future<void> _loadUserBranchId() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      print('👤 Loading branch ID for user: ${user.uid}');

      // Try to get branch ID from user's profile
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _branchId = userData['branchId'];
        print('✅ Found branch ID in user profile: $_branchId');
        return;
      }

      // Fallback: Check if user exists in any branch's mobileUsers collection
      print('🔍 User not found in main users collection, searching in branches...');

      final branchesSnapshot = await _firestore.collection('branches').get();

      for (var branchDoc in branchesSnapshot.docs) {
        final mobileUserDoc = await _firestore
            .collection('branches')
            .doc(branchDoc.id)
            .collection('mobileUsers')
            .doc(user.uid)
            .get();

        if (mobileUserDoc.exists) {
          _branchId = branchDoc.id;
          print('✅ Found user in branch: $_branchId');

          // Update main user profile with branch ID for faster future lookups
          await _firestore.collection('users').doc(user.uid).set({
            'branchId': _branchId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          return;
        }
      }

      throw Exception('User not associated with any branch');

    } catch (e) {
      print('❌ Error loading user branch ID: $e');
      throw e;
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = services;

    // Filter by category
    if (selectedCategoryId != null) {
      filtered = filtered.where((service) =>
      service['categoryId'] == selectedCategoryId).toList();
    }

    // Filter by search query
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((service) =>
          service['name'].toString().toLowerCase().contains(searchQuery.toLowerCase())).toList();
    }

    filteredServices = filtered;
    onStateChanged();
  }

  void updateSearchQuery(String query) {
    searchQuery = query;
    _applyFilters();
  }

  void selectCategory(String? categoryId) {
    selectedCategoryId = categoryId;
    _applyFilters();
  }

  void toggleService(Map<String, dynamic> service) {
    final index = selectedServices.indexWhere((s) => s['id'] == service['id']);
    if (index >= 0) {
      selectedServices.removeAt(index);
    } else {
      selectedServices.add({...service, 'quantity': 1});
    }
    onStateChanged();
  }

  void updateQuantity(String serviceId, int quantity) {
    final index = selectedServices.indexWhere((s) => s['id'] == serviceId);
    if (index >= 0) {
      if (quantity > 0) {
        selectedServices[index]['quantity'] = quantity;
      } else {
        selectedServices.removeAt(index);
      }
      onStateChanged();
    }
  }

  double calculateTotal() {
    return selectedServices.fold(0.0, (sum, service) =>
    sum + ((service['unitPrice'] ?? 0) * service['quantity']));
  }

  bool isServiceSelected(String serviceId) {
    return selectedServices.any((s) => s['id'] == serviceId);
  }

  int getServiceQuantity(String serviceId) {
    final service = selectedServices.firstWhere(
          (s) => s['id'] == serviceId,
      orElse: () => {'quantity': 0},
    );
    return service['quantity'] ?? 0;
  }

  void dispose() {
    // Clean up resources if needed
  }

  Future<bool> submitOrder({
    required String customerName,
    required String customerPhone,
    String? customerEmail,
    bool isSmartOrder = false,
  }) async {
    try {
      if (_branchId == null) {
        onError('No branch selected');
        return false;
      }
      
      // For smart orders, we don't require services to be selected
      if (!isSmartOrder && selectedServices.isEmpty) {
        onError('Please select at least one service');
        return false;
      }

      final user = FirebaseAuth.instance.currentUser;

      // Create mobile user data first (if not exists)
      await _createOrUpdateMobileUser(user, customerName, customerPhone, customerEmail);

      // Get customer location for driver navigation (MANDATORY)
      print('📍 LOCATION: Starting customer location capture...');
      Position? customerLocation;
      try {
        print('📍 LOCATION: Checking location permissions...');
        // Check location permissions
        LocationPermission permission = await Geolocator.checkPermission();
        print('📍 LOCATION: Current permission: $permission');
        
        if (permission == LocationPermission.denied) {
          print('📍 LOCATION: Permission denied, requesting permission...');
          permission = await Geolocator.requestPermission();
          print('📍 LOCATION: Permission after request: $permission');
        }
        
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          print('📍 LOCATION: Permission granted, getting position...');
          print('📍 LOCATION: Using 10-second timeout for location capture');
          
          customerLocation = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best, // Use best accuracy for driver navigation
            timeLimit: Duration(seconds: 10), // Give more time for accurate location
          );
          
          print('✅ LOCATION SUCCESS: Customer location captured');
          print('✅ LOCATION SUCCESS: Latitude: ${customerLocation.latitude}');
          print('✅ LOCATION SUCCESS: Longitude: ${customerLocation.longitude}');
          print('✅ LOCATION SUCCESS: Accuracy: ${customerLocation.accuracy}m');
          
          // Validate that location is not a test location (Google HQ coordinates)
          bool isTestLocation = customerLocation.latitude == 37.4219983 && 
                              customerLocation.longitude == -122.084;
          bool isZeroLocation = customerLocation.latitude == 0.0 && 
                               customerLocation.longitude == 0.0;
          
          if (isTestLocation || isZeroLocation) {
            print('❌ LOCATION REJECTED: Test/default coordinates detected');
            print('❌ LOCATION REJECTED: Order cannot be placed without valid location');
            onError('Please enable real location services. Test locations are not allowed.');
            return false;
          }
          
          print('✅ LOCATION VALID: Real customer location confirmed');
          print('✅ LOCATION VALID: Driver will see customer location on map');
        } else {
          print('❌ LOCATION DENIED: Location permission not granted');
          print('❌ LOCATION DENIED: Permission status: $permission');
          print('❌ LOCATION DENIED: Order cannot be placed without location access');
          onError('Location permission is required to place an order. Please enable location access.');
          return false;
        }
      } catch (e) {
        print('❌ LOCATION ERROR: Failed to get customer location');
        print('❌ LOCATION ERROR: Error type: ${e.runtimeType}');
        print('❌ LOCATION ERROR: Error message: $e');
        print('❌ LOCATION ERROR: Order cannot be placed without location');
        
        // Provide specific error messages
        if (e.toString().contains('timeout')) {
          onError('Location timeout. Please enable GPS and try again.');
        } else if (e.toString().contains('permission')) {
          onError('Location permission denied. Please enable location access to place an order.');
        } else if (e.toString().contains('unavailable')) {
          onError('Location services unavailable. Please enable GPS and try again.');
        } else {
          onError('Failed to get your location. Please enable location services and try again.');
        }
        
        return false;
      }

      final orderData = {
        'userId': user?.uid ?? 'anonymous',
        'services': isSmartOrder ? [] : selectedServices.map((service) => {
          'id': service['id'],
          'name': service['name'],
          'unitPrice': service['unitPrice'],
          'quantity': service['quantity'],
          'categoryId': service['categoryId'],
          'total': (service['unitPrice'] ?? 0) * service['quantity'],
        }).toList(),
        'totalAmount': isSmartOrder ? 0.0 : calculateTotal(),
        'status': 'pending',
        'orderType': isSmartOrder ? 'smart' : 'regular',
        'servicesSelected': !isSmartOrder,
        'createdAt': FieldValue.serverTimestamp(),
        'branchId': _branchId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerEmail': customerEmail ?? user?.email ?? '',
        'paymentStatus': 'pending',
      };

      // Add customer location if available (for driver navigation)
      print('📍 LOCATION: Adding location to order data...');
      if (customerLocation != null) {
        orderData['customerLocation'] = {
          'latitude': customerLocation.latitude,
          'longitude': customerLocation.longitude,
        };
        print('✅ LOCATION ADDED: Customer location included in order');
        print('✅ LOCATION ADDED: Driver will see navigation options');
        print('✅ LOCATION ADDED: Driver can calculate distance and ETA');
      } else {
        print('⚠️ LOCATION MISSING: No customer location in order data');
        print('⚠️ LOCATION MISSING: Driver will see order but no map/navigation');
        print('⚠️ LOCATION MISSING: Driver can still collect items using address/phone');
      }

      // Add smart order specific fields
      if (isSmartOrder) {
        orderData['smartOrderNote'] = 'Customer prefers cashier to determine services based on items brought';
        orderData['estimatedItems'] = 'Mixed laundry items - services to be determined by staff';
      }

      print('🔍 ORDER SUBMIT: Submitting ${isSmartOrder ? 'smart' : 'regular'} order to: branches/$_branchId/mobileOrders');
      print('🔍 ORDER SUBMIT: Order type: ${orderData['orderType']}');
      print('🔍 ORDER SUBMIT: Customer: ${orderData['customerName']}');
      print('🔍 ORDER SUBMIT: Phone: ${orderData['customerPhone']}');
      print('🔍 ORDER SUBMIT: Services count: ${(orderData['services'] as List?)?.length ?? 0}');
      print('🔍 ORDER SUBMIT: Total amount: \$${orderData['totalAmount']}');
      print('🔍 ORDER SUBMIT: Has customer location: ${orderData['customerLocation'] != null}');
      print('🔍 ORDER SUBMIT: Branch ID: $_branchId');

      // Save to Firestore - using dynamic branch ID
      final docRef = await _firestore
          .collection('branches')
          .doc(_branchId!)
          .collection('mobileOrders')
          .add(orderData);

      print('✅ ORDER SUCCESS: Order submitted to branch collection');
      print('✅ ORDER SUCCESS: Order ID: ${docRef.id}');
      print('✅ ORDER SUCCESS: Path: branches/$_branchId/mobileOrders/${docRef.id}');

      // CAPTURE the order ID for tracking
      lastOrderId = docRef.id;

      // Also add to city agent's collection so drivers can see it
      print('🔄 SYNC: Starting order sync from branch to city agent...');
      try {
        print('🔍 SYNC: Fetching branch data for parentAgentId lookup...');
        // Get the branch info to find its parent city agent
        final branchDoc = await _firestore
            .collection('branches')
            .doc(_branchId!)
            .get();

        if (branchDoc.exists) {
          final branchData = branchDoc.data() as Map<String, dynamic>;
          final parentAgentId = branchData['parentAgentId'] as String?;
          
          print('🏢 SYNC: Branch data retrieved');
          print('🏢 SYNC: Branch ID: $_branchId');
          print('🏢 SYNC: Parent Agent ID: $parentAgentId');
          print('🏢 SYNC: Branch name: ${branchData['name'] ?? 'Unknown'}');

          if (parentAgentId != null) {
            print('📝 SYNC: Copying order to city agent collection...');
            print('📝 SYNC: Target path: cityAgents/$parentAgentId/mobileOrders/${docRef.id}');
            print('📝 SYNC: Order type: ${orderData['orderType']}');
            print('📝 SYNC: Customer: ${orderData['customerName']}');
            print('📝 SYNC: Smart order: ${orderData['orderType'] == 'smart'}');
            
            // Copy the order to city agent's collection with the same ID
            await _firestore
                .collection('cityAgents')
                .doc(parentAgentId)
                .collection('mobileOrders')
                .doc(docRef.id)
                .set(orderData);

            print('✅ SYNC SUCCESS: Order synced to city agent collection');
            print('✅ SYNC SUCCESS: City Agent ID: $parentAgentId');
            print('✅ SYNC SUCCESS: Order ID: ${docRef.id}');
            print('✅ SYNC SUCCESS: Drivers can now see this order!');
          } else {
            print('❌ SYNC ERROR: Branch has no parentAgentId');
            print('❌ SYNC ERROR: Branch ID: $_branchId');
            print('❌ SYNC ERROR: Branch data keys: ${branchData.keys.toList()}');
            print('❌ SYNC ERROR: Order NOT synced to city agent - drivers won\'t see it');
          }
        } else {
          print('❌ SYNC ERROR: Branch document does not exist');
          print('❌ SYNC ERROR: Branch ID: $_branchId');
          print('❌ SYNC ERROR: Order NOT synced to city agent');
        }
      } catch (e) {
        print('❌ SYNC FAILURE: Exception during sync process');
        print('❌ SYNC FAILURE: Error: $e');
        print('❌ SYNC FAILURE: Stack trace: ${StackTrace.current}');
        print('❌ SYNC FAILURE: Branch ID: $_branchId');
        print('❌ SYNC FAILURE: Order ID: ${docRef.id}');
        print('❌ SYNC FAILURE: Order type: ${orderData['orderType']}');
        print('❌ SYNC FAILURE: Drivers will NOT see this order!');
        // Don't fail the entire order if syncing fails
      }

      // Clear selected services after successful submission
      selectedServices.clear();
      onStateChanged();

      return true;
    } catch (e) {
      print('❌ Error submitting order: $e');
      onError('Failed to submit order: $e');
      return false;
    }
  }

  Future<bool> submitSmartOrder({
    required String customerName,
    required String customerPhone,
    String? customerEmail,
    String? estimatedItems,
  }) async {
    return submitOrder(
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      isSmartOrder: true,
    );
  }


  Future<void> _createOrUpdateMobileUser(User? user, String name, String phone, String? email) async {
    if (user == null || _branchId == null) return;

    try {
      // Get customer location for mobile user profile
      Position? userLocation;
      try {
        print('📍 USER PROFILE: Getting location for mobile user profile...');
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          userLocation = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 10),
          );
          print('✅ USER PROFILE: Location captured for mobile user profile');
          
          // Validate that location is not a test location
          bool isTestLocation = userLocation.latitude == 37.4219983 && 
                              userLocation.longitude == -122.084;
          bool isZeroLocation = userLocation.latitude == 0.0 && 
                               userLocation.longitude == 0.0;
          
          if (isTestLocation || isZeroLocation) {
            print('❌ USER PROFILE: Test/default coordinates detected - not saving');
            userLocation = null; // Don't use test coordinates
          } else {
            print('✅ USER PROFILE: Valid location coordinates confirmed');
          }
        }
      } catch (e) {
        print('❌ USER PROFILE: Failed to get location for user profile: $e');
      }

      final mobileUserData = {
        'name': name,
        'phone': phone,
        'email': email ?? user.email ?? '',
        'city': '',
        'country': 'USA',
        'lastOrderAt': FieldValue.serverTimestamp(),
        'totalOrders': FieldValue.increment(1),
        'branchId': _branchId, // Store branch ID in mobile user data too
      };

      // Add location data to mobile user profile only if valid
      if (userLocation != null) {
        mobileUserData['locationData'] = {
          'latitude': userLocation.latitude,
          'longitude': userLocation.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        print('✅ USER PROFILE: Valid location data added to mobile user profile');
      } else {
        print('⚠️ USER PROFILE: No valid location data available for mobile user profile');
      }

      // Save/update mobile user data in the correct branch
      await _firestore
          .collection('branches')
          .doc(_branchId!)
          .collection('mobileUsers')
          .doc(user.uid)
          .set(mobileUserData, SetOptions(merge: true));

      print('✅ Mobile user data saved/updated for branch: $_branchId');
    } catch (e) {
      print('❌ Error saving mobile user: $e');
    }
  }
}
