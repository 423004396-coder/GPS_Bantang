import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

void main() {
  runApp(const LocationApp());
}

class LocationApp extends StatelessWidget {
  const LocationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Location Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BCD4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LocationScreen(),
    );
  }
}

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen>
    with TickerProviderStateMixin {
  // Location data
  Position? _currentPosition;
  String _placeName = 'Determining location...';
  String _streetAddress = '';
  String _city = '';
  String _country = '';
  String _statusMessage = 'Initializing GPS...';
  bool _isTracking = false;
  bool _isLoading = false;
  int _updateCount = 0;

  // Stream for live location updates
  StreamSubscription<Position>? _positionStream;

  // Animation controller for the pulse effect
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  // Location settings
  final LocationSettings _locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // Update every 10 meters of movement
  );

  @override
  void initState() {
    super.initState();

    // Setup animations
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _fadeController.forward();
    _checkPermissionsAndStart();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────
  // PERMISSION & LOCATION LOGIC
  // ──────────────────────────────────────────

  Future<void> _checkPermissionsAndStart() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking permissions...';
    });

    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = 'Location services are disabled. Please enable GPS.';
        _isLoading = false;
      });
      _showServiceDisabledDialog();
      return;
    }

    // Check permission status
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _statusMessage = 'Location permission denied.';
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _statusMessage =
        'Location permission permanently denied. Open app settings to enable.';
        _isLoading = false;
      });
      _showPermissionDeniedDialog();
      return;
    }

    // Permission granted — start tracking
    await _startTracking();
  }

  Future<void> _startTracking() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Getting GPS fix...';
    });

    // Get initial position immediately
    try {
      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _onPositionUpdate(initialPos);
    } catch (e) {
      setState(() => _statusMessage = 'Error getting initial position: $e');
    }

    // Start the live stream
    _positionStream = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(
          (Position position) async {
        await _onPositionUpdate(position);
      },
      onError: (error) {
        setState(() => _statusMessage = 'Stream error: $error');
      },
    );

    setState(() {
      _isTracking = true;
      _isLoading = false;
    });
  }

  Future<void> _onPositionUpdate(Position position) async {
    setState(() {
      _currentPosition = position;
      _updateCount++;
      _statusMessage = 'Reverse geocoding...';
    });

    // Reverse geocode — convert lat/lng to a human-readable address
    await _reverseGeocode(position.latitude, position.longitude);
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;

        String name = place.name ?? '';
        String street = place.street ?? '';
        String subLocality = place.subLocality ?? '';
        String locality = place.locality ?? '';
        String adminArea = place.administrativeArea ?? '';
        String country = place.country ?? '';

        // Build a clean place name (most specific available)
        String placeName = '';
        if (name.isNotEmpty && name != street) {
          placeName = name;
        } else if (subLocality.isNotEmpty) {
          placeName = subLocality;
        } else if (locality.isNotEmpty) {
          placeName = locality;
        } else {
          placeName = adminArea;
        }

        // Build full street address
        String fullStreet = '';
        if (street.isNotEmpty) {
          fullStreet = street;
        }

        String cityLine = [locality, adminArea]
            .where((s) => s.isNotEmpty)
            .join(', ');

        setState(() {
          _placeName = placeName.isNotEmpty ? placeName : 'Unknown Place';
          _streetAddress = fullStreet;
          _city = cityLine;
          _country = country;
          _statusMessage = 'Live — updates every 10m of movement';
        });
      }
    } catch (e) {
      setState(() {
        _placeName = 'Place lookup failed';
        _statusMessage = 'Geocoding error: $e';
      });
    }
  }

  void _stopTracking() {
    _positionStream?.cancel();
    setState(() {
      _isTracking = false;
      _statusMessage = 'Tracking paused.';
    });
  }

  void _toggleTracking() {
    if (_isTracking) {
      _stopTracking();
    } else {
      _checkPermissionsAndStart();
    }
  }

  // ──────────────────────────────────────────
  // DIALOGS
  // ──────────────────────────────────────────

  void _showServiceDisabledDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GPS Disabled'),
        content: const Text(
            'Please enable location services on your device to use this app.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
            'Location permission was permanently denied. Please open app settings and enable location access.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Open App Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildLocationCard(),
                const SizedBox(height: 16),
                _buildCoordinatesCard(),
                const SizedBox(height: 16),
                _buildAddressCard(),
                const SizedBox(height: 16),
                _buildAccuracyCard(),
                const SizedBox(height: 24),
                _buildControlButton(),
                const SizedBox(height: 12),
                _buildStatusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF00BCD4).withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.gps_fixed, color: Color(0xFF00BCD4), size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live Location Tracker',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Update #$_updateCount',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // Live indicator
        if (_isTracking)
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        if (_isTracking)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Text(
              'LIVE',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A5C), Color(0xFF0D2137)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00BCD4).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Map pin icon with pulse
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Stack(
              alignment: Alignment.center,
              children: [
                if (_isTracking)
                  Container(
                    width: 80 * _pulseAnimation.value,
                    height: 80 * _pulseAnimation.value,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BCD4).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                  ),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BCD4).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isTracking ? Icons.location_on : Icons.location_off,
                    color: _isTracking
                        ? const Color(0xFF00BCD4)
                        : Colors.grey,
                    size: 36,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Place name
          _isLoading
              ? const CircularProgressIndicator(color: Color(0xFF00BCD4))
              : Text(
            _placeName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          if (_city.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _city,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (_country.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _country,
              style: const TextStyle(
                color: Color(0xFF00BCD4),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoordinatesCard() {
    return Row(
      children: [
        Expanded(
          child: _buildInfoTile(
            icon: Icons.north,
            label: 'Latitude',
            value: _currentPosition != null
                ? _currentPosition!.latitude.toStringAsFixed(6)
                : 'N/A',
            color: const Color(0xFF00BCD4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildInfoTile(
            icon: Icons.east,
            label: 'Longitude',
            value: _currentPosition != null
                ? _currentPosition!.longitude.toStringAsFixed(6)
                : 'N/A',
            color: const Color(0xFF7C4DFF),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressCard() {
    if (_streetAddress.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: Color(0xFFFF9800), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Street Address',
                  style: TextStyle(
                    color: Color(0xFFFF9800),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _streetAddress,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccuracyCard() {
    if (_currentPosition == null) return const SizedBox.shrink();

    double accuracy = _currentPosition!.accuracy;
    double altitude = _currentPosition!.altitude;
    double speed = _currentPosition!.speed * 3.6; // m/s to km/h

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMiniStat(
            Icons.radar,
            '±${accuracy.toStringAsFixed(0)}m',
            'Accuracy',
            const Color(0xFF4CAF50),
          ),
          _buildDivider(),
          _buildMiniStat(
            Icons.terrain,
            '${altitude.toStringAsFixed(1)}m',
            'Altitude',
            const Color(0xFF00BCD4),
          ),
          _buildDivider(),
          _buildMiniStat(
            Icons.speed,
            '${speed.toStringAsFixed(1)} km/h',
            'Speed',
            const Color(0xFFFF9800),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 36,
      color: Colors.white.withOpacity(0.1),
    );
  }

  Widget _buildMiniStat(
      IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton() {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _toggleTracking,
      icon: _isLoading
          ? const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      )
          : Icon(_isTracking ? Icons.stop : Icons.play_arrow),
      label: Text(
        _isLoading
            ? 'Please wait...'
            : _isTracking
            ? 'Stop Tracking'
            : 'Start Tracking',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor:
        _isTracking ? const Color(0xFFE53935) : const Color(0xFF00BCD4),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: Colors.white.withOpacity(0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}