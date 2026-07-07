# Environment Setup & Run Guide

Everything needed to get **video_call_app** running on a fresh laptop, wire in
the LiveKit sandbox token, run it, and build the APK.

---

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| **Flutter SDK** | ≥ 3.27 (built on **3.41.6**) | includes Dart ≥ 3.6 (built on 3.11) |
| **Android SDK** | API 34/35, min API 23 | via Android Studio or `cmdline-tools` |
| **JDK** | 17 | bundled with recent Android Studio |
| **A device** | Android phone **or** emulator | a **physical device** is best (emulator camera is a synthetic feed) |
| **LiveKit Cloud account** | free | needed for the sandbox token server |

> iOS builds need a Mac + Xcode — not possible on Windows. This app is **Android-first**; the iOS config is written but unverified.

### Verify the toolchain
```bash
flutter --version
flutter doctor -v
```
Fix anything `flutter doctor` flags red. On Windows the two common ones:
```bash
flutter doctor --android-licenses   # accept all with 'y' — required to build
```
(Visual Studio is only needed for Windows desktop builds — ignore it for Android.)

---

## 2. Get the project onto the new laptop

If you copied the folder (not via git), **delete the stale build caches** first —
they contain absolute paths from the old machine:

```bash
# from inside the video_call_app folder
flutter clean
```

Then pull dependencies:
```bash
flutter pub get
```

> If `flutter pub get` fails with **"not enough space on the disk"**, free up a
> few GB — the pub cache + Gradle downloads need room. This actually happened
> during development.

---

## 3. Wire in the LiveKit sandbox token (the one required step)

The app never hardcodes credentials. It reads them at **runtime** via
`--dart-define`, resolved in `lib/features/call/data/datasources/token_service.dart`.

### Get a sandbox ID
1. Sign in at **https://cloud.livekit.io** (free).
2. Open your project → **Settings → Sandbox** → enable **Token server**.
3. Copy the sandbox ID — it looks like `token-server-abc123`.

That single ID is all you need. The app POSTs the room + participant name to
LiveKit's sandbox endpoint and gets back a `serverUrl` + `participantToken`.

### Two ways to supply it

**A) Sandbox ID (normal path — different identities per device):**
```bash
flutter run --dart-define=LIVEKIT_SANDBOX_ID=token-server-abc123
```

**B) A single hardcoded token (quick one-device smoke test only):**
Mint one in the LiveKit dashboard (or `lk token create`) and pass both:
```bash
flutter run --dart-define=LIVEKIT_URL=wss://<project>.livekit.cloud --dart-define=LIVEKIT_TOKEN=eyJhbGciOi...
```

> ⚠️ The sandbox token server is **development only** — any client can request a
> token with any permissions. For production you replace `SandboxTokenService`
> with one that calls **your own backend**, which signs tokens with the LiveKit
> API secret. The secret must never ship inside the app.

---

## 4. Run the app

```bash
# list connected devices
flutter devices

# run on the default device (pass your sandbox ID)
flutter run --dart-define=LIVEKIT_SANDBOX_ID=token-server-abc123

# run on a specific device id
flutter run -d <device_id> --dart-define=LIVEKIT_SANDBOX_ID=token-server-abc123
```

While running: press `r` = hot reload, `R` = hot restart, `q` = quit.

### Demo a real 2-way call with only one phone
Your phone runs the app; a browser plays the other participant:
1. Open **https://meet.livekit.io** → **Custom** tab.
2. Use the **same LiveKit project** and join the **same Room ID** you typed in the app.
3. The browser user shows up as the remote video on your phone.

---

## 5. Build the APK

```bash
# Debug APK (fast, for testing) — no signing setup needed
flutter build apk --debug

# Release APK — bake the sandbox ID in so the installed app is ready to demo
flutter build apk --release --dart-define=LIVEKIT_SANDBOX_ID=token-server-abc123
```

Output lands at:
```
build/app/outputs/flutter-apk/app-debug.apk
build/app/outputs/flutter-apk/app-release.apk
```
Copy that `.apk` to a phone and install it (enable "install from unknown sources").

> The release build currently signs with the **debug keystore** (from the Flutter
> template) so it builds out of the box. For a real Play Store release you'd add
> your own keystore and use an **app bundle**: `flutter build appbundle --release`.

---

## 6. Quality checks (run these before you hand it in)

```bash
flutter analyze        # static analysis — should say "No issues found!"
flutter test           # unit + widget tests — should say "All tests passed!" (21 tests)
```

---

## 7. Command cheat-sheet

| Goal | Command |
|------|---------|
| Install deps | `flutter pub get` |
| Clean stale build | `flutter clean` |
| Check toolchain | `flutter doctor -v` |
| Accept Android licenses | `flutter doctor --android-licenses` |
| List devices | `flutter devices` |
| Run (with token) | `flutter run --dart-define=LIVEKIT_SANDBOX_ID=<id>` |
| Analyze | `flutter analyze` |
| Test | `flutter test` |
| Debug APK | `flutter build apk --debug` |
| Release APK (with token) | `flutter build apk --release --dart-define=LIVEKIT_SANDBOX_ID=<id>` |
| App bundle (Play Store) | `flutter build appbundle --release` |

---

## 8. Project structure (quick map)

```
lib/
├── main.dart / app.dart          # bootstrap, routes, theme, portrait lock
├── core/
│   ├── di/injection.dart         # get_it dependency registration
│   ├── error/failures.dart       # typed Failure hierarchy
│   ├── permissions/              # camera/mic permission service
│   └── theme/app_theme.dart      # design tokens + ThemeData
└── features/call/
    ├── domain/                   # entities, CallRepository, use cases (SDK-free)
    ├── data/                     # LiveKitRoomDataSource, TokenService, mappers
    └── presentation/             # JoinBloc, CallBloc, pages, widgets
test/                             # bloc tests + Join screen widget tests
```

---

## 9. Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| `flutter pub get` → "not enough space on the disk" | Free a few GB for the pub/Gradle caches. |
| "Android license status unknown" | `flutter doctor --android-licenses`, accept all. |
| First `flutter build`/`run` takes minutes | Gradle downloads the toolchain once (~5–8 min), then it's cached. |
| Black video on emulator | Emulator has no real camera. Test on a **physical device**. |
| "LiveKit is not configured" error on Join | You didn't pass `--dart-define=LIVEKIT_SANDBOX_ID=...`. |
| Release build can't connect but debug works | Ensure `INTERNET` permission is in `AndroidManifest.xml` (it is here) — the Flutter default only adds it to debug/profile. |
| Two users disconnect each other | They used the same name → same identity. The app already appends a random suffix, so update if you changed that logic. |
| Local `livekit-server --dev` (ws://) won't connect on Android | Non-TLS needs `android:usesCleartextTraffic="true"`; prefer LiveKit Cloud (`wss://`). |
