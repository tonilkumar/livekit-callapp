import '../../domain/entities/connection_params.dart';
import '../../domain/entities/connection_status.dart';
import '../../domain/entities/participant.dart';
import '../../domain/repositories/call_repository.dart';
import '../datasources/livekit_room_data_source.dart';
import '../datasources/token_service.dart';

class LiveKitCallRepository implements CallRepository {
  LiveKitCallRepository(this._tokenService, this._dataSource);

  final TokenService _tokenService;
  final LiveKitRoomDataSource _dataSource;

  @override
  Future<void> connect(ConnectionParams params) async {
    // Open the session BEFORE the (slow) token fetch, so a disconnect that
    // arrives while the token is in flight invalidates this attempt instead of
    // resuming into a live room with a hot camera and mic.
    final session = await _dataSource.beginSession();
    final details = await _tokenService.fetchConnectionDetails(
      roomId: params.roomId,
      userName: params.userName,
    );
    await _dataSource.connect(session, details.serverUrl, details.token);
  }

  @override
  Future<void> disconnect() => _dataSource.disconnect();

  @override
  Future<bool> setMicrophoneEnabled(bool enabled) =>
      _dataSource.setMicrophoneEnabled(enabled);

  @override
  Future<bool> setCameraEnabled(bool enabled) =>
      _dataSource.setCameraEnabled(enabled);

  @override
  Stream<ConnectionStatus> watchConnectionStatus() =>
      _dataSource.watchConnectionStatus();

  @override
  Stream<List<Participant>> watchParticipants() =>
      _dataSource.watchParticipants();
}
