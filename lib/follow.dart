import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;

import 'models/safety_session.dart';
import 'safety_mode.dart';
import 'services/bluetooth_service.dart';

// Brand design tokens matching main.dart
const _ink = Color(0xFF263448);
const _muted = Color(0xFF7D8285);
const _paper = Color(0xFFF7F5EF);
const _card = Color(0xFFFFFEFB);
const _sand = Color(0xFFECE4D2);
const _tan = Color(0xFFB58B5D);
const _rust = Color(0xFFB56E4E);
const _softBlue = Color(0xFFE7EDF0);
const _safeGreen = Color(0xFF73A58C);

/// Screen for BLE proximity scanning and follower awareness.
class FollowPage extends StatefulWidget {
  const FollowPage({super.key, this.userName, this.userPhone});

  final String? userName;
  final String? userPhone;

  @override
  State<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends State<FollowPage> {
  late final AppBluetoothService _bluetoothService;

  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<bool>? _scanningSubscription;
  StreamSubscription<List<BleDeviceObservation>>? _observationsSubscription;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  bool _isScanning = false;
  List<BleDeviceObservation> _observations = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _bluetoothService = AppBluetoothService();

    // 1. Listen to Bluetooth adapter state changes
    _adapterSubscription = _bluetoothService.adapterState.listen((state) {
      if (mounted) {
        setState(() {
          _adapterState = state;
          if (state == BluetoothAdapterState.on && _errorMessage != null) {
            _errorMessage = null;
          }
        });
      }
    });

    // 2. Listen to scanning progress
    _scanningSubscription = _bluetoothService.isScanning.listen((scanning) {
      if (mounted) {
        setState(() {
          _isScanning = scanning;
        });
      }
    });

    // 3. Listen to discovered device observations
    _observationsSubscription =
        _bluetoothService.observationsStream.listen((results) {
      if (mounted) {
        setState(() {
          _observations = results;
        });
      }
    });

    // Initialize adapter state check
    _bluetoothService.getAdapterState().then((state) {
      if (mounted) {
        setState(() => _adapterState = state);
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _adapterSubscription?.cancel();
    _scanningSubscription?.cancel();
    _observationsSubscription?.cancel();
    _bluetoothService.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      await _bluetoothService.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _stopScan() async {
    try {
      await _bluetoothService.stopScan();
    } catch (_) {}
  }

  Future<void> _turnOnBluetooth() async {
    try {
      await _bluetoothService.turnOn();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enable Bluetooth in your device settings or quick settings panel.',
            ),
          ),
        );
      }
    }
  }

  void _navigateToSafetyMode() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SafetyModePage(
          userName: widget.userName,
          userPhone: widget.userPhone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
        ),
        title: const Text(
          'Someone Following You?',
          style: TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subheader
                    const Text(
                      'BLUETOOTH PROXIMITY SCANNER',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Observe nearby BLE devices',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Educational Disclaimer Banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _sand.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCD4C4)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: _tan, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Educational Notice: Detecting Bluetooth signals only reveals nearby electronics (such as headphones, smartwatches, or phones). It cannot reliably determine if someone is following you. Always trust your instincts.',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Adapter State & Scanning Controls Card
                    _buildScannerControlCard(),

                    const SizedBox(height: 18),

                    // Nearby Community Help Card
                    _buildNearbyCommunityBanner(),

                    const SizedBox(height: 20),

                    // Error Message Banner if any
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _rust.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: _rust.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: _rust, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: _rust,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Section Header: Observations
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Observed Signals',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_observations.isNotEmpty)
                          Text(
                            '${_observations.length} found',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Observations List / Empty States
                    _buildObservationsContent(),
                  ],
                ),
              ),
            ),

            // Persistent Bottom Emergency Action Bar
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerControlCard() {
    final bool isBtOn = _adapterState == BluetoothAdapterState.on;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECE9E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A263448),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isBtOn ? _safeGreen : _rust,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isBtOn
                    ? (_isScanning ? 'SCANNING FOREGROUND' : 'BLUETOOTH READY')
                    : 'BLUETOOTH DISABLED (${_adapterState.name.toUpperCase()})',
                style: TextStyle(
                  color: isBtOn ? _safeGreen : _rust,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              if (_isScanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_tan),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isScanning
                ? 'Listening for active Bluetooth advertisements nearby (auto-stops in 15s)...'
                : 'Tap "Start Scan" to run a short 15-second scan of surrounding devices.',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _muted.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: (!isBtOn || _isScanning) ? null : _startScan,
                  icon: const Icon(Icons.radar_rounded, size: 18),
                  label: const Text(
                    'Start Scan',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFD5CEC0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _isScanning ? _stopScan : null,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text(
                    'Stop Scan',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyCommunityBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECE9E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A263448),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: _sand,
            child: Icon(Icons.groups_rounded, color: _ink, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask Nearby People for Help',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Alert nearby HerWay users. When they accept, they get your phone number to call you.',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: _navigateToSafetyMode,
            child: const Text('Ask Help',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildObservationsContent() {
    if (_adapterState != BluetoothAdapterState.on) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECE9E0)),
        ),
        child: Column(
          children: [
            const Icon(Icons.bluetooth_disabled_rounded,
                size: 40, color: _muted),
            const SizedBox(height: 12),
            const Text(
              'Bluetooth is Switched Off',
              style: TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enable Bluetooth to detect nearby BLE signals.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              onPressed: _turnOnBluetooth,
              icon: const Icon(Icons.bluetooth_rounded, size: 18),
              label: const Text(
                'Turn On Bluetooth',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (_observations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECE9E0)),
        ),
        child: Column(
          children: [
            Icon(
              _isScanning
                  ? Icons.sensors_rounded
                  : Icons.bluetooth_searching_rounded,
              size: 40,
              color: _tan,
            ),
            const SizedBox(height: 12),
            Text(
              _isScanning ? 'Scanning in progress…' : 'No observations yet',
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isScanning
                  ? 'Listening for nearby Bluetooth Low Energy beacons and devices…'
                  : 'Tap "Start Scan" above to discover nearby signals.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children:
          _observations.map((item) => _buildObservationTile(item)).toList(),
    );
  }

  Widget _buildObservationTile(BleDeviceObservation item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECE9E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: _softBlue,
                child: Icon(Icons.devices_other_rounded, color: _ink, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.advertisedName,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${item.anonymizedId} · ${item.proximityLabel}',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _sand.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${item.rssi} dBm',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Signal strength progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.signalRatio,
              backgroundColor: const Color(0xFFF0EBE1),
              valueColor: AlwaysStoppedAnimation<Color>(
                item.rssi >= -65 ? _rust : _tan,
              ),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Seen ${item.observationCount} time${item.observationCount == 1 ? '' : 's'}',
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
              Text(
                'Last seen: ${_formatTime(item.lastSeen)}',
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '${time.hour}:$minute:$second';
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: Color(0xFFECE9E0))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _rust,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          onPressed: _navigateToSafetyMode,
          icon: const Icon(Icons.shield_rounded, size: 20),
          label: const Text(
            'I FEEL UNSAFE — ACTIVATE SOS & ALERT HELPERS',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ),
    );
  }
}
