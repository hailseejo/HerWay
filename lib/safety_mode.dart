import 'dart:async';
import 'package:flutter/material.dart';

// Brand design tokens matching main.dart
const _ink = Color(0xFF263448);
const _muted = Color(0xFF7D8285);
const _paper = Color(0xFFF7F5EF);
const _card = Color(0xFFFFFEFB);
const _sand = Color(0xFFECE4D2);
const _rust = Color(0xFFB56E4E);
const _softBlue = Color(0xFFE7EDF0);
const _safeGreen = Color(0xFF73A58C);

/// Discreet user-triggered safety mode screen.
class SafetyModePage extends StatefulWidget {
  const SafetyModePage({super.key});

  @override
  State<SafetyModePage> createState() => _SafetyModePageState();
}

class _SafetyModePageState extends State<SafetyModePage> {
  // Screen state
  bool _isDiscreetDark = false;
  bool _locationSharingActive = false;
  String? _statusBanner;

  // SOS Countdown state
  Timer? _sosTimer;
  int _sosCountdown = 0;
  bool _sosPrepared = false;

  // Check-in state
  Timer? _checkInTimer;
  int _checkInRemainingSeconds = 0;

  @override
  void dispose() {
    _sosTimer?.cancel();
    _checkInTimer?.cancel();
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
      _sosPrepared = false;
      _statusBanner = 'Emergency alert preparing in 5 seconds... Tap to abort.';
    });

    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sosCountdown <= 1) {
        timer.cancel();
        setState(() {
          _sosCountdown = 0;
          _sosPrepared = true;
          _statusBanner =
              'Simulated SOS Alert Ready: In a production release, SMS & cloud broadcast would trigger here. Contacts Sam, Maya, and Daniel are staged.';
        });
      } else {
        setState(() {
          _sosCountdown--;
        });
      }
    });
  }

  void _cancelSos() {
    _sosTimer?.cancel();
    setState(() {
      _sosCountdown = 0;
      _sosPrepared = false;
      _statusBanner = 'SOS preparation canceled.';
    });
    _showMessage('SOS countdown canceled.');
  }

  // --- Location Sharing Logic ---
  void _toggleLocationSharing() {
    setState(() {
      _locationSharingActive = !_locationSharingActive;
      if (_locationSharingActive) {
        _statusBanner =
            'Location sharing initiated locally. Coordinates will be broadcast to trusted contacts when cloud GPS relay is connected.';
      } else {
        _statusBanner = 'Location sharing stopped.';
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
              'Check-in timer expired! Staged alert for your circle.';
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

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Discreet Mode description
              const Text(
                'DISCREET RESPONSE MODE',
                style: TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You are in control.',
                style: TextStyle(
                  color: fg,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Activate quick safety protections without drawing attention.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 18),

              // Status Banner
              if (_statusBanner != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _sosCountdown > 0 || _sosPrepared
                        ? _rust.withValues(alpha: 0.15)
                        : _softBlue.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _sosCountdown > 0 || _sosPrepared
                          ? _rust
                          : const Color(0xFFC9DDE1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _sosCountdown > 0
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline_rounded,
                        color: _sosCountdown > 0 || _sosPrepared ? _rust : _ink,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusBanner!,
                          style: TextStyle(
                            color: _sosCountdown > 0 || _sosPrepared ? _rust : _ink,
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

              // 1. SOS Preparation Card
              Container(
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
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: _rust.withValues(alpha: 0.15),
                          child: const Icon(Icons.shield_rounded,
                              color: _rust, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Prepare SOS Alert',
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
                      'Starts a 5-second discreet countdown. If not canceled, stages emergency alerts to your safety circle.',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
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
                              backgroundColor: _muted,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _cancelSos,
                            child: const Text('Cancel SOS'),
                          ),
                        ],
                      ),
                    ] else if (_sosPrepared) ...[
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'SOS Stage Ready',
                              style: TextStyle(
                                color: _rust,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: fg,
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _cancelSos,
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    ] else ...[
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
                            'ARM EMERGENCY SOS',
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
              ),

              const SizedBox(height: 16),

              // 2. Share My Location
              Container(
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
                          child: Icon(Icons.location_on_rounded,
                              color: _ink, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Share Location with Circle',
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
                          ? 'Status: Active locally. When cloud sync is connected, contacts receive continuous real-time coordinates.'
                          : 'Location broadcast is currently paused. Toggle to activate.',
                      style: TextStyle(
                        color: _locationSharingActive ? _safeGreen : _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3. Timed Safety Check-in
              Container(
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
                          child: Icon(Icons.timer_outlined,
                              color: _ink, size: 18),
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
              ),

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
}

