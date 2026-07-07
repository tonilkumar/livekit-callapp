# video_call_app

Basic 1:1 video/audio call app built on [LiveKit](https://livekit.io), with
Clean Architecture + MVVM and BLoC state management.

- **Join screen** — Room ID + Your Name → Join Call
- **Call screen** — remote video full-screen, local preview PiP, controls:
  mic mute/unmute · camera on/off · leave

## Requirements

- Flutter ≥ 3.27 (built with 3.41.6)
- Android device (minSdk 23). iOS config is present but unverified (needs a Mac).
- A LiveKit Cloud **Sandbox Token Server** ID (dev only)

## Run (dev)

1. In the [LiveKit Cloud dashboard](https://cloud.livekit.io) enable
   **Sandbox → Token server** and copy the sandbox ID (looks like
   `token-server-xxxxxx`).
2. Run on a **physical Android device** (the emulator has no real camera):

```sh
flutter run --dart-define=LIVEKIT_SANDBOX_ID=token-server-xxxxxx
```

Single-device smoke test without a sandbox (paste a manually minted token):

```sh
flutter run --dart-define=LIVEKIT_URL=wss://<project>.livekit.cloud --dart-define=LIVEKIT_TOKEN=eyJ...
```

To test two-way video with one phone, join the same room from
[LiveKit Meet](https://meet.livekit.io) (Custom tab) using the same LiveKit
project.

⚠️ The sandbox token server is **dev-only** — any client can mint any token
with it. Production must mint tokens on your own backend
(swap `SandboxTokenService` for an endpoint-backed `TokenService`); the
LiveKit API secret never ships in the app.

## Architecture

```
lib/
├── main.dart / app.dart          # bootstrap, routes, theme, portrait lock
├── core/                         # DI (get_it), failures, permission service
└── features/call/
    ├── domain/                   # entities, CallRepository, use cases — SDK-free
    ├── data/                     # LiveKitRoomDataSource, TokenService, mappers
    └── presentation/             # JoinBloc, CallBloc, pages, widgets
```

- **BLoC = ViewModel.** Views dispatch events and rebuild from state; blocs call
  use cases; the data layer converts LiveKit room events into two domain
  streams (connection status + participant snapshots).
- The domain layer never imports `livekit_client`. The single deliberate
  exception is `presentation/widgets/livekit_video_view.dart`, which downcasts
  the opaque `VideoTrackRef` back to the SDK track for `VideoTrackRenderer`.
- Do **not** add `flutter_webrtc` to pubspec — `livekit_client` pins it
  transitively.

## Tests

```sh
flutter analyze
flutter test
```

18 bloc tests cover the join validation/permission flow and the call lifecycle
(connect, participant snapshots, toggles, leave, error paths).

Manual device checklist: join → leave → rejoin ×3 (camera LED must turn off
after leave), permission deny + permanently-deny paths, airplane mode
mid-call (reconnecting banner → call ends), both users muted (avatar +
mic-off badges).

## v1 limitations (deliberate)

Backgrounding may drop the call (no foreground service yet) · only the first
remote is rendered · portrait-locked · no camera flip, token refresh,
audio-route picker, or screen share.
