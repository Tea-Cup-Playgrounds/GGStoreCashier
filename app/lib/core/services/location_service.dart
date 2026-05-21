import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final String? address;
  final String? timezone; // e.g. "Asia/Makassar"

  const LocationResult({
    required this.latitude,
    required this.longitude,
    this.address,
    this.timezone,
  });
}

class LocationService {
  /// Request permission and get current position + reverse-geocoded address.
  /// Throws a descriptive [String] message if permission is denied or unavailable.
  static Future<LocationResult> getCurrentLocation() async {
    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled. Please enable GPS.';
    }

    // Check / request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permission denied.';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw 'Location permission permanently denied. Please enable it in app settings.';
    }

    // Get position
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    // Reverse geocode via OpenStreetMap Nominatim (no API key needed)
    String? address;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          // Nominatim requires a User-Agent
          'User-Agent': 'GGStoreCashier/1.0 (contact@ggstore.id)',
          'Accept-Language': 'id,en',
        },
      ));

      final response = await dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': position.latitude,
          'lon': position.longitude,
          'format': 'json',
          'addressdetails': 1,
        },
      );

      debugPrint('[LocationService] Nominatim raw: ${response.data}');

      final data = response.data as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;

      if (addr != null) {
        debugPrint('[LocationService] address fields: $addr');

        // Build a human-readable address from available fields
        final parts = <String>[
          if (addr['road'] != null) addr['road'] as String,
          if (addr['neighbourhood'] != null) addr['neighbourhood'] as String
          else if (addr['suburb'] != null) addr['suburb'] as String,
          if (addr['city'] != null) addr['city'] as String
          else if (addr['town'] != null) addr['town'] as String
          else if (addr['village'] != null) addr['village'] as String,
          if (addr['state'] != null) addr['state'] as String,
        ];

        address = parts.where((s) => s.isNotEmpty).join(', ');
        debugPrint('[LocationService] assembled address: $address');
      }
    } catch (e) {
      debugPrint('[LocationService] geocoding error: $e');
      // Non-fatal — return coordinates without address
    }

    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
    );
  }

  /// Just check/request permission without fetching position.
  /// Returns true if granted.
  static Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
