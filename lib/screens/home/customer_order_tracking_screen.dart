import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../customer_confirmation_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomerOrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String branchId;

  const CustomerOrderTrackingScreen({
    Key? key,
    required this.orderId,
    required this.branchId
  }) : super(key: key);

  @override
  State<CustomerOrderTrackingScreen> createState() => _CustomerOrderTrackingScreenState();
}

class _CustomerOrderTrackingScreenState extends State<CustomerOrderTrackingScreen> {
  GoogleMapController? _mapController;
  Position? _customerLocation;
  bool _showMap = false;
  bool _confirmationDialogShown = false;
  bool _hasVisitedConfirmationScreen = false;
  Timer? _locationUpdateTimer;
  BitmapDescriptor? _driverIcon;
  StreamSubscription<DocumentSnapshot>? _orderSubscription;
  Map<String, dynamic>? _orderData;
  String? _previousStatus; // Crucial for detecting status *changes*
  bool _isLoading = true;
  bool _isCancellable(String status) {
    final cancellableStatuses = [
      'pending',
      'confirmed',
      'en_route',
      'arrived',
    ];
    return cancellableStatuses.contains(status);
  }



  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _startPeriodicLocationUpdates();
    _loadDriverIcon();

    // === NEW STREAM HANDLING LOGIC ===
    // Start listening to the order stream and call _onOrderData whenever new data arrives.
    _orderSubscription = _getOrderStream().listen(
      _onOrderData,
      onError: (error) {
        print('❌ CUSTOMER: Error in order stream: $error');
        if (mounted) {
          setState(() {
            _isLoading = false;
            // You can set an error state here to show a message in the UI
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _orderSubscription?.cancel(); // <-- CRITICAL: Always cancel your subscriptions!
    super.dispose();
  }


  void _onOrderData(DocumentSnapshot snapshot) {
    if (!mounted || !snapshot.exists) {
      setState(() {
        _isLoading = false;
        _orderData = null; // Mark as not found
      });
      return;
    }

    final newOrderData = snapshot.data() as Map<String, dynamic>;
    final newStatus = newOrderData['status'] as String? ?? 'pending';

    // === EVENT HANDLING LOGIC ===
    // Check if the status has CHANGED to something that requires a dialog.
    // This prevents the dialog from showing on every single location update.
    if (newStatus != _previousStatus) {
      // Call your confirmation logic only when the status changes.
      _checkForConfirmationRequest(newOrderData);
    }

    // === STATE UPDATE LOGIC ===
    // Now, update all state variables inside a single setState call.
    setState(() {
      _orderData = newOrderData;
      _showMap = _shouldShowMap(newStatus);
      _previousStatus = newStatus; // Remember the status for the next update
      _isLoading = false;
    });
  }





  Future<void> _initializeLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _customerLocation = position;
      });
      
      // Update customer location in the order document so driver can see it
      await _updateCustomerLocationInOrder(position);
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  void _startPeriodicLocationUpdates() {
    // Update customer location every 30 seconds so driver always has current location
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition();
        setState(() {
          _customerLocation = position;
        });
        await _updateCustomerLocationInOrder(position);
      } catch (e) {
        print('❌ CUSTOMER: Failed periodic location update: $e');
      }
    });
  }

  Future<void> _updateCustomerLocationInOrder(Position position) async {
    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('mobileOrders')
          .doc(widget.orderId)
          .update({
        'customerLocation': {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        'customerLastLocationUpdate': FieldValue.serverTimestamp(),
      });
      
      print('✅ CUSTOMER: Location updated in order document for driver visibility');
    } catch (e) {
      print('❌ CUSTOMER: Failed to update location in order: $e');
    }
  }

  Future<void> _loadDriverIcon() async {
    try {
      // Load the custom driver icon from assets - make it very tiny
      final customIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(16, 16)),
        'assets/images/cargotruck.png',
      );
      setState(() {
        _driverIcon = customIcon;
      });
      print('✅ Driver icon loaded successfully');
    } catch (e) {
      print('❌ Failed to load driver icon: $e');
      // Fallback to default green marker if custom icon fails to load
      setState(() {
        _driverIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Navigate to home screen instead of going back
        Navigator.pushReplacementNamed(context, '/home');
        return false; // Prevent default back behavior
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Track Order'),
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {
              // Navigate to home screen instead of going back
              Navigator.pushReplacementNamed(context, '/home');
            },
          ),
          actions: [
            if (_orderData != null && _isCancellable(_orderData!['status']))
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: TextButton(
                  onPressed: _cancelOrder,
                  child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
          // Real-time connection indicator
          StreamBuilder<DocumentSnapshot>(
            stream: _getOrderStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.active) {
                return Container(
                  margin: EdgeInsets.only(right: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text('LIVE', style: TextStyle(fontSize: 10, color: Colors.green)),
                    ],
                  ),
                );
              }
              return Container(
                margin: EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text('OFFLINE', style: TextStyle(fontSize: 10, color: Colors.red)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
        body: _isLoading
            ? _buildLoadingWidget() // Show loader while waiting for the first data packet
            : _orderData == null
            ? _buildNotFoundWidget() // Show not found if the order doesn't exist
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Get the status from our state variable
              if (_orderData!['status'] == 'delivery_en_route' || _orderData!['status'] == 'delivery_arrived')
                _buildDeliveryBanner(_orderData!['status']),
              if (_orderData!['status'] == 'delivery_en_route' || _orderData!['status'] == 'delivery_arrived')
                const SizedBox(height: 16),

              // Pass the order data to your widgets
              _buildOrderInfo(_orderData!),
              const SizedBox(height: 20),
              if (_showMap && _shouldShowMap(_orderData!['status']))
                _buildMapSection(_orderData!),
              if (_showMap && _shouldShowMap(_orderData!['status']))
                const SizedBox(height: 20),
              _buildDriverInfo(_orderData!),
              const SizedBox(height: 20),
              _buildStatusTimeline(_orderData!['status']),
            ],
          ),
        ),
      ),
    );
  }

  Stream<DocumentSnapshot> _getOrderStream() {
    print('👤 CUSTOMER: Setting up order stream');
    print('👤 CUSTOMER: Branch ID: ${widget.branchId}');
    print('👤 CUSTOMER: Order ID: ${widget.orderId}');

    // Try to get from branches collection first
    final branchStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('mobileOrders')
        .doc(widget.orderId)
        .snapshots();

    return branchStream;
  }

  void _updateMapVisibility(String status) {
    // Use WidgetsBinding.instance.addPostFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final shouldShow = _shouldShowMap(status);
        if (shouldShow != _showMap) {
          setState(() {
            _showMap = shouldShow;
          });
        }
      }
    });
  }



  bool _shouldShowMap(String status) {
    final showMap = ['confirmed', 'en_route', 'arrived', 'delivery_en_route', 'delivery_arrived'].contains(status);
    print('👤 CUSTOMER: _shouldShowMap for status "$status": $showMap');
    return showMap;
  }


  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text('Error: $error'),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() {}),
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading order details...'),
        ],
      ),
    );
  }

  Widget _buildNotFoundWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Order not found'),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
            child: Text('Go to Home'),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection(Map<String, dynamic> orderData) {
    final driverLocation = orderData['driverLocation'] as Map<String, dynamic>?;

    print('👤 CUSTOMER: Building map section');
    print('👤 CUSTOMER: Driver location data: $driverLocation');
    print('👤 CUSTOMER: Customer location: ${_customerLocation?.latitude}, ${_customerLocation?.longitude}');

    if (driverLocation == null || _customerLocation == null) {
      print('👤 CUSTOMER: ❌ Missing location data - showing placeholder');
      return Container(
        height: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading driver location...'),
              SizedBox(height: 8),
              Text(
                driverLocation == null ? 'Driver location not available' : 'Getting your location...',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    print('👤 CUSTOMER: ✅ Both locations available - showing map');
    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GoogleMap(
          onMapCreated: (controller) {
            _mapController = controller;
            print('👤 CUSTOMER: ✅ Map controller created');
          },
          initialCameraPosition: CameraPosition(
            target: LatLng(
              driverLocation['latitude'],
              driverLocation['longitude'],
            ),
            zoom: 14,
          ),
          markers: _buildMapMarkers(driverLocation),
          polylines: _buildRoutePolyline(driverLocation),
        ),
      ),
    );
  }





  void _fitMapToShowBothLocations(Map<String, dynamic> driverLocation) {
  if (_mapController == null || _customerLocation == null) return;

  final driverLatLng = LatLng(driverLocation['latitude'], driverLocation['longitude']);
  final customerLatLng = LatLng(_customerLocation!.latitude, _customerLocation!.longitude);

  final bounds = LatLngBounds(
    southwest: LatLng(
      [driverLatLng.latitude, customerLatLng.latitude].reduce((a, b) => a < b ? a : b),
      [driverLatLng.longitude, customerLatLng.longitude].reduce((a, b) => a < b ? a : b),
    ),
    northeast: LatLng(
      [driverLatLng.latitude, customerLatLng.latitude].reduce((a, b) => a > b ? a : b),
      [driverLatLng.longitude, customerLatLng.longitude].reduce((a, b) => a > b ? a : b),
    ),
  );

  _mapController!.animateCamera(
    CameraUpdate.newLatLngBounds(bounds, 100.0),
  );
}

  Widget _buildMapPlaceholder() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_searching, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Waiting for driver location...'),
          ],
        ),
      ),
    );
  }

  Set<Marker> _buildMapMarkers(Map<String, dynamic> driverLocation) {
    final markers = <Marker>{};

    // Driver marker - Use custom truck icon or fallback to green marker
    markers.add(Marker(
      markerId: MarkerId('driver'),
      position: LatLng(
        driverLocation['latitude'],
        driverLocation['longitude'],
      ),
      icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: '🚚 Driver Location'),
    ));

    // Customer marker - Keep red pin for customer
    if (_customerLocation != null) {
      markers.add(Marker(
        markerId: MarkerId('customer'),
        position: LatLng(
          _customerLocation!.latitude,
          _customerLocation!.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Your Location'),
      ));
    }

    return markers;
  }

  Set<Polyline> _buildRoutePolyline(Map<String, dynamic> driverLocation) {
    if (_customerLocation == null) return {};

    return {
      Polyline(
        polylineId: PolylineId('route'),
        points: [
          LatLng(driverLocation['latitude'], driverLocation['longitude']),
          LatLng(_customerLocation!.latitude, _customerLocation!.longitude),
        ],
        color: Colors.blue,
        width: 3,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    };
  }

  Widget _buildOrderInfo(Map<String, dynamic> data) {
    final status = data['status'] ?? 'pending';
    final isReadyForDelivery = status == 'ready_for_delivery' || status == 'delivery_en_route' || status == 'delivery_arrived';
    final invoiceAmount = data['amountPaid'] ?? data['invoiceAmount'];
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Order Details'),
            SizedBox(height: 12),
            _buildInfoRow('Total', '${data['totalAmount']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildInfoRow('Items', '${data['services']?.length ?? 0} services'),
            _buildInfoRow('Status', status.toString().toUpperCase()),
            if (data['estimatedArrival'] != null)
              _buildInfoRow('ETA', _formatETA(data['estimatedArrival'])),
            
            // Show invoice amount when ready for delivery
            if (isReadyForDelivery && invoiceAmount != null) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt, color: Colors.orange[700], size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Your Bill is Ready',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Amount to Pay: ${invoiceAmount}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Please have this amount ready when the driver arrives with your clean clothes.',
                      style: TextStyle(
                        color: Colors.orange[600],
                        fontSize: 14,
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

  Widget _buildDriverInfo(Map<String, dynamic> data) {
    if (data['driverId'] == null) {
      return _buildWaitingForDriverCard();
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Driver Information'),
            SizedBox(height: 12),
            if (data['driverInfo'] != null) ...[
              _buildInfoRow('Name', data['driverInfo']['name'] ?? 'Driver'),
              if (data['driverInfo']['vehicleInfo'] != null)
                _buildInfoRow('Vehicle', data['driverInfo']['vehicleInfo']),
            ],
            if (data['driverPhone'] != null) ...[
              SizedBox(height: 12),
              _buildCallDriverButton(data['driverPhone']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingForDriverCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(width: 16),
            Text('Waiting for driver assignment...'),
          ],
        ),
      ),
    );
  }

  Widget _buildCallDriverButton(String phoneNumber) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _callDriver(phoneNumber),
        icon: Icon(Icons.phone),
        label: Text('Call Driver'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildStatusTimeline(String currentStatus) {
    final statuses = _getStatusList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Order Progress'),
            SizedBox(height: 16),
            ...statuses.map((status) => _buildStatusStep(
                status['key']!,
                status['title']!,
                status['desc']!,
                currentStatus
            )).toList(),
          ],
        ),
      ),
    );
  }

  List<Map<String, String>> _getStatusList() {
    return [
      {'key': 'pending', 'title': 'Order Placed', 'desc': 'Waiting for confirmation'},
      {'key': 'confirmed', 'title': 'Confirmed', 'desc': 'Driver assigned'},
      {'key': 'en_route', 'title': 'Driver En Route', 'desc': 'Driver coming to collect'},
      {'key': 'arrived', 'title': 'Driver Arrived', 'desc': 'Driver at your location'},
      {'key': 'collected', 'title': 'Items Collected', 'desc': 'Items picked up'},
      {'key': 'customer_confirmed', 'title': 'Collection Confirmed', 'desc': 'You confirmed collection'},
      {'key': 'delivered_to_shop', 'title': 'At Shop', 'desc': 'Items delivered to shop'},
      {'key': 'invoice_generated', 'title': 'Invoice Created', 'desc': 'Laundry created invoice'},
      {'key': 'processing', 'title': 'Being Processed', 'desc': 'Items being washed'},
      {'key': 'ready_for_delivery', 'title': 'Ready for Delivery', 'desc': 'Bill ready - prepare payment'},
      {'key': 'delivery_assigned', 'title': 'Delivery Assigned', 'desc': 'Driver assigned for delivery'},
      {'key': 'delivery_en_route', 'title': 'Driver Returning', 'desc': 'Driver coming with your items'},
      {'key': 'delivery_arrived', 'title': 'Driver Arrived', 'desc': 'Pay driver and collect items'},
      {'key': 'delivered', 'title': 'Items Delivered', 'desc': 'Items delivered to you'},
      {'key': 'delivery_confirmed', 'title': 'Delivery Confirmed', 'desc': 'You confirmed delivery'},
      {'key': 'completed', 'title': 'Order Complete', 'desc': 'Payment complete - order finished'},
    ];
  }

  Widget _buildStatusStep(String statusKey, String title, String desc, String currentStatus) {
    final isCompleted = _isStatusCompleted(statusKey, currentStatus);
    final isCurrent = currentStatus == statusKey;
    final isDeliveryStatus = statusKey == 'delivery_en_route' || statusKey == 'delivery_arrived';

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (isCurrent && isDeliveryStatus) ? Colors.green[50] : null,
        borderRadius: BorderRadius.circular(8),
        border: (isCurrent && isDeliveryStatus) ? Border.all(color: Colors.green[300]!, width: 2) : null,
      ),
      child: Row(
        children: [
          _buildStatusIndicator(isCompleted, isCurrent, isDeliveryStatus),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isCurrent 
                      ? (isDeliveryStatus ? Colors.green[700] : Colors.blue) 
                      : Colors.black,
                    fontSize: (isCurrent && isDeliveryStatus) ? 16 : 14,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    color: (isCurrent && isDeliveryStatus) ? Colors.green[600] : Colors.grey[600],
                    fontSize: (isCurrent && isDeliveryStatus) ? 13 : 12,
                    fontWeight: (isCurrent && isDeliveryStatus) ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (isCurrent && isDeliveryStatus)
            Icon(
              statusKey == 'delivery_en_route' ? Icons.local_shipping : Icons.location_on,
              color: Colors.green[600],
              size: 20,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(bool isCompleted, bool isCurrent, [bool isDeliveryStatus = false]) {
    Color bgColor;
    IconData iconData;
    
    if (isCompleted) {
      bgColor = Colors.green;
      iconData = Icons.check;
    } else if (isCurrent && isDeliveryStatus) {
      bgColor = Colors.green[600]!;
      iconData = Icons.local_shipping;
    } else if (isCurrent) {
      bgColor = Colors.blue;
      iconData = Icons.circle;
    } else {
      bgColor = Colors.grey[300]!;
      iconData = Icons.circle;
    }
    
    return Container(
      width: isCurrent && isDeliveryStatus ? 24 : 20,
      height: isCurrent && isDeliveryStatus ? 24 : 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        boxShadow: isCurrent && isDeliveryStatus ? [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ] : null,
      ),
      child: Icon(
        iconData,
        size: isCurrent && isDeliveryStatus ? 14 : 12,
        color: Colors.white,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  bool _isStatusCompleted(String statusKey, String currentStatus) {
    final statusOrder = ['pending', 'confirmed', 'en_route', 'arrived', 'collected', 'customer_confirmed', 'delivered_to_shop'];
    final currentIndex = statusOrder.indexOf(currentStatus);
    final statusIndex = statusOrder.indexOf(statusKey);
    return currentIndex > statusIndex;
  }

  String _formatETA(dynamic timestamp) {
    if (timestamp == null) return 'Calculating...';
    // Add your timestamp formatting logic here
    return 'In 15 mins'; // Placeholder
  }

  Future<void> _callDriver(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch phone dialer')),
      );
    }
  }

  void _checkForConfirmationRequest(Map<String, dynamic> orderData) {
    final status = orderData['status'];
    final hasConfirmed = orderData['customerConfirmedAt'] != null;
    final hasDeliveryConfirmed = orderData['deliveryConfirmedAt'] != null;
    final isPaymentPending = (orderData['amountPaid'] ?? orderData['invoiceAmount']) != null &&
        (orderData['invoiceAmount'] ?? 0) > 0 && // Ensure there is an amount to pay
        (orderData['paymentStatus'] ?? '') != 'paid'; // And it's not already paid

    print('🔍 CUSTOMER CONFIRMATION CHECK (Status Changed to: $status):');
    print('   - Has Collection Been Confirmed by User?: $hasConfirmed');
    print('   - Has Delivery Been Confirmed by User?: $hasDeliveryConfirmed');
    print('   - Is Payment Pending?: $isPaymentPending');
    print('   - Has User Already Visited a Confirmation Screen?: $_hasVisitedConfirmationScreen');

    // Case 1: Driver has collected items. Show the collection confirmation screen.
    // This dialog should only appear once per order. The `!hasConfirmed` and `!_hasVisitedConfirmationScreen`
    // checks prevent it from showing again if the user navigates away and back.
    if (status == 'collected' && !hasConfirmed && !_hasVisitedConfirmationScreen) {
      print('📱 ACTION: Status is "collected". Showing collection confirmation dialog.');
      // Using a post-frame callback ensures the dialog is shown after the current build is complete.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showConfirmationDialog(orderData, isDelivery: false);
      });
      return; // Stop further checks
    }

    // Case 2: Driver has arrived for the return delivery AND payment is required.
    // Show the payment options dialog.
    if (status == 'delivery_arrived' && isPaymentPending && !hasDeliveryConfirmed && !_hasVisitedConfirmationScreen) {
      print('📱 ACTION: Status is "delivery_arrived" with pending payment. Showing payment dialog.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPaymentDialog(orderData);
      });
      return; // Stop further checks
    }

    // Case 3: Driver has marked items as "delivered".
    // This is the final confirmation step for the user.
    if (status == 'delivered' && !hasDeliveryConfirmed && !_hasVisitedConfirmationScreen) {
      print('📱 ACTION: Status is "delivered". Showing final delivery confirmation dialog.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showConfirmationDialog(orderData, isDelivery: true);
      });
      return; // Stop further checks
    }

    // This logic should now be handled inside the confirmation screen itself or when the user
    // successfully completes the action. For robustness, we can keep it here as a fallback.
    // It marks that the user has passed the confirmation stage for this order.
    if (hasConfirmed || hasDeliveryConfirmed) {
      if (!_hasVisitedConfirmationScreen) {
        print('✅ Updating local state: User has confirmed this order before. Setting _hasVisitedConfirmationScreen to true.');
        _hasVisitedConfirmationScreen = true;
      }
    }
  }

  void _showConfirmationDialog(Map<String, dynamic> orderData, {bool isDelivery = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isDelivery ? Icons.home_filled : Icons.local_shipping, 
              color: Color(0xFF1E40AF)
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                isDelivery ? 'Driver Delivered Items' : 'Driver Collected Items',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isDelivery 
                ? 'The driver has delivered your clean items and is waiting for your confirmation.'
                : 'The driver has collected your items and is waiting for your confirmation.'
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDelivery ? Colors.green[50] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDelivery ? Colors.green[200]! : Colors.blue[200]!),
                ),
                child: Text(
                  isDelivery 
                    ? 'Please confirm that you received your clean laundry items.'
                    : 'Please confirm that the driver successfully collected your laundry items.',
                  style: TextStyle(color: isDelivery ? Colors.green[800] : Colors.blue[800]),
                ),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _reportIssue();
                  },
                  child: Text('Report Issue'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _hasVisitedConfirmationScreen = true; // Mark as visited
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomerConfirmationScreen(
                          orderId: widget.orderId,
                          branchId: widget.branchId,
                          orderData: orderData,
                          isDelivery: isDelivery,
                        ),
                      ),
                    );
                  },
                  child: Text(isDelivery ? 'Confirm Delivery' : 'Confirm Collection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDelivery ? Colors.green : Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(Map<String, dynamic> orderData) {
    final invoiceAmount = (orderData['amountPaid'] ?? orderData['invoiceAmount'])?.toString() ?? '0';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.payment, color: Colors.orange[700]),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Payment Required',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your laundry is ready for delivery!'),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Column(
                  children: [
                    Text(
                      'Amount to Pay',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${invoiceAmount}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Please choose your payment method:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _goToPaymentScreen(orderData, 'Cash');
                  },
                  child: Text('💰 Pay Cash'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _goToPaymentScreen(orderData, 'eBalance');
                  },
                  child: Text('💳 Pay with eBalance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _goToPaymentScreen(Map<String, dynamic> orderData, String paymentMethod) {
    _hasVisitedConfirmationScreen = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerConfirmationScreen(
          orderId: widget.orderId,
          branchId: widget.branchId,
          orderData: orderData,
          isDelivery: true,
          initialPaymentMethod: paymentMethod,
        ),
      ),
    );
  }

  void _reportIssue() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report Issue'),
        content: Text('Please contact customer service for assistance with your order.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryBanner(String status) {
    final isEnRoute = status == 'delivery_en_route';
    final isArrived = status == 'delivery_arrived';
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEnRoute 
            ? [Colors.blue[400]!, Colors.blue[600]!]
            : [Colors.green[400]!, Colors.green[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isEnRoute ? Colors.blue : Colors.green).withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              isEnRoute ? Icons.local_shipping : Icons.location_on,
              color: Colors.white,
              size: 28,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEnRoute ? '🚗 Driver Coming with Your Clean Clothes!' : '📍 Driver Has Arrived!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  isEnRoute 
                    ? 'Your laundry is ready and the driver is on the way to deliver it to you'
                    : 'The driver is at your location with your clean clothes. Please collect them!',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (isEnRoute)
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Icon(Icons.access_time, color: Colors.white, size: 16),
                  SizedBox(height: 2),
                  Text(
                    'ETA\n~15min',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }



  Future<void> _cancelOrder() async {
    if (!mounted) return;

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
            .doc(widget.branchId)
            .collection('mobileOrders')
            .doc(widget.orderId)
            .update({
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'Cancelled by customer',
        });

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order cancelled successfully.'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop();
      } catch (e) {
        if (!mounted) return;
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
