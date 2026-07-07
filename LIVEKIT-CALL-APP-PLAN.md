# Basic Video Call App — Development Plan (LiveKit + Flutter)

> Plan date: 2026-07-06. SDK facts verified live against pub.dev / LiveKit docs / GitHub on this date.
> Brand-new standalone Flutter project. Clean Architecture + MVVM, BLoC state management.

---

## 1. Scope

**Join Screen** — Room ID field, User Name field, "Join Call" button.
**Call Screen** — local video (small mirrored PiP tile), remote video (full screen), controls: mic mute/unmute, camera on/off, leave call.
**v1 is a 1:1 call app** (one remote rendered).

---

## 2. Tech stack (verified 2026-07-06)

| Package | Version | Notes |
|---|---|---|
| Flutter / Dart | ≥ 3.27 / ≥ 3.6 | required by livekit_client 2.8.x |
| `livekit_client` | `^2.8.1` | official LiveKit Flutter SDK; pins `flutter_webrtc` 1.5.2 transitively — **do NOT add flutter_webrtc yourself** |
| `flutter_bloc` / `bloc` | `^9.1.1` / `^9.0.0` | state management |
| `equatable` | latest | value equality for states/entities |
| `get_it` | latest | DI (manual registration) |
| `permission_handler` | latest | camera/mic runtime permissions |
| dev: `bloc_test`, `mocktail`, `flutter_lints` | latest | tests + lints |

Platform floors: **Android minSdk 23**, **iOS 13.0** (SDK min is 12.1; we standardize on 13.0).

---

## 3. Key decision: where tokens come from

LiveKit connects with a **`wss://` server URL + JWT access token** — but our UI only collects Room ID + User Name. Token minting is a data-layer concern, invisible to domain/UI.

**DEV (v1):** LiveKit Cloud free tier + **Sandbox Token Server** (enable in LiveKit Cloud dashboard → get a sandbox ID like `token-server-xxxxxx`). The SDK wraps it as `SandboxTokenSource(sandboxId)`; raw endpoint is `POST https://cloud-api.livekit.io/api/sandbox/connection-details` → `{ serverUrl, participantToken }`. Tokens have ~15-min TTL (fine — LiveKit keeps live sessions alive past token expiry; refresh is only needed for reconnect-after-drop, descoped).

**PROD (later):** your own backend endpoint mints tokens with `LIVEKIT_API_KEY/SECRET`. Swap = one new `TokenService` implementation. **Never mint tokens inside the app** — that means shipping the API secret.

Config injection: `SANDBOX_ID` (and optional `LIVEKIT_URL`) via `--dart-define`, read in `DevTokenService`. No hardcoded secrets.

Fallback if no LiveKit Cloud account is wanted: `livekit-server --dev` in Docker locally (`ws://<LAN-IP>:7880`, key `devkey`/`secret`) — requires `android:usesCleartextTraffic="true"` for the non-TLS ws:// URL. Recommended path is LiveKit Cloud (wss, no cleartext hack).

**Identity collision gotcha:** two participants with the same identity → LiveKit kicks the first. `TokenService` mints identity as `userName-<4 random chars>`, passes `userName` as display name.

---

## 4. Architecture

| Clean layer | MVVM role | Contents | Depends on |
|---|---|---|---|
| Presentation | View + **ViewModel (= BLoC)** | pages, widgets, `JoinBloc`, `CallBloc` | domain only |
| Domain | Model (business) | entities, `CallRepository` (abstract), use cases — **pure Dart, zero SDK imports** | nothing |
| Data | Model (infra) | `LiveKitRoomDataSource` (SDK wrapper), `TokenService`, repository impl, mappers | domain + livekit_client |

**One deliberate boundary exception:** LiveKit's `VideoTrackRenderer` needs the SDK's `VideoTrack` in the widget tree. Domain defines opaque `abstract class VideoTrackRef {}`; data implements `LiveKitVideoTrackRef(track)`; exactly **one** widget (`LiveKitVideoView`) imports both livekit_client and domain to downcast and render. Everything else stays SDK-free and testable.

### Folder structure

```
lib/
├── main.dart                     # configureDependencies() + portrait lock + runApp
├── app.dart                      # MaterialApp, onGenerateRoute
├── core/
│   ├── di/injection.dart         # get_it manual registration
│   ├── error/failures.dart       # sealed Failure: PermissionFailure / ConnectionFailure / UnknownFailure
│   └── permissions/permission_service.dart
└── features/call/
    ├── domain/
    │   ├── entities/            # connection_params, connection_status, participant, video_track_ref
    │   ├── repositories/call_repository.dart
    │   └── usecases/            # connect_to_room, leave_room, toggle_microphone,
    │                            # toggle_camera, watch_connection_status, watch_participants
    ├── data/
    │   ├── datasources/         # livekit_room_data_source.dart, token_service.dart (+ DevTokenService)
    │   ├── mappers/participant_mapper.dart
    │   └── repositories/livekit_call_repository.dart
    └── presentation/
        ├── blocs/join/          # join_bloc / join_event / join_state
        ├── blocs/call/          # call_bloc / call_event / call_state
        ├── pages/               # join_page.dart, call_page.dart
        └── widgets/             # participant_video_tile, call_control_bar, livekit_video_view
```

---

## 5. Domain layer

```dart
class ConnectionParams extends Equatable {
  final String roomId;    // trimmed + lowercased by JoinBloc
  final String userName;  // trimmed
}

enum ConnectionStatus { connecting, connected, reconnecting, disconnected, failed }

abstract class VideoTrackRef {}   // opaque; implemented in data layer

class Participant extends Equatable {
  final String sid;
  final String identity;          // display name
  final bool isLocal;
  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isSpeaking;
  final VideoTrackRef? videoTrack;   // null => placeholder avatar
}

abstract class CallRepository {
  Future<void> connect(ConnectionParams params);   // resolves token internally
  Future<void> disconnect();                        // idempotent
  Future<bool> setMicrophoneEnabled(bool enabled);  // returns applied value
  Future<bool> setCameraEnabled(bool enabled);
  Stream<ConnectionStatus> watchConnectionStatus();
  Stream<List<Participant>> watchParticipants();    // full snapshot per event; replays last on subscribe
}
```

Use cases (thin callables): `ConnectToRoom`, `LeaveRoom`, `ToggleMicrophone`, `ToggleCamera`, `WatchConnectionStatus`, `WatchParticipants`. (The two Watch* are pass-throughs — kept knowingly so BLoCs never import the repository.)

## 6. Data layer

`LiveKitRoomDataSource` owns the `Room` + `EventsListener`:

```dart
_room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
_listener = _room!.createListener();
_wireEvents();
await _room!.connect(url, token).timeout(const Duration(seconds: 15));
await _room!.localParticipant?.setCameraEnabled(true);
await _room!.localParticipant?.setMicrophoneEnabled(true);
// default to speakerphone (2.8.x API — verify exact name at build):
await AudioManager.instance.setSpeakerOutputPreferred(true);
```

**LiveKit event → domain stream mapping** (each row re-emits a fresh participant snapshot and/or status):

| RoomEvent | Effect |
|---|---|
| ParticipantConnected / Disconnected | push participants |
| TrackSubscribed / Unsubscribed | push participants |
| TrackMuted / Unmuted, LocalTrackPublished / Unpublished | push participants |
| ActiveSpeakersChanged | push participants (isSpeaking) |
| RoomReconnecting / Reconnected | status → reconnecting / connected |
| RoomDisconnected | status → disconnected (or failed if reason is an error) |

Rules baked in:
- **Disposal (the classic rejoin leak):** `disconnect()` must `await room.disconnect(); await listener.dispose(); await room.dispose();` — idempotent (CallBloc.close() calls it again as a safety net).
- **Snapshot replay:** cache the last participants snapshot; re-emit to late subscribers (broadcast controllers don't replay).
- **Mapper track selection:** first subscribed, non-muted publication with `source == TrackSource.camera` (ignore screen share).
- **Error mapping:** repository catches SDK exceptions → 3 `Failure` types → 3 user-facing messages max (permissions / network-server / unknown).

`TokenService` (abstract) + `DevTokenService` (sandbox token server via `--dart-define` config, identity suffixing).

## 7. Presentation layer

### JoinBloc
Events: `JoinRoomIdChanged`, `JoinUserNameChanged`, `JoinSubmitted`, `JoinReset`.
State: `roomId`, `userName`, `status ∈ {initial, requestingPermissions, ready, permissionDenied, failure}`, `errorMessage`, `isValid`.

Flow on submit: validate (trim; non-empty; maxLength 64; room ID lowercased + `[a-z0-9-_]` only) → request camera + mic (+ `bluetoothConnect` on Android 12+, non-blocking if denied) → both granted ⇒ `ready`; `permanentlyDenied` ⇒ dialog with "Open Settings" (`openAppSettings()`), never re-request loop. Page `BlocListener`: on `ready` → `pushNamed('/call', arguments: params)` then dispatch `JoinReset`. Join button disabled while invalid or in-flight (kills double-tap double-connect).

### CallBloc
Events: `CallStarted(params)`, `CallMicToggled`, `CallCameraToggled`, `CallLeaveRequested`, internal `_ConnectionStatusChanged`, `_ParticipantsUpdated`.
State: `status ∈ {initial, connecting, connected, reconnecting, error, ended}`, `localParticipant`, `remoteParticipants`, `isMicEnabled`, `isCameraEnabled`, `errorMessage`.

- `CallStarted`: emit connecting → subscribe both repository streams (subscription + internal-event pattern) → `await connect()`; failure ⇒ `error`.
- Status mapping: disconnected → `ended`, failed → `error` (distinguish user-initiated leave from drops via disconnect reason).
- `_ParticipantsUpdated`: split into local + remotes; sync `isMicEnabled/isCameraEnabled` from the local participant (single source of truth).
- Toggles: `await toggleMic(!state.isMicEnabled)`; emit the **applied** value returned.
- `close()`: cancel subs, `await leaveRoom()` — guarantees teardown even on system back gesture.

### Screens
- **JoinPage**: form + validation errors + loading state.
- **CallPage**: `BlocProvider(create: (_) => sl<CallBloc>()..add(CallStarted(params)))`; `BlocListener` — `ended` → pop; `error` → snackbar + pop. `PopScope` intercepts Android back → same leave flow as the button (never silent-pop a hot room). Leave button shows a small confirm dialog.

```
Stack
├── remote area: 0 remotes → "Waiting for others…"  |  ≥1 → full-screen tile (FIRST remote only, v1)
├── Positioned top-right: local preview (mirrored, small)
├── if reconnecting → "Reconnecting…" banner overlay
└── bottom: CallControlBar  [mic] [camera] [red hang-up]
```

`ParticipantVideoTile`: video if `videoTrack != null && isCameraEnabled`, else initials avatar; name label + mic-muted badge + speaking highlight. `LiveKitVideoView` = the single SDK-aware widget wrapping `VideoTrackRenderer`.

Portrait locked in `main()` (`SystemChrome.setPreferredOrientations`).

---

## 8. Platform configuration

### Android (`android/app/`)
- `build.gradle(.kts)`: `minSdk = 23`; Java 8 `compileOptions`; release build wires flutter_webrtc ProGuard rules (`-keep class org.webrtc.** { *; }`).
- `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />   <!-- main manifest lacks it; release builds fail without -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

### iOS (config written, **unverified** — dev machine is Windows; Android-first)
- `Podfile`: `platform :ios, '13.0'`; post_install adds `ONLY_ACTIVE_ARCH = YES` + permission_handler macros (`PERMISSION_CAMERA=1`, `PERMISSION_MICROPHONE=1`).
- `Info.plist`: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `UIBackgroundModes: [audio]`.

---

## 9. Edge-case decisions (v1) & descope list

Handled in v1: permission denial (soft + permanent), connect failure/timeout with typed errors, reconnecting banner, remote-not-yet-joined placeholder, remote leaves (revert to placeholder, stay in room), track-not-subscribed placeholder, mute badges both sides, identity collision suffix, back-button interception, join→leave→rejoin leak-free teardown, double-tap guard, camera-in-use publish error, room ID normalization, emulator-camera note (test on physical device).

**Explicitly OUT of v1** (documented limitations): background calls / Android foreground service (call drops when app is backgrounded — top of v1.1 list along with front/back camera switch), audio-only fallback when camera denied, token refresh, >1 remote UI (first remote only), screen rotation, audio route picker / Bluetooth handling, GSM interruption, state restoration after process death, screen share, chat.

---

## 10. Build order (milestones, each with a verification gate)

- **M0 — Prerequisites**: `flutter --version` ≥ 3.27; LiveKit Cloud account + Sandbox Token Server enabled (need sandbox ID) — or local `livekit-server --dev` via Docker.
- **M1 — Scaffold**: `flutter create --org com.example --platforms android,ios video_call_app`; pubspec deps; Android/iOS config from §8; DI skeleton; portrait lock. *Gate: builds and runs blank on device.*
- **M2 — Domain layer**: entities, repository interface, use cases (pure Dart). *Gate: `flutter analyze` clean.*
- **M3 — Data layer**: `DevTokenService`, `LiveKitRoomDataSource` (events, timeout, disposal, snapshot cache), repository impl, mappers. *Gate: analyze clean; token fetch smoke-tested.*
- **M4 — Join screen**: JoinBloc + form + permission flow. *Gate: validation + deny/permanently-deny paths work on device.*
- **M5 — Call screen (happy path)**: connect, local PiP + remote rendering. *Gate: two-way video — second participant via LiveKit Meet sample (meet.livekit.io custom tab) or a second device.*
- **M6 — Controls + edge cases**: mic/cam toggles synced to state, leave flow + PopScope + confirm, error mapping, reconnect banner, waiting placeholder.
- **M7 — Verification**: `flutter analyze` clean; `bloc_test` suites for JoinBloc + CallBloc (mocked repository via mocktail); manual matrix on physical Android — join→leave→rejoin ×3 (leak check: camera LED off after leave), permission-deny paths, airplane-mode mid-call (banner → ended), both-muted display.

---

## 11. Needed before M0/M1 kickoff

1. **Project location/name** — proposal: `video_call_app/` created under this directory (or specify another path).
2. **LiveKit Cloud** — existing account? If yes: enable Sandbox Token Server, provide the sandbox ID (safe to share; dev-only). If no: 2-minute free signup, or fall back to local Docker `livekit-server --dev`.
3. **Confirm v1 descopes** — especially background-call support (foreground service) being out of v1.
