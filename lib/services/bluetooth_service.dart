import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;

import '../models/safety_session.dart';

/// Service responsible for Bluetooth adapter state monitoring and safe BLE scanning.
/// Note: Hides the GATT `BluetoothService` from flutter_blue_plus to avoid name collision.
class AppBluetoothService {
  AppBluetoothService();

  final Map<String, BleDeviceObservation> _observations = {};
  final StreamController<List<BleDeviceObservation>> _observationsController =
      StreamController<List<BleDeviceObservation>>.broadcast();
  final StreamController<Object> _errorsController =
      StreamController<Object>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  /// Stream of adapter state changes (e.g. on, off, unauthorized, unavailable).
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  /// Stream indicating whether a scan is currently in progress.
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// Synchronous boolean check for scanning state (note: isScanningNow is a bool, NOT a Future).
  bool get isScanningNow => FlutterBluePlus.isScanningNow;

  /// Stream of discovered nearby BLE observations, sorted by signal strength.
  Stream<List<BleDeviceObservation>> get observationsStream =>
      _observationsController.stream;

  Stream<Object> get errorsStream => _errorsController.stream;

  /// Current snapshot of observed devices.
  List<BleDeviceObservation> get currentObservations {
    final list = _observations.values.toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  /// Check the current adapter state once.
  Future<BluetoothAdapterState> getAdapterState() async {
    return FlutterBluePlus.adapterState.first;
  }

  /// Request the system prompt to turn on Bluetooth on Android.
  /// (On iOS, programmatic control is restricted by Apple; user must enable in Settings).
  Future<void> turnOn() async {
    await FlutterBluePlus.turnOn();
  }

  /// Start BLE scanning safely for nearby devices.
  ///
  /// [timeout] specifies how long foreground scanning should run before stopping.
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // 1. If already scanning, don't start duplicate scan.
    if (FlutterBluePlus.isScanningNow) {
      return;
    }

    // 2. Verify Bluetooth adapter status.
    final state = await getAdapterState();
    if (state != BluetoothAdapterState.on) {
      throw Exception(
        'Bluetooth is not enabled ($state). Please turn on Bluetooth in settings to scan.',
      );
    }

    // 3. Clear or preserve observations for fresh scan.
    _observations.clear();
    _notifyObservations();

    // 4. Cancel previous scan subscription if any.
    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      _handleScanResults,
      onError: (Object error) {
        if (!_errorsController.isClosed) {
          _errorsController.add(error);
        }
      },
    );

    // 5. Start scanning with timeout.
    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
    } catch (e) {
      await stopScan();
      rethrow;
    }
  }

  /// Process incoming scan results, deduplicating devices and anonymizing identifiers.
  void _handleScanResults(List<ScanResult> results) {
    final now = DateTime.now();

    for (final result in results) {
      final rawId = result.device.remoteId.str;
      final anonymizedId = _anonymizeIdentifier(rawId);

      final advertisedName = result.advertisementData.advName.trim().isNotEmpty
          ? result.advertisementData.advName.trim()
          : (result.device.platformName.trim().isNotEmpty
              ? result.device.platformName.trim()
              : 'Anonymous Device');

      if (_observations.containsKey(anonymizedId)) {
        final existing = _observations[anonymizedId]!;
        _observations[anonymizedId] = existing.copyWith(
          rssi: result.rssi,
          lastSeen: now,
          observationCount: existing.observationCount + 1,
        );
      } else {
        _observations[anonymizedId] = BleDeviceObservation(
          anonymizedId: anonymizedId,
          advertisedName: advertisedName,
          rssi: result.rssi,
          firstSeen: now,
          lastSeen: now,
          observationCount: 1,
        );
      }
    }

    _notifyObservations();
  }

  void _notifyObservations() {
    if (!_observationsController.isClosed) {
      _observationsController.add(currentObservations);
    }
  }

  /// Stop scanning safely.
  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  /// Clears observed devices list.
  void clearObservations() {
    _observations.clear();
    _notifyObservations();
  }

  /// Anonymize raw device IDs (e.g. MAC address or long UUID) to protect user and peripheral privacy.
  /// Example: "A1:B2:C3:D4:E5:F6" becomes "BLE-E5F6"
  String _anonymizeIdentifier(String rawId) {
    final clean = rawId.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    if (clean.length >= 4) {
      return 'BLE-${clean.substring(clean.length - 4)}';
    }
    return 'BLE-$clean';
  }

  /// Clean up all stream controllers and subscriptions.
  void dispose() {
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _observationsController.close();
    _errorsController.close();
  }
}

/// Alias for compatibility with previous naming
typedef BluetoothService = AppBluetoothService;
