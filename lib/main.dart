import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

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

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
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
              firebaseReady: widget.firebaseReady,
            ),
            const _SimpleTab(
              icon: Icons.people_outline_rounded,
              title: 'Your circle',
              subtitle: 'Trusted people who have your back.',
            ),
            const _SimpleTab(
              icon: Icons.location_on_outlined,
              title: 'Safe places',
              subtitle: 'Places nearby where you can feel secure.',
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
        onDestinationSelected: (value) => setState(() => _selectedTab = value),
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
    required this.firebaseReady,
  });

  final ValueChanged<String> onMessage;
  final bool sharingLocation;
  final ValueChanged<bool> onLocationChanged;
  final bool firebaseReady;

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
          _SafetyCard(onMessage: onMessage),
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
                child: _QuickAction(
                  icon: Icons.access_time_rounded,
                  label: 'Start check-in',
                  color: const Color(0xFFF1E6D4),
                  onTap: () => onMessage('Check-in started for 30 minutes.'),
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
          const SizedBox(height: 27),
          const _SectionTitle(title: 'Your safety circle', action: 'Manage'),
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _Contact(
                    name: 'Sam',
                    initials: 'SJ',
                    color: const Color(0xFFE8C9B4),
                    onTap: onMessage),
                _Contact(
                    name: 'Maya',
                    initials: 'MJ',
                    color: const Color(0xFFD8D6E8),
                    onTap: onMessage),
                _Contact(
                    name: 'Daniel',
                    initials: 'DR',
                    color: const Color(0xFFC9DDE1),
                    onTap: onMessage),
                _AddContact(
                    onTap: () => onMessage('Invite someone you trust.')),
              ],
            ),
          ),
          const SizedBox(height: 27),
          const _SectionTitle(title: 'Nearby safe places', action: 'See map'),
          const SizedBox(height: 12),
          _PlaceTile(
            icon: Icons.local_hospital_outlined,
            title: "St. Mary's Hospital",
            detail: '0.8 mi · Open 24 hours',
            color: const Color(0xFFF1DED2),
            onTap: () =>
                onMessage('Opening directions to St. Mary’s Hospital.'),
          ),
          const SizedBox(height: 9),
          _PlaceTile(
            icon: Icons.local_cafe_outlined,
            title: 'Sunrise Café',
            detail: '1.2 mi · Open until 10:00 PM',
            color: const Color(0xFFE8E0CD),
            onTap: () => onMessage('Opening directions to Sunrise Café.'),
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
  const _SafetyCard({required this.onMessage});

  final ValueChanged<String> onMessage;

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
            'Press and hold to alert your safety circle.',
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
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.white, size: 21),
                    SizedBox(width: 10),
                    Text(
                      'PRESS & HOLD FOR SOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 13),
          const Center(
            child: Text(
              'Your location will be shared with your circle',
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
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
  const _SectionTitle({required this.title, required this.action});

  final String title;
  final String action;

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
          onPressed: () {},
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
    required this.name,
    required this.initials,
    required this.color,
    required this.onTap,
  });

  final String name;
  final String initials;
  final Color color;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap('Calling $name…'),
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
                    initials,
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
              ],
            ),
            const SizedBox(height: 7),
            Text(
              name,
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
