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
      title: 'LOCATE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0A0A0A),
          surface: Color(0xFFF5F0E8),
          onSurface: Color(0xFF0A0A0A),
        ),
        useMaterial3: true,
        fontFamily: 'Courier',
      ),
      home: const LocationScreen(),
    );
  }
}

// ─── BRUTALIST DESIGN TOKENS ───────────────────────────────────────────────
const _ink = Color(0xFF0A0A0A);
const _paper = Color(0xFFF5F0E8);
const _paperDark = Color(0xFFEAE4D6);
const _red = Color(0xFFD32F2F);
const _accent = Color(0xFFFF6B00); // cinematic amber-orange
const _border = Color(0xFF0A0A0A);
const _borderWidth = 2.5;

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen>
    with TickerProviderStateMixin {
  Position? _currentPosition;
  String _placeName = '——';
  String _streetAddress = '';
  String _city = '';
  String _country = '';
  String _statusMessage = 'INITIALIZING GPS';
  bool _isTracking = false;
  bool _isLoading = false;
  int _updateCount = 0;

  StreamSubscription<Position>? _positionStream;

  late AnimationController _blinkController;
  late AnimationController _slideController;
  late Animation<double> _blinkAnimation;
  late Animation<Offset> _slideAnimation;

  final LocationSettings _locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _slideController.forward();
    _checkPermissionsAndStart();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _blinkController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ─── PERMISSION & LOCATION LOGIC ─────────────────────────────────────────

  Future<void> _checkPermissionsAndStart() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'CHECKING PERMISSIONS';
    });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = 'GPS DISABLED — ENABLE LOCATION SERVICES';
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
          _statusMessage = 'PERMISSION DENIED';
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _statusMessage = 'PERMISSION PERMANENTLY DENIED — OPEN SETTINGS';
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
      _statusMessage = 'ACQUIRING SIGNAL';
    });

    try {
      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _onPositionUpdate(initialPos);
    } catch (e) {
      setState(() => _statusMessage = 'ERROR: $e');
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(
          (Position position) async => await _onPositionUpdate(position),
      onError: (error) => setState(() => _statusMessage = 'STREAM ERROR: $error'),
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
      _statusMessage = 'RESOLVING ADDRESS';
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

        String cityLine = [locality, adminArea]
            .where((s) => s.isNotEmpty)
            .join(', ');

        setState(() {
          _placeName = placeName.isNotEmpty ? placeName.toUpperCase() : 'UNKNOWN';
          _streetAddress = street.toUpperCase();
          _city = cityLine.toUpperCase();
          _country = country.toUpperCase();
          _statusMessage = 'LIVE — UPDATES EVERY 10M OF MOVEMENT';
        });
      }
    } catch (e) {
      setState(() {
        _placeName = 'LOOKUP FAILED';
        _statusMessage = 'GEOCODING ERROR: $e';
      });
    }
  }

  void _stopTracking() {
    _positionStream?.cancel();
    setState(() {
      _isTracking = false;
      _statusMessage = 'SIGNAL PAUSED';
    });
  }

  void _toggleTracking() {
    if (_isTracking) {
      _stopTracking();
    } else {
      _checkPermissionsAndStart();
    }
  }

  // ─── DIALOGS ─────────────────────────────────────────────────────────────

  void _showServiceDisabledDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _BrutalistDialog(
        title: 'GPS DISABLED',
        message: 'ENABLE LOCATION SERVICES ON YOUR DEVICE TO USE THIS APP.',
        confirmLabel: 'OPEN SETTINGS',
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
      builder: (ctx) => _BrutalistDialog(
        title: 'ACCESS DENIED',
        message:
        'LOCATION PERMISSION WAS PERMANENTLY DENIED. OPEN APP SETTINGS TO ENABLE.',
        confirmLabel: 'APP SETTINGS',
        onConfirm: () {
          Navigator.pop(ctx);
          Geolocator.openAppSettings();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: SlideTransition(
        position: _slideAnimation,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeroBanner(),
                      _buildCoordinatesRow(),
                      _buildAddressStrip(),
                      _buildStatsRow(),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildControlButton(),
                      ),
                      const SizedBox(height: 12),
                      _buildStatusTicker(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── TOP BAR ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        color: _ink,
        border: Border(bottom: BorderSide(color: _border, width: _borderWidth)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Wordmark
          const Text(
            'LOCATE',
            style: TextStyle(
              color: _paper,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              fontFamily: 'Courier',
            ),
          ),
          const Spacer(),
          // Update counter chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _paper,
              border: Border.all(color: _paper, width: 1),
            ),
            child: Text(
              '#${_updateCount.toString().padLeft(4, '0')}',
              style: const TextStyle(
                color: _ink,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                fontFamily: 'Courier',
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Live dot
          if (_isTracking)
            AnimatedBuilder(
              animation: _blinkAnimation,
              builder: (context, child) => Opacity(
                opacity: _blinkAnimation.value,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: _accent,
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
                  color: _accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  fontFamily: 'Courier',
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── HERO BANNER ─────────────────────────────────────────────────────────

  Widget _buildHeroBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: _paperDark,
        border: Border.all(color: _border, width: _borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Label strip
          Container(
            color: _ink,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: const Text(
              'CURRENT LOCATION',
              style: TextStyle(
                color: _paper,
                fontSize: 10,
                letterSpacing: 4,
                fontWeight: FontWeight.w700,
                fontFamily: 'Courier',
              ),
            ),
          ),
          // Main place name
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
            child: _isLoading
                ? const SizedBox(
              height: 60,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: _ink,
                    strokeWidth: 3,
                  ),
                ),
              ),
            )
                : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _placeName,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  letterSpacing: -1,
                  fontFamily: 'Courier',
                ),
              ),
            ),
          ),
          if (_city.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                _city,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  fontFamily: 'Courier',
                ),
              ),
            ),
          if (_country.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Text(
                _country,
                style: const TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  fontFamily: 'Courier',
                ),
              ),
            ),
          if (_country.isEmpty) const SizedBox(height: 20),
          // Bottom accent bar
          Container(height: 5, color: _accent),
        ],
      ),
    );
  }

  // ─── COORDINATES ROW ─────────────────────────────────────────────────────

  Widget _buildCoordinatesRow() {
    final lat = _currentPosition?.latitude.toStringAsFixed(6) ?? '——.——————';
    final lng = _currentPosition?.longitude.toStringAsFixed(6) ?? '——.——————';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(child: _buildCoordTile('LAT', lat, Icons.north)),
          const SizedBox(width: 8),
          Expanded(child: _buildCoordTile('LNG', lng, Icons.east)),
        ],
      ),
    );
  }

  Widget _buildCoordTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _paper,
        border: Border.all(color: _border, width: _borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: _accent),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: _accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  fontFamily: 'Courier',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'Courier',
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ─── ADDRESS STRIP ────────────────────────────────────────────────────────

  Widget _buildAddressStrip() {
    if (_streetAddress.isEmpty) return const SizedBox(height: 12);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        border: Border.all(color: _border, width: _borderWidth),
      ),
      child: Row(
        children: [
          Container(
            color: _ink,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: const Icon(Icons.map_outlined, color: _paper, size: 18),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STREET ADDRESS',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 9,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Courier',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _streetAddress,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Courier',
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STATS ROW ────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    if (_currentPosition == null) return const SizedBox(height: 12);

    final accuracy = _currentPosition!.accuracy;
    final altitude = _currentPosition!.altitude;
    final speed = _currentPosition!.speed * 3.6;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCell(
              Icons.radar,
              '±${accuracy.toStringAsFixed(0)}M',
              'ACCURACY',
            ),
          ),
          _buildVerticalDivider(),
          Expanded(
            child: _buildStatCell(
              Icons.terrain,
              '${altitude.toStringAsFixed(1)}M',
              'ALTITUDE',
            ),
          ),
          _buildVerticalDivider(),
          Expanded(
            child: _buildStatCell(
              Icons.speed,
              '${speed.toStringAsFixed(1)}',
              'KM/H',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(width: _borderWidth, color: _border);
  }

  Widget _buildStatCell(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: _paperDark,
        border: Border.all(color: _border, width: _borderWidth),
      ),
      child: Column(
        children: [
          Icon(icon, color: _accent, size: 16),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              fontFamily: 'Courier',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.5,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }

  // ─── CONTROL BUTTON ──────────────────────────────────────────────────────

  Widget _buildControlButton() {
    final isStop = _isTracking && !_isLoading;
    final bgColor = isStop ? _red : _ink;
    final label = _isLoading
        ? 'ACQUIRING...'
        : _isTracking
        ? 'STOP TRACKING'
        : 'START TRACKING';
    final iconData = _isTracking ? Icons.stop : Icons.play_arrow;

    return GestureDetector(
      onTap: _isLoading ? null : _toggleTracking,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: _border, width: _borderWidth),
        ),
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _paper,
                ),
              )
            else
              Icon(iconData, color: _paper, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: _paper,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                fontFamily: 'Courier',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── STATUS TICKER ────────────────────────────────────────────────────────

  Widget _buildStatusTicker() {
    return Container(
      color: _paperDark,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(width: 6, height: 6, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage,
              style: const TextStyle(
                color: _ink,
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
                fontFamily: 'Courier',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BRUTALIST DIALOG ─────────────────────────────────────────────────────

class _BrutalistDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _BrutalistDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _paper,
      shape: const RoundedRectangleBorder(),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: _border, width: _borderWidth),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              color: _ink,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Text(
                title,
                style: const TextStyle(
                  color: _paper,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  fontFamily: 'Courier',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                message,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  height: 1.6,
                  fontFamily: 'Courier',
                ),
              ),
            ),
            Container(height: _borderWidth, color: _border),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onCancel,
                    child: Container(
                      color: _paperDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: _borderWidth, color: _border),
                Expanded(
                  child: GestureDetector(
                    onTap: onConfirm,
                    child: Container(
                      color: _ink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          color: _paper,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}