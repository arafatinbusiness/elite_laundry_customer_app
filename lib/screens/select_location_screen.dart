import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';



enum LocationPermissionStatus {
  unknown,
  granted,
  denied,
  permanentlyDenied,
}

enum LocationStatus {
  unknown,
  loading,
  active,
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
}



class SelectLocationScreen extends StatefulWidget {
  const SelectLocationScreen({super.key});

  @override
  State<SelectLocationScreen> createState() => _SelectLocationScreenState();
}

class _SelectLocationScreenState extends State<SelectLocationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Position? userLocation;
  double serviceRadiusKm = 20000.0;
  String? selectedCountry;
  String? selectedCity;
  String? selectedLocalBranch;
  Map<String, dynamic>? selectedBranchData;
  bool isLocationPermissionGranted = false;
  bool isLocationServiceEnabled = false;
  bool showLocationPrompt = true;
  bool isLocationEnabled = false;
  LocationPermissionStatus locationPermissionStatus = LocationPermissionStatus.unknown;
  bool showManualSelection = false;
  List<Map<String, dynamic>> countries = [];
  List<Map<String, dynamic>> cities = [];
  List<Map<String, dynamic>> localBranches = [];

  bool isLoadingCountries = true;
  bool isLoadingCities = false;
  bool isLoadingLocalBranches = false;
  static const Color primaryBlue = Color(0xFF1E3A8A);      // Deep blue
  static const Color lightBlue = Color(0xFF3B82F6);        // Medium blue
  static const Color accentBlue = Color(0xFF60A5FA);       // Light blue
  static const Color backgroundBlue = Color(0xFFF0F9FF);   // Very light blue
  static const Color successGreen = Color(0xFF10B981);     // Professional green
  static const Color warningOrange = Color(0xFFF59E0B);    // Professional orange
  static const Color errorRed = Color(0xFFEF4444);         // Professional red



  @override
  void initState() {
    super.initState();
    // This function will now handle both getting the location
    // and then fetching the branches automatically.
    _initializeLocationAndFetchBranches();
  }

  // New initializer function
  Future<void> _initializeLocationAndFetchBranches() async {
    await _initializeLocationState();
    await _fetchAllBranchesByLocation();
  }

  Future<void> _fetchAllBranchesByLocation() async {
    // Ensure we have the latest location status before fetching
    await _initializeLocationState();

    _setLoadingState('branches', true);
    try {
      // Fetch all active branches that have location data
      Query query = _firestore.collection('branches')
          .where('isActive', isEqualTo: true)
          .where('latitude', isNotEqualTo: null)
          .where('longitude', isNotEqualTo: null);

      final snapshot = await query.get();
      final allBranches = snapshot.docs.map(_mapBranchData).toList();

      if (mounted) {
        setState(() {
          localBranches = allBranches;
        });
      }

      // If location is available, process distances and auto-select
      if (userLocation != null) {
        await _processBranchesWithLocation();
      } else {
        // If no location, sort alphabetically and prompt user to enable location
        _sortBranchesByAlternativeCriteria();
        if (mounted) {
          setState(() {
            showManualSelection = true;
          });
        }
      }
    } catch (e) {
      print('Error fetching all branches: $e');
      _handleFirestoreError('all branches', e);
    } finally {
      _setLoadingState('branches', false);
    }
  }


  void _onCitySelected(Map<String, dynamic> city) {
    setState(() {
      selectedCity = city['cityName'];
      // Clear previous branch selection when city changes
      selectedLocalBranch = null;
      selectedBranchData = null;
    });
    // Load branches first, then handle location
    _loadLocalBranchesWithLocation(city['id']);
  }

  Future<void> _loadLocalBranchesWithLocation(String cityAgentId) async {
    _clearDependentData(['branches']);
    try {
      // Set loading state
      _setLoadingState('branches', true);

      // Load branches first
      await _fetchBranches(cityAgentId);

      // Then handle location permission and processing
      await _handleLocationForBranches();

    } catch (e) {
      print('Error loading branches with location: $e');
      _handleFirestoreError('branches', e);
    } finally {
      _setLoadingState('branches', false);
    }
  }


  Future<void> _handleLocationForBranches() async {
    // If location permission is granted and we have location
    if (locationPermissionStatus == LocationPermissionStatus.granted && userLocation != null) {
      // Process branches with location data immediately
      await _processBranchesWithLocation();
      return;
    }

    // If permission is unknown or denied, try to request it
    if (locationPermissionStatus == LocationPermissionStatus.unknown ||
        locationPermissionStatus == LocationPermissionStatus.denied) {

      // Request location permission
      final locationGranted = await _requestLocationPermission();

      if (locationGranted && userLocation != null) {
        // Process branches with location data
        await _processBranchesWithLocation();
      } else {
        // Fallback to manual selection without location
        _processBranchesWithoutLocation();
      }
    } else {
      // Permission permanently denied or other issues
      _processBranchesWithoutLocation();
    }
  }



  void _processBranchesWithoutLocation() {
    if (localBranches.isEmpty) return;

    // Clear any existing location data
    for (var branch in localBranches) {
      branch['distance'] = null;
      branch['isWithinServiceArea'] = true;
      branch['formattedDistance'] = 'Distance unknown';
      branch['serviceStatus'] = _getServiceStatus(branch);
    }

    // Sort by alternative criteria
    _sortBranchesByAlternativeCriteria();

    if (mounted) {
      setState(() {
        showManualSelection = true;
      });
    }

    // Show manual selection info
    _showManualSelectionPrompt();
  }


  void _showManualSelectionPrompt() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.touch_app, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Tap to select a branch manually'),
            ),
          ],
        ),
        backgroundColor: lightBlue,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }




  Future<void> _initializeLocationState() async {
    await _checkLocationServices();
    await _checkLocationPermission();
    // Get location immediately if permission is already granted
    if (locationPermissionStatus == LocationPermissionStatus.granted && isLocationEnabled) {
      await _getCurrentLocation();
    }
  }

// NEW: Check if location services are enabled
  Future<void> _checkLocationServices() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (mounted) {
        setState(() {
          isLocationEnabled = serviceEnabled;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLocationEnabled = false;
        });
      }
    }
  }

  // NEW: Check current location permission status
  Future<void> _checkLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (mounted) {
        setState(() {
          locationPermissionStatus = _mapLocationPermission(permission);
          showManualSelection = locationPermissionStatus != LocationPermissionStatus.granted;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          locationPermissionStatus = LocationPermissionStatus.unknown;
          showManualSelection = true;
        });
      }
    }
  }



  Future<void> _getCurrentLocation() async {
    if (!isLocationEnabled || locationPermissionStatus != LocationPermissionStatus.granted) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          userLocation = position;
          showManualSelection = false; // Location is available
        });
      }

      print('Location obtained: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('Error getting current location: $e');
      if (mounted) {
        setState(() {
          userLocation = null;
          showManualSelection = true;
        });
      }
    }
  }


  // NEW: Map Geolocator permission to custom enum
  LocationPermissionStatus _mapLocationPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.permanentlyDenied;
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.unknown;
    }
  }

  // NEW: Update location state after permission changes
  void _updateLocationState({
    bool? locationEnabled,
    LocationPermissionStatus? permissionStatus,
    Position? location,
    bool? manualSelection,
  }) {
    if (!mounted) return;

    setState(() {
      if (locationEnabled != null) isLocationEnabled = locationEnabled;
      if (permissionStatus != null) locationPermissionStatus = permissionStatus;
      if (location != null) userLocation = location;
      if (manualSelection != null) showManualSelection = manualSelection;
    });
  }

  // NEW: Get location status for UI display
  LocationStatus get currentLocationStatus {
    if (!isLocationEnabled) return LocationStatus.serviceDisabled;

    switch (locationPermissionStatus) {
      case LocationPermissionStatus.granted:
        return userLocation != null ? LocationStatus.active : LocationStatus.loading;
      case LocationPermissionStatus.denied:
        return LocationStatus.permissionDenied;
      case LocationPermissionStatus.permanentlyDenied:
        return LocationStatus.permissionPermanentlyDenied;
      case LocationPermissionStatus.unknown:
        return LocationStatus.unknown;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCollection(
      String collection,
      Map<String, dynamic> filters,
      String orderBy,
      Map<String, dynamic> Function(DocumentSnapshot) mapper,
      ) async {
    Query query = _firestore.collection(collection);

    filters.forEach((field, value) {
      query = query.where(field, isEqualTo: value);
    });

    if (orderBy.isNotEmpty) {
      query = query.orderBy(orderBy);
    }

    final snapshot = await query.get();
    return snapshot.docs.map(mapper).toList();
  }



  Future<void> _fetchCountries() async {
    try {
      print('=== FETCHING COUNTRY AGENTS DEBUG ===');

      // Since your countryAgents don't have isActive field, fetch all
      countries = await _fetchCollection(
        'countryAgents',
        {'isActive': true}, // Filter for active countries only
        '',
        _mapCountryData,
      );


      print('Country agents fetched: ${countries.length}');

      // Print the mapped country data for debugging
      for (var country in countries) {
        print('Mapped country: $country');
      }

      if (countries.isEmpty) {
        print('Warning: No country agents found in database');
      }
    } catch (e) {
      print('Error fetching country agents: $e');
      print('Error type: ${e.runtimeType}');
      _handleFirestoreError('country agents', e);
      rethrow;
    }
  }


  void _setLoadingState(String type, bool loading) {
    setState(() {
      switch (type) {
        case 'countries': isLoadingCountries = loading; break;
        case 'cities': isLoadingCities = loading; break;
        case 'branches': isLoadingLocalBranches = loading; break;
      }
    });
  }


  Map<String, dynamic> _mapDocumentData(DocumentSnapshot doc, List<String> fields) {
    final data = doc.data() as Map<String, dynamic>;
    final result = {'id': doc.id};

    for (final field in fields) {
      result[field] = data[field] ?? _getDefaultValue(field);
    }
    return result;
  }

  String _getDefaultValue(String field) {
    const defaults = {
      'name': 'Unknown',
      'code': '',
      'flag': '🏳️',
      'cityName': 'Unknown City',
      'agentName': 'Unknown Agent',
      'agentEmail': '',
      'branchName': 'Unknown Branch',
      'address': '',
      'phone': '',
      'rating': 0.0,
      'isAcceptingOrders': true,
      'latitude': null,
      'longitude': null,
      'distance': null,
      'isWithinServiceArea': true,
      'formattedDistance': 'Distance unknown',
      'serviceStatus': 'Available',
    };
    return defaults[field]?.toString() ?? '';
  }




  Map<String, dynamic> _mapCountryData(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      print('Mapping country document ${doc.id}: $data');

      if (data == null) {
        print('Warning: Document ${doc.id} has null data');
        return {
          'id': doc.id,
          'name': 'Unknown Country',
          'code': '',
          'flag': '🏳️',
        };
      }

      // Map your actual fields to expected fields
      return {
        'id': doc.id,
        'name': data['country'] ?? 'Unknown Country', // Use 'country' field as the display name
        'code': data['country']?.substring(0, 2)?.toUpperCase() ?? '', // Generate code from country name
        'flag': _getCountryFlag(data['country'] ?? ''), // Generate flag based on country

        // Original fields from your database
        'email': data['email'] ?? '',
        'fullName': data['fullName'] ?? '',
        'phoneNumber': data['phoneNumber'] ?? '',
        'paypalEmail': data['paypalEmail'] ?? '',
        'uid': data['uid'] ?? '',
        'createdAt': data['createdAt'],

        // Statistics
        'activeSubscriptionsCount': data['activeSubscriptionsCount'] ?? 0,
        'cityAgentsCount': data['cityAgentsCount'] ?? 0,
        'totalRevenue': data['totalRevenue'] ?? 0,
      };
    } catch (e) {
      print('Error mapping country document ${doc.id}: $e');
      return {
        'id': doc.id,
        'name': 'Unknown Country',
        'code': '',
        'flag': '🏳️',
      };
    }
  }

  String _getCountryFlag(String countryName) {
    final country = countryName.toLowerCase();
    if (country.contains('bangladesh')) return '🇧🇩';
    if (country.contains('usa') || country.contains('america')) return '🇺🇸';
    if (country.contains('canada')) return '🇨🇦';
    if (country.contains('uk') || country.contains('britain')) return '🇬🇧';
    if (country.contains('india')) return '🇮🇳';
    if (country.contains('pakistan')) return '🇵🇰';
    // Add more countries as needed
    // Handle test/demo countries
    if (country.contains('twenty26')) return '🌍'; // Generic world flag for test data
    if (country.contains('test')) return '🧪'; // Test tube emoji for test countries
    if (country.contains('demo')) return '🎯'; // Target emoji for demo countries

    // Default flag for unknown countries
    return '🏳️';
  }

// Update city mapping to match your structure
  Map<String, dynamic> _mapCityData(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      print('Mapping city document ${doc.id}: $data');

      if (data == null) {
        return {
          'id': doc.id,
          'cityName': 'Unknown City',
          'agentName': 'Unknown Agent',
          'agentEmail': '',
        };
      }

      return {
        'id': doc.id,
        'cityName': data['city'] ?? data['name'] ?? 'Unknown City', // Use 'city' or 'name' field
        'agentName': data['name'] ?? 'Unknown Agent', // Use 'name' field
        'agentEmail': data['email'] ?? '',
        'phoneNumber': data['phoneNumber'] ?? '',
        'countryAgentId': data['countryAgentId'] ?? '',
        'isActive': data['isActive'] ?? true,
      };
    } catch (e) {
      print('Error mapping city document ${doc.id}: $e');
      return {
        'id': doc.id,
        'cityName': 'Unknown City',
        'agentName': 'Unknown Agent',
        'agentEmail': '',
      };
    }
  }

// Update branch mapping to match your structure
  Map<String, dynamic> _mapBranchData(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      print('Mapping branch document ${doc.id}: $data');

      if (data == null) {
        return _getDefaultBranchData(doc.id);
      }

      // Base mapping with your actual fields
      final mapped = {
        'id': doc.id,
        'branchName': data['name'] ?? 'Unknown Branch',
        'address': data['address'] ?? '',
        'phone': data['phoneNumber'] ?? '',
        'email': data['email'] ?? '',
        'parentAgentId': data['parentAgentId'] ?? '',
        'managerId': data['managerId'] ?? '',
        'agentType': data['agentType'] ?? '',
        'status': data['status'] ?? 'active',
        'uid': data['uid'] ?? '',
        'paypalEmail': data['paypalEmail'] ?? '',

        // Subscription related fields
        'hasActiveSubscription': data['hasActiveSubscription'] ?? false,
        'hasPOSSubscription': data['hasPOSSubscription'] ?? false,
        'subscriptionActivatedAt': data['subscriptionActivatedAt'],
        'trialEndDate': data['trialEndDate'],
        'trialStartDate': data['trialStartDate'],
        'trialInitializedAt': data['trialInitializedAt'],
        'maxTrialExtensions': data['maxTrialExtensions'] ?? 0,
        'trialExtensionCount': data['trialExtensionCount'] ?? 0,
        'trialExtensionsUsed': data['trialExtensionsUsed'] ?? 0,
        'createdAt': data['createdAt'],
        'updatedAt': data['updatedAt'],

        // Child agent management
        'childAgentIds': data['childAgentIds'] ?? [],

        // Determine if accepting orders based on subscription and status
        'isActive': data['isActive'] ?? false,
        'isAcceptingOrders': _determineAcceptingOrders(data),
      };

      // Add rating (default since not in your data)
      mapped['rating'] = 4.0; // Default rating since not in your data

      // Add location coordinates (not in your current data)
      mapped['latitude'] = _parseCoordinate(data['latitude']);
      mapped['longitude'] = _parseCoordinate(data['longitude']);

      // Calculate distance and service area if user location is available
      if (userLocation != null &&
          mapped['latitude'] != null &&
          mapped['longitude'] != null) {
        final distance = LocationService.calculateDistance(
          userLocation!.latitude,
          userLocation!.longitude,
          mapped['latitude']!,
          mapped['longitude']!,
        );

        mapped['distance'] = distance;
        mapped['isWithinServiceArea'] = distance <= serviceRadiusKm;
        mapped['formattedDistance'] = LocationService.getFormattedDistance(distance);
      } else {
        // Default values when location is not available
        mapped['distance'] = null;
        mapped['isWithinServiceArea'] = true;
        mapped['formattedDistance'] = 'Distance unknown';
      }

      // Add service availability status
      mapped['serviceStatus'] = _getServiceStatus(mapped);

      return mapped;
    } catch (e) {
      print('Error mapping branch document ${doc.id}: $e');
      return _getDefaultBranchData(doc.id);
    }
  }


  bool _determineAcceptingOrders(Map<String, dynamic> data) {
    // Check if the branch is active
    final isActive = data['isActive'] as bool? ?? false;
    if (!isActive) return false;

    // Check subscription status
    final hasActiveSubscription = data['hasActiveSubscription'] as bool? ?? false;
    final status = data['status'] as String? ?? '';

    // Branch is accepting orders if:
    // 1. It's active AND
    // 2. Has active subscription OR is in active trial
    return isActive && (hasActiveSubscription || status == 'trial_active');
  }




// Helper method for default branch data
  Map<String, dynamic> _getDefaultBranchData(String docId) {
    return {
      'id': docId,
      'branchName': 'Unknown Branch',
      'address': '',
      'phone': '',
      'isAcceptingOrders': true,
      'rating': 0.0,
      'latitude': null,
      'longitude': null,
      'distance': null,
      'isWithinServiceArea': true,
      'formattedDistance': 'Distance unknown',
      'serviceStatus': 'Available',
    };
  }

// Helper method to parse coordinate values safely
  double? _parseCoordinate(dynamic coordinate) {
    if (coordinate == null) return null;

    if (coordinate is double) return coordinate;
    if (coordinate is int) return coordinate.toDouble();
    if (coordinate is String) {
      return double.tryParse(coordinate);
    }

    return null;
  }

// Helper method to determine service status
  String _getServiceStatus(Map<String, dynamic> branchData) {
    final isAcceptingOrders = branchData['isAcceptingOrders'] as bool? ?? false;
    final status = branchData['status'] as String? ?? '';

    // Check if branch is not accepting orders
    if (!isAcceptingOrders) {
      if (status == 'trial_expired') {
        return 'Trial Expired';
      }
      return 'Currently Closed';
    }

    if (branchData['distance'] == null) {
      return 'Available';
    }

    if (branchData['isWithinServiceArea']) {
      return 'Available in your area';
    } else {
      return 'Outside service area';
    }
  }






  void _handleError(String message, dynamic error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$message. Please try again.'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _fetchAllBranchesByLocation(), // Corrected: Call the main fetch function
        ),
      ),
    );
  }

  Future<void> _loadCities(String countryAgentId) async {  // Changed parameter
    _clearDependentData(['cities', 'branches']);
    await _executeWithLoading(
          () => _setLoadingState('cities', true),
          () => _fetchCities(countryAgentId),  // Pass the ID
          () => _setLoadingState('cities', false),
    );
  }

  Future<void> _fetchCities(String countryAgentId) async {
    try {
      print('Fetching city agents for country agent ID: $countryAgentId');

      cities = await _fetchCollection(
        'cityAgents',
        {
          'countryAgentId': countryAgentId,
          'isActive': true  // Add this filter back
        },
        '',
        _mapCityData,
      );


      print('City agents fetched: ${cities.length}');

      // Filter active cities in code since some have isActive field
      cities = cities.where((city) => city['isActive'] == true).toList();
      print('Active city agents: ${cities.length}');

      if (cities.isEmpty) {
        print('Warning: No active city agents found for country agent: $countryAgentId');
      }
    } catch (e) {
      print('Error fetching city agents: $e');
      _handleFirestoreError('city agents', e);
      rethrow;
    }
  }




  Future<void> _loadLocalBranches(String cityAgentId) async {
    _clearDependentData(['branches']);
    await _executeWithLoading(
          () => _setLoadingState('branches', true),
          () async {
        await _fetchBranches(cityAgentId);
        // ADD THIS: Process branches with location data after fetching
        if (userLocation != null) {
          await _processBranchesWithLocation();
        } else {
          // Set default values when no location available
          _setDefaultBranchLocationData();
        }
      },
          () => _setLoadingState('branches', false),
    );
  }

  void _setDefaultBranchLocationData() {
    for (var branch in localBranches) {
      branch['distance'] = null;
      branch['formattedDistance'] = 'Distance unknown';
      branch['isWithinServiceArea'] = true;
      branch['serviceStatus'] = _getServiceStatus(branch);
    }
  }

  Future<void> _fetchBranches(String cityAgentId) async {
    try {
      print('Fetching branches for city agent ID: $cityAgentId');

      // Fetch branches using parentAgentId - remove hasActiveSubscription filter
      localBranches = await _fetchCollection(
        'branches',
        {
          'parentAgentId': cityAgentId, // Use parentAgentId instead of cityAgentId
          // Remove hasActiveSubscription filter since we'll filter in code
        },
        '',
        _mapBranchData,
      );

      print('Branches fetched: ${localBranches.length}');

      // Filter branches that should be shown (active ones)
      localBranches = localBranches.where((branch) {
        final isActive = branch['isActive'] as bool? ?? false;
        return isActive; // Only show active branches
      }).toList();

      print('Active branches: ${localBranches.length}');

      // Enhanced processing after fetching
      await _processBranchesWithLocation();
    } catch (e) {
      print('Error fetching branches: $e');
      _handleFirestoreError('branches', e);
      rethrow;
    }
  }

  Future<void> _processBranchesWithLocation() async {
    if (localBranches.isEmpty || userLocation == null) return;

    // Calculate distances for all branches
    _calculateBranchDistances();

    // Sort branches by distance (nearest first)
    _sortBranchesByDistanceInPlace();

    // Update service availability based on current location
    _updateServiceAvailability();

    // Update UI to show all branches with distances
    if (mounted) {
      setState(() {
        showManualSelection = false; // Location is available
      });
    }

    // Auto-select nearest available branch (but allow manual override)
    await _autoSelectNearestBranchIfNoneSelected();
  }


  Future<void> _autoSelectNearestBranchIfNoneSelected() async {
    // Only auto-select if no branch is currently selected
    if (selectedLocalBranch != null || userLocation == null || localBranches.isEmpty) {
      return;
    }

    // Filter branches within service radius and accepting orders
    final availableBranches = localBranches.where((branch) {
      final isWithinRadius = branch['isWithinServiceArea'] as bool? ?? false;
      final isAcceptingOrders = branch['isAcceptingOrders'] as bool? ?? false;
      return isWithinRadius && isAcceptingOrders;
    }).toList();

    if (availableBranches.isEmpty) {
      // No branches in service area, show message but don't auto-select
      _showNoNearbyBranchesMessage();
      return;
    }

    // Get the nearest branch (list is already sorted by distance)
    final nearestBranch = availableBranches.first;

    // Auto-select the nearest branch
    if (mounted) {
      setState(() {
        selectedLocalBranch = nearestBranch['branchName'];
        selectedBranchData = nearestBranch;
      });
    }

    // Show auto-selection notification
    _showAutoSelectionNotification(nearestBranch);
  }


  void _showAutoSelectionNotification(Map<String, dynamic> branch) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.auto_fix_high, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auto-selected nearest branch',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${branch['branchName']} (${branch['formattedDistance']})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: successGreen,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Change',
          textColor: Colors.white,
          onPressed: () {
            // Scroll to branches section or show selection hint
            _showManualSelectionHint();
          },
        ),
      ),
    );
  }

// New method to show manual selection hint
  void _showManualSelectionHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tap any branch below to select it manually'),
        backgroundColor: lightBlue,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

// New method to show no nearby branches message
  void _showNoNearbyBranchesMessage() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.location_off, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('No branches found in your immediate area. Please select manually from the list below.'),
            ),
          ],
        ),
        backgroundColor: warningOrange,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }




  void _calculateBranchDistances() {
    if (userLocation == null) return;

    for (var branch in localBranches) {
      final lat = branch['latitude'] as double?;
      final lng = branch['longitude'] as double?;

      if (lat != null && lng != null) {
        final distance = LocationService.calculateDistance(
          userLocation!.latitude,
          userLocation!.longitude,
          lat,
          lng,
        );

        branch['distance'] = distance;
        branch['isWithinServiceArea'] = distance <= serviceRadiusKm;
        branch['formattedDistance'] = LocationService.getFormattedDistance(distance);
      } else {
        // Handle branches without coordinates
        branch['distance'] = null;
        branch['isWithinServiceArea'] = true; // Assume available for manual selection
        branch['formattedDistance'] = 'Distance unknown';
      }

      // Update service status
      branch['serviceStatus'] = _getServiceStatus(branch);
    }
  }

// NEW: Sort branches by distance in place
  void _sortBranchesByDistanceInPlace() {
    localBranches.sort((a, b) {
      final distanceA = a['distance'] as double?;
      final distanceB = b['distance'] as double?;
      final isAcceptingA = a['isAcceptingOrders'] as bool? ?? false;
      final isAcceptingB = b['isAcceptingOrders'] as bool? ?? false;

      // First priority: accepting orders
      if (isAcceptingA != isAcceptingB) {
        return isAcceptingB ? 1 : -1; // Accepting orders first
      }

      // Second priority: distance (if both have distance data)
      if (distanceA != null && distanceB != null) {
        return distanceA.compareTo(distanceB);
      }

      // Third priority: branches with known distance over unknown
      if (distanceA != null && distanceB == null) return -1;
      if (distanceA == null && distanceB != null) return 1;

      // Fourth priority: rating
      final ratingA = a['rating'] as double? ?? 0.0;
      final ratingB = b['rating'] as double? ?? 0.0;
      if (ratingA != ratingB) {
        return ratingB.compareTo(ratingA); // Higher rating first
      }

      // Final priority: alphabetical by name
      final nameA = a['branchName'] as String? ?? '';
      final nameB = b['branchName'] as String? ?? '';
      return nameA.compareTo(nameB);
    });
  }

// NEW: Update service availability for all branches
  void _updateServiceAvailability() {
    for (var branch in localBranches) {
      branch['serviceStatus'] = _getServiceStatus(branch);
    }
  }

// NEW: Sort branches when location is not available
  void _sortBranchesByAlternativeCriteria() {
    localBranches.sort((a, b) {
      final isAcceptingA = a['isAcceptingOrders'] as bool? ?? false;
      final isAcceptingB = b['isAcceptingOrders'] as bool? ?? false;

      // First priority: accepting orders
      if (isAcceptingA != isAcceptingB) {
        return isAcceptingB ? 1 : -1;
      }

      // Second priority: rating
      final ratingA = a['rating'] as double? ?? 0.0;
      final ratingB = b['rating'] as double? ?? 0.0;
      if (ratingA != ratingB) {
        return ratingB.compareTo(ratingA);
      }

      // Third priority: alphabetical by name
      final nameA = a['branchName'] as String? ?? '';
      final nameB = b['branchName'] as String? ?? '';
      return nameA.compareTo(nameB);
    });
  }



  Future<void> _loadWithState(
      String loadingType,
      Future<void> Function() fetchFunction,
      ) async {
    await _executeWithLoading(
          () => _setLoadingState(loadingType, true),
      fetchFunction,
          () => _setLoadingState(loadingType, false),
    );
  }


  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  T? _findItemByField<T>(List<T> items, String field, dynamic value) {
    try {
      return items.firstWhere((item) =>
      (item as Map<String, dynamic>)[field] == value);
    } catch (e) {
      return null;
    }
  }

  void _onCountrySelected(String countryName) {
    final country = _findItemByField(countries, 'name', countryName);
    if (country == null) return;

    setState(() {
      selectedCountry = countryName;
      _resetDependentSelections();
    });

    // Use the document ID instead of a 'code' field
    _loadCities(country['id']);  // Changed this
  }



  void _onLocalBranchSelected(Map<String, dynamic> branch) {
    if (mounted) {
      setState(() {
        selectedLocalBranch = branch['branchName'];
        selectedBranchData = branch;
      });
    }

    // Show selection confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Selected: ${branch['branchName']}'),
            ),
          ],
        ),
        backgroundColor: successGreen,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }


  void _resetDependentSelections() {
    cities.clear();
    localBranches.clear();
    selectedCity = null;
    selectedLocalBranch = null;
    selectedBranchData = null;
  }


  void _proceedToSignup() {
    if (selectedLocalBranch == null || selectedBranchData == null) {
      _showErrorSnackBar('Please select a local branch');
      return;
    }

    Navigator.pushNamed(context, '/service-selection', arguments:{
        'localBranch': selectedLocalBranch,
        'branchData': selectedBranchData,
      },
    );
  }


  Future<void> _executeWithLoading(
      VoidCallback setLoading,
      Future<void> Function() execute,
      VoidCallback clearLoading,
      ) async {
    try {
      setLoading();
      await execute();
    } catch (e) {
      _handleError('Operation failed', e);
    } finally {
      clearLoading();
    }
  }

  void _clearDependentData(List<String> types) {
    setState(() {
      for (final type in types) {
        switch (type) {
          case 'cities':
            cities.clear();
            selectedCity = null;
            break;
          case 'branches':
            localBranches.clear();
            selectedLocalBranch = null;
            selectedBranchData = null;
            break;
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Nearest Branch'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAllBranchesByLocation,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAllBranchesByLocation,
        child: _buildBranchSection(), // The branch section is now the main body
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose your location to find available laundry services',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),

        // Country Selection
        _buildSectionTitle('Select Country'),
        const SizedBox(height: 8),
        _buildCountryDropdown(),
        const SizedBox(height: 24),
      ],
    );
  }



  Widget _buildBranchSection() {
    // If location is not granted, show a prompt to enable it.
    if (currentLocationStatus != LocationStatus.active && !isLoadingLocalBranches) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 60, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Location Access Needed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please enable location services to find and select the nearest branch.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('Enable Location'),
                onPressed: _requestLocationPermission,
              ),
            ],
          ),
        ),
      );
    }

    // Show a loading indicator while fetching branches
    if (isLoadingLocalBranches) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show message if no branches were found
    if (localBranches.isEmpty) {
      return _buildEmptyBranchesCard();
    }

    // Display the list of branches
    return _buildBranchList();
  }

  Widget _buildBranchList() {
    return ListView( // Use ListView for the whole section to make it scrollable
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          'Choose your branch to find available laundry services',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),
        _buildLocationToggle(),
        const SizedBox(height: 16),
        _buildServiceAvailabilityBanner(),
        if (selectedLocalBranch != null) _buildSelectionStatusBanner(),
        const SizedBox(height: 8),
        ...localBranches.map((branch) => _buildBranchCard(branch)).toList(),
      ],
    );
  }

  Widget _buildBranchCard(Map<String, dynamic> branch) {
    final isSelected = selectedLocalBranch == branch['branchName'];
    final isAcceptingOrders = branch['isAcceptingOrders'] as bool? ?? false;
    final isWithinServiceArea = branch['isWithinServiceArea'] as bool? ?? true;
    final serviceStatus = branch['serviceStatus'] as String;
    final distance = branch['distance'] as double?;
    final formattedDistance = branch['formattedDistance'] as String? ?? 'Distance unknown';

    return Card(
      elevation: isSelected ? 6 : 2,
      color: isSelected ? primaryBlue.withOpacity(0.1) : null,
      margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? primaryBlue : Colors.transparent,
          width: isSelected ? 2 : 0,
        ),
      ),
      child: ListTile(
        leading: _buildBranchAvatar(branch, isAcceptingOrders, isWithinServiceArea, isSelected),
        title: _buildBranchTitle(branch, isSelected, distance),
        subtitle: _buildBranchSubtitle(branch, serviceStatus, distance, formattedDistance, isWithinServiceArea),
        trailing: _buildBranchTrailing(branch, isSelected),
        onTap: () => _onLocalBranchSelected(branch),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildBranchAvatar(Map<String, dynamic> branch, bool isAcceptingOrders, bool isWithinServiceArea, bool isSelected) {
    return Stack(
      children: [
        CircleAvatar(
          backgroundColor: isAcceptingOrders ? successGreen : warningOrange,
          radius: 24,
          child: Text(
            branch['branchName'][0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        if (!isWithinServiceArea && userLocation != null)
          _buildStatusBadge(Icons.location_off, warningOrange),
        if (isSelected)
          _buildStatusBadge(Icons.check_circle, successGreen),
      ],
    );
  }

  Widget _buildStatusBadge(IconData icon, Color color) {
    return Positioned(
      right: -2,
      bottom: -2,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildBranchTitle(Map<String, dynamic> branch, bool isSelected, double? distance) {
    return Row(
      children: [
        Expanded(
          child: Text(
            branch['branchName'],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isSelected ? primaryBlue : null,
            ),
          ),
        ),
        if (distance != null)
          _buildDistanceIndicator(branch)
        else if (userLocation != null)
          _buildUnknownDistanceChip(),
      ],
    );
  }

  Widget _buildUnknownDistanceChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.location_off, size: 12, color: Colors.grey),
          SizedBox(width: 4),
          Text('Distance unknown', style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBranchSubtitle(Map<String, dynamic> branch, String serviceStatus, double? distance, String formattedDistance, bool isWithinServiceArea) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (branch['address'].isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            branch['address'],
            style: const TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        _buildStatusAndContactRow(branch, serviceStatus),
        if (distance != null && userLocation != null) ...[
          const SizedBox(height: 6),
          _buildDistanceRow(formattedDistance, isWithinServiceArea),
        ],
      ],
    );
  }

  Widget _buildStatusAndContactRow(Map<String, dynamic> branch, String serviceStatus) {
    return Row(
      children: [
        _buildServiceStatusChip(serviceStatus),
        const SizedBox(width: 8),
        if (branch['phone'].isNotEmpty) ...[
          const Icon(Icons.phone, size: 12, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              branch['phone'],
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildServiceStatusChip(String serviceStatus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getServiceStatusColor(serviceStatus).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getServiceStatusIcon(serviceStatus),
            size: 12,
            color: _getServiceStatusColor(serviceStatus),
          ),
          const SizedBox(width: 4),
          Text(
            serviceStatus,
            style: TextStyle(
              fontSize: 10,
              color: _getServiceStatusColor(serviceStatus),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceRow(String formattedDistance, bool isWithinServiceArea) {
    return Row(
      children: [
        Icon(Icons.directions_walk, size: 12, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          formattedDistance,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (isWithinServiceArea ? successGreen : warningOrange).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isWithinServiceArea ? 'In service area' : 'Outside service area',
            style: TextStyle(
              fontSize: 9,
              color: isWithinServiceArea ? successGreen : warningOrange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBranchTrailing(Map<String, dynamic> branch, bool isSelected) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? successGreen : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isSelected ? Icons.check : Icons.radio_button_unchecked,
            color: isSelected ? Colors.white : Colors.grey.shade600,
            size: 20,
          ),
        ),
        const SizedBox(height: 8),
        _buildRatingWidget(branch),
      ],
    );
  }

  Widget _buildRatingWidget(Map<String, dynamic> branch) {
    final rating = branch['rating'] as double? ?? 0.0;

    if (rating > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14, color: Colors.amber),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      );
    }

    return Text(
      'New',
      style: TextStyle(
        fontSize: 10,
        color: Colors.grey.shade600,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildEmptyBranchesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.store_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'No local branches available in this city',
              style: TextStyle(fontSize: 16),
            ),
            Text(
              'Please try another city or check back later',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildBottomNavigationBar() {
    if (selectedLocalBranch == null) return null;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: _proceedToSignup,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Continue to Sign Up',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }




  // Widget _buildDebugInfo() {
  //   return Container(
  //     padding: const EdgeInsets.all(8),
  //     decoration: BoxDecoration(
  //       color: Colors.grey.shade100,
  //       borderRadius: BorderRadius.circular(4),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Text('Debug Info:', style: TextStyle(fontWeight: FontWeight.bold)),
  //         Text('Countries loaded: ${countries.length}'),
  //         if (countries.isNotEmpty) ...[
  //           Text('Sample country: ${countries.first['name']} (${countries.first['cityAgentsCount']} cities)'),
  //         ],
  //         Text('Selected Country: $selectedCountry'),
  //         Text('Cities loaded: ${cities.length}'),
  //         Text('Selected City: $selectedCity'),
  //         Text('Local Branches loaded: ${localBranches.length}'),
  //         Text('Selected Branch: $selectedLocalBranch'),
  //         Text('Loading Countries: $isLoadingCountries'),
  //         Text('Loading Cities: $isLoadingCities'),
  //         Text('Loading Branches: $isLoadingLocalBranches'),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildCountryDropdown() {
    if (isLoadingCountries) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (countries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: const [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('No countries available'),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedCountry,
          hint: const Text('Choose a country'),
          isExpanded: true,
          items: countries.map((country) {
            return DropdownMenuItem<String>(
              value: country['name'],
              child: Row(
                children: [
                  Text('${country['flag']} '),
                  Expanded(
                    child: Text(
                      country['name'],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Optionally show city count
                  if (country['cityAgentsCount'] > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${country['cityAgentsCount']} cities',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _onCountrySelected(value);
            }
          },
        ),
      ),
    );
  }


  Widget _buildCityList() {
    if (isLoadingCities) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (cities.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: const [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('No cities available in this country'),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cities.length,
        itemBuilder: (context, index) {
          final city = cities[index];
          final isSelected = selectedCity == city['cityName'];

          return Container(
            width: 200,
            margin: const EdgeInsets.only(right: 12),
            child: Card(
              elevation: isSelected ? 4 : 1,
              color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
              child: InkWell(
                onTap: () => _onCitySelected(city),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              city['cityName'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isSelected ? Theme.of(context).primaryColor : null,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Agent: ${city['agentName']}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocalBranchList() {
    if (isLoadingLocalBranches) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (localBranches.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.store_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'No local branches available in this city',
                style: TextStyle(fontSize: 16),
              ),
              Text(
                'Please try another city or check back later',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Fixed header section (non-scrollable)
        Column(
          children: [
            // Location toggle
            _buildLocationToggle(),
            const SizedBox(height: 16),

            // Service availability banner
            _buildServiceAvailabilityBanner(),

            // Selection status banner
            if (selectedLocalBranch != null)
              _buildSelectionStatusBanner(),
          ],
        ),

        // Scrollable branch list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8),
            itemCount: localBranches.length,
            itemBuilder: (context, index) {
              final branch = localBranches[index];
              final isSelected = selectedLocalBranch == branch['branchName'];
              final isAcceptingOrders = branch['isAcceptingOrders'] as bool? ?? false;
              final isWithinServiceArea = branch['isWithinServiceArea'] as bool? ?? true;
              final serviceStatus = branch['serviceStatus'] as String;
              final distance = branch['distance'] as double?;
              final formattedDistance = branch['formattedDistance'] as String? ?? 'Distance unknown';

              return Card(
                elevation: isSelected ? 6 : 2,
                color: isSelected ? primaryBlue.withOpacity(0.1) : null,
                margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? primaryBlue : Colors.transparent,
                    width: isSelected ? 2 : 0,
                  ),
                ),
                child: ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: isAcceptingOrders ? successGreen : warningOrange,
                        radius: 24,
                        child: Text(
                          branch['branchName'][0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      if (!isWithinServiceArea && userLocation != null)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.location_off,
                              size: 14,
                              color: warningOrange,
                            ),
                          ),
                        ),
                      if (isSelected)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_circle,
                              size: 16,
                              color: successGreen,
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          branch['branchName'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isSelected ? primaryBlue : null,
                          ),
                        ),
                      ),
                      // Distance indicator - always show if available
                      if (distance != null)
                        _buildDistanceIndicator(branch)
                      else if (userLocation != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.location_off, size: 12, color: Colors.grey),
                              SizedBox(width: 4),
                              Text(
                                'Distance unknown',
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (branch['address'].isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          branch['address'],
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Service status and contact info row
                      Row(
                        children: [
                          // Service status
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getServiceStatusColor(serviceStatus).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getServiceStatusIcon(serviceStatus),
                                  size: 12,
                                  color: _getServiceStatusColor(serviceStatus),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  serviceStatus,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: _getServiceStatusColor(serviceStatus),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Phone number
                          if (branch['phone'].isNotEmpty) ...[
                            const Icon(Icons.phone, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                branch['phone'],
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Distance info row (if available and location enabled)
                      if (distance != null && userLocation != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.directions_walk,
                              size: 12,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formattedDistance,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (isWithinServiceArea)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: successGreen.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'In service area',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: successGreen,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: warningOrange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Outside service area',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: warningOrange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Selection indicator
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isSelected ? successGreen : Colors.grey.shade300,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isSelected ? Icons.check : Icons.radio_button_unchecked,
                          color: isSelected ? Colors.white : Colors.grey.shade600,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Rating
                      if (branch['rating'] > 0) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              branch['rating'].toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          'New',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: () => _onLocalBranchSelected(branch),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }





// Add this new method for selection status banner
  Widget _buildSelectionStatusBanner() {
    if (selectedLocalBranch == null || selectedBranchData == null) {
      return const SizedBox.shrink();
    }

    final branch = selectedBranchData!;
    final distance = branch['distance'] as double?;
    final formattedDistance = branch['formattedDistance'] as String? ?? '';
    final isWithinServiceArea = branch['isWithinServiceArea'] as bool? ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            successGreen.withOpacity(0.1),
            successGreen.withOpacity(0.05),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: successGreen.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: successGreen,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected: ${selectedLocalBranch}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: successGreen,
                  ),
                ),
                if (distance != null && userLocation != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 12,
                        color: isWithinServiceArea ? successGreen : warningOrange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formattedDistance,
                        style: TextStyle(
                          fontSize: 12,
                          color: isWithinServiceArea ? successGreen : warningOrange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!isWithinServiceArea) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(Outside service area)',
                          style: TextStyle(
                            fontSize: 11,
                            color: warningOrange,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                selectedLocalBranch = null;
                selectedBranchData = null;
              });
              _showManualSelectionHint();
            },
            child: Text(
              'Change',
              style: TextStyle(
                color: successGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }


// Helper methods for service status styling
  Color _getServiceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'available in your area':
        return successGreen;
      case 'available':
        return lightBlue;
      case 'currently closed':
        return warningOrange;
      case 'trial expired':
        return errorRed;
      case 'outside service area':
        return errorRed;
      default:
        return Colors.grey;
    }
  }


  IconData _getServiceStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'available in your area':
        return Icons.check_circle;
      case 'available':
        return Icons.store;
      case 'currently closed':
        return Icons.access_time;
      case 'trial expired':
        return Icons.block;
      case 'outside service area':
        return Icons.location_off;
      default:
        return Icons.info;
    }
  }


  Future<bool> _requestLocationPermission() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _updateLocationState(locationEnabled: false);
        _showLocationServiceDialog();
        return false;
      }

      _updateLocationState(locationEnabled: true);

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // Request permission
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _updateLocationState(permissionStatus: LocationPermissionStatus.denied);
          _showLocationPermissionDialog(
            'Location Permission Denied',
            'Location access is required to find nearby branches. Please enable location permission in settings.',
            showSettings: true,
          );
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _updateLocationState(permissionStatus: LocationPermissionStatus.permanentlyDenied);
        _showLocationPermissionDialog(
          'Location Permission Required',
          'Location permission is permanently denied. Please enable it in app settings to find nearby branches.',
          showSettings: true,
        );
        return false;
      }

      // Permission granted, update state
      _updateLocationState(
        locationEnabled: true,
        permissionStatus: LocationPermissionStatus.granted,
      );

      // Get current location using Geolocator directly
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );

        _updateLocationState(location: position);
        print('Location granted and obtained: ${position.latitude}, ${position.longitude}');

        // Reload branches with location data if already loaded
        if (localBranches.isNotEmpty) {
          await _processBranchesWithLocation();
        }

        return true;
      } catch (e) {
        print('Error getting location after permission granted: $e');
        _handleLocationError('Failed to get current location', e);
        return false;
      }
    } catch (e) {
      _handleLocationError('Location permission request failed', e);
      return false;
    }
  }


  void _showLocationPermissionDialog(String title, String message, {bool showSettings = false}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (showSettings)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await Geolocator.openAppSettings();
                },
                child: const Text('Open Settings'),
              )
            else
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _requestLocationPermission();
                },
                child: const Text('Retry'),
              ),
          ],
        );
      },
    );
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text(
            'Location services are disabled on your device. Please enable them to find nearby laundry branches.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await Geolocator.openLocationSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

// Enhanced error handling methods

  void _handleLocationError(String message, dynamic error) {
    if (!mounted) return;

    // Log the error for debugging
    debugPrint('Location Error: $message - $error');

    // Update location state to reflect error
    _updateLocationState(
      locationEnabled: false,
      permissionStatus: LocationPermissionStatus.denied,
      manualSelection: true,
    );

    // Show user-friendly error message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location Error',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('$message. You can still select branches manually.'),
          ],
        ),
        backgroundColor: warningOrange,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () => _requestLocationPermission(),
        ),
      ),
    );

    // Automatically fallback to manual selection
    _fallbackToManualSelection();
  }


  void _fallbackToManualSelection() {
    if (!mounted) return;

    // Update state to manual selection mode
    _updateLocationState(
      locationEnabled: false,
      permissionStatus: LocationPermissionStatus.denied,
      location: null,
      manualSelection: true,
    );

    // Clear any location-dependent data from branches
    _clearLocationDataFromBranches();

    // Show informational message about manual selection
    _showManualSelectionInfo();

    // If branches are already loaded, refresh them without location data
    if (localBranches.isNotEmpty && selectedCity != null) {
      final selectedCityData = cities.firstWhere(
            (city) => city['cityName'] == selectedCity,
        orElse: () => <String, dynamic>{},
      );

      if (selectedCityData.isNotEmpty) {
        _loadLocalBranches(selectedCityData['id']);
      }
    }
  }


  void _clearLocationDataFromBranches() {
    for (var branch in localBranches) {
      branch['distance'] = null;
      branch['isWithinServiceArea'] = true; // Assume available for manual selection
      branch['formattedDistance'] = 'Distance unknown';
      branch['serviceStatus'] = _getServiceStatus(branch);
    }

    // Re-sort branches using alternative criteria
    _sortBranchesByAlternativeCriteria();

    if (mounted) {
      setState(() {});
    }
  }

// Show information about manual selection mode
  void _showManualSelectionInfo() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Switched to manual selection. All branches are shown without distance information.',
              ),
            ),
          ],
        ),
        backgroundColor: lightBlue,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Enable Location',
          textColor: Colors.white,
          onPressed: () => _requestLocationPermission(),
        ),
      ),
    );
  }

// Enhanced error handling for network/Firestore errors
  void _handleFirestoreError(String operation, dynamic error) {
    if (!mounted) return;

    debugPrint('Firestore Error during $operation: $error');

    String userMessage;
    String actionLabel = 'Retry';
    VoidCallback? actionCallback;

    // Determine error type and appropriate message
    if (error.toString().contains('network') ||
        error.toString().contains('connection') ||
        error.toString().contains('timeout')) {
      userMessage = 'Network connection issue. Please check your internet connection.';
      actionCallback = () => _retryLastOperation();
    } else if (error.toString().contains('permission')) {
      userMessage = 'Access denied. Please check your app permissions.';
      actionLabel = 'Settings';
      actionCallback = () => _openAppSettings();
    } else {
      userMessage = 'Unable to load $operation. Please try again.';
      actionCallback = () => _retryLastOperation();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Connection Error',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(userMessage),
          ],
        ),
        backgroundColor: errorRed,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: actionCallback != null
            ? SnackBarAction(
          label: actionLabel,
          textColor: Colors.white,
          onPressed: actionCallback,
        )
            : null,
      ),
    );
  }

// Retry the last failed operation
  void _retryLastOperation() {
    // The only operation to retry now is fetching all branches based on location.
    _fetchAllBranchesByLocation();
  }

// Open app settings
  void _openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      _showErrorSnackBar('Unable to open app settings');
    }
  }


// Add these methods after the existing location permission methods

  Future<void> _autoSelectNearestBranch() async {
    if (userLocation == null || localBranches.isEmpty) return;

    // Filter branches within service radius
    final availableBranches = _filterBranchesWithinRadius();

    if (availableBranches.isEmpty) {
      _showErrorSnackBar('No branches available in your service area');
      return;
    }

    // Sort by distance and select the nearest
    final sortedBranches = _sortBranchesByDistance(availableBranches);
    final nearestBranch = sortedBranches.first;

    // Auto-select the nearest branch
    _onLocalBranchSelected(nearestBranch);

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Auto-selected nearest branch: ${nearestBranch['branchName']} (${nearestBranch['formattedDistance']})',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<Map<String, dynamic>> _sortBranchesByDistance(List<Map<String, dynamic>>? branches) {
    final branchesToSort = branches ?? localBranches;

    if (userLocation == null) return branchesToSort;

    // Create a copy to avoid modifying the original list
    final sortedBranches = List<Map<String, dynamic>>.from(branchesToSort);

    sortedBranches.sort((a, b) {
      final distanceA = a['distance'] as double?;
      final distanceB = b['distance'] as double?;

      // Handle null distances (put them at the end)
      if (distanceA == null && distanceB == null) return 0;
      if (distanceA == null) return 1;
      if (distanceB == null) return -1;

      return distanceA.compareTo(distanceB);
    });

    return sortedBranches;
  }

  List<Map<String, dynamic>> _filterBranchesWithinRadius() {
    if (userLocation == null) return localBranches;

    return localBranches.where((branch) {
      final isWithinRadius = branch['isWithinServiceArea'] as bool? ?? false;
      final isAcceptingOrders = branch['isAcceptingOrders'] as bool? ?? false;

      return isWithinRadius && isAcceptingOrders;
    }).toList();
  }




  Widget _buildLocationToggle() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: currentLocationStatus == LocationStatus.active
                      ? successGreen
                      : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Use My Location',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: currentLocationStatus == LocationStatus.active,
                  onChanged: _handleLocationToggle,
                  activeColor: successGreen,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _getLocationStatusText(),
              style: TextStyle(
                fontSize: 12,
                color: _getLocationStatusColor(),
              ),
            ),
            if (currentLocationStatus == LocationStatus.active && userLocation != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: successGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Location detected • Finding nearby branches',
                  style: TextStyle(
                    fontSize: 11,
                    color: successGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

// NEW: Handle location toggle
  void _handleLocationToggle(bool value) async {
    if (value) {
      // User wants to enable location
      final success = await _requestLocationPermission();
      if (success && localBranches.isNotEmpty) {
        // Reload branches with location data
        final selectedCityData = cities.firstWhere(
              (city) => city['cityName'] == selectedCity,
        );
        await _loadLocalBranches(selectedCityData['id']);
      }
    } else {
      // User wants to disable location
      _updateLocationState(
        location: null,
        manualSelection: true,
      );
      // Reload branches without location data
      if (localBranches.isNotEmpty) {
        final selectedCityData = cities.firstWhere(
              (city) => city['cityName'] == selectedCity,
        );
        await _loadLocalBranches(selectedCityData['id']);
      }
    }
  }

// NEW: Get location status text
  String _getLocationStatusText() {
    switch (currentLocationStatus) {
      case LocationStatus.active:
        return 'Location enabled • Showing distances to branches';
      case LocationStatus.loading:
        return 'Getting your location...';
      case LocationStatus.serviceDisabled:
        return 'Location services are disabled';
      case LocationStatus.permissionDenied:
        return 'Location permission denied';
      case LocationStatus.permissionPermanentlyDenied:
        return 'Location permission permanently denied';
      case LocationStatus.unknown:
        return 'Tap to enable location for better results';
    }
  }

// NEW: Get location status color
  Color _getLocationStatusColor() {
    switch (currentLocationStatus) {
      case LocationStatus.active:
        return successGreen;
      case LocationStatus.loading:
        return lightBlue;
      case LocationStatus.serviceDisabled:
      case LocationStatus.permissionDenied:
      case LocationStatus.permissionPermanentlyDenied:
        return errorRed;
      case LocationStatus.unknown:
        return Colors.grey;
    }
  }

// NEW: Build distance indicator widget
  Widget _buildDistanceIndicator(Map<String, dynamic> branch) {
    final distance = branch['distance'] as double?;
    final formattedDistance = branch['formattedDistance'] as String;
    final isWithinServiceArea = branch['isWithinServiceArea'] as bool? ?? true;

    if (distance == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.location_off, size: 12, color: Colors.grey),
            SizedBox(width: 4),
            Text(
              'Distance unknown',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isWithinServiceArea
            ? successGreen.withOpacity(0.1)
            : warningOrange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWithinServiceArea ? Icons.location_on : Icons.location_off,
            size: 12,
            color: isWithinServiceArea ? successGreen : warningOrange,
          ),
          const SizedBox(width: 4),
          Text(
            formattedDistance,
            style: TextStyle(
              fontSize: 10,
              color: isWithinServiceArea ? successGreen : warningOrange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

// NEW: Build service availability banner
  Widget _buildServiceAvailabilityBanner() {
    if (localBranches.isEmpty) return const SizedBox.shrink();

    final availableBranches = localBranches.where(
          (branch) => branch['isAcceptingOrders'] as bool? ?? false,
    ).length;

    final withinServiceArea = userLocation != null
        ? localBranches.where(
          (branch) => (branch['isWithinServiceArea'] as bool? ?? true) &&
          (branch['isAcceptingOrders'] as bool? ?? false),
    ).length
        : availableBranches;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryBlue.withOpacity(0.1),
            accentBlue.withOpacity(0.05),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryBlue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Service Availability',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildAvailabilityChip(
                '$availableBranches Available',
                successGreen,
                Icons.check_circle,
              ),
              const SizedBox(width: 8),
              if (userLocation != null)
                _buildAvailabilityChip(
                  '$withinServiceArea Near You',
                  lightBlue,
                  Icons.location_on,
                ),
            ],
          ),
          if (userLocation != null && withinServiceArea == 0) ...[
            const SizedBox(height: 8),
            Text(
              'No branches in your immediate area. Consider expanding your search or selecting manually.',
              style: TextStyle(
                fontSize: 11,
                color: warningOrange,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

// Helper for availability chips
  Widget _buildAvailabilityChip(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }


}
