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
      title: 'Serenity',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: _ocean,
          surface: _sand,
          onSurface: _dusk,
        ),
        useMaterial3: true,
        fontFamily: 'Georgia',
      ),
      home: const LocationScreen(),
    );
  }
}

// ─── OCEAN BLUE SERENITY PALETTE ───────────────────────────────────────────
const _sand       = Color(0xFFF0F6FF);       // misty white-blue base
const _sandMid    = Color(0xFFDEEAF7);       // soft periwinkle mist
const _sandDeep   = Color(0xFFBDD4EE);       // deeper blue-grey mist
const _ocean      = Color(0xFF1565C0);       // deep sapphire ocean
const _oceanLight = Color(0xFF4A90D9);       // clear mid-ocean blue
const _sky        = Color(0xFF5BA3D9);       // serene sky blue
const _skyLight   = Color(0xFFCCE5F7);       // pale horizon blue
const _coral      = Color(0xFF4FC3F7);       // bright aqua accent
const _sun        = Color(0xFF90CAF9);       // soft powder blue highlight
const _dusk       = Color(0xFF0D2B4E);       // deep midnight navy
const _foam       = Color(0xFFFFFFFF);       // white foam

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen>
    with TickerProviderStateMixin {
  Position? _currentPosition;
  String _placeName = 'Searching…';
  String _streetAddress = '';
  String _city = '';
  String _country = '';
  String _statusMessage = 'Initializing GPS';
  bool _isTracking = false;
  bool _isLoading = false;
  int _updateCount = 0;

  StreamSubscription<Position>? _positionStream;

  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  late Animation<double> _fadeAnimation;

  final LocationSettings _locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.medium,
    distanceFilter: 1,
  );

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.linear),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _fadeController.forward();
    _checkPermissionsAndStart();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionsAndStart() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking permissions…';
    });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = 'GPS disabled — enable location services';
        _isLoading = false;
      });
      _showServiceDisabledDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _statusMessage = 'Permission denied';
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _statusMessage = 'Permission permanently denied — open settings';
        _isLoading = false;
      });
      _showPermissionDeniedDialog();
      return;
    }

    await _startTracking();
  }

  Future<void> _startTracking() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Catching your signal…';
    });

    try {
      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _onPositionUpdate(initialPos);
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(
          (Position position) async => await _onPositionUpdate(position),
      onError: (error) =>
          setState(() => _statusMessage = 'Stream error: $error'),
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
      _statusMessage = 'Resolving address…';
    });
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

        String cityLine =
        [locality, adminArea].where((s) => s.isNotEmpty).join(', ');

        setState(() {
          _placeName =
          placeName.isNotEmpty ? _toTitleCase(placeName) : 'Unknown';
          _streetAddress = _toTitleCase(street);
          _city = _toTitleCase(cityLine);
          _country = _toTitleCase(country);
          _statusMessage = 'Live · Updates every 10m of movement';
        });
      }
    } catch (e) {
      setState(() {
        _placeName = 'Lookup failed';
        _statusMessage = 'Geocoding error: $e';
      });
    }
  }

  String _toTitleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  void _stopTracking() {
    _positionStream?.cancel();
    setState(() {
      _isTracking = false;
      _statusMessage = 'Signal paused';
    });
  }

  void _toggleTracking() {
    if (_isTracking) {
      _stopTracking();
    } else {
      _checkPermissionsAndStart();
    }
  }

  void _showServiceDisabledDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _BeachDialog(
        title: 'GPS Disabled',
        message:
        'Enable location services on your device to start exploring.',
        confirmLabel: 'Open Settings',
        onConfirm: () {
          Navigator.pop(ctx);
          Geolocator.openLocationSettings();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _BeachDialog(
        title: 'Access Denied',
        message:
        'Location permission was permanently denied. Open settings to enable.',
        confirmLabel: 'App Settings',
        onConfirm: () {
          Navigator.pop(ctx);
          Geolocator.openAppSettings();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFCCE5F7), Color(0xFFF0F6FF)],
            stops: [0.0, 0.45],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroCard(),
                        const SizedBox(height: 16),
                        _buildCoordinatesRow(),
                        const SizedBox(height: 12),
                        if (_streetAddress.isNotEmpty) ...[
                          _buildAddressCard(),
                          const SizedBox(height: 12),
                        ],
                        if (_currentPosition != null) ...[
                          _buildStatsRow(),
                          const SizedBox(height: 12),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildControlButton(),
                        ),
                        const SizedBox(height: 12),
                        _buildStatusBar(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── TOP BAR ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Sun icon
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _ocean,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _ocean.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.waves_rounded,
                color: _foam, size: 20),
          ),
          const SizedBox(width: 10),
          // Wordmark
          Text(
            'Serenity',
            style: TextStyle(
              color: _dusk,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          // Update counter pill
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _ocean.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_updateCount} fixes',
              style: TextStyle(
                color: _ocean,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Live badge
          if (_isTracking)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Opacity(
                opacity: _pulseAnimation.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _coral,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: _foam,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Live',
                        style: TextStyle(
                          color: _foam,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── HERO CARD ────────────────────────────────────────────────────────────

  Widget _buildHeroCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_ocean, Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _ocean.withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative wave circles
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _foam.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _foam.withOpacity(0.06),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        color: _sun, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'You are here',
                      style: TextStyle(
                        color: _foam.withOpacity(0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _isLoading
                    ? const SizedBox(
                  height: 64,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _foam,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
                    : Text(
                  _placeName,
                  style: const TextStyle(
                    color: _foam,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFamily: 'Georgia',
                  ),
                ),
                const SizedBox(height: 8),
                if (_city.isNotEmpty)
                  Text(
                    _city,
                    style: TextStyle(
                      color: _foam.withOpacity(0.75),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                  ),
                const SizedBox(height: 4),
                if (_country.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _sun.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _country,
                      style: const TextStyle(
                        color: _sun,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── COORDINATES ROW ─────────────────────────────────────────────────────

  Widget _buildCoordinatesRow() {
    final lat =
        _currentPosition?.latitude.toStringAsFixed(6) ?? '—.——————';
    final lng =
        _currentPosition?.longitude.toStringAsFixed(6) ?? '—.——————';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _buildCoordCard('Latitude', lat, Icons.north_rounded, _sky)),
          const SizedBox(width: 10),
          Expanded(child: _buildCoordCard('Longitude', lng, Icons.east_rounded, _coral)),
        ],
      ),
    );
  }

  Widget _buildCoordCard(
      String label, String value, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _foam,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _dusk.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: _dusk,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'Courier',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── ADDRESS CARD ─────────────────────────────────────────────────────────

  Widget _buildAddressCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _foam,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _dusk.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _sandMid,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.map_rounded, color: _ocean, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Street Address',
                  style: TextStyle(
                    color: _dusk.withOpacity(0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _streetAddress,
                  style: const TextStyle(
                    color: _dusk,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── STATS ROW ────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    final accuracy = _currentPosition!.accuracy;
    final altitude = _currentPosition!.altitude;
    final speed = _currentPosition!.speed * 3.6;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              Icons.radar_rounded,
              '±${accuracy.toStringAsFixed(0)}m',
              'Accuracy',
              _sky,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              Icons.terrain_rounded,
              '${altitude.toStringAsFixed(1)}m',
              'Altitude',
              _ocean,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              Icons.speed_rounded,
              '${speed.toStringAsFixed(1)}',
              'km/h',
              _coral,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: _foam,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _dusk.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: _dusk,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'Courier',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: _dusk.withOpacity(0.5),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ─── CONTROL BUTTON ──────────────────────────────────────────────────────

  Widget _buildControlButton() {
    final isStop = _isTracking && !_isLoading;
    final gradient = isStop
        ? const LinearGradient(
        colors: [Color(0xFF29B6F6), Color(0xFF0288D1)])
        : const LinearGradient(
        colors: [_ocean, Color(0xFF0D47A1)]);
    final label = _isLoading
        ? 'Acquiring signal…'
        : _isTracking
        ? 'Stop Tracking'
        : 'Start Tracking';
    final icon = _isTracking ? Icons.stop_rounded : Icons.navigation_rounded;

    return GestureDetector(
      onTap: _isLoading ? null : _toggleTracking,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _ocean.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _foam,
                ),
              )
            else
              Icon(icon, color: _foam, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: _foam,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── STATUS BAR ──────────────────────────────────────────────────────────

  Widget _buildStatusBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _sandMid.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isTracking ? _ocean : _sandDeep,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: _dusk.withOpacity(0.65),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BEACH DIALOG ─────────────────────────────────────────────────────────

class _BeachDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _BeachDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _foam,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _dusk.withOpacity(0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_ocean, Color(0xFF0D47A1)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _foam.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_off_rounded,
                        color: _foam, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: _foam,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Georgia',
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                message,
                style: TextStyle(
                  color: _dusk.withOpacity(0.75),
                  fontSize: 14,
                  height: 1.6,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onCancel,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _sandMid,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: _dusk.withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: onConfirm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_ocean, Color(0xFF0D47A1)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _ocean.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(
                            color: _foam,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}