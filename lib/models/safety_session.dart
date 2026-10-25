import 'package:flutter/foundation.dart';

/// Represents an anonymized Bluetooth Low Energy device observed nearby.
class BleDeviceObservation {
  BleDeviceObservation({
    required this.anonymizedId,
    required this.advertisedName,
    required this.rssi,
    required this.firstSeen,
    required this.lastSeen,
    this.observationCount = 1,
  });

  /// Masked or anonymized identifier (e.g. "BLE-8F2B") to prevent leaking raw MAC addresses.
  final String anonymizedId;

  /// The broadcast name if available, otherwise a generic label.
  final String advertisedName;

  /// Signal strength in dBm (higher / closer to 0 means stronger signal).
  final int rssi;

  /// Timestamp when this device was first detected in the current session.
  final DateTime firstSeen;

  /// Timestamp when this device was last detected.
  final DateTime lastSeen;

  /// Number of times advertisements were received from this device.
  final int observationCount;

  /// Human-readable proximity estimation based on RSSI.
  String get proximityLabel {
    if (rssi >= -60) {
      return 'Very close (< 3m)';
    } else if (rssi >= -75) {
      return 'Nearby (3m - 10m)';
    } else if (rssi >= -90) {
      return 'In vicinity (10m - 20m)';
    } else {
      return 'Weak / Distant (> 20m)';
    }
  }

  /// Normalized signal strength ratio between 0.0 (weakest) and 1.0 (strongest).
  /// Typical BLE RSSI ranges from -100 dBm to -40 dBm.
  double get signalRatio {
    const minRssi = -100.0;
    const maxRssi = -40.0;
    final clamped = rssi.clamp(minRssi, maxRssi);
    return (clamped - minRssi) / (maxRssi - minRssi);
  }

  BleDeviceObservation copyWith({
    String? anonymizedId,
    String? advertisedName,
    int? rssi,
    DateTime? firstSeen,
    DateTime? lastSeen,
    int? observationCount,
  }) {
    return BleDeviceObservation(
      anonymizedId: anonymizedId ?? this.anonymizedId,
      advertisedName: advertisedName ?? this.advertisedName,
      rssi: rssi ?? this.rssi,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      observationCount: observationCount ?? this.observationCount,
    );
  }
}

/// Represents the status of a user's safety session or check-in.
enum SafetyStatus {
  normal,
  monitoring,
  checkInActive,
  sosPreparing,
  sosTriggered,
}

/// State data for active safety check-in countdown.
@immutable
class SafetyCheckInState {
  const SafetyCheckInState({
    required this.isActive,
    required this.totalDuration,
    required this.remainingDuration,
    this.startedAt,
  });

  final bool isActive;
  final Duration totalDuration;
  final Duration remainingDuration;
  final DateTime? startedAt;

  static const SafetyCheckInState idle = SafetyCheckInState(
    isActive: false,
    totalDuration: Duration.zero,
    remainingDuration: Duration.zero,
  );

  SafetyCheckInState copyWith({
    bool? isActive,
    Duration? totalDuration,
    Duration? remainingDuration,
    DateTime? startedAt,
  }) {
    return SafetyCheckInState(
      isActive: isActive ?? this.isActive,
      totalDuration: totalDuration ?? this.totalDuration,
      remainingDuration: remainingDuration ?? this.remainingDuration,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}

