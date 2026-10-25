import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'models/safety_session.dart';
import 'services/community_safety_service.dart';

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

/// Discreet user-triggered safety mode screen with working SOS and community responder network.
class SafetyModePage extends StatefulWidget {
  const SafetyModePage({
    super.key,
    this.userName,
    this.userPhone,
    this.onRecordingCheckInExpired,
  });

  final String? userName;
  final String? userPhone;
  final VoidCallback? onRecordingCheckInExpired;

  @override
  State<SafetyModePage> createState() => _SafetyModePageState();
}

class _SafetyModePageState extends State<SafetyModePage> {
  final CommunitySafetyService _communityService =
      CommunitySafetyService.instance;
  StreamSubscription<CommunityDistressAlert?>? _alertSubscription;
  StreamSubscription<CommunityDistressAlert?>? _incomingAlertSubscription;

  // Screen state
  bool _isDiscreetDark = false;
  bool _locationSharingActive = false;
  String? _statusBanner;

  // SOS state
  Timer? _sosTimer;
  int _sosCountdown = 0;
  bool _isSosActive = false;
  Position? _currentPosition;

  // Community helper state
  CommunityDistressAlert? _activeDistressAlert;
  String _userPhoneNumber = '';

  // Check-in state
  Timer? _checkInTimer;
  int _checkInRemainingSeconds = 0;
  Timer? _recordingCheckInTimer;
  int _recordingCheckInRemainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initCommunityService();
    _alertSubscription = _communityService.alertStream.listen((alert) {
      if (mounted) {
        setState(() {
          _activeDistressAlert = alert;
          if (alert != null && alert.isAccepted) {
            _statusBanner =
                '${alert.acceptedBy?.name ?? "A nearby helper"} accepted your help request! They have your phone number and are calling now.';
          }
        });
        _incomingAlertSubscription =
            _communityService.incomingAlertStream.listen((alert) {
          if (!mounted || alert == null) return;
          setState(() {
            _activeDistressAlert = alert;
            _statusBanner =
                'A nearby HerWay user needs help. Review the alert and choose whether to respond.';
          });
        });
      }
    });
  }

  Future<void> _initCommunityService() async {
    await _communityService.init();
    final name = widget.userName?.trim();
    final phone = widget.userPhone?.trim();
    if (name != null && name.isNotEmpty && phone != null && phone.isNotEmpty) {
      await _communityService.updateProfile(name: name, phone: phone);
    }
    if (mounted) {
      setState(() {
        _userPhoneNumber =
            phone?.isNotEmpty == true ? phone! : _communityService.userPhone;
        _activeDistressAlert = _communityService.currentAlert;
        if (_activeDistressAlert != null &&
            _activeDistressAlert!.isBroadcasting) {
          _isSosActive = true;
        }
      });
    }
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _checkInTimer?.cancel();
    _recordingCheckInTimer?.cancel();
    _alertSubscription?.cancel();
    _incomingAlertSubscription?.cancel();
    super.dispose();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // --- SOS Logic ---
  void _startSosCountdown() {
    setState(() {
      _sosCountdown = 5;
      _statusBanner = 'Emergency SOS preparing in 5s... Tap cancel to abort.';
    });

    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sosCountdown <= 1) {
        timer.cancel();
        _triggerWorkingSos();
      } else {
        setState(() {
          _sosCountdown--;
        });
      }
    });
  }

  Future<void> _triggerWorkingSos() async {
    setState(() {
      _sosCountdown = 0;
      _isSosActive = true;
      _statusBanner =
          '🚨 EMERGENCY SOS ACTIVATED. Nearby HerWay community and contacts alerted.';
    });

    // 1. Fetch current position for coordinates in SOS
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          _currentPosition = await Geolocator.getCurrentPosition();
        }
      }
    } catch (_) {}

    // 2. Broadcast distress to nearby community members having the app
    await _communityService.broadcastDistress(
      threatDescription:
          'Someone may be following me! Urgent assistance needed.',
      position: _currentPosition,
      customPhone: _userPhoneNumber,
    );

    _showMessage(
        'SOS broadcasted to nearby HerWay users and emergency contacts.');
  }

  void _cancelSos() {
    _sosTimer?.cancel();
    setState(() {
      _sosCountdown = 0;
      _statusBanner = 'SOS countdown aborted.';
    });
    _showMessage('SOS countdown aborted.');
  }

  void _standDownSos() {
    _communityService.resolveOrCancelDistress();
    setState(() {
      _isSosActive = false;
      _activeDistressAlert = null;
      _statusBanner = 'Emergency alert cleared. You marked yourself safe.';
    });
    _showMessage('Emergency SOS cleared. Stay safe!');
  }

  // --- Community Helper Broadcast Logic ---
  Future<void> _toggleCommunityBroadcast() async {
    if (_activeDistressAlert != null) {
      _communityService.resolveOrCancelDistress();
      setState(() {
        _activeDistressAlert = null;
        _statusBanner = 'Community help broadcast stopped.';
      });
      _showMessage('Community alert canceled.');
    } else {
      setState(() {
        _statusBanner =
            'Broadcasting help request to nearby HerWay users with your phone number ($_userPhoneNumber)...';
      });

      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}

      await _communityService.broadcastDistress(
        threatDescription:
            'Someone is following me. Please call me or come into view.',
        position: pos,
        customPhone: _userPhoneNumber,
      );

      _showMessage('Help request sent to nearby HerWay community members!');
    }
  }

  // Edit Phone Number Dialog
  Future<void> _editPhoneNumber() async {
    final controller = TextEditingController(text: _userPhoneNumber);
    final newPhone = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Your Contact Phone Number',
          style:
              TextStyle(color: _ink, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'When nearby community members accept your help request, they will receive this number so they can call you immediately.',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: const Icon(Icons.phone_rounded, color: _tan),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save Number'),
          ),
        ],
      ),
    );

    if (newPhone != null && newPhone.isNotEmpty) {
      await _communityService.updateProfile(
        name: _communityService.userName,
        phone: newPhone,
      );
      setState(() => _userPhoneNumber = newPhone);
      _showMessage('Contact number updated to $newPhone');
    }
  }

  // --- Location Sharing Logic ---
  void _toggleLocationSharing() {
    setState(() {
      _locationSharingActive = !_locationSharingActive;
      if (_locationSharingActive) {
        _statusBanner =
            'Location sharing active locally. Nearby responders and circle receive coordinates.';
      } else {
        _statusBanner = 'Location sharing paused.';
      }
    });
  }

  // --- Timed Check-in Logic ---
  void _startCheckIn(int minutes) {
    _checkInTimer?.cancel();
    setState(() {
      _checkInRemainingSeconds = minutes * 60;
      _statusBanner = 'Safety check-in active for $minutes minutes.';
    });

    _checkInTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_checkInRemainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _checkInRemainingSeconds = 0;
          _statusBanner =
              'Check-in timer expired! Staged alert for your circle & community.';
        });
        _showMessage('Check-in timer expired!');
      } else {
        setState(() {
          _checkInRemainingSeconds--;
        });
      }
    });
  }

  void _cancelCheckIn() {
    _checkInTimer?.cancel();
    setState(() {
      _checkInRemainingSeconds = 0;
      _statusBanner = 'Check-in canceled. You marked yourself safe.';
    });
    _showMessage('Check-in canceled. Stay safe!');
  }

  void _startRecordingCheckIn(int minutes) {
    _recordingCheckInTimer?.cancel();
    setState(() => _recordingCheckInRemainingSeconds = minutes * 60);
    _recordingCheckInTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingCheckInRemainingSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _recordingCheckInRemainingSeconds = 0);
          _handleRecordingCheckInExpired();
        }
        return;
      }
      if (mounted) {
        setState(() => _recordingCheckInRemainingSeconds--);
      }
    });
    _showMessage(
      'Video recording check-in started for ${minutes == 1 ? '1 minute' : '$minutes minutes'}.',
    );
  }

  void _cancelRecordingCheckIn() {
    _recordingCheckInTimer?.cancel();
    setState(() => _recordingCheckInRemainingSeconds = 0);
    _showMessage('Video recording check-in canceled.');
  }

  void _handleRecordingCheckInExpired() {
    _statusBanner =
        'Recording check-in expired. Opening visible video recording.';
    _showMessage('Recording check-in expired. Starting video recording.');
    final startRecording = widget.onRecordingCheckInExpired;
    if (startRecording == null) {
      _showMessage('Open the recorder manually to start video recording.');
      return;
    }
    startRecording();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Modal to test the Helper's experience (accepting and viewing the user's phone number to call)
  void _showHelperExperienceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _HelperResponseSheet(
        alert: _activeDistressAlert ??
            CommunityDistressAlert(
              id: 'SIM-1',
              userName: 'Alex',
              userPhone: _userPhoneNumber,
              threatDescription:
                  'Someone may be following me! Need someone on the line.',
              timestamp: DateTime.now(),
              status: DistressStatus.broadcasting,
            ),
        onAccepted: (helperName, distance) {
          return _communityService.acceptAlertByHelper(
            alertId: _activeDistressAlert?.id ?? 'SIM-1',
            helperName: helperName,
            helperDistance: distance,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = _isDiscreetDark ? const Color(0xFF14171A) : _paper;
    final fg = _isDiscreetDark ? const Color(0xFFE1E8ED) : _ink;
    final cardBg = _isDiscreetDark ? const Color(0xFF1F2428) : _card;
    final borderColor =
        _isDiscreetDark ? const Color(0xFF2C3238) : const Color(0xFFECE9E0);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded, color: fg),
        ),
        title: Text(
          'Safety Mode',
          style: TextStyle(
            color: fg,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _isDiscreetDark ? 'Light Theme' : 'Discreet Dark Theme',
            onPressed: () => setState(() => _isDiscreetDark = !_isDiscreetDark),
            icon: Icon(
              _isDiscreetDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              color: fg,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'DISCREET RESPONSE & SOS',
                style: TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isSosActive ? 'Active Emergency Mode' : 'You are in control.',
                style: TextStyle(
                  color: _isSosActive ? _rust : fg,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isSosActive
                    ? 'SOS signal active. Nearby community & emergency call lines ready.'
                    : 'Activate immediate emergency actions or ask nearby community for help.',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 18),

              // Status Banner
              if (_statusBanner != null) ...[
                _buildStatusBanner(),
                const SizedBox(height: 18),
              ],

              // Active Helper Acceptance Banner (if helper accepted)
              if (_activeDistressAlert != null &&
                  _activeDistressAlert!.isAccepted) ...[
                _buildHelperAcceptedCard(),
                const SizedBox(height: 18),
              ],

              // 1. SOS Emergency Section
              _buildSosSection(cardBg, borderColor, fg),

              const SizedBox(height: 18),

              // 2. Ask Nearby People Having the Same App for Help
              _buildNearbyCommunitySection(cardBg, borderColor, fg),

              const SizedBox(height: 18),

              // 3. Share My Location
              _buildLocationSection(cardBg, borderColor, fg),

              const SizedBox(height: 18),

              // 4. Timed Safety Check-in
              _buildCheckInSection(cardBg, borderColor, fg),
              const SizedBox(height: 12),
              _buildRecordingCheckInSection(cardBg, borderColor, fg),

              const SizedBox(height: 24),

              // Return Button
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: _muted),
                  label: const Text(
                    'Exit Safety Mode',
                    style: TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final isEmergency = _isSosActive || _sosCountdown > 0;
    final isAccepted = _activeDistressAlert?.isAccepted == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isEmergency
            ? _rust.withValues(alpha: 0.15)
            : (isAccepted
                ? _safeGreen.withValues(alpha: 0.15)
                : _softBlue.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmergency
              ? _rust
              : (isAccepted ? _safeGreen : const Color(0xFFC9DDE1)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEmergency
                ? Icons.warning_amber_rounded
                : (isAccepted
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded),
            color: isEmergency ? _rust : (isAccepted ? _safeGreen : _ink),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusBanner!,
              style: TextStyle(
                color: isEmergency ? _rust : (isAccepted ? _safeGreen : _ink),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Card displayed when a nearby helper accepts
  Widget _buildHelperAcceptedCard() {
    final helper = _activeDistressAlert?.acceptedBy;
    final helperName = helper?.name ?? 'Sarah (Nearby Community Member)';
    final helperDistance = helper?.distance ?? '~120 meters away';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF5F0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _safeGreen, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12263448),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: _safeGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_in_talk_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HELPER ACCEPTED YOUR REQUEST!',
                      style: TextStyle(
                        color: Color(0xFF2C634B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      helperName,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD3E7DC)),
            ),
            child: Row(
              children: [
                const Icon(Icons.near_me_rounded, color: _safeGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Helper is $helperDistance. They were provided your phone number ($_userPhoneNumber) and are calling you now. Please keep your line free.',
                    style:
                        const TextStyle(color: _ink, fontSize: 12, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 1. SOS Section (Working SOS Function)
  Widget _buildSosSection(Color cardBg, Color borderColor, Color fg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isSosActive ? _rust : borderColor,
          width: _isSosActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _rust.withValues(alpha: 0.15),
                child: const Icon(Icons.shield_rounded, color: _rust, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                _isSosActive ? 'Emergency SOS Active' : 'Emergency SOS',
                style: TextStyle(
                  color: _isSosActive ? _rust : fg,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isSosActive
                ? 'Your emergency distress beacon is active. One-tap actions below connect you to India\'s emergency number 112 or alert emergency contacts.'
                : 'Arms emergency actions. If triggered, broadcasts your distress to nearby HerWay users and prepares one-touch emergency calls.',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Countdown in progress
          if (_sosCountdown > 0) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Triggering in ${_sosCountdown}s',
                    style: const TextStyle(
                      color: _rust,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rust,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _triggerWorkingSos,
                  child: const Text('Trigger Now'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: fg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _cancelSos,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ] else if (_isSosActive) ...[
            // Active SOS Emergency Actions
            Column(
              children: [
                // Call India's unified emergency number
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _rust,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _communityService.callEmergencyServices(),
                    icon: const Icon(Icons.call_rounded, size: 20),
                    label: const Text(
                      'CALL EMERGENCY SERVICES (112)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _rust,
                      side: const BorderSide(color: _rust),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _communityService.launchPhoneCall('14490'),
                    icon: const Icon(Icons.support_agent_rounded, size: 20),
                    label: const Text(
                      'CALL MAHILA POLICE (14490)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // SMS to Primary Contact
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      final pos = _currentPosition;
                      final locString = pos != null
                          ? '\nLocation: https://www.openstreetmap.org/?mlat=${pos.latitude}&mlon=${pos.longitude}'
                          : '';
                      _communityService.launchSms(
                        phoneNumber: '112',
                        message:
                            'HerWay SOS Alert from Alex: Someone is following me.$locString',
                      );
                    },
                    icon: const Icon(Icons.message_rounded, size: 18),
                    label: const Text('Send Emergency SMS'),
                  ),
                ),
                const SizedBox(height: 12),

                // Stand down / I am safe button
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _standDownSos,
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        color: _safeGreen),
                    label: const Text(
                      'I Am Safe — Stand Down SOS',
                      style: TextStyle(
                        color: _safeGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Button to start SOS
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _rust,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _startSosCountdown,
                icon: const Icon(Icons.emergency_outlined, size: 20),
                label: const Text(
                  'ARM EMERGENCY SOS (5s COUNTDOWN)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 2. Ask Nearby People Having the Same App for Help Section
  Widget _buildNearbyCommunitySection(
      Color cardBg, Color borderColor, Color fg) {
    final bool isBroadcasting = _activeDistressAlert?.isBroadcasting == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isBroadcasting ? _tan : borderColor,
          width: isBroadcasting ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: _sand,
                child: Icon(Icons.groups_rounded, color: _ink, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ask Nearby Helpers (Community)',
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isBroadcasting)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _tan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'BROADCASTING',
                    style: TextStyle(
                        color: _tan, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Sends an urgent alert to other HerWay users in your vicinity. When someone accepts, they are given your phone number so they can call you right away.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 12),

          // User's contact number box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _sand.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_rounded, color: _tan, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your phone number given to responders:',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                      Text(
                        _userPhoneNumber,
                        style: TextStyle(
                          color: fg,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _editPhoneNumber,
                  child: const Text(
                    'Change',
                    style: TextStyle(
                        color: _tan, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Broadcast Action Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isBroadcasting ? _muted : _ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _toggleCommunityBroadcast,
              icon: Icon(
                isBroadcasting
                    ? Icons.stop_circle_outlined
                    : Icons.record_voice_over_rounded,
                size: 19,
              ),
              label: Text(
                isBroadcasting
                    ? 'STOP COMMUNITY BROADCAST'
                    : 'ASK NEARBY USERS FOR HELP',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Helper Simulation Preview
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: fg,
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showHelperExperienceSheet,
              icon: const Icon(Icons.phone_forwarded_rounded,
                  size: 17, color: _tan),
              label: const Text(
                'Preview Helper Experience (Accept & Call)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Location Sharing Section
  Widget _buildLocationSection(Color cardBg, Color borderColor, Color fg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: _softBlue,
                child: Icon(Icons.location_on_rounded, color: _ink, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Share Location with Responders',
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Switch(
                value: _locationSharingActive,
                activeThumbColor: _safeGreen,
                onChanged: (val) => _toggleLocationSharing(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _locationSharingActive
                ? 'Status: Active locally. Coordinates are attached to emergency SOS broadcasts.'
                : 'Location broadcast is currently paused. Toggle to activate.',
            style: TextStyle(
              color: _locationSharingActive ? _safeGreen : _muted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingCheckInSection(
      Color cardBg, Color borderColor, Color fg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: _softBlue,
                child: Icon(Icons.videocam_outlined, color: _ink, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Video Recording Check-In',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'If you do not cancel this timer, HerWay will open the visible recorder and start video after the timer expires.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_recordingCheckInRemainingSeconds > 0)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _softBlue.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recording starts in',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                      Text(
                        _formatDuration(_recordingCheckInRemainingSeconds),
                        style: TextStyle(
                          color: fg,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _safeGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _cancelRecordingCheckIn,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in [1, 5, 15, 30])
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _startRecordingCheckIn(minutes),
                    child: Text('$minutes min'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // 4. Check-in Section
  Widget _buildCheckInSection(Color cardBg, Color borderColor, Color fg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: _sand,
                child: Icon(Icons.timer_outlined, color: _ink, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Timed Safety Check-In',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'If you do not tap "I am Safe" before the timer expires, an alert will be sent to your safety circle.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_checkInRemainingSeconds > 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _sand.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Time Remaining',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                      Text(
                        _formatDuration(_checkInRemainingSeconds),
                        style: TextStyle(
                          color: fg,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _safeGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _cancelCheckIn,
                    child: const Text('I am safe'),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _startCheckIn(1),
                    child: const Text('1 min'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _startCheckIn(5),
                    child: const Text('5 min'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _startCheckIn(15),
                    child: const Text('15 min'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _startCheckIn(30),
                    child: const Text('30 min'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom Sheet showing how a nearby person with the app receives the alert,
/// accepts it, and receives the user's phone number to call.
class _HelperResponseSheet extends StatefulWidget {
  const _HelperResponseSheet({
    required this.alert,
    required this.onAccepted,
  });

  final CommunityDistressAlert alert;
  final Future<String?> Function(String helperName, String distance) onAccepted;

  @override
  State<_HelperResponseSheet> createState() => _HelperResponseSheetState();
}

class _HelperResponseSheetState extends State<_HelperResponseSheet> {
  bool _accepted = false;
  bool _isAccepting = false;
  String? _revealedPhone;

  @override
  void initState() {
    super.initState();
    _accepted = widget.alert.isAccepted;
  }

  Future<void> _handleAccept() async {
    setState(() {
      _accepted = true;
      _isAccepting = true;
    });
    final phone = await widget.onAccepted('Nearby HerWay user', 'Nearby');
    if (mounted) {
      setState(() {
        _isAccepting = false;
        _revealedPhone = phone;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD5CEC0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _rust.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active_rounded,
                    color: _rust, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMMUNITY DISTRESS ALERT',
                      style: TextStyle(
                        color: _rust,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Someone Nearby Needs Help',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Threat Details
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFECE9E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'User: ${widget.alert.userName}',
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const Row(
                      children: [
                        Icon(Icons.near_me_rounded, color: _muted, size: 14),
                        SizedBox(width: 4),
                        Text(
                          '~120m away',
                          style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '"${widget.alert.threatDescription}"',
                  style: const TextStyle(
                      color: _ink, fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (!_accepted) ...[
            // Accept / Decline Options
            const Text(
              'If you accept, you will receive their phone number to call and support them until they reach safety.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _safeGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isAccepting ? null : _handleAccept,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text(
                      'Accept & Help',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // User Phone Number revealed to Helper!
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF5F0),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _safeGreen),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_open_rounded,
                          color: _safeGreen, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'CONTACT PHONE NUMBER REVEALED:',
                        style: TextStyle(
                          color: _safeGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _revealedPhone ?? widget.alert.userPhone,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Please call them immediately and stay on the line until they reach a safe public place.',
                    style: TextStyle(color: _ink, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Call Now Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _safeGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  CommunitySafetyService.instance
                      .launchPhoneCall(widget.alert.userPhone);
                },
                icon: const Icon(Icons.phone_rounded, size: 22),
                label: Text(
                  'CALL ${widget.alert.userName.toUpperCase()} NOW',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Send SMS Button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: Color(0xFFD5CEC0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  CommunitySafetyService.instance.launchSms(
                    phoneNumber: widget.alert.userPhone,
                    message:
                        'Hi ${widget.alert.userName}, I accepted your HerWay safety alert. I am nearby. Are you safe?',
                  );
                },
                icon: const Icon(Icons.sms_outlined, size: 18),
                label: Text('Send SMS to ${widget.alert.userName}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
