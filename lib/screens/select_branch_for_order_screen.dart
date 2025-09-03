
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart'; // Assuming you have this from your signup screen

class SelectBranchForOrderScreen extends StatefulWidget {
  const SelectBranchForOrderScreen({super.key});

  @override
  State<SelectBranchForOrderScreen> createState() => _SelectBranchForOrderScreenState();
}

class _SelectBranchForOrderScreenState extends State<SelectBranchForOrderScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> localBranches = [];
  Map<String, dynamic>? selectedBranch;
  Position? userLocation;
  bool isLoading = true;
  String loadingMessage = 'Getting your location...';
  int _currentPage = 0;
  final int _branchesPerPage = 5;



  @override
  void initState() {
    super.initState();
    _initializeAndFetchBranches();
  }

  Future<void> _initializeAndFetchBranches() async {
    try {
      // 1. Get User Location
      // ... (This part remains the same)
      final locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied ||
          locationPermission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
      // Added a try-catch specifically for location to handle it gracefully
      try {
        userLocation = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 10));
      } catch(e) {
        print("Could not get user location: $e");
        // userLocation will remain null, we will handle this below.
      }

      if (!mounted) return;
      setState(() {
        loadingMessage = 'Finding nearby branches...';
      });

      // 2. Fetch All Active Branches
      final snapshot = await _firestore
          .collection('branches')
          .where('isActive', isEqualTo: true)
      // We fetch ALL active branches, and handle missing coordinates in the code.
          .get();

      // 3. Calculate Distances and Sort (>>> THIS IS THE CORRECTED PART <<<)
      localBranches = snapshot.docs.map((doc) {
        final data = doc.data();

        // --- SAFE PARSING LOGIC ---
        final lat = (data['latitude'] is num) ? (data['latitude'] as num).toDouble() : null;
        final lng = (data['longitude'] is num) ? (data['longitude'] as num).toDouble() : null;
        // --------------------------

        // If branch has no coordinates OR we couldn't get user's location,
        // we can't calculate distance.
        if (lat == null || lng == null || userLocation == null) {
          return {
            'id': doc.id,
            'distance': null, // Use null to indicate unknown distance
            'formattedDistance': 'Distance unknown',
            ...data
          };
        }

        // If we have coordinates, calculate the distance.
        final distance = LocationService.calculateDistance(
          userLocation!.latitude,
          userLocation!.longitude,
          lat,
          lng,
        );
        return {
          'id': doc.id,
          'distance': distance,
          'formattedDistance': LocationService.getFormattedDistance(distance),
          ...data
        };
      }).toList();

      // --- IMPROVED SORTING LOGIC ---
      localBranches.sort((a, b) {
        final distA = a['distance'] as double?;
        final distB = b['distance'] as double?;

        // If both have a valid distance, sort by nearest.
        if (distA != null && distB != null) {
          return distA.compareTo(distB);
        }
        // If A has a distance but B doesn't, A comes first.
        if (distA != null && distB == null) {
          return -1;
        }
        // If B has a distance but A doesn't, B comes first.
        if (distA == null && distB != null) {
          return 1;
        }
        // If neither has a distance, sort them alphabetically by name.
        return (a['name'] as String).compareTo(b['name'] as String);
      });
      // --------------------------------

      if (!mounted) return;
      setState(() {
        // Auto-select the nearest branch if its distance is known.
        if (localBranches.isNotEmpty && localBranches.first['distance'] != null) {
          selectedBranch = localBranches.first;
        }
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error finding branches: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- PAGINATION LOGIC ---
    // Calculate the total number of pages based on all found branches.
    final totalPages = (localBranches.length / _branchesPerPage).ceil();

    // Get the specific sublist of branches to display for the current page.
    final startIndex = _currentPage * _branchesPerPage;
    final endIndex = (startIndex + _branchesPerPage > localBranches.length)
        ? localBranches.length
        : startIndex + _branchesPerPage;
    final paginatedBranches = localBranches.sublist(startIndex, endIndex);
    // --- END OF PAGINATION LOGIC ---

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 20), // Increase the default height
        child: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Retry:branch unknown issue'),
              const SizedBox(height: 4),
              Text(
                'If distance is unknown, retry opening the app',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
      body: isLoading
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(loadingMessage)]))

          : Column( // Use a Column to hold the list and the buttons
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              // IMPORTANT: itemCount is now based on the paginated list
              itemCount: paginatedBranches.length,
              itemBuilder: (context, index) {
                // Get the branch from the paginated list
                final branch = paginatedBranches[index];
                final isSelected = selectedBranch != null && selectedBranch!['id'] == branch['id'];

                return Card(
                  elevation: isSelected ? 4 : 1,
                  color: isSelected ? Colors.blue.withOpacity(0.1) : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isSelected ? Colors.blueAccent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: ListTile(
                    leading: Icon(Icons.store, color: isSelected ? Colors.blueAccent : Colors.grey),
                    title: Text(branch['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(branch['address']),
                    trailing: Text(
                      branch['formattedDistance'],
                      style: TextStyle(color: isSelected ? Colors.blueAccent : Colors.black54, fontWeight: FontWeight.w500),
                    ),
                    onTap: () => setState(() => selectedBranch = branch),
                  ),
                );
              },
            ),
          ),

          // --- PAGINATION CONTROLS WIDGET ---
          if (totalPages > 1) // Only show controls if there's more than one page
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    // Disable the button if on the first page
                    onPressed: _currentPage == 0
                        ? null
                        : () {
                      setState(() {
                        _currentPage--;
                      });
                    },
                    child: const Text('Previous'),
                  ),
                  Text(
                    'Page ${_currentPage + 1} of $totalPages',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton(
                    // Disable the button if on the last page
                    onPressed: _currentPage >= totalPages - 1
                        ? null
                        : () {
                      setState(() {
                        _currentPage++;
                      });
                    },
                    child: const Text('Other'),
                  ),
                ],
              ),
            ),
          // --- END OF PAGINATION CONTROLS WIDGET ---
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.check_circle),
          label: const Text('Confirm Branch and Continue'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: selectedBranch == null
              ? null
              : () => Navigator.of(context).pop(selectedBranch),
        ),
      ),
    );
  }
}