import 'package:geolocator/geolocator.dart';
import 'dart:math';

class LocationService {
  static const double _earthRadiusKm = 6371.0;
  static const double _defaultServiceRadiusKm = 20.0;

  /// Get current user location with permission handling
  static Future<Position?> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw LocationServiceDisabledException();
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw LocationPermissionDeniedException();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw LocationPermissionPermanentlyDeniedException();
      }

      // Get current position with high accuracy
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      print('LocationService Error: $e');
      return null;
    }

  }

  /// Calculate distance between two coordinates using Haversine formula
  static double calculateDistance(
      double lat1,
      double lon1,
      double lat2,
      double lon2
      ) {
    // Convert degrees to radians
    double lat1Rad = _degreesToRadians(lat1);
    double lon1Rad = _degreesToRadians(lon1);
    double lat2Rad = _degreesToRadians(lat2);
    double lon2Rad = _degreesToRadians(lon2);

    // Haversine formula
    double deltaLat = lat2Rad - lat1Rad;
    double deltaLon = lon2Rad - lon1Rad;

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
            sin(deltaLon / 2) * sin(deltaLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusKm * c;
  }

  /// Check if branch is within service radius
  static bool isWithinRadius(
      double userLat,
      double userLng,
      double branchLat,
      double branchLng,
      {double radiusKm = _defaultServiceRadiusKm}
      ) {
    double distance = calculateDistance(userLat, userLng, branchLat, branchLng);
    return distance <= radiusKm;
  }

  /// Helper method to convert degrees to radians
  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  /// Get formatted distance string
  static String getFormattedDistance(double distanceKm) {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()}m';
    } else if (distanceKm < 10) {
      return '${distanceKm.toStringAsFixed(1)}km';
    } else {
      return '${distanceKm.round()}km';
    }
  }

  /// Check if location permissions are granted
  static Future<bool> hasLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Open app settings for location permission
  static Future<bool> openLocationSettings() async {
    return await Geolocator.openAppSettings();
  }
}

// Custom exceptions for better error handling
class LocationServiceDisabledException implements Exception {
  final String message = 'Location services are disabled';
}

class LocationPermissionDeniedException implements Exception {
  final String message = 'Location permission denied';
}

class LocationPermissionPermanentlyDeniedException implements Exception {
  final String message = 'Location permission permanently denied';
}
