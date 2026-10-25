# HerWay System Architecture and Technical Approach

## 1. System overview

HerWay is a Flutter mobile safety application with three operating layers:

```text
┌──────────────────────────────────────┐
│              Flutter UI              │
│ Dashboard · Safety Mode · Follow     │
│ Check-in · Simulated Call · Recorder │
└──────────────────┬───────────────────┘
                   │
┌──────────────────▼───────────────────┐
│       Application and Domain Logic    │
│ SOS state · timers · contacts · rides │
│ alert models · validation · workflows │
└───────────────┬──────────────┬────────┘
                │              │
┌───────────────▼───────┐  ┌───▼────────────────┐
│ Local Device Services │  │ Cloud/API Services │
│ Secure storage        │  │ Firebase Auth      │
│ Local recordings      │  │ Cloud Firestore    │
│ GPS                  │  │ OpenStreetMap API  │
│ Bluetooth LE          │  └────────────────────┘
│ Phone/SMS launcher    │
│ Audio playback        │
└───────────────────────┘
```

The main application entry point and dashboard orchestration are in
[`lib/main.dart`](lib/main.dart). The safety-mode experience is implemented in
[`lib/safety_mode.dart`](lib/safety_mode.dart), while nearby-user discovery is
handled through [`lib/follow.dart`](lib/follow.dart).

## 2. Main components

### Presentation layer

[`lib/main.dart`](lib/main.dart) currently contains:

- App initialization
- Firebase initialization
- Authentication gate
- Main dashboard navigation
- Trusted contacts UI
- Ride information
- Check-in timer
- Simulated-call flow
- Recording screens
- Nearby safe-place UI
- Bluetooth scan UI

[`SafetyModePage`](lib/safety_mode.dart) provides:

- Discreet safety interface
- SOS countdown
- Current-location lookup
- Community distress broadcast
- Helper acceptance status
- Check-in state
- Emergency escalation actions

[`lib/follow.dart`](lib/follow.dart) provides nearby-device discovery and
follow/safety-related screens. It consumes the Bluetooth service instead of
implementing BLE scanning directly.

### Domain and model layer

The main safety models are in
[`lib/models/safety_session.dart`](lib/models/safety_session.dart).

Important domain objects include:

- `CommunityDistressAlert`
- `NearbyHelper`
- `BleDeviceObservation`
- Distress and helper statuses
- Alert location and timestamp data

The dashboard also defines local models such as:

- `TrustedContact`
- `RideTrip`
- `AlertStatus`

These models represent user state and safety workflows without directly
depending on Firebase or HTTP.

### Service layer

#### Community safety service

[`lib/services/community_safety_service.dart`](lib/services/community_safety_service.dart)
is the main community-alert service.

Responsibilities:

- Load locally saved name and phone information
- Broadcast SOS/community distress alerts
- Listen for nearby distress alerts
- Track helper acceptance
- Update alert status
- Retrieve a protected contact number after helper acceptance
- Launch phone calls and SMS

It exposes reactive streams:

```dart
Stream<CommunityDistressAlert?> get alertStream
Stream<CommunityDistressAlert?> get incomingAlertStream
```

The UI subscribes to these streams and updates when alerts or helper responses
change.

#### Bluetooth service

[`lib/services/bluetooth_service.dart`](lib/services/bluetooth_service.dart)
wraps `flutter_blue_plus`.

Responsibilities:

- Check Bluetooth adapter state
- Start and stop BLE scans
- Deduplicate scan results
- Anonymize device identifiers
- Sort devices by RSSI
- Publish scan results through streams
- Report Bluetooth errors

The service intentionally avoids exposing raw device identifiers to the UI.

#### Nearby places service

[`lib/services/nearby_places_service.dart`](lib/services/nearby_places_service.dart)
calls the OpenStreetMap Overpass API.

Responsibilities:

- Query nearby police stations, hospitals, shelters, libraries, public places,
  and transport stations
- Parse OpenStreetMap results
- Calculate distance from the user
- Categorize results
- Sort places by proximity

This service requires an internet connection.

#### Local recording storage

[`lib/services/recording_storage_io.dart`](lib/services/recording_storage_io.dart)
stores recordings inside the device application documents directory:

```text
<Application Documents>/HerWayRecordings/
```

The platform-specific storage implementation is selected using conditional
imports in [`lib/main.dart`](lib/main.dart).

## 3. External integrations

### Firebase

Firebase is initialized during application startup in
[`lib/main.dart`](lib/main.dart).

Used for:

- Firebase Authentication
- User login and registration
- Firestore community distress alerts
- Helper response synchronization
- Remote alert status updates

Firebase configuration is defined in
[`lib/firebase_options.dart`](lib/firebase_options.dart).

### Firestore alert structure

The community service uses a structure similar to:

```text
distress_alerts/
  {alertId}
    ownerUid
    userName
    threatDescription
    latitude
    longitude
    createdAt
    status

    private/
      contact
        phone
```

Phone numbers are stored in a private subcollection instead of the public
alert document.

### OpenStreetMap Overpass API

The nearby-place feature calls:

```text
https://overpass-api.de/api/interpreter
```

The query searches within approximately 5 km of the user's location. It
requires internet access, location permission, and location services.

### Native phone and SMS

`url_launcher` opens:

- Phone dialer through `tel:`
- SMS composer through `sms:`

HerWay prepares the call or SMS, but the operating system performs the actual
action. The user must confirm and send the SMS manually.

### Device capabilities

HerWay integrates with:

- GPS through `geolocator`
- Bluetooth Low Energy through `flutter_blue_plus`
- Camera through `camera`
- Audio recording through `record`
- Audio playback through `just_audio` and `audioplayers`
- Local encrypted preferences through `flutter_secure_storage`
- Local files through `path_provider`
- Video playback through `video_player`

## 4. Main data flows

### SOS flow

```text
User taps SOS
      │
      ▼
5-second local countdown
      │
      ├── User cancels → stop countdown
      │
      ▼
Read current GPS location
      │
      ▼
Create CommunityDistressAlert locally
      │
      ├── Firebase available?
      │       │
      │       ├── Yes → write alert to Firestore
      │       └── No  → keep alert in local app state
      │
      ▼
Update UI through alertStream
```

The SOS countdown is local and does not need internet. Broadcasting the alert
to other HerWay users requires Firebase connectivity.

### Community helper flow

```text
Helper app starts
      │
      ▼
Authenticate with Firebase
      │
      ▼
Read nearby distress alerts from Firestore
      │
      ▼
Filter by distance and alert age
      │
      ▼
Show alert to helper
      │
      ▼
Helper accepts
      │
      ▼
Update Firestore alert status
      │
      ▼
Retrieve protected contact number
      │
      ▼
Open phone dialer
```

This requires internet for cross-device communication and phone service for
the final call.

### Check-in flow

```text
User selects duration
      │
      ▼
Start local Dart Timer
      │
      ├── User cancels → stop timer
      │
      └── Timer expires → show local escalation UI
```

The timer works offline because it is maintained locally in the app. Calling
or texting from the escalation screen depends on phone connectivity.

### Simulated-call flow

```text
User schedules simulated call
      │
      ▼
Local Timer waits for configured delay
      │
      ▼
Open simulated call screen
      │
      ▼
Configure iOS playback audio session
      │
      ▼
Play bundled ringtone asset
      │
      ├── Answer → stop ringtone and start call timer
      └── Decline/end → stop ringtone and close screen
```

The ringtone is packaged locally at
[`assets/audio/simulated_call_ringtone.wav`](assets/audio/simulated_call_ringtone.wav)
and declared in [`pubspec.yaml`](pubspec.yaml). This feature works without
internet.

### Recording flow

```text
User opens recorder
      │
      ▼
Request camera/microphone permission
      │
      ▼
Record audio or video
      │
      ▼
Move file to local HerWayRecordings directory
      │
      ▼
List and play recordings locally
```

Recordings are stored locally and are not automatically uploaded to Firebase.

## 5. Offline and online boundaries

| Feature | Offline | Internet/data | Phone service |
|---|---:|---:|---:|
| Dashboard | Yes | No | No |
| Check-in timer | Yes | No | No |
| Simulated call/ringtone | Yes | No | No |
| Local recordings | Yes | No | No |
| Trusted contacts | Yes | No | No |
| Ride details | Yes | No | No |
| Bluetooth scan | Yes | No | No |
| GPS location | Usually | No | No |
| Firebase login/sync | No | Yes | No |
| Community SOS broadcast | Local state only | Yes | No |
| Receive helper alerts | No | Yes | No |
| Nearby safe places | No | Yes | No |
| Phone call | No | Optional Wi-Fi calling | Yes |
| SMS | No | Optional Wi-Fi SMS | Yes |

The core emergency interaction is local-first, but community communication and
live location-based discovery depend on network connectivity.

## 6. Technical approach

### State management

The current implementation uses Flutter's built-in state management:

- `StatefulWidget`
- `setState`
- `Timer`
- `StreamSubscription`
- `StreamController`
- `StreamBuilder`

This keeps dependencies low and is suitable for the current prototype. The
main risk is that [`lib/main.dart`](lib/main.dart) is becoming large and
contains multiple independent feature states.

### Reactive communication

Services publish changes using Dart streams:

```text
Service event
    │
    ▼
StreamController
    │
    ▼
Widget subscription
    │
    ▼
setState()
    │
    ▼
Updated UI
```

This approach is used for Bluetooth scan results, Firebase community alerts,
battery state, Firebase authentication, and recording playback state.

### Local-first behavior

The app follows a partial local-first approach:

- Local alert state is created before remote synchronization.
- Local user details are stored in secure storage.
- Recordings are stored on-device.
- Check-in and simulated-call timers are local.
- Remote synchronization is attempted when Firebase is available.

The current implementation does not yet include a complete offline queue or
retry mechanism for failed Firestore writes.

### Privacy approach

Current privacy protections include:

- BLE identifiers are anonymized before being exposed to the UI.
- Contact phone numbers are stored in a Firestore private subcollection.
- Recordings stay in local application storage.
- Location is only added to distress alerts when available.
- SMS is user-reviewed rather than automatically sent.

## 7. Recommended production architecture

The current app can be evolved toward:

```text
lib/
  app/
    app.dart
    routes.dart
    theme.dart

  features/
    authentication/
    dashboard/
    safety_mode/
    check_in/
    simulated_call/
    recordings/
    nearby_places/
    bluetooth_follow/

  domain/
    models/
    repositories/
    use_cases/

  data/
    local/
      secure_storage.dart
      recording_storage.dart
      local_database.dart
    remote/
      firebase_auth_data_source.dart
      firestore_alert_data_source.dart
      nearby_places_api.dart

  platform/
    audio/
    phone/
    sms/
    location/
    bluetooth/

  shared/
    widgets/
    utilities/
```

Recommended responsibilities:

- **Widgets:** display state and capture user actions.
- **Controllers/ViewModels:** coordinate feature workflows.
- **Use cases:** implement actions such as `TriggerSos`, `StartCheckIn`,
  and `AcceptDistressAlert`.
- **Repositories:** hide Firebase, local storage, GPS, and API details.
- **Data sources:** directly communicate with Firebase, HTTP, or device APIs.
- **Models:** contain validated domain data and status values.

Example:

```text
SafetyModePage
      │
      ▼
SafetyModeController
      │
      ▼
TriggerSosUseCase
      │
      ├── LocationRepository
      ├── AlertRepository
      └── LocalSafetyStateRepository
```

This allows the UI to remain stable if Firebase is replaced or a local
database is added later.

## 8. Important production improvements

1. **Add an offline event queue**
   - Queue SOS and status updates locally.
   - Retry when connectivity returns.
   - Show whether an alert is local-only or successfully broadcast.

2. **Move state out of `main.dart`**
   - Extract check-in, simulated call, recordings, contacts, and rides into
     feature controllers.

3. **Use a local database**
   - Secure storage is useful for small values.
   - A local database would be better for contacts, ride history, alerts,
     check-ins, and queued actions.

4. **Improve background support**
   - Current Dart timers are reliable while the app is active.
   - Background check-in escalation requires iOS local notifications and
     background-safe scheduling.

5. **Add explicit connectivity state**
   - Display `Offline`, `Syncing`, and `Broadcasted` statuses.
   - Avoid implying that an SOS reached the community when only local state
     was created.

6. **Harden data access**
   - Validate all Firestore writes with security rules.
   - Limit alert visibility by age and geographic radius.
   - Ensure only authorized helpers can access private contact data.

7. **Add integration tests**
   - Offline SOS behavior
   - Firebase unavailable behavior
   - Audio playback on physical iOS devices
   - Bluetooth permission denial
   - Location permission denial
   - SMS/dialer unavailable scenarios

## Summary

HerWay currently uses a Flutter client with local device capabilities,
Firebase-based community coordination, and OpenStreetMap-based nearby-place
discovery. Its core emergency interaction remains local-first, while community
communication and live location-based discovery depend on internet connectivity.
