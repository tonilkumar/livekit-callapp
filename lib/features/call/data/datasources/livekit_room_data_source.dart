import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../../core/error/failures.dart';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/participant.dart';
import '../mappers/participant_mapper.dart';

/// Owns the LiveKit [lk.Room] and translates its events into two clean domain
/// streams. Exactly one live room at a time; a fresh Room per connect.
class LiveKitRoomDataSource {
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _participantsController =
      StreamController<List<Participant>>.broadcast();

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  ConnectionStatus? _lastStatus;
  List<Participant>? _lastParticipants;

  /// Bumped by [beginSession] and [disconnect]. A connect attempt captures its
  /// session id and aborts if it stops matching. This is what stops a leave
  /// during the token fetch or handshake from resuming into a live room with a
  /// hot camera and microphone that nobody is watching.
  int _session = 0;

  /// Replays the latest value so a subscriber attaching just after connect
  /// doesn't miss the current state. A terminal status is never replayed — the
  /// next call's bloc must not be told the PREVIOUS call ended.
  Stream<ConnectionStatus> watchConnectionStatus() async* {
    final last = _lastStatus;
    if (last != null && !_isTerminal(last)) yield last;
    yield* _statusController.stream;
  }

  Stream<List<Participant>> watchParticipants() async* {
    final last = _lastParticipants;
    if (last != null) yield last;
    yield* _participantsController.stream;
  }

  /// Opens a new connect session, tearing down anything left over, and returns
  /// the session id to hand back to [connect].
  Future<int> beginSession() async {
    await _disposeRoom(pushStatus: false);
    _lastStatus = null;
    _lastParticipants = null;
    return ++_session;
  }

  Future<void> connect(int session, String url, String token) async {
    // A leave during the token fetch already invalidated this session.
    if (session != _session) return;

    _pushStatus(ConnectionStatus.connecting);
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
    );
    _room = room;
    final listener = room.createListener();
    _listener = listener;
    _wireEvents(listener);

    try {
      await room.connect(url, token).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      if (session == _session) await disconnect();
      throw const ConnectionFailure(
        'Connecting to the room timed out. Check your network and try again.',
      );
    } catch (error) {
      if (session == _session) await disconnect();
      throw ConnectionFailure('Could not join the room: ${_shortError(error)}');
    }

    // A leave during the handshake invalidates the session; the disconnect that
    // did so has already torn this room down, so just stop.
    if (session != _session) return;

    await room.localParticipant?.setCameraEnabled(true);
    await room.localParticipant?.setMicrophoneEnabled(true);
    await _preferSpeakerOutput();

    if (session != _session) return; // left while enabling tracks

    _pushStatus(ConnectionStatus.connected);
    _pushParticipants();
  }

  /// Idempotent: the CallBloc's close() calls this again as a safety net
  /// after an explicit leave.
  Future<void> disconnect() async {
    _session++; // invalidate any in-flight connect
    await _disposeRoom(pushStatus: true);
    // Don't leave a terminal status cached to replay into the next session.
    _lastStatus = null;
  }

  Future<void> _disposeRoom({required bool pushStatus}) async {
    final room = _room;
    final listener = _listener;
    _room = null;
    _listener = null;

    // Listener first: teardown events must not echo back into the streams.
    if (listener != null) {
      await listener.dispose();
    }
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {
        // Best effort — dispose below still releases native resources.
      }
      await room.dispose();
      _lastParticipants = null;
      if (pushStatus) _pushStatus(ConnectionStatus.disconnected);
    }
  }

  Future<bool> setMicrophoneEnabled(bool enabled) async {
    final local = _room?.localParticipant;
    if (local == null) return false;
    await local.setMicrophoneEnabled(enabled);
    _pushParticipants();
    return enabled;
  }

  Future<bool> setCameraEnabled(bool enabled) async {
    final local = _room?.localParticipant;
    if (local == null) return false;
    await local.setCameraEnabled(enabled);
    _pushParticipants();
    return enabled;
  }

  void _wireEvents(lk.EventsListener<lk.RoomEvent> listener) {
    listener
      ..on<lk.ParticipantConnectedEvent>((_) => _pushParticipants())
      ..on<lk.ParticipantDisconnectedEvent>((_) => _pushParticipants())
      ..on<lk.TrackSubscribedEvent>((_) => _pushParticipants())
      ..on<lk.TrackUnsubscribedEvent>((_) => _pushParticipants())
      ..on<lk.TrackMutedEvent>((_) => _pushParticipants())
      ..on<lk.TrackUnmutedEvent>((_) => _pushParticipants())
      ..on<lk.LocalTrackPublishedEvent>((_) => _pushParticipants())
      ..on<lk.LocalTrackUnpublishedEvent>((_) => _pushParticipants())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _pushParticipants())
      ..on<lk.RoomReconnectingEvent>(
          (_) => _pushStatus(ConnectionStatus.reconnecting))
      ..on<lk.RoomReconnectedEvent>((_) {
        _pushStatus(ConnectionStatus.connected);
        _pushParticipants();
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        if (event.reason == lk.DisconnectReason.clientInitiated) {
          _pushStatus(ConnectionStatus.disconnected);
        } else {
          _pushStatus(ConnectionStatus.failed);
        }
      });
  }

  Future<void> _preferSpeakerOutput() async {
    // Communication audio mode defaults to the earpiece on phones, which
    // users read as "no sound" — prefer the loudspeaker for a video call.
    try {
      await lk.Hardware.instance.setSpeakerphoneOn(true);
    } catch (_) {
      // Non-fatal: keep the platform's default route.
    }
  }

  void _pushStatus(ConnectionStatus status) {
    _lastStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _pushParticipants() {
    final room = _room;
    if (room == null) return;
    final local = room.localParticipant;
    final snapshot = <Participant>[
      if (local != null) ParticipantMapper.map(local, isLocal: true),
      ...room.remoteParticipants.values
          .map((p) => ParticipantMapper.map(p, isLocal: false)),
    ];
    _lastParticipants = snapshot;
    if (!_participantsController.isClosed) {
      _participantsController.add(snapshot);
    }
  }

  String _shortError(Object error) {
    final text = error.toString();
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  bool _isTerminal(ConnectionStatus status) =>
      status == ConnectionStatus.disconnected ||
      status == ConnectionStatus.failed;
}
