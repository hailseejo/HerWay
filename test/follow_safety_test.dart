import 'package:flutter_test/flutter_test.dart';
import 'package:herway/models/safety_session.dart';

void main() {
  group('BleDeviceObservation tests', () {
    test('calculates correct proximity label based on RSSI', () {
      final now = DateTime.now();

      final veryClose = BleDeviceObservation(
        anonymizedId: 'BLE-1234',
        advertisedName: 'Device A',
        rssi: -55,
        firstSeen: now,
        lastSeen: now,
      );
      expect(veryClose.proximityLabel, contains('Very close'));

      final nearby = BleDeviceObservation(
        anonymizedId: 'BLE-5678',
        advertisedName: 'Device B',
        rssi: -70,
        firstSeen: now,
        lastSeen: now,
      );
      expect(nearby.proximityLabel, contains('Nearby'));

      final vicinity = BleDeviceObservation(
        anonymizedId: 'BLE-9999',
        advertisedName: 'Device C',
        rssi: -85,
        firstSeen: now,
        lastSeen: now,
      );
      expect(vicinity.proximityLabel, contains('vicinity'));

      final distant = BleDeviceObservation(
        anonymizedId: 'BLE-0000',
        advertisedName: 'Device D',
        rssi: -95,
        firstSeen: now,
        lastSeen: now,
      );
      expect(distant.proximityLabel, contains('Weak / Distant'));
    });

    test('calculates normalized signal ratio clamped between 0 and 1', () {
      final now = DateTime.now();

      final strongest = BleDeviceObservation(
        anonymizedId: 'BLE-1111',
        advertisedName: 'Device',
        rssi: -30, // above max -40
        firstSeen: now,
        lastSeen: now,
      );
      expect(strongest.signalRatio, equals(1.0));

      final weakest = BleDeviceObservation(
        anonymizedId: 'BLE-2222',
        advertisedName: 'Device',
        rssi: -110, // below min -100
        firstSeen: now,
        lastSeen: now,
      );
      expect(weakest.signalRatio, equals(0.0));
    });
  });
}

