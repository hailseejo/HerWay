import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/safety_session.dart';

/// Service managing the community helper distress network and emergency dialing.
class CommunitySafetyService {
  CommunitySafetyService._internal();

  static final CommunitySafetyService instance = CommunitySafetyService._internal();

  factory CommunitySafetyService() => instance;

  final _storage = const FlutterSecureStorage();

  // Active distress alert broadcast by current user
  CommunityDistressAlert? _currentAlert;
  final _alertController = StreamController<CommunityDistressAlert?>.broadcast();

  // Incoming alert from nearby people needing help (for helper mode)
  CommunityDistressAlert? _incomingNearbyAlert;
  final _incomingAlertController = StreamController<CommunityDistressAlert?>.broadcast();

  Stream<CommunityDistressAlert?> get alertStream => _alertController.stream;
  Stream<CommunityDistressAlert?> get incomingAlertStream => _incomingAlertController.stream;

  CommunityDistressAlert? get currentAlert => _currentAlert;
  CommunityDistressAlert? get incomingNearbyAlert => _incomingNearbyAlert;

  String _userPhone = '+1 (555) 019-2834';
  String _userName = 'Alex';

  String get userPhone => _userPhone;
  String get userName => _userName;

  Future<void> init() async {
    final storedPhone = await _storage.read(key: 'user_phone_number');
    if (storedPhone != null && storedPhone.trim().isNotEmpty) {
      _userPhone = storedPhone.trim();
    }
    final storedName = await _storage.read(key: 'user_display_name');
    if (storedName != null && storedName.trim().isNotEmpty) {
      _userName = storedName.trim();
    }
  }

  Future<void> updateProfile({required String name, required String phone}) async {
    _userName = name.trim();
    _userPhone = phone.trim();
    await _storage.write(key: 'user_phone_number', value: _userPhone);
    await _storage.write(key: 'user_display_name', value: _userName);
  }

  /// Start broadcasting an SOS / "Someone is following me" distress signal
  /// to nearby community members having the HerWay app.
  Future<CommunityDistressAlert> broadcastDistress({
    required String threatDescription,
    Position? position,
    String? customPhone,
  }) async {
    final phone = customPhone?.trim().isNotEmpty == true ? customPhone!.trim() : _userPhone;

    final alert = CommunityDistressAlert(
      id: 'SOS-${DateTime.now().millisecondsSinceEpoch}',
      userName: _userName,
      userPhone: phone,
      threatDescription: threatDescription,
      latitude: position?.latitude,
      longitude: position?.longitude,
      timestamp: DateTime.now(),
      status: DistressStatus.broadcasting,
    );

    _currentAlert = alert;
    _notifyAlert();

    // In a production backend, this sends a push/BLE broadcast to nearby users.
    // For local simulation, also populate incoming alert so the user can test
    // accepting the request as a helper.
    _incomingNearbyAlert = alert;
    _notifyIncomingAlert();

    return alert;
  }

  /// Accept an alert as a nearby helper.
  /// When accepted, the helper is given the user's phone number to call immediately.
  void acceptAlertByHelper({
    required String alertId,
    required String helperName,
    required String helperDistance,
  }) {
    if (_currentAlert != null && _currentAlert!.id == alertId) {
      final helper = NearbyHelper(
        name: helperName,
        distance: helperDistance,
        acceptedAt: DateTime.now(),
      );

      _currentAlert = _currentAlert!.copyWith(
        status: DistressStatus.helperAccepted,
        acceptedBy: helper,
      );
      _notifyAlert();
    }

    if (_incomingNearbyAlert != null && _incomingNearbyAlert!.id == alertId) {
      _incomingNearbyAlert = _incomingNearbyAlert!.copyWith(
        status: DistressStatus.helperAccepted,
      );
      _notifyIncomingAlert();
    }
  }

  /// Simulate a nearby helper accepting after a short delay (for testing on one device).
  void simulateNearbyHelperAccepting({
    String helperName = 'Sarah (Nearby Community Member)',
    String helperDistance = '~120 meters away',
    Duration delay = const Duration(seconds: 4),
  }) {
    Timer(delay, () {
      if (_currentAlert != null && _currentAlert!.status == DistressStatus.broadcasting) {
        acceptAlertByHelper(
          alertId: _currentAlert!.id,
          helperName: helperName,
          helperDistance: helperDistance,
        );
      }
    });
  }

  /// Cancel or resolve the active distress broadcast.
  void resolveOrCancelDistress() {
    _currentAlert = null;
    _incomingNearbyAlert = null;
    _notifyAlert();
    _notifyIncomingAlert();
  }

  /// Make a direct phone call using the native phone dialer.
  Future<bool> launchPhoneCall(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanPhone);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  /// Launch SMS composer addressed to the phone number with emergency text.
  Future<bool> launchSms({
    required String phoneNumber,
    required String message,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(
      scheme: 'sms',
      path: cleanPhone,
      queryParameters: {'body': message},
    );
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  /// Direct one-tap call to emergency services (e.g. 911 / 112).
  Future<bool> callEmergencyServices({String emergencyNumber = '911'}) async {
    return launchPhoneCall(emergencyNumber);
  }

  void _notifyAlert() {
    if (!_alertController.isClosed) {
      _alertController.add(_currentAlert);
    }
  }

  void _notifyIncomingAlert() {
    if (!_incomingAlertController.isClosed) {
      _incomingAlertController.add(_incomingNearbyAlert);
    }
  }

  void dispose() {
    _alertController.close();
    _incomingAlertController.close();
  }
}
