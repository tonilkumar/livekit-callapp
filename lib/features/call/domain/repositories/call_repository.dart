import '../entities/connection_params.dart';
import '../entities/connection_status.dart';
import '../entities/participant.dart';

abstract class CallRepository {
  /// Resolves an access token for [params], connects to the room and
  /// publishes camera + microphone. Throws a `Failure` on error.
  Future<void> connect(ConnectionParams params);

  /// Tears the room down. Safe to call more than once.
  Future<void> disconnect();

  /// Returns the value actually applied by the SDK.
  Future<bool> setMicrophoneEnabled(bool enabled);

  /// Returns the value actually applied by the SDK.
  Future<bool> setCameraEnabled(bool enabled);

  /// Emits on every connection state change. Replays the latest value to new
  /// subscribers.
  Stream<ConnectionStatus> watchConnectionStatus();

  /// Emits a full snapshot (local + remotes) on every relevant room event.
  /// Replays the latest snapshot to new subscribers.
  Stream<List<Participant>> watchParticipants();
}
