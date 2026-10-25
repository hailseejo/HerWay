import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'follow.dart';
import 'safety_mode.dart';

const ink = Color(0xFF263448);
const muted = Color(0xFF7D8285);
const paper = Color(0xFFF7F5EF);
const card = Color(0xFFFFFEFB);
const sand = Color(0xFFECE4D2);
const tan = Color(0xFFB58B5D);
const rust = Color(0xFFB56E4E);
const softBlue = Color(0xFFE7EDF0);

String _formatOverviewDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class TrustedContact {
  const TrustedContact({required this.name, required this.phone});

  final String name;
  final String phone;

  String get encoded => '$name|$phone';

  static TrustedContact decode(String value) {
    final separator = value.indexOf('|');
    if (separator <= 0) {
      throw const FormatException('Invalid trusted contact');
    }
    return TrustedContact(
      name: value.substring(0, separator),
      phone: value.substring(separator + 1),
    );
  }
}

class RideTrip {
  const RideTrip({
    required this.vehicleType,
    required this.registration,
    required this.driverName,
    required this.driverPhone,
    required this.destination,
    required this.tripInfo,
  });

  final String vehicleType;
  final String registration;
  final String driverName;
  final String driverPhone;
  final String destination;
  final String tripInfo;

  String get summary =>
      '$vehicleType · $registration · Destination: $destination';

  Map<String, String> toJson() => {
        'vehicleType': vehicleType,
        'registration': registration,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'destination': destination,
        'tripInfo': tripInfo,
      };

  factory RideTrip.fromJson(Map<String, dynamic> json) => RideTrip(
        vehicleType: json['vehicleType'] as String? ?? 'Taxi',
        registration: json['registration'] as String? ?? '',
        driverName: json['driverName'] as String? ?? '',
        driverPhone: json['driverPhone'] as String? ?? '',
        destination: json['destination'] as String? ?? '',
        tripInfo: json['tripInfo'] as String? ?? '',
      );
}

enum AlertStatus { idle, prepared, composerOpened, acknowledged }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(HerWayApp(firebaseReady: Firebase.apps.isNotEmpty));
}

class HerWayApp extends StatelessWidget {
  const HerWayApp({super.key, this.firebaseReady = false});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HerWay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(seedColor: tan),
        fontFamily: 'Arial',
        useMaterial3: true,
      ),
      home: SafetyDashboard(firebaseReady: firebaseReady),
    );
  }
}

class SafetyDashboard extends StatefulWidget {
  const SafetyDashboard({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<SafetyDashboard> createState() => _SafetyDashboardState();
}

class _SafetyDashboardState extends State<SafetyDashboard> {
  int _selectedTab = 0;
  bool _sharingLocation = false;
  final _storage = const FlutterSecureStorage();
  final _contacts = <TrustedContact>[];
  final _selectedContacts = <TrustedContact>{};
  int _selectedContact = 0;
  AlertStatus _alertStatus = AlertStatus.idle;
  final _bluetooth = AppBluetoothService();
  final _nearbyPlacesService = NearbyPlacesService();
  final _battery = Battery();
  StreamSubscription<List<BleDeviceObservation>>? _nearbySubscription;
  StreamSubscription<Object>? _bluetoothErrorSubscription;
  List<BleDeviceObservation> _nearbyDevices = [];
  BluetoothAdapterState _bluetoothState = BluetoothAdapterState.unknown;
  bool _isScanning = false;
  List<NearbyPlace> _nearbyPlaces = [];
  bool _isLoadingPlaces = false;
  String? _placesError;
  StreamSubscription<BatteryState>? _batterySubscription;
  bool _lowBatteryWarningShown = false;
  RideTrip? _activeRide;
  Timer? _checkInTimer;
  int _checkInRemainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadRide();
    _startBatteryMonitoring();
    if (!_supportsBluetooth) return;
    _nearbySubscription = _bluetooth.observationsStream.listen((devices) {
      if (mounted) setState(() => _nearbyDevices = devices);
    });
    _bluetoothErrorSubscription = _bluetooth.errorsStream.listen((error) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      _message('Bluetooth scan error: ${_bluetoothErrorMessage(error)}');
    });
    _watchBluetoothState();
  }

  Future<void> _watchBluetoothState() async {
    try {
      await for (final state in _bluetooth.adapterState) {
        if (mounted) setState(() => _bluetoothState = state);
      }
    } on UnsupportedError {
      // BLE is not available on the host running widget tests or web.
    }
  }

  bool get _supportsBluetooth =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void dispose() {
    _nearbySubscription?.cancel();
    _bluetoothErrorSubscription?.cancel();
    _bluetooth.dispose();
    _nearbyPlacesService.dispose();
    _batterySubscription?.cancel();
    _checkInTimer?.cancel();
    super.dispose();
  }

  Future<void> _startBatteryMonitoring() async {
    try {
      final level = await _battery.batteryLevel;
      _handleBatteryLevel(level);
      _batterySubscription = _battery.onBatteryStateChanged.listen((_) async {
        _handleBatteryLevel(await _battery.batteryLevel);
      });
    } catch (_) {
      // Battery monitoring is unavailable on unsupported platforms.
    }
  }

  void _handleBatteryLevel(int level) {
    if (!mounted) return;
    if (level > 10) {
      _lowBatteryWarningShown = false;
      return;
    }
    if (_lowBatteryWarningShown) return;
    _lowBatteryWarningShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showLowBatteryWarning(level);
    });
  }

  Future<void> _showLowBatteryWarning(int level) async {
    final share = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('⚠️ LOW BATTERY — $level% REMAINING'),
        content: const Text(
          'Your phone may switch off soon. Stay connected to your trusted circle.\n\nWould you like to share your current location with your trusted contacts before your battery runs out?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("I'll do this later"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Share location via SMS'),
          ),
        ],
      ),
    );
    if (share == true) {
      await _shareLowBatteryLocation();
    }
  }

  Future<void> _shareLowBatteryLocation() async {
    final selectedContacts =
        _contacts.where(_selectedContacts.contains).toList();
    if (selectedContacts.isEmpty) {
      _message('Select at least one trusted contact before sharing.');
      return;
    }
    final recipientCount = selectedContacts.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share with your trusted circle?'),
        content: Text(
          'One SMS will be prepared for $recipientCount selected trusted ${recipientCount == 1 ? 'contact' : 'contacts'}. You can review it before sending.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final position = await _getLocation();
    if (!mounted || position == null) return;
    final phones = selectedContacts.map((contact) => contact.phone).toList();
    final body =
        'Hi, my phone battery is critically low, and I may become unreachable soon. Here is my current location so you can check on me if needed:\n\nhttps://www.openstreetmap.org/?mlat=${position.latitude}&mlon=${position.longitude}#map=18/${position.latitude}/${position.longitude}\n\nI\'ll update you when I can.';
    await _openSmsComposer(phones, body);
  }

  Future<bool> _openSmsComposer(List<String> phones, String body) async {
    if (phones.isEmpty) {
      _message('Select at least one trusted contact before sharing.');
      return false;
    }
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    if (isIos) {
      try {
        final opened =
            await const MethodChannel('herway/sms').invokeMethod<bool>(
          'composeSms',
          {'recipients': phones, 'body': body},
        );
        if (!mounted) return false;
        if (opened != true) {
          _message('SMS is unavailable on this device.');
          return false;
        } else {
          _message('Location message prepared. Review it and press Send.');
          return true;
        }
      } on PlatformException {
        if (mounted) _message('Messages could not open on this device.');
        return false;
      }
    }
    try {
      final opened = await const MethodChannel('herway/sms').invokeMethod<bool>(
        'composeSms',
        {'recipients': phones, 'body': body},
      );
      if (!mounted) return false;
      if (opened == true) {
        _message(
            'One message prepared for ${phones.length} contacts. Review it and press Send.');
        return true;
      } else {
        _message('Your messaging app is unavailable on this device.');
        return false;
      }
    } on PlatformException {
      if (mounted) {
        _message('Your messaging app is unavailable on this device.');
      }
      return false;
    }
  }

  Future<void> _loadNearbyPlaces() async {
    if (_isLoadingPlaces) return;
    if (mounted) {
      setState(() {
        _isLoadingPlaces = true;
        _placesError = null;
      });
    }
    try {
      final position = await _getLocationForPlaces();
      if (position == null) {
        if (mounted) setState(() => _isLoadingPlaces = false);
        return;
      }
      final places = await _nearbyPlacesService.fetchNearby(position);
      if (!mounted) return;
      setState(() {
        _nearbyPlaces = places;
        _isLoadingPlaces = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPlaces = false;
        _placesError =
            'Nearby places could not be loaded. Check your connection and try again.';
      });
    }
  }

  Future<Position?> _getLocationForPlaces() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        setState(() => _placesError =
            'Turn on Location Services to find places near you.');
      }
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _placesError =
            'Location permission is needed to find nearby places.');
      }
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _scanNearby() async {
    if (!_supportsBluetooth) {
      _message('Bluetooth discovery is unavailable on this platform.');
      return;
    }
    if (_isScanning) {
      await _bluetooth.stopScan();
      if (mounted) setState(() => _isScanning = false);
      return;
    }
    try {
      if (_bluetoothState != BluetoothAdapterState.on) {
        _message('Turn on Bluetooth in Settings to find nearby HerWay users.');
        return;
      }
      setState(() {
        _isScanning = true;
        _nearbyDevices = [];
      });
      await _bluetooth.startScan(timeout: const Duration(seconds: 12));
      if (mounted) setState(() => _isScanning = false);
    } catch (error) {
      if (mounted) {
        setState(() => _isScanning = false);
        _message(
            'Bluetooth scan could not start: ${_bluetoothErrorMessage(error)}');
      }
    }
  }

  String _bluetoothErrorMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('permission') || text.contains('unauthorized')) {
      return 'Bluetooth permission is denied. Enable Nearby devices in Settings.';
    }
    if (text.contains('unsupported')) {
      return 'BLE is unavailable on this device or simulator.';
    }
    if (text.contains('poweredoff') || text.contains('off')) {
      return 'Bluetooth is turned off.';
    }
    return 'Check Bluetooth is enabled and try again.';
  }

  Future<void> _loadContacts() async {
    final stored = await _storage.read(key: 'trusted_contacts');
    if (!mounted || stored == null || stored.isEmpty) return;
    final loaded = <TrustedContact>[];
    for (final value in stored.split('\n')) {
      try {
        loaded.add(TrustedContact.decode(value));
      } on FormatException {
        // Ignore corrupted entries without exposing them in the UI.
      }
    }
    setState(() {
      _contacts.addAll(loaded);
      _selectedContacts.addAll(loaded);
    });
  }

  Future<void> _loadRide() async {
    final stored = await _storage.read(key: 'active_ride');
    if (!mounted || stored == null) return;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Saved ride data is invalid.');
      }
      setState(() => _activeRide = RideTrip.fromJson(decoded));
    } on FormatException {
      // Ignore an invalid saved trip and let the user create a new one.
    }
  }

  Future<void> _saveRide(RideTrip ride) async {
    await _storage.write(key: 'active_ride', value: jsonEncode(ride.toJson()));
    if (mounted) setState(() => _activeRide = ride);
  }

  Future<void> _addRide() async {
    final ride = await showDialog<RideTrip>(
      context: context,
      builder: (context) => const _RideDialog(),
    );
    if (ride == null) return;
    await _saveRide(ride);
    _message(
        'Ride details saved. Your trusted circle can be alerted if needed.');
  }

  Future<void> _clearRide() async {
    await _storage.delete(key: 'active_ride');
    if (mounted) setState(() => _activeRide = null);
  }

  Future<void> _sendRideAlert() async {
    final ride = _activeRide;
    final selectedContacts =
        _contacts.where(_selectedContacts.contains).toList();
    if (ride == null) return;
    if (selectedContacts.isEmpty) {
      _message('Select at least one trusted contact before sending.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send ride safety alert?'),
        content: Text(
          'One SMS will be prepared for ${selectedContacts.length} selected trusted ${selectedContacts.length == 1 ? 'contact' : 'contacts'} with the vehicle, driver, destination, and trip details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Prepare SMS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final position = await _getLocation();
    if (!mounted || position == null) {
      if (mounted) {
        _message(
            'Ride alert was not prepared because your current location is unavailable.');
      }
      return;
    }
    final locationUrl =
        'https://www.openstreetmap.org/?mlat=${position.latitude}&mlon=${position.longitude}#map=18/${position.latitude}/${position.longitude}';
    final body = '''RIDE SAFETY ALERT
I may be unsafe and need someone to check on my ride.

Vehicle: ${ride.vehicleType}
Registration: ${ride.registration}
Driver: ${ride.driverName}
Driver phone: ${ride.driverPhone.isEmpty ? 'Not provided' : ride.driverPhone}
Destination: ${ride.destination}
Trip information: ${ride.tripInfo.isEmpty ? 'Not provided' : ride.tripInfo}
Current location: $locationUrl

Please contact me and check on me if needed.''';
    await _openSmsComposer(
      selectedContacts.map((contact) => contact.phone).toList(),
      body,
    );
  }

  Future<void> _saveContacts() {
    return _storage.write(
      key: 'trusted_contacts',
      value: _contacts.map((contact) => contact.encoded).join('\n'),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<Position?> _getLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message(
            'Location services are off. The SOS will be prepared without a location.');
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _message(
            'Location permission was not granted. The SOS will omit location.');
        return null;
      }
      final position = await Geolocator.getCurrentPosition();
      return position;
    } catch (_) {
      _message(
          'Location is unavailable right now. The SOS will omit location.');
      return null;
    }
  }

  String _alertMessage(Position? position) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.now(),
      alwaysUse24HourFormat: false,
    );
    final location = position == null
        ? ''
        : '\nLocation: https://www.openstreetmap.org/?mlat=${position.latitude}&mlon=${position.longitude}#map=18/${position.latitude}/${position.longitude}';
    return 'HerWay safety alert from Alex. I need help. Alert prepared at $time.$location';
  }

  Future<bool> _confirmComposer(String contactName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open message composer?'),
        content: Text(
          'A prepared SOS will be addressed to $contactName. You must review and press Send yourself; HerWay cannot send SMS silently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _sendSosTo(TrustedContact contact) async {
    await _sendSosToContacts([contact]);
  }

  Future<void> _sendSosToContacts(List<TrustedContact> contacts) async {
    if (contacts.isEmpty) {
      _message('Select at least one trusted contact before sending an SOS.');
      return;
    }
    final names = contacts.map((contact) => contact.name).join(', ');
    final consented = await _confirmComposer(names);
    if (!consented) return;
    final position = await _getLocation();
    if (!mounted) return;
    final phones = <String>[];
    for (final contact in contacts) {
      final phone = contact.phone.trim();
      if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)) {
        _message(
            '${contact.name} has an invalid phone number. Please edit it first.');
        return;
      }
      phones.add(phone);
    }
    final body = _alertMessage(position);
    setState(() => _alertStatus = AlertStatus.prepared);
    final opened = await _openSmsComposer(phones, body);
    if (opened && mounted) {
      setState(() => _alertStatus = AlertStatus.composerOpened);
      _message(
          'SOS prepared for ${contacts.length} contacts. Review it and press Send.');
    }
  }

  Future<void> _sendSosToSelectedContacts() async {
    final selectedContacts =
        _contacts.where(_selectedContacts.contains).toList();
    await _sendSosToContacts(selectedContacts);
  }

  Future<void> _callContact(TrustedContact contact) async {
    final uri = Uri(scheme: 'tel', path: contact.phone);
    if (!await canLaunchUrl(uri) || !await launchUrl(uri)) {
      _message('The phone dialler is unavailable on this device.');
    }
  }

  Future<void> _callEmergencyServices() async {
    final uri = Uri(scheme: 'tel', path: '112');
    if (!await canLaunchUrl(uri) ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message(
          'Emergency calling is unavailable on this device. Call 112 manually.');
    }
  }

  Future<void> _chooseCheckInDuration() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Start a safety check-in'),
              subtitle:
                  Text('If you do not cancel it, your circle will be alerted.'),
            ),
            for (final duration in [5, 15, 30, 60])
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: tan),
                title: Text(duration == 60 ? '1 hour' : '$duration minutes'),
                onTap: () => Navigator.pop(context, duration),
              ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    _startCheckIn(minutes);
  }

  void _startCheckIn(int minutes) {
    _checkInTimer?.cancel();
    setState(() => _checkInRemainingSeconds = minutes * 60);
    _checkInTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_checkInRemainingSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _checkInRemainingSeconds = 0);
          _handleCheckInExpired();
        }
        return;
      }
      if (mounted) {
        setState(() => _checkInRemainingSeconds--);
      }
    });
    _message(
        'Check-in started for ${minutes == 60 ? '1 hour' : '$minutes minutes'}.');
  }

  void _cancelCheckIn() {
    _checkInTimer?.cancel();
    setState(() => _checkInRemainingSeconds = 0);
    _message('Check-in canceled. You marked yourself safe.');
  }

  Future<void> _handleCheckInExpired() async {
    _message('Check-in expired. Preparing an alert for your trusted circle.');
    final selectedContacts =
        _contacts.where(_selectedContacts.contains).toList();
    if (selectedContacts.isNotEmpty) {
      final position = await _getLocation();
      if (mounted) {
        final location = position == null
            ? 'Location unavailable.'
            : 'Current location: https://www.openstreetmap.org/?mlat=${position.latitude}&mlon=${position.longitude}#map=18/${position.latitude}/${position.longitude}';
        await _openSmsComposer(
          selectedContacts.map((contact) => contact.phone).toList(),
          'CHECK-IN ALERT\nI did not check in before my safety timer expired. Please check on me.\n\n$location',
        );
      }
    } else {
      _message('No trusted contacts are selected for the check-in alert.');
    }
    if (!mounted) return;
    final call = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Check-in expired'),
        content: const Text(
          'Your trusted-circle alert was prepared. If you are in immediate danger, call emergency services now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.phone_in_talk_rounded),
            label: const Text('Call 112'),
          ),
        ],
      ),
    );
    if (call == true) await _callEmergencyServices();
  }

  Future<void> _addContact() async {
    final result = await showDialog<TrustedContact>(
      context: context,
      builder: (context) => const _ContactDialog(),
    );
    if (result == null) return;
    setState(() {
      _contacts.add(result);
      _selectedContacts.add(result);
    });
    await _saveContacts();
    _message('${result.name} was added to your safety circle.');
  }

  Future<void> _removeContact(TrustedContact contact) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove trusted contact?'),
        content: Text(
            '${contact.name} will no longer receive prepared SOS messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    setState(() {
      _contacts.remove(contact);
      _selectedContacts.remove(contact);
      if (_selectedContact >= _contacts.length) {
        _selectedContact = _contacts.isEmpty ? 0 : _contacts.length - 1;
      }
    });
    await _saveContacts();
  }

  Future<void> _escalate() async {
    if (_contacts.length < 2) {
      _message('Add another trusted contact to use escalation.');
      return;
    }
    final next = (_selectedContact + 1) % _contacts.length;
    setState(() => _selectedContact = next);
    await _sendSosTo(_contacts[next]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () {},
          icon: const Icon(Icons.menu_rounded, color: ink),
        ),
        title: const Text(
          'HerWay',
          style: TextStyle(
            color: ink,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _message('You have no new notifications.'),
            icon: const Icon(Icons.notifications_none_rounded, color: ink),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 17,
              backgroundColor: sand,
              child: Text(
                'AM',
                style: TextStyle(
                  color: ink,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _selectedTab,
          children: [
            _Overview(
              onMessage: _message,
              sharingLocation: _sharingLocation,
              onLocationChanged: (value) =>
                  setState(() => _sharingLocation = value),
              checkInRemainingSeconds: _checkInRemainingSeconds,
              onStartCheckIn: _chooseCheckInDuration,
              onCancelCheckIn: _cancelCheckIn,
              firebaseReady: widget.firebaseReady,
              contacts: _contacts,
              selectedContact: _selectedContact,
              selectedContacts: _selectedContacts,
              alertStatus: _alertStatus,
              onSelectContact: (value) =>
                  setState(() => _selectedContact = value),
              onToggleContact: (contact) {
                setState(() {
                  if (!_selectedContacts.add(contact)) {
                    _selectedContacts.remove(contact);
                  }
                });
              },
              onAddContact: _addContact,
              onRemoveContact: _removeContact,
              onSendSos: () {
                if (_contacts.isEmpty) {
                  _message('Add a trusted contact before preparing an SOS.');
                  return;
                }
                _sendSosToSelectedContacts();
              },
              onCallContact: () {
                if (_contacts.isEmpty) {
                  _message('Add a trusted contact before calling.');
                  return;
                }
                _callContact(_contacts[_selectedContact]);
              },
              onCallEmergency: _callEmergencyServices,
              onEscalate: _escalate,
              nearbyPlaces: _nearbyPlaces,
              onOpenPlaces: () => setState(() => _selectedTab = 2),
              activeRide: _activeRide,
              onAddRide: _addRide,
              onClearRide: _clearRide,
              onSendRideAlert: _sendRideAlert,
            ),
            _CircleTab(
              devices: _nearbyDevices,
              adapterState: _bluetoothState,
              isScanning: _isScanning,
              onScan: _scanNearby,
              onMessage: _message,
            ),
            _PlacesTab(
              places: _nearbyPlaces,
              isLoading: _isLoadingPlaces,
              error: _placesError,
              onRefresh: _loadNearbyPlaces,
              onMessage: _message,
            ),
            const _SimpleTab(
              icon: Icons.person_outline_rounded,
              title: 'Your profile',
              subtitle: 'Manage your safety preferences.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: card,
        elevation: 0,
        selectedIndex: _selectedTab,
        onDestinationSelected: (value) {
          setState(() => _selectedTab = value);
          if (value == 2 && _nearbyPlaces.isEmpty) {
            _loadNearbyPlaces();
          }
        },
        indicatorColor: sand,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: ink),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded, color: ink),
            label: 'Circle',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on_rounded, color: ink),
            label: 'Places',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: ink),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.onMessage,
    required this.sharingLocation,
    required this.onLocationChanged,
    required this.checkInRemainingSeconds,
    required this.onStartCheckIn,
    required this.onCancelCheckIn,
    required this.firebaseReady,
    required this.contacts,
    required this.selectedContact,
    required this.selectedContacts,
    required this.alertStatus,
    required this.onSelectContact,
    required this.onToggleContact,
    required this.onAddContact,
    required this.onRemoveContact,
    required this.onSendSos,
    required this.onCallContact,
    required this.onCallEmergency,
    required this.onEscalate,
    required this.nearbyPlaces,
    required this.onOpenPlaces,
    required this.activeRide,
    required this.onAddRide,
    required this.onClearRide,
    required this.onSendRideAlert,
  });

  final ValueChanged<String> onMessage;
  final bool sharingLocation;
  final ValueChanged<bool> onLocationChanged;
  final int checkInRemainingSeconds;
  final VoidCallback onStartCheckIn;
  final VoidCallback onCancelCheckIn;
  final bool firebaseReady;
  final List<TrustedContact> contacts;
  final int selectedContact;
  final Set<TrustedContact> selectedContacts;
  final AlertStatus alertStatus;
  final ValueChanged<int> onSelectContact;
  final ValueChanged<TrustedContact> onToggleContact;
  final VoidCallback onAddContact;
  final ValueChanged<TrustedContact> onRemoveContact;
  final VoidCallback onSendSos;
  final VoidCallback onCallContact;
  final VoidCallback onCallEmergency;
  final VoidCallback onEscalate;
  final List<NearbyPlace> nearbyPlaces;
  final VoidCallback onOpenPlaces;
  final RideTrip? activeRide;
  final VoidCallback onAddRide;
  final VoidCallback onClearRide;
  final VoidCallback onSendRideAlert;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SATURDAY, OCTOBER 24',
            style: TextStyle(
              color: muted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.7,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Good evening, Alex',
            style: TextStyle(
              color: ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Let’s make sure you get home safely.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 22),
          _SafetyCard(
            onMessage: onMessage,
            onSendSos: onSendSos,
            onCallContact: onCallContact,
            onCallEmergency: onCallEmergency,
            onEscalate: onEscalate,
            alertStatus: alertStatus,
            selectedContact:
                contacts.isEmpty ? null : contacts[selectedContact],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.location_on_outlined,
                  label: sharingLocation ? 'Location on' : 'Share location',
                  color: softBlue,
                  onTap: () => onLocationChanged(!sharingLocation),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.access_time_rounded,
                        label: checkInRemainingSeconds > 0
                            ? _formatOverviewDuration(checkInRemainingSeconds)
                            : 'Start check-in',
                        color: const Color(0xFFF1E6D4),
                        onTap: checkInRemainingSeconds > 0
                            ? () {}
                            : onStartCheckIn,
                      ),
                    ),
                    if (checkInRemainingSeconds > 0)
                      IconButton(
                        onPressed: onCancelCheckIn,
                        tooltip: 'Cancel check-in',
                        icon: const Icon(Icons.close_rounded, color: rust),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FollowMeBanner(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const FollowPage()),
              );
            },
          ),
          const SizedBox(height: 12),
          _RideSafetyCard(
            ride: activeRide,
            onAddRide: onAddRide,
            onClearRide: onClearRide,
            onSendAlert: onSendRideAlert,
          ),
          const SizedBox(height: 27),
          _SectionTitle(
            title: 'Your safety circle',
            action: 'Add',
            onPressed: onAddContact,
          ),
          const SizedBox(height: 12),
          if (contacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${selectedContacts.length} selected for low-battery location sharing · Tap to toggle',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < contacts.length; i++)
                  _Contact(
                    contact: contacts[i],
                    selected: selectedContacts.contains(contacts[i]),
                    color: [
                      const Color(0xFFE8C9B4),
                      const Color(0xFFD8D6E8),
                      const Color(0xFFC9DDE1),
                    ][i % 3],
                    onTap: () {
                      onSelectContact(i);
                      onToggleContact(contacts[i]);
                    },
                    onRemove: () => onRemoveContact(contacts[i]),
                  ),
                _AddContact(onTap: onAddContact),
              ],
            ),
          ),
          if (contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Add someone you trust before using SOS.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          const SizedBox(height: 27),
          _SectionTitle(
            title: 'Nearby safe places',
            action: 'See all',
            onPressed: onOpenPlaces,
          ),
          const SizedBox(height: 12),
          if (nearbyPlaces.isEmpty)
            _PlaceTile(
              icon: Icons.location_searching_rounded,
              title: 'Find places near you',
              detail: 'Open Places to use your location',
              color: softBlue,
              onTap: onOpenPlaces,
            )
          else
            ...nearbyPlaces.take(2).map(
                  (place) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _NearbyPlaceTile(
                      place: place,
                      onMessage: onMessage,
                    ),
                  ),
                ),
          if (firebaseReady) ...[
            const SizedBox(height: 18),
            const Row(
              children: [
                Icon(Icons.cloud_done_outlined, size: 14, color: muted),
                SizedBox(width: 6),
                Text(
                  'Your safety data is securely connected',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({
    required this.onMessage,
    required this.onSendSos,
    required this.onCallContact,
    required this.onCallEmergency,
    required this.onEscalate,
    required this.alertStatus,
    required this.selectedContact,
  });

  final ValueChanged<String> onMessage;
  final VoidCallback onSendSos;
  final VoidCallback onCallContact;
  final VoidCallback onCallEmergency;
  final VoidCallback onEscalate;
  final AlertStatus alertStatus;
  final TrustedContact? selectedContact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFECE9E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D263448),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF73A58C),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'YOU ARE SAFE',
                style: TextStyle(
                  color: Color(0xFF658872),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Text(
            'Need help?',
            style: TextStyle(
              color: ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Call emergency services directly or inform your inner circle.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onLongPress: () {
                onMessage('Your safety circle has been alerted.');
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SafetyModePage()),
                );
              },
              child: Container(
                height: 62,
                decoration: BoxDecoration(
                  color: rust,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSendSos,
              icon: const Icon(Icons.groups_rounded),
              label: const Text('PRESS TO INFORM INNER CIRCLE'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                side: const BorderSide(color: tan),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'A single SMS will be prepared for selected contacts. Review and press Send.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCallContact,
                  icon: const Icon(Icons.call_outlined, size: 16),
                  label: const Text('Call trusted contact'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: const BorderSide(color: sand),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onEscalate,
                tooltip: 'Escalate to next contact',
                icon: const Icon(Icons.skip_next_rounded, color: tan),
              ),
            ],
          ),
          if (selectedContact != null)
            Text(
              'Selected: ${selectedContact!.name} · ${_statusLabel(alertStatus)}',
              style: const TextStyle(color: muted, fontSize: 10),
            ),
        ],
      ),
    );
  }

  String _statusLabel(AlertStatus status) {
    switch (status) {
      case AlertStatus.idle:
        return 'Ready';
      case AlertStatus.prepared:
        return 'Prepared';
      case AlertStatus.composerOpened:
        return 'Composer opened — not sent yet';
      case AlertStatus.acknowledged:
        return 'Acknowledged';
    }
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: ink, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ink,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowMeBanner extends StatelessWidget {
  const _FollowMeBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFECE9E0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08263448),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: sand,
              child: Icon(Icons.radar_rounded, color: ink, size: 20),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Someone may be following me?',
                    style: TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Scan nearby BLE signals & enter safety mode',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.action,
    this.onPressed,
  });

  final String title;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        TextButton(
          onPressed: onPressed,
          child: Text(
            action,
            style: const TextStyle(
              color: tan,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({
    required this.contact,
    required this.selected,
    required this.color,
    required this.onTap,
    required this.onRemove,
  });

  final TrustedContact contact;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onRemove,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: color,
                  child: Text(
                    contact.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: ink,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF73A58C),
                      shape: BoxShape.circle,
                      border: Border.all(color: paper, width: 2),
                    ),
                  ),
                ),
                if (selected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: rust, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              contact.name,
              style: const TextStyle(color: ink, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddContact extends StatelessWidget {
  const _AddContact({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: card,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD5CEC0)),
              ),
              child: const Icon(Icons.add_rounded, color: tan),
            ),
            const SizedBox(height: 7),
            const Text('Add', style: TextStyle(color: muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog();

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _consent = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final normalized = value?.replaceAll(RegExp(r'[\s()-]'), '') ?? '';
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add trusted contact'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name'
                    : null,
              ),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
                validator: _validatePhone,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (value) => setState(() => _consent = value ?? false),
                title: const Text(
                  'I have this person’s consent to contact them in an emergency.',
                  style: TextStyle(fontSize: 12),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate() || !_consent) return;
            Navigator.pop(
              context,
              TrustedContact(
                name: _nameController.text.trim(),
                phone: _phoneController.text.replaceAll(RegExp(r'[\s()-]'), ''),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFECE9E0)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color,
              child: Icon(icon, color: ink, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    );
  }
}

class _CircleTab extends StatelessWidget {
  const _CircleTab({
    required this.devices,
    required this.adapterState,
    required this.isScanning,
    required this.onScan,
    required this.onMessage,
  });

  final List<BleDeviceObservation> devices;
  final BluetoothAdapterState adapterState;
  final bool isScanning;
  final VoidCallback onScan;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) {
    final bluetoothReady = adapterState == BluetoothAdapterState.on;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SAFETY CIRCLE',
            style: TextStyle(
              color: muted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.7,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Nearby Bluetooth devices',
            style: TextStyle(
              color: ink,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan for nearby BLE devices. A phone will only appear if it is actively advertising.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFECE9E0)),
            ),
            child: Row(
              children: [
                Icon(
                  bluetoothReady
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_disabled_rounded,
                  color: bluetoothReady ? const Color(0xFF658872) : rust,
                  size: 25,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    bluetoothReady
                        ? 'Bluetooth is ready to scan'
                        : 'Bluetooth is off or unavailable',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: onScan,
                  style: FilledButton.styleFrom(
                    backgroundColor: isScanning ? rust : tan,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isScanning ? 'Stop' : 'Scan'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (isScanning)
            const LinearProgressIndicator(color: tan, backgroundColor: sand),
          const SizedBox(height: 14),
          if (devices.isEmpty)
            _BluetoothEmptyState(
              scanning: isScanning,
              onMessage: onMessage,
            )
          else
            ...devices.map(
              (device) => _NearbyDeviceTile(
                device: device,
                onTap: () => onMessage(
                  '${device.advertisedName} is nearby. Bluetooth does not verify their identity.',
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'Privacy note: HerWay shows anonymized Bluetooth observations only. A nearby device is not automatically a trusted person, and no contact information is exchanged by scanning. Two phones running HerWay do not appear to each other yet because this feature currently scans but does not advertise.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _BluetoothEmptyState extends StatelessWidget {
  const _BluetoothEmptyState({required this.scanning, required this.onMessage});

  final bool scanning;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EDE3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.radar_rounded, color: tan, size: 38),
          const SizedBox(height: 10),
          Text(
            scanning ? 'Looking nearby…' : 'No HerWay devices found',
            style: const TextStyle(
              color: ink,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            scanning
                ? 'Keep this screen open while scanning.'
                : 'Nearby BLE devices must be powered on and advertising. Test with a physical device, not an iOS simulator.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _NearbyDeviceTile extends StatelessWidget {
  const _NearbyDeviceTile({required this.device, required this.onTap});

  final BleDeviceObservation device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: card,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFECE9E0)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(
          backgroundColor: softBlue,
          child: Icon(Icons.bluetooth_rounded, color: ink),
        ),
        title: Text(
          device.advertisedName,
          style: const TextStyle(
            color: ink,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${device.proximityLabel} · ${device.rssi} dBm',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: muted),
      ),
    );
  }
}

class _NearbyPlaceTile extends StatelessWidget {
  const _NearbyPlaceTile({required this.place, required this.onMessage});

  final NearbyPlace place;
  final ValueChanged<String> onMessage;

  IconData get _icon {
    switch (place.category) {
      case NearbyPlaceCategory.police:
        return Icons.local_police_outlined;
      case NearbyPlaceCategory.hospital:
        return Icons.local_hospital_outlined;
      case NearbyPlaceCategory.public:
        return Icons.account_balance_outlined;
    }
  }

  Color get _color {
    switch (place.category) {
      case NearbyPlaceCategory.police:
        return const Color(0xFFD8D6E8);
      case NearbyPlaceCategory.hospital:
        return const Color(0xFFF1DED2);
      case NearbyPlaceCategory.public:
        return const Color(0xFFE8E0CD);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = [
      place.categoryLabel,
      place.distanceLabel,
      if (place.openingHours != null) place.openingHours!,
    ].join(' · ');
    return _PlaceTile(
      icon: _icon,
      title: place.name,
      detail: detail,
      color: _color,
      onTap: () async {
        final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${place.latitude},${place.longitude}',
        );
        if (!await canLaunchUrl(uri) ||
            !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          onMessage('Directions could not be opened on this device.');
        }
      },
    );
  }
}

class _RideSafetyCard extends StatelessWidget {
  const _RideSafetyCard({
    required this.ride,
    required this.onAddRide,
    required this.onClearRide,
    required this.onSendAlert,
  });

  final RideTrip? ride;
  final VoidCallback onAddRide;
  final VoidCallback onClearRide;
  final VoidCallback onSendAlert;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECE9E0)),
      ),
      child: ride == null
          ? InkWell(
              onTap: onAddRide,
              child: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: softBlue,
                    child: Icon(Icons.local_taxi_outlined, color: ink),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ride safety',
                            style: TextStyle(
                                color: ink,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 3),
                        Text('Save taxi, cab, or auto details',
                            style: TextStyle(color: muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: muted),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_taxi_outlined, color: tan),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Ride safety active',
                          style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: onClearRide,
                      tooltip: 'Clear ride',
                      icon: const Icon(Icons.close_rounded, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(ride!.summary,
                    style: const TextStyle(color: ink, fontSize: 12)),
                const SizedBox(height: 4),
                Text('Driver: ${ride!.driverName} · ${ride!.tripInfo}',
                    style: const TextStyle(color: muted, fontSize: 11)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onAddRide,
                        child: const Text('Edit details'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onSendAlert,
                        icon: const Icon(Icons.sms_outlined, size: 17),
                        label: const Text('Send alert'),
                        style: FilledButton.styleFrom(
                          backgroundColor: rust,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _RideDialog extends StatefulWidget {
  const _RideDialog();

  @override
  State<_RideDialog> createState() => _RideDialogState();
}

class _RideDialogState extends State<_RideDialog> {
  final _formKey = GlobalKey<FormState>();
  final _registration = TextEditingController();
  final _driverName = TextEditingController();
  final _driverPhone = TextEditingController();
  final _destination = TextEditingController();
  final _tripInfo = TextEditingController();
  String _vehicleType = 'Taxi';

  @override
  void dispose() {
    _registration.dispose();
    _driverName.dispose();
    _driverPhone.dispose();
    _destination.dispose();
    _tripInfo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ride safety details'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _vehicleType,
                decoration: const InputDecoration(labelText: 'Vehicle type'),
                items: ['Taxi', 'Cab', 'Auto'].map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (value) =>
                    setState(() => _vehicleType = value ?? 'Taxi'),
              ),
              TextFormField(
                controller: _registration,
                decoration: const InputDecoration(
                    labelText: 'Vehicle registration number'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the registration number'
                    : null,
              ),
              TextFormField(
                controller: _driverName,
                decoration: const InputDecoration(labelText: 'Driver name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the driver name'
                    : null,
              ),
              TextFormField(
                controller: _driverPhone,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'Driver phone (optional)'),
              ),
              TextFormField(
                controller: _destination,
                decoration: const InputDecoration(labelText: 'Destination'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the destination'
                    : null,
              ),
              TextFormField(
                controller: _tripInfo,
                decoration: const InputDecoration(
                    labelText: 'Trip information (optional)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              RideTrip(
                vehicleType: _vehicleType,
                registration: _registration.text.trim(),
                driverName: _driverName.text.trim(),
                driverPhone: _driverPhone.text.trim(),
                destination: _destination.text.trim(),
                tripInfo: _tripInfo.text.trim(),
              ),
            );
          },
          child: const Text('Save ride'),
        ),
      ],
    );
  }
}

class _PlacesTab extends StatelessWidget {
  const _PlacesTab({
    required this.places,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onMessage,
  });

  final List<NearbyPlace> places;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NEARBY PLACES',
            style: TextStyle(
              color: muted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.7,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Help close to you',
            style: TextStyle(
              color: ink,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Find police stations, hospitals, and staffed public places using your current location.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isLoading ? null : onRefresh,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: Text(isLoading ? 'Finding places…' : 'Use my location'),
              style: FilledButton.styleFrom(
                backgroundColor: tan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1DED2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: rust),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(color: ink, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isLoading && error == null && places.isEmpty) ...[
            const SizedBox(height: 22),
            const Center(
              child: Text(
                'Use your location to see nearby places.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
          if (places.isNotEmpty) ...[
            const SizedBox(height: 22),
            ...places.map(
              (place) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _NearbyPlaceTile(
                  place: place,
                  onMessage: onMessage,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Place information comes from OpenStreetMap and may be incomplete. Always verify opening hours in an emergency.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _SimpleTab extends StatelessWidget {
  const _SimpleTab(
      {required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: tan, size: 45),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: ink,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(subtitle, style: const TextStyle(color: muted)),
          ],
        ),
      ),
    );
  }
}
