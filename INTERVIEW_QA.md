# Interview Q&A — video_call_app

Likely questions for this LiveKit + Flutter take-home, with answers grounded in
the actual code. Read these once and you can defend every decision.

---

## 30-second pitch (say this first if asked "walk me through it")

> It's a 1:1 video calling app on **LiveKit**. You enter a Room ID and name, it
> requests camera/mic permission, fetches a token, and connects. The call screen
> shows the remote participant full-screen with your own preview as a draggable
> picture-in-picture, plus mic, camera, and leave controls. It's built in
> **Clean Architecture** with **MVVM**, where **BLoC is the ViewModel**, and the
> domain layer has zero LiveKit imports so the business logic is fully testable
> and the SDK is swappable.

---

## A. Architecture

**Q: Explain your architecture.**
Three layers, dependencies point inward:
- **domain** — entities (`Participant`, `ConnectionParams`, `ConnectionStatus`), an abstract `CallRepository`, and use cases. Pure Dart, no Flutter, no LiveKit.
- **data** — `LiveKitRoomDataSource` (wraps the SDK), `TokenService`, `ParticipantMapper`, and `LiveKitCallRepository` implementing the domain contract.
- **presentation** — `JoinBloc`/`CallBloc` (ViewModels), pages, and widgets.

**Q: How does MVVM map onto that?**
The **View** (pages/widgets) dispatches events and rebuilds from state. The
**ViewModel** is the BLoC — it holds UI state and calls use cases, but never
touches the SDK. The **Model** is the domain + data layers.

**Q: What's the dependency rule and why does it matter?**
Domain depends on nothing; data and presentation depend on domain. The domain
never imports `livekit_client`. Benefit: I can unit-test all logic with a fake
repository, and swapping LiveKit for another SDK only touches the data layer.

**Q: You said "no SDK in domain" — but video rendering needs the SDK object. How?**
One deliberate, documented exception. Domain exposes an **opaque**
`abstract class VideoTrackRef`. The data layer implements it wrapping LiveKit's
`VideoTrack`. Exactly **one** widget — `LiveKitVideoView` — is allowed to import
both, downcast, and render `VideoTrackRenderer`. Every other widget and BLoC
stays SDK-free.

**Q: Why use cases if they just call the repository?**
They keep the BLoC from importing the repository directly, give each action a
single-responsibility name, and are trivial to mock in tests. It's a small app
so they're thin — I kept them knowingly for consistency and testability.

---

## B. State management (BLoC)

**Q: Why BLoC over setState / Provider / Riverpod?**
The task asked for BLoC, and it fits: a call is an explicit **state machine**
(`connecting → connected → reconnecting → ended/error`) driven by asynchronous
SDK events. BLoC's event-in / state-out model captures that cleanly and is
deterministically testable with `bloc_test`.

**Q: How do LiveKit's events get into the bloc?**
The data source converts the SDK's event stream into two clean domain streams —
a `ConnectionStatus` stream and a `List<Participant>` snapshot stream. In
`CallBloc`, I subscribe to both and bridge each emission back in as an **internal
event** (`_ConnectionStatusChanged`, `_ParticipantsUpdated`), so every state
change flows through one place. Two streams of different types → the
subscription-plus-internal-event pattern is cleaner than `emit.forEach`.

**Q: Why is JoinBloc separate from CallBloc?**
Separation of concerns. `JoinBloc` owns the form + permission gate and does
**not** connect. `CallBloc` owns the entire connection lifecycle. That keeps each
small and lets the call screen fully own teardown.

**Q: How do you avoid the mic/camera buttons lying about their state?**
The buttons read `isMicEnabled`/`isCameraEnabled` from state, and I sync those
from the **local participant in the latest snapshot** — the SDK's published
tracks are the single source of truth, not optimistic UI.

---

## C. LiveKit / real-time

**Q: How does connecting work?**
`Room.connect(url, token)` needs a `wss://` URL and a JWT. The UI only collects
Room ID + name, so the data layer resolves the token first (`TokenService`),
then connects, then enables camera + mic, and prefers the loudspeaker.

**Q: Why not generate the token inside the app?**
Minting a token requires the LiveKit **API secret**. Shipping that in the app
lets anyone extract it and mint tokens with any permissions. So tokens come from
outside: a **sandbox token server** in dev, **your backend** in production. The
app only ever receives a short-lived token.

**Q: What's `adaptiveStream` and `dynacast`?**
Bandwidth optimizations I enabled in `RoomOptions`. Adaptive stream requests
lower video resolution when a tile is small/hidden; dynacast stops sending layers
no one is subscribed to. Free efficiency for a real call.

**Q: How do you pick which video track to show?**
`ParticipantMapper` selects the first **subscribed, unmuted** publication whose
source is `camera` (screen-share is explicitly ignored). If there's none, the UI
renders an initials avatar instead of a black tile.

**Q: It's "1:1" — what if a third person joins?**
v1 renders the **first** remote by join time and documents the limitation. The
data still tracks everyone; it's purely a UI scope choice. Multi-party grid is a
v2 item.

---

## D. Security

**Q: Walk me through the token security model.**
Dev uses LiveKit's sandbox token server — convenient but unrestricted, so it's
**dev-only**. Production swaps in a `TokenService` that calls my backend, which
authenticates the user and signs a token (scoped to that room, short TTL) with
the API secret server-side. The client only holds the resulting JWT; the secret
never leaves the server.

**Q: Where do credentials live in the app?**
Nowhere hardcoded. The sandbox ID / URL come in via `--dart-define` at build
time, read in `SandboxTokenService`. No secrets in source control.

---

## E. Lifecycle & edge cases (this is where you stand out)

**Q: When do you request permissions?**
On the **Join tap**, before navigating — not on app launch, not after connecting.
If denied, I block navigation and show an inline error; if *permanently* denied,
I show a dialog with an "Open Settings" deep link instead of re-prompting.

**Q: How do you handle a mid-call network drop?**
I listen for LiveKit's reconnecting/reconnected/disconnected events. Reconnecting
shows a non-blocking pill; a genuine failure maps to an error state, surfaces a
message, and returns to the join screen. I distinguish a **user-initiated** leave
from a dropped connection via the disconnect reason.

**Q: How do you prevent resource leaks?**
Teardown is deterministic and idempotent: `disconnect()` disposes the events
listener, then disconnects and disposes the room. `CallBloc.close()` cancels both
stream subscriptions and calls leave again as a safety net — so even a system
back-gesture can't leave the camera hot. I specifically tested the
join → leave → **rejoin** loop, which is the classic leak reproducer.

**Q: (Strong answer) Tell me about a real bug you caught.**
I ran an adversarial review and found four:
1. **Rejoin bounce** — the data source is a singleton and cached a terminal
   `disconnected` status that replayed into the *next* call, instantly ending it.
   Fixed with a session-generation counter and by never replaying terminal
   statuses.
2. **Hot camera on cancel** — leaving during the token fetch left an ownerless
   connected room with the camera/mic live. Fixed by threading a session id
   through and aborting the connect if it was invalidated.
3. **Black-screen on leave** — a terminal event while the "Leave?" dialog was
   open popped the *dialog* instead of the page. Fixed with an idempotent
   `popUntil(isFirst)`.
4. **Silent re-validation** — resubmitting the same invalid Room ID was swallowed
   by equal-state dedupe; fixed by resetting status before re-validating.

*(Talking about bugs you found and fixed is one of the most impressive things you
can do in an interview — it shows you test your own work.)*

**Q: Why intercept the Android back button?**
A raw back-pop would remove the screen without tearing down the room. `PopScope`
routes back through the same leave flow as the button, so the room always closes
cleanly.

---

## F. Testing

**Q: What did you test and how?**
21 tests. `bloc_test` + `mocktail` cover both BLoCs with a mocked repository:
Join validation/permission paths, and the Call lifecycle — connect, participant
splitting/sorting, toggle-applies-returned-value, leave, and error mapping. Plus
two widget smoke tests that actually build the redesigned Join screen and verify
the CTA gating. Gate: `flutter analyze` clean + all tests green + a manual
device pass.

**Q: Why mock the repository instead of LiveKit?**
Because the domain boundary is an abstract `CallRepository` — mocking it tests my
logic without the SDK, network, or a device. That's the payoff of the clean
boundary.

---

## G. Trade-offs & scope

**Q: What did you deliberately leave out, and why?**
Documented v1 descopes: background calls (needs an Android foreground service),
audio-only fallback, token refresh, multi-party UI, rotation (portrait-locked),
an audio-route picker, and screen share. Each is a known extension point, not an
oversight — I scoped to a solid, correct 1:1 call.

**Q: How would you take this to production?**
Swap the sandbox `TokenService` for a backend endpoint; add a foreground service
for background calls; add token refresh for long calls; multi-party grid UI;
proper release signing + app bundle; crash/analytics; and a CI pipeline running
`analyze` + `test` + build.

**Q: What was the hardest part?**
The connection **lifecycle races** — making connect cancellable and teardown
idempotent so the camera never stays live and rejoin always works. That's the
part I'd point a reviewer at.

**Q: What would you improve with more time?**
A draggable-PiP snap-to-corner animation, a light theme, an app launcher icon, an
in-call participant list for multi-party, and golden tests for the call screen.

---

## H. Rapid-fire facts (know these cold)

- **Packages:** `livekit_client ^2.8.1`, `flutter_bloc ^9.1.1`, `get_it`, `equatable`, `permission_handler`, `http`.
- **Don't add `flutter_webrtc` directly** — LiveKit pins it transitively; a version clash breaks the native build.
- **Android minSdk 23** — required by WebRTC.
- **`INTERNET` permission** must be in the main manifest — Flutter only adds it to debug/profile, so release builds would fail to connect without it.
- **Identity vs display name** — identity gets a random suffix so two people with the same name don't kick each other; the UI strips the suffix.
- **DI:** `get_it` — the data source is a lazy singleton (one call at a time), BLoCs are factories (fresh per screen).
- **Navigation:** plain `Navigator` with `onGenerateRoute` — no router package needed for two screens.
