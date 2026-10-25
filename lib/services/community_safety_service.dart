import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/safety_session.dart';

/// Service managing the community helper distress network and emergency dialing.
class CommunitySafetyService {
  CommunitySafetyService._internal();

  static final CommunitySafetyService instance =
      CommunitySafetyService._internal();

  factory CommunitySafetyService() => instance;

  final _storage = const FlutterSecureStorage();
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _nearbyAlertsSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _ownedAlertSubscription;
  String? _activeAlertId;
  Position? _myPosition;

  // Active distress alert broadcast by current user
  CommunityDistressAlert? _currentAlert;
  final _alertController =
      StreamController<CommunityDistressAlert?>.broadcast();

  // Incoming alert from nearby people needing help (for helper mode)
  CommunityDistressAlert? _incomingNearbyAlert;
  final _incomingAlertController =
      StreamController<CommunityDistressAlert?>.broadcast();

  Stream<CommunityDistressAlert?> get alertStream => _alertController.stream;
  Stream<CommunityDistressAlert?> get incomingAlertStream =>
      _incomingAlertController.stream;

  CommunityDistressAlert? get currentAlert => _currentAlert;
  CommunityDistressAlert? get incomingNearbyAlert => _incomingNearbyAlert;

  String _userPhone = '';
  String _userName = 'HerWay user';

  String get userPhone => _userPhone;
  String get userName => _userName;

  Future<void> init() async {
    if (Firebase.apps.isEmpty) return;
    final storedPhone = await _storage.read(key: 'user_phone_number');
    if (storedPhone != null && storedPhone.trim().isNotEmpty) {
      _userPhone = storedPhone.trim();
    }
    final storedName = await _storage.read(key: 'user_display_name');
    if (storedName != null && storedName.trim().isNotEmpty) {
      _userName = storedName.trim();
    }
    await _startRemoteListeners();
  }

  Future<void> updateProfile(
      {required String name, required String phone}) async {
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
    final phone = customPhone?.trim().isNotEmpty == true
        ? customPhone!.trim()
        : _userPhone;

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

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && position != null) {
      try {
        final alertReference =
            _firestore.collection('distress_alerts').doc(alert.id);
        await alertReference.set({
          'ownerUid': user.uid,
          'userName': _userName,
          'threatDescription': threatDescription,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'createdAt': Timestamp.fromDate(alert.timestamp),
          'status': 'broadcasting',
        });
        await alertReference.collection('private').doc('contact').set({
          'phone': phone,
        });
        _activeAlertId = alert.id;
        _listenToOwnedAlert(alertReference);
      } on FirebaseException {
        // Keep the local alert usable when Firestore is unavailable.
      }
    }
    _currentAlert = alert;
    _notifyAlert();

    return alert;
  }

  /// Accept an alert as a nearby helper.
  /// When accepted, the helper is given the user's phone number to call immediately.
  Future<String?> acceptAlertByHelper({
    required String alertId,
    required String helperName,
    required String helperDistance,
  }) async {
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      await _firestore.collection('distress_alerts').doc(alertId).update({
        'status': 'helperAccepted',
        'acceptedByUid': user.uid,
        'acceptedByName': helperName,
        'acceptedDistance': helperDistance,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      final contact = await _firestore
          .collection('distress_alerts')
          .doc(alertId)
          .collection('private')
          .doc('contact')
          .get();
      final phone = contact.data()?['phone'] as String?;
      if (phone != null && _incomingNearbyAlert?.id == alertId) {
        _incomingNearbyAlert = _incomingNearbyAlert!.copyWith(userPhone: phone);
        _notifyIncomingAlert();
      }
      return phone;
    } on FirebaseException {
      // The local state remains available if the network is unavailable.
      return null;
    }
  }

  /// Cancel or resolve the active distress broadcast.
  void resolveOrCancelDistress() {
    final alertId = _activeAlertId;
    if (alertId != null) {
      unawaited(_firestore.collection('distress_alerts').doc(alertId).update({
        'status': 'resolved',
      }).catchError((_) {}));
    }
    _activeAlertId = null;
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

  /// Direct one-tap call to India's unified emergency number.
  Future<bool> callEmergencyServices({String emergencyNumber = '112'}) async {
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
    _nearbyAlertsSubscription?.cancel();
    _ownedAlertSubscription?.cancel();
    _alertController.close();
    _incomingAlertController.close();
  }

  Future<void> _startRemoteListeners() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    _myPosition = await Geolocator.getLastKnownPosition();
    if (_myPosition == null) {
      try {
        _myPosition = await Geolocator.getCurrentPosition();
      } catch (_) {}
    }
    await _nearbyAlertsSubscription?.cancel();
    _nearbyAlertsSubscription = _firestore
        .collection('distress_alerts')
        .where('status', isEqualTo: 'broadcasting')
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final candidates = snapshot.docs
          .where((doc) => doc.data()['ownerUid'] != currentUid)
          .map(_alertFromDocument)
          .whereType<CommunityDistressAlert>()
          .where(_isNearby)
          .toList();
      _incomingNearbyAlert = candidates.isEmpty ? null : candidates.first;
      _notifyIncomingAlert();
    }, onError: (_) {});
  }

  void _listenToOwnedAlert(DocumentReference<Map<String, dynamic>> reference) {
    _ownedAlertSubscription?.cancel();
    _ownedAlertSubscription = reference.snapshots().listen((snapshot) {
      if (!snapshot.exists) return;
      final alert = _alertFromDocument(snapshot);
      if (alert == null) return;
      _currentAlert = alert.copyWith(userPhone: _userPhone);
      _notifyAlert();
    });
  }

  CommunityDistressAlert? _alertFromDocument(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return null;
    final createdAt = data['createdAt'];
    final timestamp =
        createdAt is Timestamp ? createdAt.toDate() : DateTime.now();
    final status = data['status'] == 'helperAccepted'
        ? DistressStatus.helperAccepted
        : DistressStatus.broadcasting;
    final acceptedByName = data['acceptedByName'] as String?;
    return CommunityDistressAlert(
      id: snapshot.id,
      userName: data['userName'] as String? ?? 'HerWay user',
      userPhone: '',
      threatDescription:
          data['threatDescription'] as String? ?? 'Needs help nearby.',
      timestamp: timestamp,
      status: status,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      acceptedBy: acceptedByName == null
          ? null
          : NearbyHelper(
              name: acceptedByName,
              distance: data['acceptedDistance'] as String? ?? 'Nearby',
              acceptedAt: timestamp,
            ),
    );
  }

  bool _isNearby(CommunityDistressAlert alert) {
    if (_myPosition == null ||
        alert.latitude == null ||
        alert.longitude == null) {
      return false;
    }
    const earthRadiusKm = 6371.0;
    final latitudeDelta =
        (alert.latitude! - _myPosition!.latitude) * math.pi / 180;
    final longitudeDelta =
        (alert.longitude! - _myPosition!.longitude) * math.pi / 180;
    final a = math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(_myPosition!.latitude * math.pi / 180) *
            math.cos(alert.latitude! * math.pi / 180) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    final distanceKm =
        earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return distanceKm <= 5;
  }
}
